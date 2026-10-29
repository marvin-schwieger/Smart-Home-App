"""CoAP device simulator.

Besides the open resources it serves /secure/temperature and /secure/lamp,
which answer only authenticated requests (4.01 otherwise):

* OSCORE on coap://HOST:5683, one security context per algorithm. All use
  Master Secret 0x0102030405060708090a0b0c0d0e0f10 and Master Salt
  0x9e7ca92223786340 (RFC 8613 Appendix C.1.1); in the app the Recipient ID
  is always 0x01, the Sender ID picks the algorithm:

      app Sender ID   AEAD algorithm        HKDF
      (empty)         AES-CCM-16-64-128     SHA-256
      0x10            AES-CCM-16-128-128    SHA-256
      0x11            A128GCM               SHA-256
      0x12            A256GCM               SHA-256
      0x13            ChaCha20/Poly1305     SHA-256
      0x14            AES-CCM-16-64-128     SHA-384
      0x15            AES-CCM-16-64-128     SHA-512

  The contexts live in credentials/oscore/, where aiocoap also keeps the
  sequence numbers it has seen. Needs `pip install aiocoap[oscore]`.
* DTLS with a pre-shared key on coaps://HOST:5684, identity "app" and key
  "secretPSK". Needs `pip install aiocoap[tinydtls]`, which builds DTLSSocket
  and for that needs `sudo apt install autoconf automake build-essential`.

Missing modules only switch the respective method off.
"""

import datetime
import logging
import json
import asyncio
import os
import random
from pathlib import Path
import aiocoap.resource as resource
from aiocoap.credentials import CredentialsMap
from aiocoap.defaults import dtls_missing_modules, oscore_missing_modules
from aiocoap.numbers.contentformat import ContentFormat
import aiocoap

HOST = os.environ.get("SIMULATOR_HOST", "172.30.13.2")

CREDENTIALS_DIR = Path(__file__).resolve().parent / "credentials"

# Test credentials only - the app has to be set up with the same values
DTLS_IDENTITY = "app"
DTLS_PSK = "secretPSK"

OSCORE_SECRET = "0102030405060708090a0b0c0d0e0f10"
OSCORE_SALT = "9e7ca92223786340"
OSCORE_DEVICE_ID = "01"

# Sender ID of the app (hex), AEAD algorithm and HKDF hash, see the table above
OSCORE_CONTEXTS = [
    ("", "AES-CCM-16-64-128", "sha256"),
    ("10", "AES-CCM-16-128-128", "sha256"),
    ("11", "A128GCM", "sha256"),
    ("12", "A256GCM", "sha256"),
    ("13", "ChaCha20/Poly1305", "sha256"),
    ("14", "AES-CCM-16-64-128", "sha384"),
    ("15", "AES-CCM-16-64-128", "sha512"),
]


class Welcome(resource.Resource):
    representations = {
        ContentFormat.TEXT: b"Welcome to the demo server",
        ContentFormat.LINKFORMAT: b"</.well-known/core>,ct=40",
        # ad-hoc for application/xhtml+xml;charset=utf-8
        ContentFormat(65000): b'<html xmlns="http://www.w3.org/1999/xhtml">'
        b"<head><title>aiocoap demo</title></head>"
        b"<body><h1>Welcome to the aiocoap demo server!</h1>"
        b'<ul><li><a href="time">Current time</a></li>'
        b'<li><a href="whoami">Report my network address</a></li>'
        b"</ul></body></html>",
    }

    default_representation = ContentFormat.TEXT

    async def render_get(self, request):
        cf = (
            self.default_representation
            if request.opt.accept is None
            else request.opt.accept
        )
        try:
            return aiocoap.Message(payload=self.representations[cf], content_format=cf)
        except KeyError:
            raise aiocoap.error.UnsupportedContentFormat


class BlockResource(resource.Resource):
    """Example resource which supports the GET and PUT methods. It sends large
    responses, which trigger blockwise transfer."""

    def __init__(self):
        super().__init__()
        self.set_content(
            b"This is the resource's default content. It is padded "
            b"with numbers to be large enough to trigger blockwise "
            b"transfer.\n"
        )

    def set_content(self, content):
        self.content = content
        while len(self.content) <= 1024:
            self.content = self.content + b"0123456789\n"

    async def render_get(self, request):
        return aiocoap.Message(payload=self.content, content_format=ContentFormat.TEXT)

    async def render_put(self, request):
        print("PUT payload: %s" % request.payload)
        self.set_content(request.payload)
        return aiocoap.Message(code=aiocoap.CHANGED, payload=self.content)


