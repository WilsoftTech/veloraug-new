"""Pesapal API 3.0: orders, their status, and the notification address.

See docs/step-10a-payments-plan.md. Pesapal's hosted page takes the
payment; nothing here sees a card number or a mobile money PIN. Only
`status()` says whether a payment went through: the viewer's return and
Pesapal's notification never do.

Registering the notification address, once per environment:

    python -m app.pesapal register-ipn https://<api>/api/v1/passes/ipn

It prints the IPN ID for VELORAUG_PESAPAL_IPN_ID.
"""

import sys
import threading
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from types import TracebackType
from typing import Any, Self
from urllib.parse import urlsplit

import httpx2

BASE_URLS = {
    "sandbox": "https://cybqa.pesapal.com/pesapalv3",
    "live": "https://pay.pesapal.com/v3",
}
TIMEOUT_SECONDS = 15.0
# Tokens last at most 5 minutes. One is reused until this close to its end.
TOKEN_MARGIN_SECONDS = 30
# Pesapal's status_code values.
INVALID, COMPLETED, FAILED, REVERSED = 0, 1, 2, 3


class PesapalError(Exception):
    """Pesapal refused, or answered something unusable. The message never
    includes the keys."""


class PesapalUnavailable(PesapalError):
    """No answer, or a server error: worth trying again later."""


class PesapalOrderNotSent(PesapalUnavailable):
    """Could not authenticate before making the order request."""


@dataclass(frozen=True)
class Order:
    tracking_id: str
    redirect_url: str


@dataclass(frozen=True)
class Status:
    code: int | None
    description: str
    amount: float | None
    currency: str | None
    merchant_reference: str | None
    payment_method: str | None
    confirmation_code: str | None


def safe_redirect(url: object) -> str:
    """Pesapal's page address, only if it's https on pesapal.com."""
    if not isinstance(url, str):
        raise PesapalError("Pesapal gave no payment page")
    parts = urlsplit(url)
    host = (parts.hostname or "").lower()
    if (
        parts.scheme != "https"
        or parts.username
        or parts.password
        or not (host == "pesapal.com" or host.endswith(".pesapal.com"))
    ):
        raise PesapalError("Pesapal's payment page isn't on pesapal.com")
    return url


def _text(value: object, limit: int) -> str | None:
    if value is None or value == "":
        return None
    return str(value)[:limit]


def parse_status(data: Any) -> Status:
    if not isinstance(data, dict):
        raise PesapalError("Pesapal's status isn't a JSON object")
    code = data.get("status_code")
    amount = data.get("amount")
    return Status(
        code=code if isinstance(code, int) and not isinstance(code, bool) else None,
        description=str(data.get("payment_status_description") or "")[:50],
        amount=float(amount)
        if isinstance(amount, int | float) and not isinstance(amount, bool)
        else None,
        currency=_text(data.get("currency"), 3),
        merchant_reference=_text(data.get("merchant_reference"), 50),
        payment_method=_text(data.get("payment_method"), 50),
        confirmation_code=_text(data.get("confirmation_code"), 100),
    )


