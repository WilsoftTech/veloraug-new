"""The admin routes, /api/v1/admin/..., Step 9C.

Every route needs a signed-in user listed in public.admins, checked on each
request, and connects as veloraug_editor. The work is in app/admin_catalogue.py
and app/editions.py. See docs/step-09a-vj-catalogue-plan.md, section 5.

The log names the admin and what changed, never an upload key or a grant.
"""

import logging
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import asdict
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status
from psycopg.errors import UniqueViolation
from pydantic import BaseModel, Field, StringConstraints

from app import admin_catalogue as work
from app import audit, editions
from app.admin_catalogue import AdminError, NotFound
from app.auth import VerifiedUser, current_user
from app.db import Database
from app.editions import EditionError, PublishRefused
from app.images import ImageUrls
from app.matching import clean_title, clear_match
from app.playback import Granter, image_path
from app.tmdb import DEFAULT_IMAGES, TmdbClient, TmdbError, TmdbNotFound

logger = logging.getLogger("veloraug.admin")
router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

NOT_ADMIN = "This account isn't an admin."
EDITOR_OFF = "The admin screens aren't set up on this server."
TMDB_OFF = "TMDB isn't set up on this server."


# --- Dependencies ------------------------------------------------------------


def editor_database(request: Request) -> Database:
    db: Database | None = request.app.state.editor_database
    if db is None:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, EDITOR_OFF)
    return db


EditorDatabase = Annotated[Database, Depends(editor_database)]


def admin_user(
    user: Annotated[VerifiedUser, Depends(current_user)], db: EditorDatabase
) -> VerifiedUser:
    """The signed-in user, if they are an admin now. 403 otherwise."""
    with db.as_user(user.user_id) as conn:
        if not work.is_admin(conn, user.user_id):
            logger.info("Admin refused: user %s isn't an admin", user.user_id)
            raise HTTPException(status.HTTP_403_FORBIDDEN, NOT_ADMIN)
    return user


AdminUser = Annotated[VerifiedUser, Depends(admin_user)]


def tmdb_client(request: Request) -> TmdbClient:
    client: TmdbClient | None = request.app.state.tmdb
    if client is None:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, TMDB_OFF)
    return client


def images(request: Request) -> ImageUrls:
    refresher = request.app.state.refresher
    return ImageUrls(
        tmdb=refresher.images if refresher else DEFAULT_IMAGES,
        gateway=granter.gateway if (granter := request.app.state.granter) else None,
    )


Images = Annotated[ImageUrls, Depends(images)]


@contextmanager
def editing(db: Database, user: VerifiedUser) -> Iterator:
    """A transaction as the editor, with mistakes turned into answers."""
    try:
        with db.as_user(user.user_id) as conn:
            yield conn
    except PublishRefused as refused:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            {"message": str(refused), "missing": refused.missing},
        ) from None
    except NotFound as missing:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(missing)) from None
    except EditionError as error:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(error)) from None
    except UniqueViolation as error:
        if error.diag.constraint_name != "editions_one_series_per_vj_idx":
            raise
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "This VJ already has an edition of that series"
        ) from None


# --- Shapes ------------------------------------------------------------------

Title = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)
]
Label = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)
]


class Me(BaseModel):
    user_id: UUID
    admin: bool


class NewDraft(BaseModel):
    kind: Literal["movie", "series"]
    # Not needed when adding an episode to an existing series edition.
    title: Title | None = None
    year: int | None = Field(default=None, ge=1900, le=2100)
    language: str = editions.DEFAULT_LANGUAGE
    series_edition_id: UUID | None = None
    season: int | None = Field(default=None, ge=0, le=999)
    episode: int | None = Field(default=None, ge=1, le=9999)
    episode_title: Annotated[str, StringConstraints(max_length=200)] | None = None
    key_label: Label = "Owner"
    key_days: int = Field(default=work.KEY_DAYS, ge=1, le=work.MAX_KEY_DAYS)


class KeyMade(BaseModel):
    key_id: UUID
    # Shown once. Never logged or stored.
    upload_key: str
    expires_at: datetime


