"""Viewers' catalogue routes, Step 9D: VJs, editions, episodes, playback.

No sign-in is needed to browse; playback needs one. See
docs/step-09a-vj-catalogue-plan.md, section 5. The routes from Milestone 6,
/api/v1/movies, stay in app/routes.py until the app moves to these.
"""

import logging
from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    Header,
    HTTPException,
    Query,
    Request,
    status,
)
from fastapi.responses import JSONResponse
from pydantic import BaseModel, StringConstraints
from starlette.background import BackgroundTask

from app import account, devices, discovery, passes, playback, ratelimit, viewer
from app.auth import VerifiedUser, current_user
from app.db import Database
from app.images import ImageUrls
from app.playback import Granter
from app.tmdb import DEFAULT_IMAGES

router = APIRouter(prefix="/api/v1", tags=["catalogue"])
playback_logger = logging.getLogger("veloraug.playback")

NOT_AVAILABLE = "This isn't available."
NOT_READY = "This can't be watched yet."
NEEDS_PASS = "You need a pass to watch."
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
    # TMDB's score for the source title, out of 10 with one decimal. Null
    # when there is none or too few votes: the app shows nothing then.
    rating: float | None = None


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
    # How many TMDB votes the rating is from. Null whenever rating is.
    vote_count: int | None = None
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


class FeaturedOut(EditionCard):
    """A title in Home's hero. Every one has something to watch."""

    genres: list[str]
    # Wide enough for a desktop screen. Null without a TMDB backdrop: the
    # app shows the poster instead.
    backdrop_url: str | None
    # For a movie, the item to ask playback for. Null for a series, which
    # opens its page to choose an episode.
    item_id: UUID | None


class RailOut(BaseModel):
    # vj, recommended, popular, top_rated, recent or new_episodes. The app
    # names it: "More from VJ Junior", "Recommended for you" and so on.
    key: str
    editions: list[EditionCard]


class RailsOut(BaseModel):
    # Only rails with at least three titles, in the order to show them.
    rails: list[RailOut]


class LanguageOut(BaseModel):
    code: str
    name: str
    editions: int


class GenreOut(BaseModel):
    # Exactly as stored, so it can be passed back as /editions?genre=.
    name: str
    editions: int


class PlaybackOut(BaseModel):
    playlist_url: str
    expires_at: datetime
    # With passes required: the playback session, which the player keeps
    # alive every heartbeat_seconds.
    session_id: UUID | None = None
    heartbeat_seconds: int | None = None


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
        rating=summary.rating,
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
        vote_count=detail.summary.vote_count,
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


@router.get("/featured")
def list_featured(
    request: Request,
    db: AppDatabase,
    images: Images,
    background: BackgroundTasks,
) -> list[FeaturedOut]:
    """The newest published titles with something to watch, for Home's
    hero: at most three, test films left out. Needs no sign-in."""
    with db.anonymous() as conn:
        rows = viewer.list_featured(conn)
    refresher = request.app.state.refresher
    if refresher is not None and refresher.sweep_due():
        background.add_task(refresher.sweep)
    return [
        FeaturedOut(
            **_card(row.summary, images).model_dump(),
            genres=row.genres,
            backdrop_url=images.hero_backdrop(row.backdrop_path),
            item_id=row.movie_item,
        )
        for row in rows
    ]


@router.get(
    "/editions/{edition_id}/rails",
    responses={404: {"description": NOT_AVAILABLE}},
)
def edition_rails(edition_id: UUID, db: AppDatabase, images: Images) -> RailsOut:
    """Titles to discover from a published edition's page: more from its
    VJ, recommended, most popular, top rated, and recently added movies or
    new episodes. Needs no sign-in."""
    with db.anonymous() as conn:
        found = discovery.rails(conn, edition_id)
    if found is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_AVAILABLE)
    return RailsOut(
        rails=[
            RailOut(key=rail.key, editions=[_card(e, images) for e in rail.editions])
            for rail in found
        ]
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


@router.get("/genres")
def list_genres(db: AppDatabase) -> list[GenreOut]:
    """Genres with published editions, most editions first, for browsing and
    filtering by genre. Each name is the exact value /editions?genre=
    matches. Needs no sign-in."""
    with db.anonymous() as conn:
        return [
            GenreOut(name=name, editions=count)
            for name, count in viewer.list_genres(conn)
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
        402: {"description": NEEDS_PASS},
        403: {"description": "This device isn't registered, or was removed."},
        404: {"description": NOT_AVAILABLE},
        409: {"description": NOT_READY + " Or a device or stream limit."},
        429: {"description": "Too many requests."},
        503: {"description": "Busy, or playback isn't set up."},
    },
)
def grant_playback(
    item_id: UUID,
    request: Request,
    user: Annotated[VerifiedUser, Depends(current_user)],
    db: AppDatabase,
    granter: Annotated[Granter, Depends(granter)],
    device_credential: Annotated[
        str | None, Header(alias=devices.HEADER, max_length=100)
    ] = None,
) -> PlaybackOut:
    """A playback address for one movie edition's video, or one episode.

    With passes off, or for an admin, as before: 6 hours. With passes
    required, a viewer also needs, in order: a running pass (402), this
    device registered to them (403, code `device_required`), no more
    devices than their plan allows (409, `device_limit`), and a free stream
    (409, `stream_limit`). The address is then bound to a new playback
    session, ends no later than the pass, and stops working within a minute
    of the session ending."""
    settings = request.app.state.settings
    limiter = request.app.state.rate_limiter
    limiter.check("playback", str(user.user_id), ratelimit.PLAYBACK)
    until = None
    session_id = None
    with db.as_user(user.user_id) as conn:
        visible = viewer.playable_item(conn, item_id)
        original = playback.ready_original(conn, item_id) if visible else None
        if (
            visible
            and original is not None
            and settings.passes_required
            and not passes.is_admin(conn, user.user_id)
        ):
            now = datetime.now(UTC)
            entitlement = passes.current_entitlement(conn, user.user_id, now)
            if entitlement is None:
                raise HTTPException(status.HTTP_402_PAYMENT_REQUIRED, NEEDS_PASS)
            device = devices.authenticate(conn, device_credential)
            if device is None:
                raise HTTPException(
                    status.HTTP_403_FORBIDDEN,
                    {"code": "device_required", "message": DEVICE_REQUIRED},
                )
            try:
                session_id = devices.start_session(
                    conn, user.user_id, device, entitlement, item_id, now
                )
            except devices.DeviceProblem as problem:
                raise device_refusal(problem) from None
            until = entitlement.ends_at
        if visible and original is not None:
            account.record_playback_grant(conn, user.user_id, item_id)
    if not visible:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_AVAILABLE)
    if original is None:
        raise HTTPException(status.HTTP_409_CONFLICT, NOT_READY)
    grant = granter.grant(item_id, original, until=until, session_id=session_id)
    # The item only: never the user, the grant or the address.
    playback_logger.info("Playback granted for item %s", item_id)
    return PlaybackOut(
        playlist_url=grant.playlist_url,
        expires_at=grant.expires_at,
        session_id=session_id,
        heartbeat_seconds=devices.HEARTBEAT_SECONDS if session_id else None,
    )


