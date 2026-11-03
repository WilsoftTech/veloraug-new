from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import Settings
from app.routes import router


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build the application. Tests pass their own settings."""
    settings = settings or Settings()

    app = FastAPI(title="VeloraUG API", version="0.1.0")
    app.state.settings = settings
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_credentials=False,
        allow_methods=["GET"],
    )
    app.include_router(router)
    return app