class DraftMade(KeyMade):
    edition_id: UUID
    item_id: UUID


class NewKey(BaseModel):
    label: Label
    days: int = Field(default=work.KEY_DAYS, ge=1, le=work.MAX_KEY_DAYS)


class Match(BaseModel):
    tmdb_id: int
    title: str
    original_title: str | None
    year: int | None
    overview: str | None
    poster_url: str | None


class Item(BaseModel):
    id: UUID
    season: int | None
    episode: int | None
    episode_title: str | None
    approved: bool
    video: str | None
    video_reason: str | None
    previewable: bool
    filename: str | None
    credit_hints: str | None
    keys: list[dict]
    # From the media worker, while it converts or publishes: 0 to 100.
    progress: int | None = None
    eta_seconds: int | None = None
    # Waiting to be converted: its place in the queue, from 1.
    queue_position: int | None = None
    size_bytes: int | None = None


class Edition(BaseModel):
    id: UUID
    kind: str
    display_title: str
    submitted_year: int | None
    language: str
    status: str
    test: bool
    tmdb_lookup: str | None
    source_tmdb_id: int | None
    source_title: str | None
    source_year: int | None
    source_overview: str | None
    details_from: str | None
    poster_path: str | None
    poster_url: str | None
    vj_id: UUID | None
    vj_name: str | None
    created_at: datetime
    items: list[Item]
    missing: list[str]
    matches: list[Match]
    categories: list[str] = []
    # No video has finished uploading yet.
    incomplete: bool = False


class EditionList(BaseModel):
    editions: list[Edition]


class SeriesOut(BaseModel):
    id: UUID
    display_title: str
    language: str
    status: str
    vj_id: UUID | None
    vj_name: str | None
    # [season, episode] pairs.
    episodes: list[tuple[int | None, int | None]]


class TitleChange(BaseModel):
    display_title: Title


class Search(BaseModel):
    title: Title | None = None
    year: int | None = Field(default=None, ge=1900, le=2100)


class ManualDetails(BaseModel):
    title: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)
    ]
    overview: Annotated[str, StringConstraints(max_length=5000)] | None = None
    year: int | None = Field(default=None, ge=1900, le=2100)
    genres: list[Annotated[str, StringConstraints(max_length=50)]] = Field(
        default_factory=list, max_length=10
    )
    runtime_minutes: int | None = Field(default=None, ge=1, le=1000)


class SourceChoice(BaseModel):
    tmdb_id: int | None = Field(default=None, gt=0)
    manual: ManualDetails | None = None
    reuse_edition_id: UUID | None = None


class MovieMetadataChoice(BaseModel):
    id: UUID
    title: str
    poster_url: str | None
    vj_name: str | None


class Lookup(BaseModel):
    outcome: str
    edition: Edition


class Posters(BaseModel):
    chosen: str | None
    options: list[dict]


class PosterChoice(BaseModel):
    path: Annotated[str, StringConstraints(max_length=300)]


class CreditSuggestion(BaseModel):
    vj_id: UUID | None
    name: str
    found_in: str


class Credit(BaseModel):
    vj_id: UUID | None
    vj_name: str | None
    suggestions: list[CreditSuggestion]


class CreditChoice(BaseModel):
    vj_id: UUID | None = None
    # Adds a VJ with this name and credits them.
    new_vj: (
        Annotated[
            str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)
        ]
        | None
    ) = None


class CategoryOut(BaseModel):
    id: UUID
    name: str
    slug: str
    editions: int


class Categories(BaseModel):
    # Checked again, after trimming, by admin_catalogue.set_categories.
    names: list[Annotated[str, StringConstraints(max_length=200)]] = Field(
        max_length=50
    )


class Preview(BaseModel):
    playlist_url: str
    expires_at: datetime


class VjOut(BaseModel):
    id: UUID
    name: str
    slug: str
    match_names: list[str]
    photo_path: str | None
    photo_url: str | None = None
    bio: str | None
    editions: int


