import runpy
from pathlib import Path

import pytest

CHECK = Path(__file__).resolve().parents[3] / "infra" / "check_paid_runtime.py"


@pytest.fixture
def paid_runtime(monkeypatch):
    settings = {
        "ENVIRONMENT": "production",
        "PASSES_REQUIRED": "true",
        "MEDIA_GATEWAY_URL": "https://media.veloraug.com",
        "PLAYBACK_SIGNING_KEY": "private-test-marker" * 3,
        "DATABASE_URL": "postgresql://veloraug_app:private-test-marker@localhost/db",
        "NEON_AUTH_URL": "https://issuer.example.test/auth",
        "API_RESOURCE": "https://api.example.test",
        "NEON_AUTH_CLIENT_IDS": '["test"]',
        "PESAPAL_ENVIRONMENT": "live",
        "PESAPAL_CONSUMER_KEY": "private-test-marker",
        "PESAPAL_CONSUMER_SECRET": "private-test-marker",
        "PESAPAL_IPN_ID": "test-notification",
        "PUBLIC_API_URL": "https://api.veloraug.com",
    }
    for name, value in settings.items():
        monkeypatch.setenv(f"VELORAUG_{name}", value)
    return runpy.run_path(str(CHECK))["main"]


@pytest.mark.parametrize(
    ("name", "value", "result", "message"),
    [
        ("PASSES_REQUIRED", "true", 0, "Viewer passes required: OK"),
        ("PASSES_REQUIRED", None, 1, "Viewer passes required: CHECK"),
        ("PASSES_REQUIRED", "false", 1, "Viewer passes required: CHECK"),
        ("ENVIRONMENT", "development", 1, "Production API environment: CHECK"),
        (
            "MEDIA_GATEWAY_URL",
            "https://other.test",
            1,
            "Production media gateway: CHECK",
        ),
        ("PESAPAL_ENVIRONMENT", "sandbox", 1, "Production checkout: CHECK"),
        ("PUBLIC_API_URL", "https://other.test", 1, "Production checkout: CHECK"),
        ("PESAPAL_IPN_ID", None, 0, "Checkout: not configured"),
        ("ALLOWED_ORIGINS", "private-test-marker", 1, "could not be validated"),
        ("DATABASE_URL", "private-test-marker", 1, "could not be validated"),
    ],
)
def test_check_reports_only_safe_outcomes(
    paid_runtime, monkeypatch, capsys, name, value, result, message
):
    if value is None:
        monkeypatch.delenv(f"VELORAUG_{name}")
    else:
        monkeypatch.setenv(f"VELORAUG_{name}", value)
    assert paid_runtime() == result
    captured = capsys.readouterr()
    output = captured.out + captured.err
    assert message in output
    assert "private-test-marker" not in output
