import logging
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    HTTPException,
    Query,
    Request,
    status,
)
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, StringConstraints
from starlette.background import BackgroundTask

from app import catalogue, playback, profiles
from app.auth import VerifiedUser, current_user
from app.catalogue import DetailsUnavailable, MovieRow, Refresher
from app.db import Database
from app.playback import Granter
from app.tmdb import DEFAULT_IMAGES, ImageConfig

SERVICE_NAME = "veloraug-api"
API_VERSION = "v1"

router = APIRouter()
playback_logger = logging.getLogger("veloraug.playback")


class HealthResponse(BaseModel):
    status: Literal["ok"]


class ServiceInfoResponse(BaseModel):
    service: str
    api_version: str
    environment: str


class MeResponse(BaseModel):
    user_id: UUID
    display_name: str | None


DisplayName = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)
]


class MeUpdate(BaseModel):
    # Other fields, such as a user_id, are ignored: the user is always the
    # one in the token.
    model_config = ConfigDict(extra="ignore")

    display_name: DisplayName | None


def database(request: Request) -> Database:
    db: Database | None = request.app.state.database
    if db is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The database isn't set up on this server.",
        )
    return db


SignedInUser = Annotated[VerifiedUser, Depends(current_user)]
AppDatabase = Annotated[Database, Depends(database)]


class MovieSummary(BaseModel):
    id: UUID
    title: str
    year: int | None
    poster_url: str | None


class MovieList(BaseModel):
    movies: list[MovieSummary]
    # The offset for the next page, or null on the last one.
    next_offset: int | None


class MovieDetail(BaseModel):
    id: UUID
    title: str
    year: int | None
    overview: str | None
    runtime_minutes: int | None
    genres: list[str]
    poster_url: str | None
    backdrop_url: str | None
    # True when there is something to watch: a ready original.
    playable: bool


class PlaybackResponse(BaseModel):
    # The Worker's address for the master playlist, with the grant in its
    # path. It works for anyone holding it until expires_at.
    playlist_url: str
    expires_at: datetime


SearchText = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=2, max_length=80)
]
NOT_AVAILABLE = "This movie isn't available."
NOT_READY = "This movie can't be watched yet."
PLAYBACK_OFF = "Playback isn't set up on this server."
DETAILS_PENDING = "This movie's details aren't available right now."


def refresher(request: Request) -> Refresher | None:
    return request.app.state.refresher


AppRefresher = Annotated[Refresher | None, Depends(refresher)]


def _images(refresher: Refresher | None) -> ImageConfig:
    return refresher.images if refresher else DEFAULT_IMAGES


def _summary(row: MovieRow, images: ImageConfig) -> MovieSummary:
    return MovieSummary(
        id=row.id,
        title=row.title,
        year=row.year,
        poster_url=images.poster_url(row.poster_path),
    )


@router.get("/health")
def health() -> HealthResponse:
    """Report that this process can answer HTTP requests.

    This does not check a database or any external service.
    """
    return HealthResponse(status="ok")


@router.get("/api/v1")
def service_info(request: Request) -> ServiceInfoResponse:
    """Identify this service and the API version it serves."""
    return ServiceInfoResponse(
        service=SERVICE_NAME,
        api_version=API_VERSION,
        environment=request.app.state.settings.environment,
    )


@router.get("/api/v1/me")
def me(user: SignedInUser, db: AppDatabase) -> MeResponse:
    """The signed-in user's profile, created on first use.

    Answers 401 without a valid token, and 503 when the token or the
    database can't be checked.
    """
    with db.as_user(user.user_id) as conn:
        profile = profiles.get_or_create(conn, user.user_id)
    return MeResponse(user_id=profile.user_id, display_name=profile.display_name)


