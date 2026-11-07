from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from app.auth import VerifiedUser, current_user

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
def me(user: Annotated[VerifiedUser, Depends(current_user)]) -> MeResponse:
    """The signed-in user's ID, from a verified access token.

    Answers 401 without a valid token, and 503 when the token can't be
    checked. Step 5F adds the profile.
    """
    return MeResponse(user_id=user.user_id)
