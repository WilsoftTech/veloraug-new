"""The Pesapal client, Step 10B, against a fake Pesapal. No network."""

import json

import httpx2
import pytest

from app.pesapal import (
    COMPLETED,
    PesapalClient,
    PesapalError,
    PesapalUnavailable,
    safe_redirect,
)

SANDBOX = "https://cybqa.pesapal.com/pesapalv3/api"


class FakePesapal:
    """Pesapal API 3.0 as its documentation describes it, for tests.

    Orders get tracking IDs; `statuses` holds each one's status_code, and
    `amounts` what was paid, if not the order's amount."""

    def __init__(self) -> None:
        self.requests: list[httpx2.Request] = []
        self.orders: dict[str, dict] = {}
        self.statuses: dict[str, int] = {}
        self.amounts: dict[str, float] = {}
        self.currency = "UGX"
        self.tokens = 0
        self.redirect_host = "cybqa.pesapal.com"
        self.down = False
        self.refuse_orders = False

    def handle(self, request: httpx2.Request) -> httpx2.Response:
        self.requests.append(request)
        if self.down:
            return httpx2.Response(503, text="maintenance")
        path = request.url.path.removeprefix("/pesapalv3/api")
        if path == "/Auth/RequestToken":
            self.tokens += 1
            body = json.loads(request.content)
            if body != {"consumer_key": "key", "consumer_secret": "secret"}:
                return httpx2.Response(
                    200,
                    json={"token": None, "error": {"code": "invalid_consumer_key"}},
                )
            return httpx2.Response(
                200,
                json={
                    "token": f"token-{self.tokens}",
                    "expiryDate": "2099-01-01T00:05:00Z",
                    "error": None,
                    "status": "200",
                },
            )
        if request.headers.get("Authorization", "")[:13] != "Bearer token-":
            return httpx2.Response(401, json={"error": {"code": "unauthorized"}})
        if path == "/Transactions/SubmitOrderRequest":
            if self.refuse_orders:
                return httpx2.Response(
                    200,
                    json={
                        "error": {"code": "invalid_amount", "message": "Bad amount"},
                        "status": "500",
                    },
                )
            order = json.loads(request.content)
            tracking = f"track-{len(self.orders) + 1:04d}-0000-0000"
            self.orders[tracking] = order
            return httpx2.Response(
                200,
                json={
                    "order_tracking_id": tracking,
                    "merchant_reference": order["id"],
                    "redirect_url": f"https://{self.redirect_host}/iframe?id={tracking}",
                    "error": None,
                    "status": "200",
                },
            )
        if path == "/Transactions/GetTransactionStatus":
            tracking = request.url.params["orderTrackingId"]
            order = self.orders.get(tracking)
            if order is None:
                return httpx2.Response(
                    200,
                    json={
                        "error": {"code": "payment_details_not_found"},
                        "status": "500",
                    },
                )
            code = self.statuses.get(tracking, 0)
            return httpx2.Response(
                200,
                json={
                    "payment_method": "MTN" if code else "",
                    "amount": self.amounts.get(tracking, order["amount"]),
                    "created_date": "2026-11-19T10:00:00",
                    "confirmation_code": "ABC123" if code == COMPLETED else "",
                    "payment_status_description": {
                        0: "INVALID",
                        1: "COMPLETED",
                        2: "FAILED",
                        3: "REVERSED",
                    }[code],
                    "description": "",
                    "message": "Request processed successfully",
                    "status_code": code,
                    "merchant_reference": order["id"],
                    "currency": self.currency,
                    "error": {"error_type": None, "code": None, "message": None},
                    "status": "200",
                },
            )
        if path == "/URLSetup/RegisterIPN":
            return httpx2.Response(
                200, json={"ipn_id": "ipn-1234-5678", "error": None, "status": "200"}
            )
        return httpx2.Response(404, json={"error": {"code": "not_found"}})

    def client(self, **options) -> PesapalClient:
        return PesapalClient(
            "key", "secret", transport=httpx2.MockTransport(self.handle), **options
        )


