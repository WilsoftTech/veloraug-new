"""Token checks for /api/v1/me.

Tokens are signed with keys generated here, and the public keys are served by
a small local server, as Neon serves its JWKS. No network or real project is
needed. The cases follow the Step 5E criteria in docs/step-05a-neon-plan.md.
"""

import base64
import hashlib
import hmac
import json
import logging
import socket
import threading
import time
import uuid
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi.testclient import TestClient
from jwt import PyJWKClient
from jwt.algorithms import OKPAlgorithm, RSAAlgorithm

from app.auth import TokenVerifier
from app.config import Settings
from app.main import create_app

ISSUER = "https://ep-test-123.neonauth.example.test/neondb/auth"
OTHER_BRANCH_ISSUER = "https://ep-other-456.neonauth.example.test/neondb/auth"
RESOURCE = "https://api-dev.veloraug.invalid"
USERINFO = f"{ISSUER}/oauth2/userinfo"
CLIENTS = ["web-client", "android-client"]
USER = "5f0c2b1e-8a4d-4c1e-9b2f-3d6a7e8f9a0b"
OTHER_USER = "0b9a8f7e-6d3a-4f2b-9e1c-4d8a1e2b0c5f"

KID = "key-1"
KEY = Ed25519PrivateKey.generate()
ROTATED_KEY = Ed25519PrivateKey.generate()
IMPOSTOR_KEY = Ed25519PrivateKey.generate()
RSA_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
EC_KEY = ec.generate_private_key(ec.SECP256R1())

SETTINGS = Settings(
    neon_auth_url=ISSUER, api_resource=RESOURCE, neon_auth_client_ids=CLIENTS
)

REMOVE = object()


def public_jwk(algorithm, key, kid, alg):
    jwk = algorithm.to_jwk(key.public_key(), as_dict=True)
    return {**jwk, "kid": kid, "alg": alg, "use": "sig"}


def neon_jwks():
    return {
        "keys": [
            public_jwk(OKPAlgorithm, KEY, KID, "EdDSA"),
            # An RSA key the server also publishes. Tokens signed with it are
            # still refused, because only EdDSA is accepted.
            public_jwk(RSAAlgorithm, RSA_KEY, "rsa-key", "RS256"),
        ]
    }


def claims(**changes):
    now = int(time.time())
    payload = {
        "iss": ISSUER,
        "aud": [RESOURCE, USERINFO],
        "sub": USER,
        "client_id": "web-client",
        "azp": "web-client",
        "iat": now,
        "exp": now + 3600,
        "scope": "openid email profile offline_access",
        "jti": str(uuid.uuid4()),
        "sid": "session-1",
    }
    for name, value in changes.items():
        if value is REMOVE:
            payload.pop(name, None)
        else:
            payload[name] = value
    return payload


def token(payload=None, *, key=KEY, kid=KID, alg="EdDSA"):
    headers = {} if kid is None else {"kid": kid}
    return jwt.encode(
        claims() if payload is None else payload, key, algorithm=alg, headers=headers
    )