DEVICE_REQUIRED = "Register this device to watch on it."


class DownloadOut(BaseModel):
    playlist_url: str
    expires_at: datetime
    # Each quality's file is <quality>/download.mp4 beside the playlist. The
    # app adds ?name=<file_name> - <quality>.mp4 to it.
    file_name: str


def _check_download(
    conn, user_id: UUID, settings, device_credential: str | None, now: datetime
):
    """With passes required, and not an admin: a running pass (402), this
    device registered (403 `device_required`) and no more devices than the
    pass allows (409 `device_limit`). Answers the pass, or None."""
    if not settings.passes_required or passes.is_admin(conn, user_id):
        return None
    entitlement = passes.current_entitlement(conn, user_id, now)
    if entitlement is None:
        raise HTTPException(status.HTTP_402_PAYMENT_REQUIRED, NEEDS_PASS)
    device = devices.authenticate(conn, device_credential)
    if device is None:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            {"code": "device_required", "message": DEVICE_REQUIRED},
        )
    try:
        devices.check_device_limit(conn, entitlement)
    except devices.DeviceProblem as problem:
        raise device_refusal(problem) from None
    return entitlement


@router.post(
    "/items/{item_id}/download",
    responses={
        401: {"description": "Not signed in."},
        402: {"description": NEEDS_PASS},
        403: {"description": "This device isn't registered, or was removed."},
        404: {"description": NOT_AVAILABLE},
        409: {"description": NOT_READY + " Or a device limit."},
        429: {"description": "Too many requests."},
        503: {"description": "Busy, or playback isn't set up."},
    },
)
def grant_download(
    item_id: UUID,
    request: Request,
    user: Annotated[VerifiedUser, Depends(current_user)],
    db: AppDatabase,
    granter: Annotated[Granter, Depends(granter)],
    device_credential: Annotated[
        str | None, Header(alias=devices.HEADER, max_length=100)
    ] = None,
) -> DownloadOut:
    """Where to download one item's video as an .mp4 file, kept by the
    viewer on their phone or computer.

    The same checks as playback, but the grant has no playback session: a
    download takes no stream, and the browser's or Android's own downloader,
    which can't renew a grant, fetches the file. So it lasts
    DOWNLOAD_GRANT_SECONDS, and no later than the pass. Once downloaded, the
    file is the viewer's: nothing checks it again."""
    settings = request.app.state.settings
    limiter = request.app.state.rate_limiter
    limiter.check("playback", str(user.user_id), ratelimit.PLAYBACK)
    now = datetime.now(UTC)
    with db.as_user(user.user_id) as conn:
        visible = viewer.playable_item(conn, item_id)
        original = playback.ready_original(conn, item_id) if visible else None
        entitlement = None
        name = None
        if visible and original is not None:
            entitlement = _check_download(
                conn, user.user_id, settings, device_credential, now
            )
            name = viewer.download_name(conn, item_id)
    if not visible:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_AVAILABLE)
    if original is None or name is None:
        raise HTTPException(status.HTTP_409_CONFLICT, NOT_READY)
    grant = granter.grant(
        item_id,
        original,
        until=entitlement.ends_at if entitlement else None,
        seconds=playback.DOWNLOAD_GRANT_SECONDS,
    )
    playback_logger.info("Download granted for item %s", item_id)
    return DownloadOut(
        playlist_url=grant.playlist_url,
        expires_at=grant.expires_at,
        file_name=name,
    )


def device_refusal(problem: devices.DeviceProblem) -> HTTPException:
    """409 for a device or stream limit, 429 for too many new devices, with
    a code the app understands and the details it shows."""
    code = (
        status.HTTP_429_TOO_MANY_REQUESTS
        if isinstance(problem, devices.SwitchLimit)
        else status.HTTP_409_CONFLICT
    )
    return HTTPException(
        code, {"code": problem.code, "message": str(problem), **problem.details}
    )
