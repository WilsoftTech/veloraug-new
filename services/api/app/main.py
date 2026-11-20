import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.admin import router as admin_router
from app.auth import TokenVerifier
from app.catalogue import Refresher
from app.config import Settings
from app.db import Database, DatabaseUnavailable
from app.pass_routes import router as pass_router
from app.pesapal import PesapalClient
from app.playback import Granter
from app.routes import router
from app.tmdb import TmdbClient
from app.viewer_routes import router as viewer_router

logger = logging.getLogger("veloraug.db")
catalogue_logger = logging.getLogger("veloraug.catalogue")


def create_app(
    settings: Settings | None = None,
    token_verifier: TokenVerifier | None = None,
    database: Database | None = None,
    refresher: Refresher | None = None,
    granter: Granter | None = None,
    editor_database: Database | None = None,
    tmdb: TmdbClient | None = None,
    pesapal: PesapalClient | None = None,
) -> FastAPI:
    """Build the application. Tests pass their own settings, verifier,
    databases, TMDB refresher and client, playback granter and Pesapal."""
    settings = settings or Settings()
    if pesapal is None and settings.pesapal_configured:
        pesapal = PesapalClient(
            settings.pesapal_consumer_key.get_secret_value(),
            settings.pesapal_consumer_secret.get_secret_value(),
            environment=settings.pesapal_environment,
        )
    if editor_database is None and settings.editor_database_url is not None:
        editor_database = Database(
            settings.editor_database_url.get_secret_value(), max_size=2
        )
    if tmdb is None and settings.tmdb_read_access_token is not None:
        # The admin routes' own client, for searches, separate from the
        # refresher's.
        tmdb = TmdbClient(settings.tmdb_read_access_token.get_secret_value())
    if granter is None and settings.playback_configured:
        granter = Granter(
            key=settings.playback_signing_key.get_secret_value().encode(),
            gateway_url=settings.media_gateway_url,
        )
    if token_verifier is None and settings.sign_in_configured:
        token_verifier = TokenVerifier(
            issuer=settings.neon_auth_url,
            audience=settings.api_resource,
            client_ids=settings.neon_auth_client_ids,
        )
    if database is None and settings.database_url is not None:
        database = Database(settings.database_url.get_secret_value())
    if (
        refresher is None
        and database is not None
        and settings.tmdb_read_access_token is not None
    ):
        refresher = Refresher(
            database, TmdbClient(settings.tmdb_read_access_token.get_secret_value())
        )

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if database is not None:
            database.open()
        if editor_database is not None:
            editor_database.open()
        if database is not None and refresher is None:
            catalogue_logger.warning(
                "VELORAUG_TMDB_READ_ACCESS_TOKEN isn't set: the catalogue serves "
                "the details it has, and none are refreshed"
            )
        yield
        if refresher is not None:
            refresher.close()
        if tmdb is not None:
            tmdb.close()
        if pesapal is not None:
            pesapal.close()
        if database is not None:
            database.close()
        if editor_database is not None:
            editor_database.close()

    # Production has no documentation pages: decision 7 of
    # docs/step-11a-pilot-deployment-plan.md. Development keeps them.
    production = settings.environment == "production"
    app = FastAPI(
        title="VeloraUG API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None if production else "/docs",
        redoc_url=None if production else "/redoc",
        openapi_url=None if production else "/openapi.json",
    )
    app.state.settings = settings
    # None when sign-in or the database isn't configured. Only development
    # allows that, and the routes that need them answer 503.
    app.state.token_verifier = token_verifier
    app.state.database = database
    # None without a database or a TMDB token. The catalogue still works,
    # without refreshing.
    app.state.refresher = refresher
    # None without the playback settings. Granting a viewing answers 503.
    app.state.granter = granter
    # None without the editor's settings. The admin routes answer 503.
    app.state.editor_database = editor_database
    # None without a TMDB token. TMDB searches answer 503.
    app.state.tmdb = tmdb
    # None without the Pesapal settings. Buying a pass answers 503.
    app.state.pesapal = pesapal
    if settings.passes_required and pesapal is None:
        logger.warning(
            "VELORAUG_PASSES_REQUIRED is on, but Pesapal isn't set up: "
            "viewers without a pass can't buy one"
        )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        # No cookies are used: the app sends its token in a header.
        allow_credentials=False,
        allow_methods=["GET", "PATCH", "POST", "PUT", "DELETE"],
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
    app.include_router(viewer_router)
    app.include_router(admin_router)
    app.include_router(pass_router)
    return app