def segment(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def handmade(header, payload, sign) -> str:
    signing_input = (
        f"{segment(json.dumps(header).encode())}."
        f"{segment(json.dumps(payload).encode())}"
    )
    return f"{signing_input}.{segment(sign(signing_input.encode()))}"


def with_payload(original: str, payload) -> str:
    header, _, signature = original.split(".")
    return f"{header}.{segment(json.dumps(payload).encode())}.{signature}"


def with_changed_signature(original: str) -> str:
    header, payload, signature = original.split(".")
    changed = "A" if signature[10] != "A" else "B"
    return f"{header}.{payload}.{signature[:10]}{changed}{signature[11:]}"


PUBLIC_PEM = KEY.public_key().public_bytes(
    serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
)
PUBLIC_RAW = KEY.public_key().public_bytes(
    serialization.Encoding.Raw, serialization.PublicFormat.Raw
)


class KeyServer:
    """Serves a JWKS, counts fetches, and can fail on request."""

    def __init__(self):
        self.jwks = neon_jwks()
        self.raw: bytes | None = None
        self.failing = False
        self.fetches = 0
        self.url = ""


@pytest.fixture
def key_server():
    state = KeyServer()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            state.fetches += 1
            if state.failing:
                self.send_error(500)
                return
            body = state.raw if state.raw is not None else json.dumps(state.jwks)
            body = body.encode() if isinstance(body, str) else body
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    state.url = f"http://127.0.0.1:{port}/neondb/auth/.well-known/jwks.json"
    yield state
    server.shutdown()
    server.server_close()


def api(jwks_url: str, cooldown: float = 30) -> TestClient:
    verifier = TokenVerifier(
        issuer=ISSUER,
        audience=RESOURCE,
        client_ids=CLIENTS,
        jwks_client=PyJWKClient(
            jwks_url, timeout=2, lifespan=300, cooldown_duration=cooldown
        ),
    )
    return TestClient(
        create_app(SETTINGS, token_verifier=verifier, database=FakeDatabase())
    )


class FakeDatabase:
    """Stands in for Postgres, which tests/test_database.py covers. Every
    profile it returns belongs to the user it was asked for."""

    class _Connection:
        def __init__(self, user_id):
            self._user_id = user_id

        def execute(self, query, params=()):
            return self

        def fetchone(self):
            return (self._user_id, None)

    @contextmanager
    def as_user(self, user_id):
        yield self._Connection(user_id)


@pytest.fixture
def client(key_server):
    return api(key_server.url)


def me(client, value):
    return client.get("/api/v1/me", headers={"Authorization": f"Bearer {value}"})


def assert_refused(response):
    assert response.status_code == 401
    assert response.headers["www-authenticate"].startswith("Bearer")
    # The same body for every failure, so it doesn't say which check failed.
    assert response.json() == {"detail": "Not signed in."}


# --- Accepted ---------------------------------------------------------------


def test_a_valid_token_returns_the_user_id(client):
    response = me(client, token())

    assert response.status_code == 200
    assert response.json() == {"user_id": USER, "display_name": None}


@pytest.mark.parametrize(
    "aud", [RESOURCE, [RESOURCE], [RESOURCE, USERINFO], [USERINFO, RESOURCE]]
)
def test_audience_as_a_string_or_an_array_is_accepted(client, aud):
    assert me(client, token(claims(aud=aud))).status_code == 200


def test_each_listed_client_is_accepted(client):
    for client_id in CLIENTS:
        assert me(client, token(claims(client_id=client_id))).status_code == 200


def test_the_scheme_name_is_case_insensitive(client):
    response = client.get("/api/v1/me", headers={"Authorization": f"bearer {token()}"})

    assert response.status_code == 200


def test_a_small_clock_difference_is_allowed(client):
    now = int(time.time())

    assert me(client, token(claims(iat=now + 10))).status_code == 200


def test_the_default_key_address_is_under_the_issuer():
    verifier = TokenVerifier(issuer=ISSUER, audience=RESOURCE, client_ids=CLIENTS)

    assert verifier._jwks.uri == f"{ISSUER}/.well-known/jwks.json"


# --- Refused: the header ----------------------------------------------------


def test_no_header_is_refused(client):
    response = client.get("/api/v1/me")

    assert_refused(response)
    assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize(
    "value",
    ["Basic dXNlcjpwYXNz", "Token {t}", "Bearer", "Bearer ", "Bearer  {t}", "{t}"],
)
def test_other_schemes_and_shapes_are_refused(client, value):
    response = client.get(
        "/api/v1/me", headers={"Authorization": value.format(t=token())}
    )

    assert_refused(response)


# --- Refused: the token -----------------------------------------------------

REFUSED = {
    "malformed": lambda: "not-a-token",
    "three dots of junk": lambda: "a.b.c",
    "too long": lambda: token(claims(padding="x" * 9000)),
    "expired": lambda: token(claims(exp=int(time.time()) - 120)),
    "issued in the future": lambda: token(claims(iat=int(time.time()) + 600)),
    "payload changed": lambda: with_payload(token(), claims(sub=OTHER_USER)),
    "signature changed": lambda: with_changed_signature(token()),
    "signature removed": lambda: token().rsplit(".", 1)[0] + ".",
    "alg none": lambda: handmade({"alg": "none", "kid": KID}, claims(), lambda _: b""),
    "HS256 with the public key as PEM": lambda: handmade(
        {"alg": "HS256", "kid": KID},
        claims(),
        lambda m: hmac.new(PUBLIC_PEM, m, hashlib.sha256).digest(),
    ),
    "HS256 with the raw public key": lambda: handmade(
        {"alg": "HS256", "kid": KID},
        claims(),
        lambda m: hmac.new(PUBLIC_RAW, m, hashlib.sha256).digest(),
    ),
    "RS256 with the published RSA key": lambda: token(
        key=RSA_KEY, kid="rsa-key", alg="RS256"
    ),
    "RS256 claiming the Ed25519 kid": lambda: token(key=RSA_KEY, alg="RS256"),
    "ES256": lambda: token(key=EC_KEY, alg="ES256"),
    "another key claiming the right kid": lambda: token(key=IMPOSTOR_KEY),
    "no kid": lambda: token(kid=None),
    "another branch's issuer": lambda: token(claims(iss=OTHER_BRANCH_ISSUER)),
    "the Auth URL's origin as issuer": lambda: token(
        claims(iss="https://ep-test-123.neonauth.example.test")
    ),
    "issuer with a trailing slash": lambda: token(claims(iss=f"{ISSUER}/")),
    "wrong audience": lambda: token(claims(aud="https://other.invalid")),
    "audience without the resource": lambda: token(claims(aud=[USERINFO])),
    "client not on the list": lambda: token(claims(client_id="other-client")),
    "no client_id": lambda: token(claims(client_id=REMOVE)),
    "client_id as a list": lambda: token(claims(client_id=["web-client"])),
    "no exp": lambda: token(claims(exp=REMOVE)),
    "no iat": lambda: token(claims(iat=REMOVE)),
    "no iss": lambda: token(claims(iss=REMOVE)),
    "no aud": lambda: token(claims(aud=REMOVE)),
    "no sub": lambda: token(claims(sub=REMOVE)),
    "sub not a UUID": lambda: token(claims(sub="not-a-uuid")),
    "sub empty": lambda: token(claims(sub="")),
    "sub a number": lambda: token(claims(sub=42)),
    "sub in braces": lambda: token(claims(sub=f"{{{USER}}}")),
    "sub as a URN": lambda: token(claims(sub=f"urn:uuid:{USER}")),
    "sub without hyphens": lambda: token(claims(sub=USER.replace("-", ""))),
}


@pytest.mark.parametrize("make", REFUSED.values(), ids=REFUSED.keys())
def test_invalid_tokens_are_refused(client, make):
    assert_refused(me(client, make()))


# --- Keys -------------------------------------------------------------------


def test_keys_are_fetched_once_for_many_requests(client, key_server):
    for _ in range(5):
        assert me(client, token()).status_code == 200

    assert key_server.fetches == 1


def test_unknown_key_ids_dont_refetch_the_keys_each_time(client, key_server):
    assert me(client, token()).status_code == 200

    for _ in range(20):
        assert_refused(me(client, token(kid=f"invented-{uuid.uuid4()}")))

    assert key_server.fetches == 1


def test_a_rotated_key_is_picked_up_after_the_cooldown(key_server):
    client = api(key_server.url, cooldown=0.2)
    assert me(client, token()).status_code == 200

    key_server.jwks["keys"].append(
        public_jwk(OKPAlgorithm, ROTATED_KEY, "key-2", "EdDSA")
    )
    time.sleep(0.3)

    assert me(client, token(key=ROTATED_KEY, kid="key-2")).status_code == 200
    assert key_server.fetches == 2


def test_keys_that_fail_to_load_give_503(client, key_server):
    key_server.failing = True

    response = me(client, token())

    assert response.status_code == 503
    assert "www-authenticate" not in response.headers


def test_an_unreachable_key_address_gives_503():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    client = api(f"http://127.0.0.1:{port}/.well-known/jwks.json")

    assert me(client, token()).status_code == 503


@pytest.mark.parametrize("raw", [b"not json", b"[]", b'{"keys": []}'])
def test_an_unusable_key_set_gives_503(client, key_server, raw):
    key_server.raw = raw

    assert me(client, token()).status_code == 503


def test_cached_keys_keep_working_when_the_key_address_fails(client, key_server):
    assert me(client, token()).status_code == 200
    key_server.failing = True

    assert me(client, token()).status_code == 200


# --- Public routes, CORS and logs -------------------------------------------


@pytest.mark.parametrize("path", ["/health", "/api/v1"])
def test_public_routes_need_no_token(client, key_server, path):
    for headers in [{}, {"Authorization": "Bearer junk"}]:
        assert client.get(path, headers=headers).status_code == 200

    assert key_server.fetches == 0


def test_a_refusal_is_readable_by_the_flutter_web_app(client):
    # Without this header the browser would hide the 401 from the app.
    response = client.get(
        "/api/v1/me",
        headers={"Origin": "http://localhost:8765", "Authorization": "Bearer junk"},
    )

    assert response.status_code == 401
    assert response.headers["access-control-allow-origin"] == "http://localhost:8765"


def test_no_token_reaches_the_logs_or_replies(client, key_server, caplog):
    caplog.set_level(logging.DEBUG)
    tokens = [token(), *(make() for make in REFUSED.values())]
    replies = [me(client, value).text for value in tokens]
    key_server.failing = True
    replies.append(me(api(key_server.url), token()).text)

    logged = caplog.text
    assert "Token refused" in logged
    for value in tokens:
        for part in value.split("."):
            if len(part) > 8:
                assert part not in logged
                assert all(part not in reply for reply in replies)