@router.get("/api/v1/movies")
def list_movies(
    db: AppDatabase,
    refresher: AppRefresher,
    background: BackgroundTasks,
    q: Annotated[SearchText | None, Query(description="Part of a title")] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 24,
    offset: Annotated[int, Query(ge=0, le=10_000)] = 0,
) -> MovieList:
    """Published movies, newest first, or matching a title when q is given.

    Needs no sign-in. Movies whose details aren't available yet are left out.
    """
    with db.anonymous() as conn:
        rows = catalogue.list_movies(conn, limit=limit + 1, offset=offset, query=q)
    more = len(rows) > limit
    rows = rows[:limit]
    if refresher is not None:
        stale = [row.tmdb_id for row in rows if row.stale]
        if stale:
            background.add_task(refresher.refresh, stale)
        if refresher.sweep_due():
            background.add_task(refresher.sweep)
    images = _images(refresher)
    return MovieList(
        movies=[_summary(row, images) for row in rows],
        next_offset=offset + limit if more else None,
    )


@router.get(
    "/api/v1/movies/{movie_id}",
    responses={
        404: {"description": NOT_AVAILABLE},
        503: {"description": DETAILS_PENDING},
    },
)
def get_movie(
    movie_id: UUID,
    db: AppDatabase,
    refresher: AppRefresher,
    background: BackgroundTasks,
) -> MovieDetail:
    """One published movie. Needs no sign-in.

    Answers 404 if it doesn't exist or isn't published, with the same message
    for both, and 503 while its details are being fetched.
    """
    try:
        with db.anonymous() as conn:
            row = catalogue.get_movie(conn, movie_id)
            item = catalogue.movie_item(conn, movie_id) if row else None
            original = playback.ready_original(conn, item) if item else None
    except DetailsUnavailable as missing:
        # Returned, not raised: FastAPI runs background tasks only for a
        # response the route returns, and this one must fetch the details.
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"detail": DETAILS_PENDING},
            headers={"Retry-After": "30"},
            background=(
                BackgroundTask(refresher.refresh, [missing.tmdb_id])
                if refresher is not None
                else None
            ),
        )
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=NOT_AVAILABLE)
    if row.stale and row.tmdb_id is not None and refresher is not None:
        background.add_task(refresher.refresh, [row.tmdb_id])
    images = _images(refresher)
    return MovieDetail(
        id=row.id,
        title=row.title,
        year=row.year,
        overview=row.overview,
        runtime_minutes=row.runtime_minutes,
        genres=list(row.genres),
        poster_url=images.poster_url(row.poster_path),
        backdrop_url=images.backdrop_url(row.backdrop_path),
        playable=original is not None,
    )


def granter(request: Request) -> Granter:
    granter: Granter | None = request.app.state.granter
    if granter is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=PLAYBACK_OFF
        )
    return granter


@router.post(
    "/api/v1/movies/{movie_id}/playback",
    responses={
        401: {"description": "Not signed in."},
        404: {"description": NOT_AVAILABLE},
        409: {"description": NOT_READY},
        503: {"description": "Busy, or playback isn't set up."},
    },
)
def grant_playback(
    movie_id: UUID,
    user: SignedInUser,
    db: AppDatabase,
    granter: Annotated[Granter, Depends(granter)],
) -> PlaybackResponse:
    """A playback address for one published, ready movie, for 6 hours.

    Any signed-in viewer may watch, until payments arrive in Milestone 10.
    Answers 404 for a movie that doesn't exist or isn't published, and 409
    for one with nothing ready to watch. The movie is a movie edition; the
    grant names its playable item.
    """
    with db.as_user(user.user_id) as conn:
        item = catalogue.movie_item(conn, movie_id)
        original = playback.ready_original(conn, item) if item is not None else None
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=NOT_AVAILABLE)
    if original is None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=NOT_READY)
    grant = granter.grant(item, original)
    # The item only: never the user, the grant or the address.
    playback_logger.info("Playback granted for item %s", item)
    return PlaybackResponse(
        playlist_url=grant.playlist_url, expires_at=grant.expires_at
    )


@router.patch("/api/v1/me")
def update_me(user: SignedInUser, db: AppDatabase, update: MeUpdate) -> MeResponse:
    """Changes the signed-in user's display name. null clears it."""
    with db.as_user(user.user_id) as conn:
        profile = profiles.set_display_name(conn, user.user_id, update.display_name)
    return MeResponse(user_id=profile.user_id, display_name=profile.display_name)
