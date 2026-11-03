from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel

SERVICE_NAME = "veloraug-api"
API_VERSION = "v1"

router = APIRouter()


class HealthResponse(BaseModel):
    status: Literal["ok"]


class ServiceInfoResponse(BaseModel):
    service: str
    api_version: str
    environment: str


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
