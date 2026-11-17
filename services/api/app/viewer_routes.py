"""Viewers' catalogue routes, Step 9D: VJs, editions, episodes, playback.

No sign-in is needed to browse; playback needs one. See
docs/step-09a-vj-catalogue-plan.md, section 5. The routes from Milestone 6,
/api/v1/movies, stay in app/routes.py until the app moves to these.
"""

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
from pydantic import BaseModel, StringConstraints
from starlette.background import BackgroundTask

from app import playback, viewer
from app.auth import VerifiedUser, current_user
from app.db import Database
from app.images import ImageUrls
from app.playback import Granter
from app.tmdb import DEFAULT_IMAGES

router = APIRouter(prefix="/api/v1", tags=["catalogue"])
playback_logger = logging.getLogger("veloraug.playback")

NOT_AVAILABLE = "This isn't available."
NOT_READY = "This can't be watched yet."
DETAILS_PENDING = "These details aren't available right now."
YOUTUBE = "https://www.youtube.com/watch?v="


def database(request: Request) -> Database:
    db: Database | None = request.app.state.database
    if db is None:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "The database isn't set up on this server.",
        )
    return db


AppDatabase = Annotated[Database, Depends(database)]


def images(request: Request) -> ImageUrls:
    refresher = request.app.state.refresher
    granter = request.app.state.granter
    return ImageUrls(
        tmdb=refresher.images if refresher else DEFAULT_IMAGES,
        gateway=granter.gateway if granter else None,
    )


Images = Annotated[ImageUrls, Depends(images)]
SearchText = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=2, max_length=80)
]


class EditionCard(BaseModel):
    id: UUID
    kind: str
    title: str
    year: int | None
    poster_url: str | None
    # Shown on the poster's top-left corner: the VJ's name only.
    vj_name: str | None
    vj_slug: str | None
    language: str
    # "Luganda · VJ Junior", for the edition's page.
    label: str


class EditionPage(BaseModel):
    editions: list[EditionCard]
    next_offset: int | None


class VjCard(BaseModel):
    id: UUID
    name: str
    slug: str
    photo_url: str | None
    editions: int


class VjPage(VjCard):
    bio: str | None
    movies: list[EditionCard]
    series: list[EditionCard]


class EpisodeOut(BaseModel):
    item_id: UUID
    season: int
    episode: int
    title: str | None
    playable: bool


class SeasonOut(BaseModel):
    season: int
    episodes: list[EpisodeOut]


class EditionDetailOut(EditionCard):
    source_title: str
    overview: str | None
    runtime_minutes: int | None
    genres: list[str]
    backdrop_url: str | None
    trailer_url: str | None
    vj_id: UUID | None
    vj_photo_url: str | None
    # For a movie, the item to ask playback for. Null for a series.
    item_id: UUID | None
    playable: bool
    seasons: list[SeasonOut]


class LanguageOut(BaseModel):
    code: str
    name: str
    editions: int


class PlaybackOut(BaseModel):
    playlist_url: str
    expires_at: datetime


def _card(summary: viewer.EditionSummary, images: ImageUrls) -> EditionCard:
    return EditionCard(
        id=summary.id,
        kind=summary.kind,
        title=summary.title,
        year=summary.year,
        poster_url=images.poster(summary.poster_path),
        vj_name=summary.vj_name,
        vj_slug=summary.vj_slug,
        language=summary.language,
        label=summary.label,
    )


def _vj(vj: viewer.VjSummary, images: ImageUrls) -> VjCard:
    return VjCard(
        id=vj.id,
        name=vj.name,
        slug=vj.slug,
        photo_url=images.photo(vj.photo_path),
        editions=vj.editions,
    )


@router.get("/editions")
def list_editions(
    request: Request,
    db: AppDatabase,
    images: Images,
    background: BackgroundTasks,
    kind: Literal["movie", "series"] | None = None,
    vj: Annotated[str | None, Query(max_length=80)] = None,
    language: Annotated[str | None, Query(max_length=3)] = None,
    genre: Annotated[str | None, Query(max_length=50)] = None,
    q: SearchText | None = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 24,
    offset: Annotated[int, Query(ge=0, le=10_000)] = 0,
) -> EditionPage:
    """Published editions, newest first. `vj` is a VJ's slug; `q` searches
    titles and VJ names. Needs no sign-in."""
    with db.anonymous() as conn:
        rows = viewer.list_editions(
            conn,
            limit=limit + 1,
            offset=offset,
            kind=kind,
            vj=vj,
            language=language,
            genre=genre,
            query=q,
        )
    refresher = request.app.state.refresher
    if refresher is not None and refresher.sweep_due():
        background.add_task(refresher.sweep)
    return EditionPage(
        editions=[_card(row, images) for row in rows[:limit]],
        next_offset=offset + limit if len(rows) > limit else None,
    )