def order(client: PesapalClient, **changes):
    options = dict(
        reference="7b0e3c5a-0000-4000-8000-000000000001",
        amount=5000,
        currency="UGX",
        description="VeloraUG pass, 1 week",
        callback_url="http://127.0.0.1:8000/api/v1/passes/return",
        notification_id="ipn-1234-5678",
        email="viewer@example.com",
        phone=None,
    )
    return client.submit_order(**(options | changes))


def test_an_order_goes_to_pesapal_with_one_token():
    fake = FakePesapal()
    client = fake.client()

    first = order(client)
    order(client)

    assert first.tracking_id == "track-0001-0000-0000"
    assert first.redirect_url.startswith("https://cybqa.pesapal.com/")
    assert fake.tokens == 1
    sent = json.loads(fake.requests[1].content)
    assert str(fake.requests[1].url).startswith(SANDBOX)
    assert sent == {
        "id": "7b0e3c5a-0000-4000-8000-000000000001",
        "currency": "UGX",
        "amount": 5000,
        "description": "VeloraUG pass, 1 week",
        "callback_url": "http://127.0.0.1:8000/api/v1/passes/return",
        "notification_id": "ipn-1234-5678",
        "redirect_mode": "TOP_WINDOW",
        "billing_address": {
            "country_code": "UG",
            "email_address": "viewer@example.com",
        },
    }


def test_a_token_is_renewed_before_it_runs_out():
    fake = FakePesapal()
    now = [1000.0]
    client = fake.client(clock=lambda: now[0])

    order(client)
    now[0] += 4 * 60 + 31
    order(client)

    assert fake.tokens == 2


def test_the_status_is_read_from_pesapal():
    fake = FakePesapal()
    client = fake.client()
    made = order(client)
    fake.statuses[made.tracking_id] = COMPLETED

    status = client.status(made.tracking_id)

    assert status.code == COMPLETED
    assert status.amount == 5000
    assert status.currency == "UGX"
    assert status.merchant_reference == "7b0e3c5a-0000-4000-8000-000000000001"
    assert status.payment_method == "MTN"
    assert status.confirmation_code == "ABC123"


def test_a_payment_page_elsewhere_is_refused():
    fake = FakePesapal()
    fake.redirect_host = "pesapal.com.example.net"

    with pytest.raises(PesapalError, match="pesapal.com"):
        order(fake.client())


@pytest.mark.parametrize(
    "url",
    [
        "http://cybqa.pesapal.com/iframe",
        "https://evilpesapal.com/x",
        "https://user:pw@pay.pesapal.com/x",
        None,
    ],
)
def test_only_https_pages_on_pesapal_com_are_safe(url):
    with pytest.raises(PesapalError):
        safe_redirect(url)
    assert safe_redirect("https://pay.pesapal.com/iframe/x?y=1").startswith("https")


def test_refusals_and_outages_are_told_apart():
    fake = FakePesapal()
    fake.refuse_orders = True
    with pytest.raises(PesapalError, match="invalid_amount") as refused:
        order(fake.client())
    assert not isinstance(refused.value, PesapalUnavailable)

    fake.down = True
    with pytest.raises(PesapalUnavailable):
        order(fake.client())


def test_wrong_keys_are_refused_without_quoting_them():
    fake = FakePesapal()
    client = PesapalClient(
        "key", "not-the-secret", transport=httpx2.MockTransport(fake.handle)
    )

    with pytest.raises(PesapalError) as refused:
        order(client)
    assert "not-the-secret" not in str(refused.value)


def test_the_live_environment_has_its_own_address():
    fake = FakePesapal()
    client = PesapalClient(
        "key", "secret", environment="live", transport=httpx2.MockTransport(fake.handle)
    )
    try:
        order(client)
    except PesapalError:
        pass
    assert str(fake.requests[0].url).startswith("https://pay.pesapal.com/v3/api/")
    with pytest.raises(ValueError):
        PesapalClient("key", "secret", environment="test")


def test_the_notification_address_is_registered_as_get():
    fake = FakePesapal()

    assert fake.client().register_ipn("https://api.example/x") == "ipn-1234-5678"
    assert json.loads(fake.requests[-1].content) == {
        "url": "https://api.example/x",
        "ipn_notification_type": "GET",
    }