class VjIn(BaseModel):
    name: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)
    ]
    match_names: list[Annotated[str, StringConstraints(max_length=80)]] = Field(
        default_factory=list, max_length=20
    )
    bio: Annotated[str, StringConstraints(max_length=1000)] | None = None


class VjChange(BaseModel):
    name: (
        Annotated[
            str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)
        ]
        | None
    ) = None
    match_names: list[Annotated[str, StringConstraints(max_length=80)]] | None = Field(
        default=None, max_length=20
    )
    bio: Annotated[str, StringConstraints(max_length=1000)] | None = None
    # The path an image upload answered with, or "" to remove the photo.
    photo_path: Annotated[str, StringConstraints(max_length=300)] | None = None


class ImageUpload(BaseModel):
    folder: Literal["posters", "vjs"]
    # The edition the poster is for, or the VJ the photo is of.
    owner_id: UUID
    content_type: Literal["image/jpeg", "image/png", "image/webp"]


class ImageUploadAddress(BaseModel):
    # PUT the image here, with this Content-Type, within 10 minutes. At most
    # 2 MB. Then choose the path as the poster, or as the VJ's photo.
    upload_url: str
    path: str
    expires_at: datetime


class Language(BaseModel):
    code: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=2, max_length=3)
    ]
    name: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=50)
    ]


class AdminOut(BaseModel):
    user_id: UUID
    email: str | None
    added_by_email: str | None
    added_at: datetime


class NewAdmin(BaseModel):
    email: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=3, max_length=320)
    ]


def _edition(state: work.EditionState, images: ImageUrls) -> Edition:
    poster_url = images.poster

    return Edition(
        id=state.id,
        kind=state.kind,
        display_title=state.display_title,
        submitted_year=state.submitted_year,
        language=state.language,
        status=state.status,
        test=state.test,
        tmdb_lookup=state.tmdb_lookup,
        source_tmdb_id=state.source_tmdb_id,
        source_title=state.source_title,
        source_year=state.source_year,
        source_overview=state.source_overview,
        details_from=state.details_from,
        poster_path=state.poster_path,
        poster_url=poster_url(state.poster_path),
        vj_id=state.vj_id,
        vj_name=state.vj_name,
        created_at=state.created_at,
        items=[
            Item(
                id=item.id,
                season=item.season,
                episode=item.episode,
                episode_title=item.episode_title,
                approved=item.approved,
                video=item.video,
                video_reason=item.video_reason,
                previewable=item.ready_original is not None,
                filename=item.filename,
                credit_hints=item.credit_hints,
                keys=item.keys,
                progress=item.progress,
                eta_seconds=item.eta_seconds,
                queue_position=item.queue_position,
                size_bytes=item.size_bytes,
            )
            for item in state.items
        ],
        missing=state.missing,
        categories=state.categories,
        incomplete=state.incomplete,
        matches=[
            Match(
                tmdb_id=m.tmdb_id,
                title=m.title,
                original_title=m.original_title,
                year=m.year,
                overview=m.overview,
                poster_url=poster_url(m.poster_path),
            )
            for m in state.matches
        ],
    )


def _current(db: Database, user: VerifiedUser, edition_id: UUID, images: ImageUrls):
    with editing(db, user) as conn:
        return _edition(work.get_edition(conn, edition_id), images)


# --- TMDB lookups ------------------------------------------------------------


