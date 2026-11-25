"""The account hub's routes: watch history, notifications, and deleting the
account. Each acts only on the signed-in viewer, named by the verified
token, never by anything in the request.
"""

import logging
from datetime import UTC, datetime, timedelta
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app import account, discovery, ratelimit, viewer
from app.auth import VerifiedUser, current_user
from app.viewer_routes import AppDatabase, EditionCard, Images, _card

router = APIRouter(prefix="/api/v1/me", tags=["account"])
logger = logging.getLogger("veloraug.account")

Viewer = Annotated[VerifiedUser, Depends(current_user)]

# Saving where the player got to: about once a minute while watching, with
# room for pauses and seeks.
POSITION_SAVES = ratelimit.Limit(20, 60)
DELETION_ATTEMPTS = ratelimit.Limit(5, 60 * 60)

DELETION_UNAVAILABLE = "Deleting an account from the app isn't available yet."
REAUTH_REQUIRED = "Sign in again to confirm it's you."
DELETION_INCOMPLETE = (
    "Your account couldn't be deleted completely. Nothing more will be "
    "removed until you try again."
)


def _now() -> datetime:
    return datetime.now(UTC)


# --- Watch history -----------------------------------------------------------


class HistoryOut(BaseModel):
    item_id: UUID
    edition: EditionCard
    season: int | None
    episode: int | None
    episode_title: str | None
    last_watched_at: datetime
    # Where to resume, in seconds, when a reliable position was saved.
    resume_seconds: int | None


class SavedItemOut(BaseModel):
    item_id: UUID
    edition: EditionCard
    season: int | None
    episode: int | None
    episode_title: str | None


class BecauseYouWatchedOut(BaseModel):
    # The title the viewer played most recently, other than this one.
    watched_id: UUID
    watched_title: str
    editions: list[EditionCard]


@router.get("/because-you-watched/{edition}")
def because_you_watched(
    edition: UUID, user: Viewer, db: AppDatabase, images: Images
) -> BecauseYouWatchedOut | None:
    """For an edition's page: titles like the one the viewer played most
    recently. Null without history, or with fewer than three titles."""
    with db.as_user(user.user_id) as conn:
        found = discovery.because_you_watched(conn, edition)
    if found is None:
        return None
    return BecauseYouWatchedOut(
        watched_id=found.watched_id,
        watched_title=found.watched_title,
        editions=[_card(e, images) for e in found.editions],
    )


@router.get("/watch-list")
def my_watch_list(user: Viewer, db: AppDatabase, images: Images) -> list[SavedItemOut]:
    with db.as_user(user.user_id) as conn:
        return [
            SavedItemOut(
                item_id=item.item_id,
                edition=_card(item.edition, images),
                season=item.season,
                episode=item.episode,
                episode_title=item.episode_title,
            )
            for item in account.watch_list(conn, user.user_id)
        ]


@router.get("/watch-list/editions/{edition_id}")
def watch_list_for_edition(
    edition_id: UUID, user: Viewer, db: AppDatabase
) -> list[UUID]:
    with db.as_user(user.user_id) as conn:
        return account.saved_item_ids(conn, user.user_id, edition_id)


