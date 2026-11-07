import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

FLUTTER_WEB_ORIGIN = "http://localhost:8765"


def preflight(client, origin, method="GET"):
    return client.options(
        "/health",
        headers={"Origin": origin, "Access-Control-Request-Method": method},
    )


def test_preflight_from_the_flutter_origin_is_allowed(client):
    response = preflight(client, FLUTTER_WEB_ORIGIN)

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == FLUTTER_WEB_ORIGIN
    assert "GET" in response.headers["access-control-allow-methods"]


def test_credentials_are_not_enabled(client):
    response = preflight(client, FLUTTER_WEB_ORIGIN)

    assert "access-control-allow-credentials" not in response.headers


def test_get_from_the_flutter_origin_can_be_read_by_the_browser(client):
    response = client.get("/health", headers={"Origin": FLUTTER_WEB_ORIGIN})

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == FLUTTER_WEB_ORIGIN


@pytest.mark.parametrize(
    "origin",
    [
        "https://evil.example",
        "http://localhost:8766",
        "https://localhost:8765",
        "http://127.0.0.1:8765",
        "http://localhost:8765.evil.example",
    ],
)
def test_preflight_from_other_origins_is_refused(client, origin):
    response = preflight(client, origin)

    assert response.status_code == 400
    assert "access-control-allow-origin" not in response.headers


def test_get_from_another_origin_gets_no_cors_permission(client):
    # The server still answers. CORS is the browser's rule: without this header
    # the browser hides the response from the web page.
    response = client.get("/health", headers={"Origin": "https://evil.example"})

    assert response.status_code == 200
    assert "access-control-allow-origin" not in response.headers


@pytest.mark.parametrize("method", ["POST", "PUT", "DELETE"])
def test_preflight_for_other_methods_is_refused(client, method):
    response = preflight(client, FLUTTER_WEB_ORIGIN, method=method)

    assert response.status_code == 400


def test_preflight_allows_patch_with_the_authorization_header(client):
    response = client.options(
        "/api/v1/me",
        headers={
            "Origin": FLUTTER_WEB_ORIGIN,
            "Access-Control-Request-Method": "PATCH",
            "Access-Control-Request-Headers": "authorization, content-type",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == FLUTTER_WEB_ORIGIN
    assert "PATCH" in response.headers["access-control-allow-methods"]
    allowed = response.headers["access-control-allow-headers"].lower()
    assert "authorization" in allowed
    assert "content-type" in allowed
    assert "access-control-allow-credentials" not in response.headers


def test_preflight_with_authorization_from_another_origin_is_refused(client):
    response = client.options(
        "/api/v1/me",
        headers={
            "Origin": "https://evil.example",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )

    assert response.status_code == 400
    assert "access-control-allow-origin" not in response.headers


def test_preflight_for_another_header_is_refused(client):
    response = client.options(
        "/api/v1/me",
        headers={
            "Origin": FLUTTER_WEB_ORIGIN,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "x-user-id",
        },
    )

    assert response.status_code == 400


def test_configured_origins_replace_the_default():
    settings = Settings(allowed_origins=["https://app.example"])
    client = TestClient(create_app(settings))

    assert preflight(client, "https://app.example").status_code == 200
    assert preflight(client, FLUTTER_WEB_ORIGIN).status_code == 400