def run_lookup(
    db: Database,
    client: TmdbClient,
    user_id: UUID,
    edition_id: UUID,
    title: str | None = None,
    year: int | None = None,
) -> str:
    """Searches TMDB for the edition, then prefills it from a clear match,
    keeps the candidates, or records that nothing was found. TMDB is asked
    between transactions."""
    with db.as_user(user_id) as conn:
        state = work.get_edition(conn, edition_id)
        names = [vj.name for vj in work.known_vjs(conn)]
    cleaned, found_year = clean_title(title or state.display_title, names)
    year = year or state.submitted_year or found_year
    try:
        results = client.search(state.kind, cleaned, year)
        if not results and year is not None:
            results = client.search(state.kind, cleaned)
    except TmdbError as error:
        logger.warning("TMDB search for edition %s failed: %s", edition_id, error)
        with db.as_user(user_id) as conn:
            work.lookup_failed(conn, edition_id, "failed")
        return "failed"
    if not results:
        with db.as_user(user_id) as conn:
            work.lookup_failed(conn, edition_id, "none")
        return "none"
    match = clear_match(results, cleaned, year)
    if match is None:
        with db.as_user(user_id) as conn:
            work.save_matches(conn, edition_id, results)
        return "choose"
    try:
        use_tmdb_title(
            db, client, user_id, edition_id, state.kind, match.tmdb_id, "clear"
        )
    except (TmdbError, AdminError) as error:
        logger.warning("TMDB details for edition %s failed: %s", edition_id, error)
        with db.as_user(user_id) as conn:
            work.save_matches(conn, edition_id, results)
        return "choose"
    return "clear"


def use_tmdb_title(
    db: Database,
    client: TmdbClient,
    user_id: UUID,
    edition_id: UUID,
    kind: str,
    tmdb_id: int,
    outcome: str,
) -> None:
    details = client.details(kind, tmdb_id)
    try:
        trailer = client.trailer(kind, tmdb_id)
    except TmdbError:
        trailer = None
    try:
        posters = client.posters(kind, tmdb_id)
    except TmdbError:
        posters = []
    with db.as_user(user_id) as conn:
        work.use_source(
            conn, edition_id, details, trailer=trailer, posters=posters, outcome=outcome
        )


def lookups_in_background(db: Database, client: TmdbClient, user_id: UUID) -> None:
    """Looks up drafts whose video has become ready, after answering."""
    try:
        with db.as_user(user_id) as conn:
            due = work.due_for_lookup(conn)
        for edition_id in due:
            outcome = run_lookup(db, client, user_id, edition_id)
            logger.info("TMDB lookup for edition %s: %s", edition_id, outcome)
    except Exception as error:  # A background task has nobody to tell.
        logger.warning("Background TMDB lookups stopped: %s", type(error).__name__)


# --- Routes: who is asking ---------------------------------------------------


@router.get("/me")
def me(user: AdminUser) -> Me:
    """200 for an admin, 403 for anyone else signed in. The app shows its
    Admin menu on 200."""
    return Me(user_id=user.user_id, admin=True)


# --- Drafts and editions -----------------------------------------------------


@router.get("/drafts")
def list_drafts(
    request: Request,
    user: AdminUser,
    db: EditorDatabase,
    images: Images,
    background: BackgroundTasks,
) -> EditionList:
    """Drafts, hidden editions and series with episodes waiting, each with
    what it still needs. Drafts whose video has just become ready are
    looked up on TMDB after answering."""
    with editing(db, user) as conn:
        # Deleted drafts whose files the worker has removed by now.
        work.purge_deleted(conn)
        found = work.list_work(conn)
        due = work.due_for_lookup(conn, limit=1)
    client = request.app.state.tmdb
    if due and client is not None:
        background.add_task(lookups_in_background, db, client, user.user_id)
    return EditionList(editions=[_edition(state, images) for state in found])


@router.get("/series")
def list_series(user: AdminUser, db: EditorDatabase) -> list[SeriesOut]:
    """Every series edition, in any state, with its episodes' numbers, so the
    upload screen can add a dropped episode to the series it belongs to."""
    with editing(db, user) as conn:
        return [SeriesOut(**asdict(s)) for s in work.list_series(conn)]