class SeparateLargeResource(resource.Resource):
    """Example resource which supports the GET method. It uses asyncio.sleep to
    simulate a long-running operation, and thus forces the protocol to send
    empty ACK first."""

    def get_link_description(self):
        # Publish additional data in .well-known/core
        return dict(**super().get_link_description(), title="A large resource")

    async def render_get(self, request):
        await asyncio.sleep(3)

        payload = (
            "Three rings for the elven kings under the sky, seven rings "
            "for dwarven lords in their halls of stone, nine rings for "
            "mortal men doomed to die, one ring for the dark lord on his "
            "dark throne.".encode("ascii")
        )
        return aiocoap.Message(payload=payload, content_format=ContentFormat.TEXT)


class TimeResource(resource.ObservableResource):
    """Example resource that can be observed. The `notify` method keeps
    scheduling itself, and calls `update_state` to trigger sending
    notifications."""

    def __init__(self):
        super().__init__()

        self.handle = None

    def notify(self):
        self.updated_state()
        self.reschedule()

    def reschedule(self):
        self.handle = asyncio.get_running_loop().call_later(5, self.notify)

    def update_observation_count(self, count):
        if count and self.handle is None:
            print("Starting the clock")
            self.reschedule()
        if count == 0 and self.handle:
            print("Stopping the clock")
            self.handle.cancel()
            self.handle = None

    async def render_get(self, request):
        payload = datetime.datetime.now().strftime("%Y-%m-%d %H:%M").encode("ascii")
        return aiocoap.Message(payload=payload, content_format=ContentFormat.TEXT)

# Simulated Temp. Sensor 
class TemperatureSensor(resource.ObservableResource):

    MAX_TEMP = 30.0
    MIN_TEMP = 10.0

    def __init__(self, interval=2):
        super().__init__()
        self.interval = interval
        self.current_temp = 20.0

    async def simulate_temperature_change(self):
        while True:
            await asyncio.sleep(self.interval)
            self.current_temp += (self.MAX_TEMP - self.MIN_TEMP) * (0.5 - random.random())
            self.current_temp = max(self.MIN_TEMP, min(self.MAX_TEMP, self.current_temp))
            self.updated_state()

    def get_link_description(self):
        return dict(**super().get_link_description(), title="Temperature Sensor", rt="temperature")

    async def render_get(self, request):
        payload = json.dumps({"temperature": self.current_temp, "unit": "°C"}).encode("utf-8")
        return aiocoap.Message(payload=payload, content_format=ContentFormat.JSON)


# Simulated lamp for the "Smart lamp" preset of the app
class Lamp(resource.Resource):
    """GET returns the state, PUT/POST change the fields given as JSON,
    e.g. {"on": true, "brightness": 80, "color": "#FF0000"}"""

    def __init__(self):
        super().__init__()
        self.state = {"on": False, "brightness": 100, "color": "#FFFFFF"}

    def _state_message(self, code=aiocoap.CONTENT):
        payload = json.dumps(self.state).encode("utf-8")
        return aiocoap.Message(code=code, payload=payload, content_format=ContentFormat.JSON)

    async def render_get(self, request):
        return self._state_message()

    async def render_put(self, request):
        try:
            update = json.loads(request.payload)
        except ValueError:
            raise aiocoap.error.BadRequest("Payload is not JSON")
        if not isinstance(update, dict):
            raise aiocoap.error.BadRequest("Payload is not a JSON object")
        self.state.update({k: v for k, v in update.items() if k in self.state})
        print("Lamp state: %s" % self.state)
        return self._state_message(aiocoap.CHANGED)

    render_post = render_put


class AuthRequired:
    """Mixin for resources that only answer requests over OSCORE or DTLS.
    aiocoap only marks who a request came from in its authenticated claims,
    checking them is up to the resource"""

    async def render(self, request):
        claims = list(request.remote.authenticated_claims)
        if not claims:
            raise aiocoap.error.Unauthorized("Use OSCORE or DTLS for this resource")
        logging.info("Authenticated request from %s", ", ".join(map(str, claims)))
        return await super().render(request)


class SecureTemperature(AuthRequired, resource.Resource):
    """The values of [sensor], only for authenticated clients"""

    def __init__(self, sensor):
        super().__init__()
        self.sensor = sensor

    async def render_get(self, request):
        return await self.sensor.render_get(request)


class SecureLamp(AuthRequired, Lamp):
    pass


