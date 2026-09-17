import datetime
import logging
import json
import asyncio
import random
import aiocoap.resource as resource
from aiocoap.numbers.contentformat import ContentFormat
import aiocoap


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

    await aiocoap.Context.create_server_context(root, bind=("172.30.13.2", 5683))

    print("Starting temperature sensor simulation...")
    sensor_task = asyncio.create_task(temperature.simulate_temperature_change())

    # Run forever
    await asyncio.get_running_loop().create_future()


if __name__ == "__main__":
    asyncio.run(main())