@router.post("/drafts", status_code=status.HTTP_201_CREATED)
def create_draft(body: NewDraft, user: AdminUser, db: EditorDatabase) -> DraftMade:
    """Starts a draft, or adds an episode to a series edition, and makes its
    upload key. The key is in this answer only."""
    with editing(db, user) as conn:
        draft = editions.create_draft(
            conn,
            kind=body.kind,
            title=body.title,
            year=body.year,
            language=body.language,
            series_edition=body.series_edition_id,
            season=body.season,
            episode=body.episode,
            episode_title=body.episode_title,
        )
        key_id, text, expires_at = work.make_key(
            conn, draft.item_id, body.key_label, body.key_days
        )
    logger.info(
        "Admin %s started draft %s, item %s",
        user.user_id,
        draft.edition_id,
        draft.item_id,
    )
    return DraftMade(
        edition_id=draft.edition_id,
        item_id=draft.item_id,
        key_id=key_id,
        upload_key=text,
        expires_at=expires_at,
    )


@router.get("/editions/{edition_id}")
def get_edition(
    edition_id: UUID, user: AdminUser, db: EditorDatabase, images: Images
) -> Edition:
    return _current(db, user, edition_id, images)


@router.patch("/editions/{edition_id}")
def change_edition(
    edition_id: UUID,
    body: TitleChange,
    user: AdminUser,
    db: EditorDatabase,
    images: Images,
) -> Edition:
    """Changes the title viewers see."""
    with editing(db, user) as conn:
        work.set_title(conn, edition_id, body.display_title)
    return _current(db, user, edition_id, images)


@router.post("/editions/{edition_id}/tmdb/search")
def search_tmdb(
    edition_id: UUID,
    body: Search,
    user: AdminUser,
    db: EditorDatabase,
    images: Images,
    client: Annotated[TmdbClient, Depends(tmdb_client)],
) -> Lookup:
    """Searches TMDB again, optionally with a corrected title or year."""
    with editing(db, user) as conn:
        work.get_edition(conn, edition_id)
    outcome = run_lookup(db, client, user.user_id, edition_id, body.title, body.year)
    return Lookup(outcome=outcome, edition=_current(db, user, edition_id, images))


@router.get("/editions/{edition_id}/movie-metadata")
def movie_metadata_options(
    edition_id: UUID,
    q: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=2, max_length=120)
    ],
    user: AdminUser,
    db: EditorDatabase,
    images: Images,
) -> list[MovieMetadataChoice]:
    with editing(db, user) as conn:
        return [
            MovieMetadataChoice(
                id=id_, title=title, poster_url=images.poster(poster), vj_name=vj
            )
            for id_, title, poster, vj in work.movie_metadata_candidates(
                conn, edition_id, q
            )
        ]


@router.put("/editions/{edition_id}/source")
def choose_source(
    edition_id: UUID,
    body: SourceChoice,
    request: Request,
    user: AdminUser,
    db: EditorDatabase,
    images: Images,
) -> Edition:
    """Choose TMDB details, type them in, or reuse a published movie's details."""
    if (
        sum(
            value is not None
            for value in (body.tmdb_id, body.manual, body.reuse_edition_id)
        )
        != 1
    ):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "Choose one source for the title details"
        )
    if body.reuse_edition_id is not None:
        with editing(db, user) as conn:
            work.reuse_movie_metadata(conn, edition_id, body.reuse_edition_id)
    elif body.manual is not None:
        with editing(db, user) as conn:
            work.use_manual_details(conn, edition_id, **body.manual.model_dump())
    else:
        client = tmdb_client(request)
        with editing(db, user) as conn:
            kind, _ = work.source_of(conn, edition_id)
        try:
            use_tmdb_title(
                db, client, user.user_id, edition_id, kind, body.tmdb_id, "chosen"
            )
        except TmdbNotFound:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND,
                f"TMDB has no {kind} {body.tmdb_id}",
            ) from None
        except TmdbError as error:
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE, str(error)
            ) from None
        except NotFound as missing:
            raise HTTPException(status.HTTP_404_NOT_FOUND, str(missing)) from None
        except EditionError as error:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, str(error)) from None
    logger.info("Admin %s set the source of edition %s", user.user_id, edition_id)
    return _current(db, user, edition_id, images)


