from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.auth import TokenVerifier
from app.config import Settings
from app.routes import router


def create_app(
    settings: Settings | None = None,
    token_verifier: TokenVerifier | None = None,
) -> FastAPI:
    """Build the application. Tests pass their own settings and verifier."""
    settings = settings or Settings()
    if token_verifier is None and settings.sign_in_configured:
        token_verifier = TokenVerifier(
            issuer=settings.neon_auth_url,
            audience=settings.api_resource,
            client_ids=settings.neon_auth_client_ids,
        )

    app = FastAPI(title="VeloraUG API", version="0.1.0")
    app.state.settings = settings
    # None when sign-in isn't configured. Only development allows that, and
    # signed-in routes then answer 503.
    app.state.token_verifier = token_verifier
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        # No cookies are used: the app sends its token in a header.
        allow_credentials=False,
        allow_methods=["GET", "PATCH"],
        allow_headers=["Authorization", "Content-Type"],
    )
    app.include_router(router)
    return app