@router.put("/watch-list/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def save_watch_list_item(item_id: UUID, user: Viewer, db: AppDatabase) -> Response:
    with db.as_user(user.user_id) as conn:
        if not viewer.playable_item(conn, item_id):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "This title is unavailable.")
        account.add_to_watch_list(conn, user.user_id, item_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/watch-list/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_watch_list_item(item_id: UUID, user: Viewer, db: AppDatabase) -> Response:
    with db.as_user(user.user_id) as conn:
        account.remove_from_watch_list(conn, user.user_id, item_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


class PositionIn(BaseModel):
    model_config = ConfigDict(extra="ignore")

    position_seconds: Annotated[int, Field(ge=0, le=86400)]
    finished: bool = False


@router.get("/history")
def my_history(
    user: Viewer,
    db: AppDatabase,
    images: Images,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> list[HistoryOut]:
    """What the viewer watched, latest first, one row per movie or episode.
    Titles no longer published are left out."""
    with db.as_user(user.user_id) as conn:
        entries = account.history(conn, user.user_id, limit)
    return [
        HistoryOut(
            item_id=entry.item_id,
            edition=_card(entry.edition, images),
            season=entry.season,
            episode=entry.episode,
            episode_title=entry.episode_title,
            last_watched_at=entry.last_watched_at,
            resume_seconds=entry.resume_at,
        )
        for entry in entries
    ]


class ProgressOut(BaseModel):
    item_id: UUID
    # Null once finished.
    position_seconds: int | None
    finished: bool


@router.get("/editions/{edition_id}/progress")
def my_progress(edition_id: UUID, user: Viewer, db: AppDatabase) -> list[ProgressOut]:
    """Where the viewer got to in each movie or episode of one edition, for
    the progress bars on its page. Only what they have played is listed."""
    with db.as_user(user.user_id) as conn:
        return [
            ProgressOut(
                item_id=p.item_id,
                position_seconds=p.position_seconds,
                finished=p.finished,
            )
            for p in account.progress(conn, user.user_id, edition_id)
        ]


@router.put(
    "/history/{item_id}/position",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={
        404: {"description": "Not watched by this viewer."},
        429: {"description": ratelimit.TOO_MANY},
    },
)
def save_position(
    item_id: UUID,
    body: PositionIn,
    request: Request,
    user: Viewer,
    db: AppDatabase,
) -> Response:
    """Saves where the viewer got to in something they started watching.
    Finished clears the position, so Resume isn't offered."""
    request.app.state.rate_limiter.check("position", str(user.user_id), POSITION_SAVES)
    with db.as_user(user.user_id) as conn:
        saved = account.save_position(
            conn,
            user.user_id,
            item_id,
            body.position_seconds,
            finished=body.finished,
        )
    if not saved:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not watched yet.")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Notifications -----------------------------------------------------------


class NotificationOut(BaseModel):
    # Stable, such as payment.completed:<payment ID>.
    id: str
    kind: Literal[
        "payment_completed",
        "payment_refunded",
        "pass_ending",
        "pass_ended",
        "device_removed",
    ]
    at: datetime
    read: bool
    plan_name: str | None
    device_label: str | None


class NotificationsOut(BaseModel):
    notifications: list[NotificationOut]
    unread: int


NotificationId = Annotated[
    str, StringConstraints(pattern=r"^[a-z_.]{3,40}:[0-9a-f-]{36}$")
]


class MarkReadIn(BaseModel):
    model_config = ConfigDict(extra="ignore")

    # Some notifications, or all those listed now.
    ids: Annotated[list[NotificationId], Field(max_length=100)] = []
    all: bool = False


@router.get("/notifications")
def my_notifications(user: Viewer, db: AppDatabase) -> NotificationsOut:
    """The viewer's notifications from the last 90 days, newest first, built
    from their own payments, passes and devices."""
    with db.as_user(user.user_id) as conn:
        found = account.notifications(conn, user.user_id, _now())
    return NotificationsOut(
        notifications=[
            NotificationOut(
                id=n.id,
                kind=n.kind,
                at=n.at,
                read=n.read,
                plan_name=n.plan_name,
                device_label=n.device_label,
            )
            for n in found
        ],
        unread=sum(1 for n in found if not n.read),
    )


@router.post("/notifications/read", status_code=status.HTTP_204_NO_CONTENT)
def mark_read(body: MarkReadIn, user: Viewer, db: AppDatabase) -> Response:
    """Marks notifications read: those named, or all listed now."""
    with db.as_user(user.user_id) as conn:
        if body.all:
            ids = [n.id for n in account.notifications(conn, user.user_id, _now())]
        else:
            ids = list(dict.fromkeys(body.ids))
        account.mark_read(conn, user.user_id, ids)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Account deletion --------------------------------------------------------


class DeletionOut(BaseModel):
    # Whether this server can delete an account from the app now.
    available: bool
    state: Literal["none", "pending", "completed"]
    requested_at: datetime | None = None


def _deletion_available(request: Request) -> bool:
    return (
        request.app.state.settings.account_deletion_enabled
        and request.app.state.identity_deleter is not None
    )


@router.get("/deletion")
def deletion_status(request: Request, user: Viewer, db: AppDatabase) -> DeletionOut:
    """Whether the account can be deleted from the app, and how far a
    deletion asked for before got."""
    with db.as_user(user.user_id) as conn:
        found = account.get_deletion(conn, user.user_id)
    return DeletionOut(
        available=_deletion_available(request),
        state="none"
        if found is None
        else ("completed" if found.completed_at else "pending"),
        requested_at=found.requested_at if found else None,
    )


@router.post(
    "/deletion",
    responses={
        401: {"description": REAUTH_REQUIRED},
        429: {"description": ratelimit.TOO_MANY},
        502: {"description": DELETION_INCOMPLETE},
        503: {"description": DELETION_UNAVAILABLE},
    },
)
def delete_account(request: Request, user: Viewer, db: AppDatabase) -> DeletionOut:
    """Deletes the signed-in viewer's account, after a recent sign-in.

    In order, each step safe to repeat: the request is recorded; the
    profile, watch history and read marks are deleted, every device is
    removed and playback stopped; the sign-in account is removed at the
    identity provider; the deletion is marked complete. Payments and passes
    are kept. If the identity provider fails, the answer is 502 and the
    viewer can try again: what was already removed stays removed."""
    if not _deletion_available(request):
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            {"code": "deletion_unavailable", "message": DELETION_UNAVAILABLE},
        )
    now = _now()
    if user.auth_time is None or not (
        timedelta(0) <= now - user.auth_time <= account.RECENT_SIGN_IN
    ):
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            {"code": "reauth_required", "message": REAUTH_REQUIRED},
        )
    request.app.state.rate_limiter.check(
        "deletion", str(user.user_id), DELETION_ATTEMPTS
    )
    with db.as_user(user.user_id) as conn:
        found = account.start_deletion(conn, user.user_id)
        if found.completed_at is not None:
            return DeletionOut(
                available=True, state="completed", requested_at=found.requested_at
            )
        account.remove_account_data(conn, user.user_id, now)
    deleter: account.IdentityDeleter = request.app.state.identity_deleter
    try:
        deleter.delete(user.user_id)
    except account.IdentityDeletionFailed:
        logger.warning("Identity deletion failed for an account; it can be retried")
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            {"code": "deletion_incomplete", "message": DELETION_INCOMPLETE},
        ) from None
    with db.as_user(user.user_id) as conn:
        account.finish_deletion(conn, user.user_id, _now())
    return DeletionOut(
        available=True, state="completed", requested_at=found.requested_at
    )