@router.get("/editions/{edition_id}/posters")
def poster_options(
    edition_id: UUID,
    user: AdminUser,
    db: EditorDatabase,
    images: Images,
    client: Annotated[TmdbClient, Depends(tmdb_client)],
) -> Posters:
    """The eligible TMDB posters for the edition's source, to choose from."""
    with editing(db, user) as conn:
        kind, tmdb_id = work.source_of(conn, edition_id)
        chosen = work.get_edition(conn, edition_id).poster_path
    paths: list[str] = []
    if tmdb_id is not None:
        try:
            paths = client.posters(kind, tmdb_id)
        except TmdbError as error:
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE, str(error)
            ) from None
    return Posters(
        chosen=chosen,
        options=[{"path": path, "url": images.poster(path)} for path in paths],
    )


@router.put("/editions/{edition_id}/poster")
def choose_poster(
    edition_id: UUID,
    body: PosterChoice,
    user: AdminUser,
    db: EditorDatabase,
    images: Images,
) -> Edition:
    with editing(db, user) as conn:
        work.set_poster(conn, edition_id, body.path)
    return _current(db, user, edition_id, images)


@router.get("/editions/{edition_id}/credit")
def credit(edition_id: UUID, user: AdminUser, db: EditorDatabase) -> Credit:
    """The VJ credited, if any, and the VJs the files seem to name."""
    with editing(db, user) as conn:
        state = work.get_edition(conn, edition_id)
        suggestions = work.credit_suggestions(conn, edition_id)
    return Credit(
        vj_id=state.vj_id,
        vj_name=state.vj_name,
        suggestions=[CreditSuggestion(**asdict(s)) for s in suggestions],
    )


@router.put("/editions/{edition_id}/credit")
def set_credit(
    edition_id: UUID,
    body: CreditChoice,
    user: AdminUser,
    db: EditorDatabase,
    images: Images,
) -> Edition:
    """Credits a VJ, after the admin has previewed the video. A new VJ can be
    added by name at the same time."""
    if (body.vj_id is None) == (body.new_vj is None):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "Choose a VJ, or give a new VJ's name"
        )
    with editing(db, user) as conn:
        vj_id = body.vj_id or work.add_vj(conn, body.new_vj)
        work.set_credit(conn, edition_id, vj_id)
    logger.info(
        "Admin %s credited VJ %s on edition %s", user.user_id, vj_id, edition_id
    )
    return _current(db, user, edition_id, images)


@router.get("/categories")
def list_categories(user: AdminUser, db: EditorDatabase) -> list[CategoryOut]:
    """Every category, the most used first, for autocomplete."""
    with editing(db, user) as conn:
        return [CategoryOut(**asdict(c)) for c in work.list_categories(conn)]


@router.put("/editions/{edition_id}/categories")
def set_categories(
    edition_id: UUID,
    body: Categories,
    user: AdminUser,
    db: EditorDatabase,
    images: Images,
) -> Edition:
    """Replaces the edition's categories. New names are added as categories;
    a name matching one whatever its case uses that one."""
    with editing(db, user) as conn:
        saved = work.set_categories(conn, edition_id, body.names)
    logger.info(
        "Admin %s set %d categories on edition %s", user.user_id, len(saved), edition_id
    )
    return _current(db, user, edition_id, images)


@router.post("/editions/{edition_id}/publish")
def publish(
    edition_id: UUID, user: AdminUser, db: EditorDatabase, images: Images
) -> Edition:
    """Publishes, or answers 409 with what is missing."""
    with editing(db, user) as conn:
        editions.publish(conn, edition_id)
    logger.info("Admin %s published edition %s", user.user_id, edition_id)
    return _current(db, user, edition_id, images)


@router.post("/editions/{edition_id}/hide")
def hide(
    edition_id: UUID, user: AdminUser, db: EditorDatabase, images: Images
) -> Edition:
    with editing(db, user) as conn:
        editions.hide(conn, edition_id)
    logger.info("Admin %s hid edition %s", user.user_id, edition_id)
    return _current(db, user, edition_id, images)


class DeleteAll(BaseModel):
    # The word the admin typed, so a stray request can't delete every draft.
    confirm: Literal["DELETE"]


