import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.auth import TokenVerifier
from app.config import Settings
from app.db import Database, DatabaseUnavailable
from app.routes import router

logger = logging.getLogger("veloraug.db")


def create_app(
    settings: Settings | None = None,
    token_verifier: TokenVerifier | None = None,
    database: Database | None = None,
) -> FastAPI:
    """Build the application. Tests pass their own settings, verifier and
    database."""
    settings = settings or Settings()
    if token_verifier is None and settings.sign_in_configured:
        token_verifier = TokenVerifier(
            issuer=settings.neon_auth_url,
            audience=settings.api_resource,
            client_ids=settings.neon_auth_client_ids,
        )
    if database is None and settings.database_url is not None:
        database = Database(settings.database_url.get_secret_value())

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if database is not None:
            database.open()
        yield
        if database is not None:
            database.close()

    app = FastAPI(title="VeloraUG API", version="0.1.0", lifespan=lifespan)
    app.state.settings = settings
    # None when sign-in or the database isn't configured. Only development
    # allows that, and the routes that need them answer 503.
    app.state.token_verifier = token_verifier
    app.state.database = database
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        # No cookies are used: the app sends its token in a header.
        allow_credentials=False,
        allow_methods=["GET", "PATCH"],
        allow_headers=["Authorization", "Content-Type"],
    )

    @app.exception_handler(DatabaseUnavailable)
    def database_unavailable(request: Request, error: DatabaseUnavailable):
        logger.warning("Database unavailable: %s", error)
        return JSONResponse(
            status_code=503,
            content={"detail": "The service is busy. Try again shortly."},
        )

    app.include_router(router)
    return app
