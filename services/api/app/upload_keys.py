"""Upload keys, as both the owner's script and the upload hooks see them.

A key is shown once, when the owner makes it. Only its SHA-256 is stored, and
the hooks look a key up by that hash.
"""

import hashlib
import secrets

KEY_PREFIX = "vu_"


def new_key() -> str:
    """32 random bytes, as 43 URL-safe characters, after a recognisable prefix."""
    return KEY_PREFIX + secrets.token_urlsafe(32)


def key_hash(key: str) -> bytes:
    """What the database stores, and what the upload hooks look a key up by."""
    return hashlib.sha256(key.strip().encode()).digest()