def oscore_context_dirs():
    """Writes the settings of each OSCORE context into its directory, where
    aiocoap keeps the sequence numbers next to them. Yields a name for the log
    and the directory"""
    for app_sender_id, algorithm, hashfun in OSCORE_CONTEXTS:
        path = CREDENTIALS_DIR / "oscore" / (app_sender_id or "default")
        path.mkdir(parents=True, exist_ok=True)
        # The device's view: its Sender ID is the app's Recipient ID
        settings = {
            "sender-id_hex": OSCORE_DEVICE_ID,
            "recipient-id_hex": app_sender_id,
            "algorithm": algorithm,
            "kdf-hashfun": hashfun,
        }
        secret = {"secret_hex": OSCORE_SECRET, "salt_hex": OSCORE_SALT}
        (path / "settings.json").write_text(json.dumps(settings, indent=2) + "\n")
        (path / "secret.json").write_text(json.dumps(secret, indent=2) + "\n")
        yield "%s-%s" % (algorithm, hashfun), path


def server_credentials():
    """Credentials of all clients the server accepts, labelled with the claim
    the resources see"""
    entries = {}
    if not oscore_missing_modules():
        for name, path in oscore_context_dirs():
            entries[":app-oscore-" + name] = {"oscore": {"basedir": str(path)}}
    if not dtls_missing_modules():
        entries[":app-dtls"] = {
            "dtls": {
                "psk": {"ascii": DTLS_PSK},
                "client-identity": {"ascii": DTLS_IDENTITY},
            }
        }
    credentials = CredentialsMap()
    credentials.load_from_dict(entries)
    return credentials


class WhoAmI(resource.Resource):
    async def render_get(self, request):
        text = ["Used protocol: %s." % request.remote.scheme]

        try:
            text.append("Request came from %s." % request.remote.hostinfo)
            text.append("The server address used %s." % request.remote.hostinfo_local)
        except aiocoap.error.AnonymousHost as e:
            text.append("Network peer: %r" % request.remote)

        claims = list(request.remote.authenticated_claims)
        if claims:
            text.append(
                "Authenticated claims of the client: %s."
                % ", ".join(repr(c) for c in claims)
            )
        else:
            text.append("No claims authenticated.")

        return aiocoap.Message(
            payload="\n".join(text).encode("utf8"),
            content_format=ContentFormat.TEXT,
        )


# logging setup

logging.basicConfig(level=logging.INFO)
logging.getLogger("coap-server").setLevel(logging.DEBUG)


async def main():
    # Resource tree creation
    logging.info("Starting CoAP server...")

    root = resource.Site()

    root.add_resource(
        [".well-known", "core"], resource.WKCResource(root.get_resources_as_linkheader)
    )
    root.add_resource([], Welcome())
    root.add_resource(["time"], TimeResource())
    root.add_resource(["other", "block"], BlockResource())
    root.add_resource(["other", "separate"], SeparateLargeResource())
    root.add_resource(["whoami"], WhoAmI())

    # Register the temperature sensor resource
    temperature = TemperatureSensor()
    root.add_resource(["temperature"], temperature)
    root.add_resource(["lamp"], Lamp())

    # The same devices, only for authenticated clients
    root.add_resource(["secure", "temperature"], SecureTemperature(temperature))
    root.add_resource(["secure", "lamp"], SecureLamp())

    credentials = server_credentials()
    site = root
    if oscore_missing_modules():
        logging.warning("OSCORE off, missing: %s", ", ".join(oscore_missing_modules()))
    else:
        from aiocoap.oscore_sitewrapper import OscoreSiteWrapper

        # Decrypts OSCORE requests before they reach the resources
        site = OscoreSiteWrapper(root, credentials)
        logging.info("OSCORE on coap://%s:5683", HOST)
    if dtls_missing_modules():
        logging.warning("DTLS off, missing: %s", ", ".join(dtls_missing_modules()))
    else:
        # aiocoap only starts its DTLS server when asked to, on port 5684
        os.environ["AIOCOAP_DTLSSERVER_ENABLED"] = "1"
        logging.info("DTLS (PSK) on coaps://%s:5684", HOST)

    await aiocoap.Context.create_server_context(
        site, bind=(HOST, 5683), server_credentials=credentials
    )

    print("Starting temperature sensor simulation...")
    sensor_task = asyncio.create_task(temperature.simulate_temperature_change())

    # Run forever
    await asyncio.get_running_loop().create_future()


if __name__ == "__main__":
    asyncio.run(main())