class Deleted(BaseModel):
    deleted: int
    # The editions deleted, so the app stops only their uploads.
    ids: list[UUID] = []


@router.delete("/editions/{edition_id}")
def delete_edition(edition_id: UUID, user: AdminUser, db: EditorDatabase) -> Deleted:
    """Deletes a draft or hidden edition for good: its videos, keys and
    details. It goes from every list at once. Its files are deleted by the
    media worker, and its rows after them."""
    with editing(db, user) as conn:
        work.delete_edition(conn, edition_id)
    audit.event("edition_deleted", admin_id=user.user_id, edition_id=edition_id)
    logger.info("Admin %s deleted edition %s", user.user_id, edition_id)
    return Deleted(deleted=1, ids=[edition_id])


@router.post("/drafts/delete-all")
def delete_all_drafts(body: DeleteAll, user: AdminUser, db: EditorDatabase) -> Deleted:
    """Deletes every draft, as above. Published and hidden editions stay."""
    with editing(db, user) as conn:
        ids = work.delete_all_drafts(conn)
    audit.event("drafts_deleted", admin_id=user.user_id, count=len(ids))
    logger.info("Admin %s deleted %s drafts", user.user_id, len(ids))
    return Deleted(deleted=len(ids), ids=ids)


# --- Items and keys ----------------------------------------------------------


@router.post("/items/{item_id}/approve")
def approve(item_id: UUID, user: AdminUser, db: EditorDatabase) -> dict:
    """Shows a new episode of a published series."""
    with editing(db, user) as conn:
        editions.approve_item(conn, item_id)
    logger.info("Admin %s approved item %s", user.user_id, item_id)
    return {"item_id": str(item_id), "approved": True}


def granter(request: Request) -> Granter:
    granter: Granter | None = request.app.state.granter
    if granter is None:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, "Playback isn't set up on this server."
        )
    return granter


@router.post("/items/{item_id}/preview")
def preview(
    item_id: UUID,
    user: AdminUser,
    db: EditorDatabase,
    granter: Annotated[Granter, Depends(granter)],
) -> Preview:
    """A playback address for the item's ready video, published or not, so
    the admin can check it and its VJ credit."""
    with editing(db, user) as conn:
        original = work.ready_original(conn, item_id)
    if original is None:
        raise HTTPException(status.HTTP_409_CONFLICT, "This video isn't ready yet.")
    grant = granter.grant(item_id, original)
    logger.info("Admin %s previewed item %s", user.user_id, item_id)
    return Preview(playlist_url=grant.playlist_url, expires_at=grant.expires_at)


@router.post("/items/{item_id}/keys", status_code=status.HTTP_201_CREATED)
def new_key(
    item_id: UUID, body: NewKey, user: AdminUser, db: EditorDatabase
) -> KeyMade:
    """Another key for the item, such as for a better copy. The key is in
    this answer only."""
    with editing(db, user) as conn:
        if not conn.execute(
            "select 1 from public.items where id = %s", (item_id,)
        ).fetchone():
            raise NotFound("No such item")
        key_id, text, expires_at = work.make_key(conn, item_id, body.label, body.days)
    logger.info("Admin %s made key %s for item %s", user.user_id, key_id, item_id)
    return KeyMade(key_id=key_id, upload_key=text, expires_at=expires_at)


@router.post("/keys/{key_id}/revoke")
def revoke(key_id: UUID, user: AdminUser, db: EditorDatabase) -> dict:
    with editing(db, user) as conn:
        work.revoke_key(conn, key_id)
    logger.info("Admin %s revoked key %s", user.user_id, key_id)
    return {"key_id": str(key_id), "revoked": True}


# --- VJs, languages and admins -----------------------------------------------


def _vj(vj: work.Vj, images: ImageUrls) -> VjOut:
    return VjOut(**asdict(vj), photo_url=images.photo(vj.photo_path))


