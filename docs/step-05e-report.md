# Step 5E report: the API checks sign-in

Date: 7 November 2026. Branch: `feature/step-05e-api-token-verification`, started from the Step 5D branch, because `main` doesn't have Steps 5B to 5D yet. This follows the [Neon plan](step-05a-neon-plan.md#4-token-verification-in-fastapi).

**Step 5E is complete.** Every criterion is automated. The tests use a locally generated Ed25519 key and a local key server, as the plan requires. The container was also run with the real development settings. It fetched Neon's real keys, and it refused requests without a valid token. No real token was used: calling the API with one from the app is [Step 5G](step-05a-neon-plan.md#5g-end-to-end). Nothing was deployed or pushed, and no Neon setting changed.

## What changed

| Item | Where |
| --- | --- |
| Token checks, and the `current_user` dependency for signed-in routes | [`app/auth.py`](../services/api/app/auth.py) |
| `GET /api/v1/me`, which returns `{"user_id": "<uuid>"}` from the verified token | [`app/routes.py`](../services/api/app/routes.py) |
| Three sign-in settings, which go together. Production refuses to start without them | [`app/config.py`](../services/api/app/config.py) |
| CORS adds `PATCH`, and the `Authorization` and `Content-Type` headers. Credentials stay off | [`app/main.py`](../services/api/app/main.py) |
| `PyJWT[crypto]` 2.15.1, with cryptography 50.0.2, cffi 2.1.1 and pycparser 3.12. All other pins unchanged | [`requirements.txt`](../services/api/requirements.txt) |
| Compose passes `services/api/.env` to the container, if it exists | [`infra/compose.local.yaml`](../infra/compose.local.yaml) |
| Docs | [API README](../services/api/README.md), [infra README](../infra/README.md), [`.env.example`](../services/api/.env.example) |

**The checks, in order:**

1. The header must be `Bearer <token>`, in any letter case.
2. The token must be at most 8 KB, with header algorithm `EdDSA` and a key ID (`kid`). This is checked before any key lookup, so other algorithms never cause a fetch.
3. The key comes from `<issuer>/.well-known/jwks.json` only.
4. `jwt.decode` runs with `algorithms=["EdDSA"]`, the exact issuer and the audience. It requires `exp`, `iat`, `iss`, `aud` and `sub`, and allows 30 seconds of clock difference.
5. `client_id` must be on the list.
6. `sub` must be a hyphenated UUID.

Every failure gets the same `401`, `{"detail": "Not signed in."}` with `WWW-Authenticate: Bearer`. Keys that can't be fetched give `503`. Logs name only the failed check, never the token.

**Keys.** PyJWT's `PyJWKClient` holds the keys for 5 minutes and times out after 5 seconds. An unknown `kid` refetches at most once per 30-second cooldown, and the client doesn't follow redirects. This settles the plan's open question on [refetch limits](step-05a-neon-plan.md#still-unconfirmed). A rotated key is accepted within 30 seconds.

**Differences from the plan:**

- **Without the settings, in development,** the API starts and `/api/v1/me` answers `503`, "Sign-in isn't set up on this server." The plan only covered production, which still refuses to start.
- **An empty setting counts as unset,** so `KEY=""` in `.env` gives the "set all three or none" message rather than a parse error.
- **`WWW-Authenticate`** adds `error="invalid_token"` when a token was sent, as RFC 6750 describes. It still doesn't say which check failed.

## Your local `.env`

The container first failed to start. `services/api/.env` still had the **old us-east-2 project's** Auth URL from before the move to Frankfurt, and an empty client ID list. I copied the Frankfurt Auth URL, the resource and the two client IDs from `apps/client/dart_defines.local.json`. All four are public. The file is still Git-ignored.

**I didn't open or change `VELORAUG_DATABASE_URL`.** It probably belongs to the old project too. It isn't used until [Step 5F](step-05a-neon-plan.md#5f-database-and-isolation), which replaces it with a pooled `veloraug_app` connection to the Frankfurt project.

## Tested

| Check | Result |
| --- | --- |
| `ruff format --check`, `ruff check` | Clean |
| `pytest` | 108 passed, 64 of them in [`tests/test_auth.py`](../services/api/tests/test_auth.py) |
| Each refused token fails at the check it names | Confirmed by running each case against the verifier directly. For example, the impostor key fails on its signature, and the other branch's issuer fails on the issuer |
| Docker image builds, and the container is healthy with the real `.env` | Passed |
| In the container: `/health` and `/api/v1` | `200` |
| In the container: `/api/v1/me` with no token, a junk token, and an EdDSA token with an invented `kid` | `401` each time. The last one fetched Neon's real keys, or it would have been `503` |
| Container log | No token text |

## Acceptance criteria

**A token gets `401` when it is:**

| Criterion | State |
| --- | --- |
| Missing, or sent with a scheme other than `Bearer` | **Met** |
| Malformed, expired, or tampered with in the payload or signature | **Met** |
| Signed with `alg: none`, or with HS256 using the public key as the secret (PEM and raw) | **Met** |
| Signed with RS256 or ES256, by any key, including an RSA key the server publishes | **Met** |
| Signed by a different key that claims the right issuer and `kid` | **Met** |
| Validly signed with another branch's issuer | **Met** |
| Carrying the origin of the Auth URL as issuer | **Met** |
| Carrying the wrong audience, or issued to a client not on the list | **Met** |
| Missing `exp`, `iat`, `iss`, `aud` or `sub`, or with an invalid `sub` | **Met** |
| Using an unknown `kid`, without refetching the keys each time | **Met**. 20 invented `kid` values caused no extra fetch |

**Other checks:**

| Criterion | State |
| --- | --- |
| A valid token returns `200` from `/api/v1/me`, with the `sub` from the token | **Met** |
| `aud` as a string and as an array containing the resource are both accepted | **Met** |
| Unreachable keys return `503`, not `200` or `401` | **Met**: a failing server, a closed port, and an unusable key set. Keys already held keep working |
| `/health` and `/api/v1` stay public, and `/health` makes no database call | **Met**. There is no database yet, and neither route fetches keys |
| A preflight from `http://localhost:8765` allows `Authorization` and `PATCH`, and other origins are refused | **Met**. A `401` is also readable by the web app |
| No token or connection string appears in logs or error responses | **Met** in tests and in the container log |
| Production refuses to start without the settings | **Met** for the sign-in settings. Database settings are added in 5F |
| `ruff` and `pytest` pass, and the Docker image builds and runs healthy | **Met** |

## Known limits

- **A token stays valid until it expires,** up to an hour, even after sign-out. This is the [revocation limit](step-05a-neon-plan.md#revocation-limits) the plan accepts. 5G records it with a real token.
- **ARM64.** `cryptography` and `cffi` have native code. ARM64 wheels are checked in Milestone 10, with the rest of the image.
