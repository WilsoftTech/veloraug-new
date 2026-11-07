"""Checks Neon Auth access tokens.

Tokens are verified here, with Neon's public keys, and no request to Neon is
made per token. The rules are in docs/step-05a-neon-plan.md, section 4. Only
the verified `sub` identifies the user. Nothing else in the token decides
access.

No token, or any part of one, is ever logged or returned. Logs name only the
kind of failure.
"""

import logging
import re
from dataclasses import dataclass
from uuid import UUID

import jwt
from fastapi import HTTPException, Request, status
from jwt import PyJWKClient
from jwt.exceptions import (
    PyJWKClientConnectionError,
    PyJWKClientError,
    PyJWKSetError,
    PyJWTError,
)

# Fixed in the code. Never taken from the token or from settings.
ALGORITHMS = ["EdDSA"]
REQUIRED_CLAIMS = ["exp", "iat", "iss", "aud", "sub"]

# Allows for a small difference between Neon's clock and this server's, for
# `iat` and `exp`.
CLOCK_LEEWAY_SECONDS = 30

# Keys are cached for this long, and a token with an unknown key ID can make
# the API fetch the keys again at most once per cooldown. That stops invented
# key IDs from forcing constant fetching, and still picks up a rotated key.
JWKS_TIMEOUT_SECONDS = 5
JWKS_LIFESPAN_SECONDS = 300
JWKS_COOLDOWN_SECONDS = 30

# Real tokens are about 1 KB. Anything far larger isn't worth parsing.
MAX_TOKEN_LENGTH = 8192

_UUID = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.IGNORECASE
)

logger = logging.getLogger("veloraug.auth")


class InvalidToken(Exception):
    """The token is refused. The message names the check, for the log only."""


class KeysUnavailable(Exception):
    """Neon's public keys couldn't be fetched, so no token can be checked."""


@dataclass(frozen=True)
class VerifiedUser:
    user_id: UUID
    client_id: str


class TokenVerifier:
    def __init__(
        self,
        *,
        issuer: str,
        audience: str,
        client_ids: list[str],
        jwks_client: PyJWKClient | None = None,
    ) -> None:
        self._issuer = issuer
        self._audience = audience
        self._client_ids = frozenset(client_ids)
        self._jwks = jwks_client or PyJWKClient(
            f"{issuer}/.well-known/jwks.json",
            timeout=JWKS_TIMEOUT_SECONDS,
            lifespan=JWKS_LIFESPAN_SECONDS,
            cooldown_duration=JWKS_COOLDOWN_SECONDS,
        )

    def verify(self, token: str) -> VerifiedUser:
        if len(token) > MAX_TOKEN_LENGTH:
            raise InvalidToken("too long")
        try:
            header = jwt.get_unverified_header(token)
        except PyJWTError as error:
            raise InvalidToken("malformed") from error

        # Checked before looking up a key, so a token with another algorithm
        # never causes a key fetch. jwt.decode checks the algorithm again.
        if header.get("alg") not in ALGORITHMS:
            raise InvalidToken("algorithm")
        kid = header.get("kid")
        if not isinstance(kid, str) or not kid:
            raise InvalidToken("no key ID")

        key = self._signing_key(kid)
        try:
            claims = jwt.decode(
                token,
                key,
                algorithms=ALGORITHMS,
                issuer=self._issuer,
                # `aud` is an array in Neon's tokens, so strict_aud stays off.
                audience=self._audience,
                leeway=CLOCK_LEEWAY_SECONDS,
                options={"require": REQUIRED_CLAIMS},
            )
        except PyJWTError as error:
            # Only the type: PyJWT's messages aren't written for logs.
            raise InvalidToken(type(error).__name__) from error

        client_id = claims.get("client_id")
        if not isinstance(client_id, str) or client_id not in self._client_ids:
            raise InvalidToken("client")
        sub = claims["sub"]
        if not isinstance(sub, str) or not _UUID.fullmatch(sub):
            raise InvalidToken("subject")
        return VerifiedUser(user_id=UUID(sub), client_id=client_id)

    def _signing_key(self, kid: str):
        # First make sure the keys themselves are available, from the cache or
        # Neon. If not, no token can be checked: that's a 503, not a 401.
        try:
            self._jwks.get_signing_keys()
        except (PyJWKClientError, PyJWKSetError, ValueError) as error:
            raise KeysUnavailable(type(error).__name__) from error
        try:
            return self._jwks.get_signing_key(kid).key
        except PyJWKClientConnectionError as error:
            raise KeysUnavailable(type(error).__name__) from error
        except (PyJWKClientError, PyJWKSetError) as error:
            raise InvalidToken("unknown key ID") from error


def _bearer_token(authorization: str | None) -> str | None:
    if not authorization:
        return None
    parts = authorization.split(" ")
    if len(parts) != 2 or parts[0].lower() != "bearer" or not parts[1]:
        return None
    return parts[1]


def _not_signed_in(*, token_given: bool) -> HTTPException:
    # The same reply for every failed check, so it doesn't say which failed.
    challenge = 'Bearer error="invalid_token"' if token_given else "Bearer"
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Not signed in.",
        headers={"WWW-Authenticate": challenge},
    )


def current_user(request: Request) -> VerifiedUser:
    """FastAPI dependency: the signed-in user, or a 401 or 503 reply.

    A plain `def`, so FastAPI runs it in its thread pool: fetching keys
    blocks.
    """
    verifier: TokenVerifier | None = request.app.state.token_verifier
    if verifier is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Sign-in isn't set up on this server.",
        )

    authorization = request.headers.get("authorization")
    token = _bearer_token(authorization)
    if token is None:
        if authorization:
            logger.info("Token refused: not a Bearer header")
        raise _not_signed_in(token_given=bool(authorization))

    try:
        return verifier.verify(token)
    except InvalidToken as error:
        logger.info("Token refused: %s", error)
        raise _not_signed_in(token_given=True) from None
    except KeysUnavailable as error:
        logger.warning("Signing keys unavailable: %s", error)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Sign-in can't be checked right now. Try again shortly.",
        ) from None