@router.get("/vjs")
def list_vjs(user: AdminUser, db: EditorDatabase, images: Images) -> list[VjOut]:
    with editing(db, user) as conn:
        return [_vj(vj, images) for vj in work.list_vjs(conn)]


@router.post("/vjs", status_code=status.HTTP_201_CREATED)
def add_vj(body: VjIn, user: AdminUser, db: EditorDatabase, images: Images) -> VjOut:
    with editing(db, user) as conn:
        vj_id = work.add_vj(conn, body.name, body.match_names, body.bio)
        vj = next(v for v in work.list_vjs(conn) if v.id == vj_id)
    logger.info("Admin %s added VJ %s", user.user_id, vj_id)
    return _vj(vj, images)


@router.patch("/vjs/{vj_id}")
def change_vj(
    vj_id: UUID, body: VjChange, user: AdminUser, db: EditorDatabase, images: Images
) -> VjOut:
    with editing(db, user) as conn:
        work.update_vj(
            conn,
            vj_id,
            name=body.name,
            match_names=body.match_names,
            bio=body.bio,
            photo_path=body.photo_path,
        )
        vj = next(v for v in work.list_vjs(conn) if v.id == vj_id)
    return _vj(vj, images)


@router.get("/languages")
def list_languages(user: AdminUser, db: EditorDatabase) -> list[Language]:
    with editing(db, user) as conn:
        return [Language(code=c, name=n) for c, n in work.list_languages(conn)]


@router.post("/languages", status_code=status.HTTP_201_CREATED)
def add_language(body: Language, user: AdminUser, db: EditorDatabase) -> Language:
    with editing(db, user) as conn:
        work.add_language(conn, body.code, body.name)
    logger.info("Admin %s added language %s", user.user_id, body.code)
    return body


@router.get("/admins")
def list_admins(user: AdminUser, db: EditorDatabase) -> list[AdminOut]:
    with editing(db, user) as conn:
        return [
            AdminOut(
                user_id=a.user_id,
                email=a.email,
                added_by_email=a.added_by_email,
                added_at=a.added_at,
            )
            for a in work.list_admins(conn)
        ]


@router.post("/admins", status_code=status.HTTP_201_CREATED)
def add_admin(body: NewAdmin, user: AdminUser, db: EditorDatabase) -> dict:
    """Adds an admin by email. They must have signed in to VeloraUG once and
    confirmed that email."""
    with editing(db, user) as conn:
        added = work.add_admin(conn, body.email, user.user_id)
    logger.info("Admin %s added admin %s", user.user_id, added)
    return {"user_id": str(added)}


@router.delete("/admins/{user_id}")
def remove_admin(user_id: UUID, user: AdminUser, db: EditorDatabase) -> dict:
    """Removes an admin. The last one can't be removed."""
    with editing(db, user) as conn:
        work.remove_admin(conn, user_id)
    logger.info("Admin %s removed admin %s", user.user_id, user_id)
    return {"user_id": str(user_id), "removed": True}


# --- Uploaded images ---------------------------------------------------------


@router.post("/images", status_code=status.HTTP_201_CREATED)
def image_upload(
    body: ImageUpload,
    user: AdminUser,
    db: EditorDatabase,
    granter: Annotated[Granter, Depends(granter)],
) -> ImageUploadAddress:
    """Where to send a poster for an edition, or a VJ's photo. The browser
    sends the image straight to the media gateway, which stores it in R2; the
    API never holds R2's keys. See docs/step-09a-vj-catalogue-plan.md,
    decision 15."""
    table = "editions" if body.folder == "posters" else "vjs"
    with editing(db, user) as conn:
        if not conn.execute(
            f"select 1 from public.{table} where id = %s", (body.owner_id,)
        ).fetchone():
            raise NotFound("No such edition" if table == "editions" else "No such VJ")
    path = image_path(body.folder, body.owner_id, body.content_type)
    address = granter.upload(path, body.content_type)
    logger.info("Admin %s is uploading %s", user.user_id, path)
    return ImageUploadAddress(
        upload_url=address.playlist_url, path=path, expires_at=address.expires_at
    )
