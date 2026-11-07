from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def test_health_returns_ok(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_service_info_identifies_the_service(client):
    response = client.get("/api/v1")

    assert response.status_code == 200
    assert response.json() == {
        "service": "veloraug-api",
        "api_version": "v1",
        "environment": "development",
    }


def test_service_info_reports_the_configured_environment():
    settings = Settings(
        environment="production",
        neon_auth_url="https://auth.example.test/neondb/auth",
        api_resource="https://api.example.invalid",
        neon_auth_client_ids=["client-1"],
        database_url="postgresql://veloraug_app:pw@127.0.0.1:1/test",
    )
    client = TestClient(create_app(settings))

    assert client.get("/api/v1").json()["environment"] == "production"


def test_docs_page_is_served(client):
    response = client.get("/docs")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    assert "swagger-ui" in response.text


def test_openapi_describes_the_endpoints(client):
    response = client.get("/openapi.json")

    assert response.status_code == 200
    assert {"/health", "/api/v1", "/api/v1/me"} <= response.json()["paths"].keys()


def test_me_without_sign_in_settings_is_unavailable(client):
    # Development without the settings starts, but can't check anyone.
    response = client.get("/api/v1/me", headers={"Authorization": "Bearer x"})

    assert response.status_code == 503
