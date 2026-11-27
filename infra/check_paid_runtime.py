"""Read the API container's effective configuration without contacting its services."""

import sys

from app.config import Settings
from pydantic_settings import SettingsError


def main() -> int:
    try:
        settings = Settings()
    except (SettingsError, ValueError):
        print("API settings could not be validated.", file=sys.stderr)
        return 1

    checks = {
        "Production API environment": settings.environment == "production",
        "Viewer passes required": settings.passes_required,
        "Production media gateway": settings.media_gateway_url
        == "https://media.veloraug.com",
    }
    if settings.pesapal_configured:
        checks["Production checkout"] = (
            settings.pesapal_environment == "live"
            and settings.public_api_url == "https://api.veloraug.com"
        )
    else:
        print("Checkout: not configured")
    for name, ok in checks.items():
        print(f"{name}: {'OK' if ok else 'CHECK'}")
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