class PesapalClient:
    def __init__(
        self,
        consumer_key: str,
        consumer_secret: str,
        *,
        environment: str = "sandbox",
        transport: httpx2.BaseTransport | None = None,
        timeout: float = TIMEOUT_SECONDS,
        clock=time.time,
    ) -> None:
        if environment not in BASE_URLS:
            raise ValueError("The Pesapal environment is sandbox or live")
        if not consumer_key.strip() or not consumer_secret.strip():
            raise ValueError("The Pesapal keys are empty")
        self._key = consumer_key.strip()
        self._secret = consumer_secret.strip()
        self._clock = clock
        self._token: str | None = None
        self._token_until = 0.0
        self._lock = threading.Lock()
        self._client = httpx2.Client(
            base_url=BASE_URLS[environment] + "/api",
            headers={"Accept": "application/json", "Content-Type": "application/json"},
            timeout=timeout,
            transport=transport,
            follow_redirects=False,
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(
        self,
        kind: type[BaseException] | None,
        error: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self.close()

    # --- The three calls --------------------------------------------------

    def submit_order(
        self,
        *,
        reference: str,
        amount: int,
        currency: str,
        description: str,
        callback_url: str,
        notification_id: str,
        email: str | None,
        phone: str | None,
    ) -> Order:
        address: dict[str, str] = {"country_code": "UG"}
        if email:
            address["email_address"] = email
        if phone:
            address["phone_number"] = phone
        try:
            token = self._token_now()
        except PesapalUnavailable as error:
            raise PesapalOrderNotSent(str(error)) from None
        data = self._send(
            "POST",
            "/Transactions/SubmitOrderRequest",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "id": reference,
                "currency": currency,
                "amount": amount,
                "description": description[:100],
                "callback_url": callback_url,
                "notification_id": notification_id,
                "redirect_mode": "TOP_WINDOW",
                "billing_address": address,
            },
        )
        tracking_id = data.get("order_tracking_id")
        if not isinstance(tracking_id, str) or not tracking_id:
            raise PesapalError("Pesapal didn't make the order")
        return Order(tracking_id, safe_redirect(data.get("redirect_url")))

    def status(self, tracking_id: str) -> Status:
        data = self._call(
            "GET",
            "/Transactions/GetTransactionStatus",
            params={"orderTrackingId": tracking_id},
        )
        return parse_status(data)

    def register_ipn(self, url: str) -> str:
        data = self._call(
            "POST",
            "/URLSetup/RegisterIPN",
            json={"url": url, "ipn_notification_type": "GET"},
        )
        ipn_id = data.get("ipn_id")
        if not isinstance(ipn_id, str) or not ipn_id:
            raise PesapalError("Pesapal didn't register the address")
        return ipn_id

    # --- Plumbing ---------------------------------------------------------

    def _token_now(self) -> str:
        with self._lock:
            if self._token and self._clock() < self._token_until:
                return self._token
            data = self._send(
                "POST",
                "/Auth/RequestToken",
                json={"consumer_key": self._key, "consumer_secret": self._secret},
            )
            token = data.get("token")
            if not isinstance(token, str) or not token:
                raise PesapalError("Pesapal refused the keys")
            until = self._clock() + 5 * 60
            expiry = data.get("expiryDate")
            if isinstance(expiry, str):
                try:
                    stamp = datetime.fromisoformat(expiry.replace("Z", "+00:00"))
                    if stamp.tzinfo is None:
                        stamp = stamp.replace(tzinfo=UTC)
                    until = min(until, stamp.timestamp())
                except ValueError:
                    pass
            self._token = token
            self._token_until = until - TOKEN_MARGIN_SECONDS
            return token

    def _call(self, method: str, path: str, **options) -> dict:
        token = self._token_now()
        return self._send(
            method, path, headers={"Authorization": f"Bearer {token}"}, **options
        )

    def _send(self, method: str, path: str, **options) -> dict:
        try:
            response = self._client.request(method, path, **options)
        except httpx2.TimeoutException:
            raise PesapalUnavailable("Pesapal didn't answer in time") from None
        except httpx2.HTTPError as error:
            raise PesapalUnavailable(
                f"Couldn't reach Pesapal ({type(error).__name__})"
            ) from None
        if response.status_code >= 500:
            raise PesapalUnavailable(f"Pesapal answered {response.status_code}")
        try:
            data = response.json()
        except ValueError:
            raise PesapalError(
                f"Pesapal answered {response.status_code}, not in JSON"
            ) from None
        if not isinstance(data, dict):
            raise PesapalError("Pesapal's answer isn't a JSON object")
        error = data.get("error")
        if response.status_code != 200 or (
            isinstance(error, dict) and any(error.get(k) for k in ("code", "message"))
        ):
            message = error.get("message") if isinstance(error, dict) else None
            code = error.get("code") if isinstance(error, dict) else None
            raise PesapalError(
                f"Pesapal refused ({response.status_code}"
                + (f", {str(code)[:50]}" if code else "")
                + (f": {str(message)[:150]}" if message else "")
                + ")"
            )
        return data


def main(argv: list[str]) -> int:
    from app.config import Settings

    if len(argv) != 2 or argv[0] != "register-ipn":
        print("Use: python -m app.pesapal register-ipn <address>", file=sys.stderr)
        return 2
    url = argv[1]
    if urlsplit(url).scheme not in ("http", "https"):
        print("The address starts with https:// or http://", file=sys.stderr)
        return 2
    settings = Settings()
    if settings.pesapal_consumer_key is None:
        print(
            "Put VELORAUG_PESAPAL_CONSUMER_KEY and VELORAUG_PESAPAL_CONSUMER_SECRET "
            "in services/api/.env first, and run this where the API runs, with "
            "that file's settings",
            file=sys.stderr,
        )
        return 1
    with PesapalClient(
        settings.pesapal_consumer_key.get_secret_value(),
        settings.pesapal_consumer_secret.get_secret_value(),
        environment=settings.pesapal_environment,
    ) as client:
        try:
            ipn_id = client.register_ipn(url)
        except PesapalError as error:
            print(error, file=sys.stderr)
            return 1
    print(f"Registered with Pesapal's {settings.pesapal_environment}.")
    print(f"Put this in services/api/.env: VELORAUG_PESAPAL_IPN_ID={ipn_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
