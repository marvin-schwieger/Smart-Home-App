"""HTTP device simulator, the counterpart of device_simulator.py.

The same temperature sensor and lamp, once open and once behind each of the
two authentication methods the app supports for HTTP. Test credentials:

  /temperature, /lamp   no authentication
  /basic/...            Basic       user "admin", password "secret"
  /oauth/...            OAuth 2.0   token URL /oauth/token, client ID "app",
                                    client secret "app-secret" (client credentials)

http:// runs on port 8080. With the certificates of make_test_certs.py also
https:// on port 8443; enter credentials/tls/ca.pem as CA certificate in the
app.

    python http_simulator.py
"""

import asyncio
import base64
import binascii
import contextlib
import json
import logging
import os
import random
import secrets
import time
from pathlib import Path
from urllib.parse import parse_qs, unquote_plus

import uvicorn
from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

HOST = os.environ.get("SIMULATOR_HOST", "172.30.13.2")
HTTP_PORT = 8080
HTTPS_PORT = 8443
TLS_DIR = Path(__file__).resolve().parent / "credentials" / "tls"

# Test credentials only - the app has to be set up with the same values
USERNAME = "admin"
PASSWORD = "secret"
CLIENT_ID = "app"
CLIENT_SECRET = "app-secret"

REALM = "device-simulator"
TOKEN_LIFETIME = 300  # seconds

log = logging.getLogger("http-simulator")


def _same(a, b):
    """Constant-time comparison, so the timing doesn't reveal secrets"""
    return a is not None and secrets.compare_digest(a.encode(), b.encode())


def _credentials(request, scheme):
    """Value of the Authorization header after [scheme], None without it"""
    name, _, value = request.headers.get("authorization", "").partition(" ")
    return value.strip() if name.lower() == scheme.lower() else None


def _unauthorized(challenge):
    # RFC 7235: a 401 says with which scheme to authenticate
    return HTTPException(401, "Unauthorized", headers={"WWW-Authenticate": challenge})


def _decode_basic(value):
    """User and password of Basic credentials, (None, None) if unreadable"""
    try:
        user, separator, password = base64.b64decode(value, validate=True).decode().partition(":")
    except (binascii.Error, UnicodeDecodeError):
        return None, None
    return (user, password) if separator else (None, None)


# The simulated devices

state = {"temperature": 20.0}
lamp = {"on": False, "brightness": 100, "color": "#FFFFFF"}

device = APIRouter()


@device.get("/temperature")
async def read_temperature():
    # Random walk between 10 and 30 °C, one step per request
    value = state["temperature"] + random.uniform(-1.0, 1.0)
    state["temperature"] = max(10.0, min(30.0, value))
    return {"temperature": round(state["temperature"], 2), "unit": "°C"}


@device.get("/lamp")
async def read_lamp():
    return lamp


@device.api_route("/lamp", methods=["PUT", "POST"])
async def switch_lamp(request: Request):
    # The app sends the JSON as text/plain, so the body is parsed here
    try:
        update = json.loads(await request.body())
    except ValueError:
        raise HTTPException(400, "Body is not JSON")
    if not isinstance(update, dict):
        raise HTTPException(400, "Body is not a JSON object")
    lamp.update({k: v for k, v in update.items() if k in lamp})
    log.info("Lamp state: %s", lamp)
    return lamp


# Basic (RFC 7617)


async def require_basic(request: Request):
    user, password = _decode_basic(_credentials(request, "Basic") or "")
    if not (_same(user, USERNAME) and _same(password, PASSWORD)):
        raise _unauthorized(f'Basic realm="{REALM}", charset="UTF-8"')


# OAuth 2.0 client credentials grant (RFC 6749 4.4) with bearer tokens
# (RFC 6750). Token endpoint and device are one server here, in practice the
# token endpoint usually belongs to a separate authorization server

# Issued access tokens and when they expire
_tokens = {}


async def issue_token(request: Request):
    form = {k: v[0] for k, v in parse_qs((await request.body()).decode()).items()}
    # client_secret_basic, both parts form encoded (RFC 6749 2.3.1), or
    # client_secret_post in the body
    client_id, client_secret = form.get("client_id"), form.get("client_secret")
    basic = _credentials(request, "Basic")
    if basic is not None:
        client_id, client_secret = _decode_basic(basic)
        if client_id is not None:
            client_id, client_secret = unquote_plus(client_id), unquote_plus(client_secret)
    if not (_same(client_id, CLIENT_ID) and _same(client_secret, CLIENT_SECRET)):
        return JSONResponse(
            {"error": "invalid_client"},
            401,
            headers={"WWW-Authenticate": f'Basic realm="{REALM}"'},
        )
    if form.get("grant_type") != "client_credentials":
        return JSONResponse({"error": "unsupported_grant_type"}, 400)

    token = secrets.token_urlsafe(32)
    _tokens[token] = time.time() + TOKEN_LIFETIME
    body = {"access_token": token, "token_type": "Bearer", "expires_in": TOKEN_LIFETIME}
    if form.get("scope"):
        body["scope"] = form["scope"]
    log.info("Issued a token to %s", client_id)
    return JSONResponse(body, headers={"Cache-Control": "no-store", "Pragma": "no-cache"})


async def require_oauth(request: Request):
    token = _credentials(request, "Bearer")
    expires = _tokens.get(token)
    if expires is None or expires < time.time():
        _tokens.pop(token, None)
        error = "" if token is None else ', error="invalid_token"'
        raise _unauthorized(f'Bearer realm="{REALM}"{error}')


app = FastAPI(title="Device simulator")
app.add_api_route("/oauth/token", issue_token, methods=["POST"])
app.include_router(device)
app.include_router(device, prefix="/basic", dependencies=[Depends(require_basic)])
app.include_router(device, prefix="/oauth", dependencies=[Depends(require_oauth)])


class _Server(uvicorn.Server):
    """http and https share the event loop. Without their own signal
    handlers Ctrl+C stops both instead of only the last one"""

    @contextlib.contextmanager
    def capture_signals(self):
        yield


async def main():
    configs = [uvicorn.Config(app, host=HOST, port=HTTP_PORT)]
    certificate, key = TLS_DIR / "server.pem", TLS_DIR / "server.key"
    if certificate.exists():
        configs.append(
            uvicorn.Config(app, host=HOST, port=HTTPS_PORT, ssl_certfile=certificate, ssl_keyfile=key)
        )
    else:
        log.warning("No certificates in %s, https off - run make_test_certs.py", TLS_DIR)
    for config in configs:
        log.info("Listening on %s://%s:%d", "https" if config.ssl_certfile else "http", HOST, config.port)
    await asyncio.gather(*(_Server(config).serve() for config in configs))


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