@router.get(
    "/editions/{edition_id}",
    responses={
        404: {"description": NOT_AVAILABLE},
        503: {"description": DETAILS_PENDING},
    },
)
def get_edition(
    edition_id: UUID,
    request: Request,
    db: AppDatabase,
    images: Images,
    background: BackgroundTasks,
) -> EditionDetailOut:
    """One published edition: its label, details, trailer, and either its
    one video or its seasons and episodes. Needs no sign-in."""
    refresher = request.app.state.refresher
    try:
        with db.anonymous() as conn:
            detail = viewer.get_edition(conn, edition_id)
    except viewer.DetailsUnavailable as missing:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"detail": DETAILS_PENDING},
            headers={"Retry-After": "30"},
            background=(
                BackgroundTask(refresher.refresh, [(missing.kind, missing.tmdb_id)])
                if refresher is not None
                else None
            ),
        )
    if detail is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_AVAILABLE)
    if detail.stale and detail.tmdb_id is not None and refresher is not None:
        background.add_task(refresher.refresh, [(detail.summary.kind, detail.tmdb_id)])
    seasons: dict[int, list[EpisodeOut]] = {}
    for episode in detail.episodes:
        seasons.setdefault(episode.season, []).append(
            EpisodeOut(
                item_id=episode.item_id,
                season=episode.season,
                episode=episode.episode,
                title=episode.title,
                playable=episode.playable,
            )
        )
    card = _card(detail.summary, images)
    return EditionDetailOut(
        **card.model_dump(),
        source_title=detail.source_title,
        overview=detail.overview,
        runtime_minutes=detail.runtime_minutes,
        genres=detail.genres,
        backdrop_url=images.backdrop(detail.backdrop_path),
        trailer_url=f"{YOUTUBE}{detail.trailer_key}" if detail.trailer_key else None,
        vj_id=detail.vj_id,
        vj_photo_url=images.photo(detail.vj_photo_path),
        item_id=detail.movie_item,
        playable=detail.playable,
        seasons=[
            SeasonOut(season=number, episodes=episodes)
            for number, episodes in sorted(seasons.items())
        ],
    )


@router.get("/vjs")
def list_vjs(db: AppDatabase, images: Images) -> list[VjCard]:
    """VJs with something published, by name. Needs no sign-in."""
    with db.anonymous() as conn:
        return [_vj(vj, images) for vj in viewer.list_vjs(conn)]


@router.get("/vjs/{slug}", responses={404: {"description": NOT_AVAILABLE}})
def get_vj(
    slug: Annotated[str, StringConstraints(max_length=80)],
    db: AppDatabase,
    images: Images,
) -> VjPage:
    """A VJ's page: photo, name and bio, then their movies and series."""
    with db.anonymous() as conn:
        vj = viewer.get_vj(conn, slug)
        if vj is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_AVAILABLE)
        movies = viewer.list_editions(conn, limit=200, offset=0, kind="movie", vj=slug)
        series = viewer.list_editions(conn, limit=200, offset=0, kind="series", vj=slug)
    return VjPage(
        **_vj(vj, images).model_dump(),
        bio=vj.bio,
        movies=[_card(row, images) for row in movies],
        series=[_card(row, images) for row in series],
    )


@router.get("/languages")
def list_languages(db: AppDatabase) -> list[LanguageOut]:
    """Languages with published editions, for browsing by language."""
    with db.anonymous() as conn:
        return [
            LanguageOut(code=code, name=name, editions=count)
            for code, name, count in viewer.list_languages(conn)
        ]


def granter(request: Request) -> Granter:
    granter: Granter | None = request.app.state.granter
    if granter is None:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, "Playback isn't set up on this server."
        )
    return granter


@router.post(
    "/items/{item_id}/playback",
    responses={
        401: {"description": "Not signed in."},
        404: {"description": NOT_AVAILABLE},
        409: {"description": NOT_READY},
        503: {"description": "Busy, or playback isn't set up."},
    },
)
def grant_playback(
    item_id: UUID,
    user: Annotated[VerifiedUser, Depends(current_user)],
    db: AppDatabase,
    granter: Annotated[Granter, Depends(granter)],
) -> PlaybackOut:
    """A playback address for one movie edition's video, or one episode, for
    6 hours. Any signed-in viewer may watch, until passes in Milestone 10."""
    with db.as_user(user.user_id) as conn:
        visible = viewer.playable_item(conn, item_id)
        original = playback.ready_original(conn, item_id) if visible else None
    if not visible:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_AVAILABLE)
    if original is None:
        raise HTTPException(status.HTTP_409_CONFLICT, NOT_READY)
    grant = granter.grant(item_id, original)
    # The item only: never the user, the grant or the address.
    playback_logger.info("Playback granted for item %s", item_id)
    return PlaybackOut(playlist_url=grant.playlist_url, expires_at=grant.expires_at)
