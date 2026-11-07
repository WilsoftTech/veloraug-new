from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, StringConstraints

from app import profiles
from app.auth import VerifiedUser, current_user
from app.db import Database

SERVICE_NAME = "veloraug-api"
API_VERSION = "v1"

router = APIRouter()


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


@router.patch("/api/v1/me")
def update_me(user: SignedInUser, db: AppDatabase, update: MeUpdate) -> MeResponse:
    """Changes the signed-in user's display name. null clears it."""
    with db.as_user(user.user_id) as conn:
        profile = profiles.set_display_name(conn, user.user_id, update.display_name)
    return MeResponse(user_id=profile.user_id, display_name=profile.display_name)
