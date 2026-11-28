from pathlib import Path

import httpx2
import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from app.payment_queue import PaymentQueue
from app.ratelimit import Limit, RateLimiter
from app.upload_proxy import create_app as create_upload_proxy
from app.upload_resume import UploadSecurity

ORIGINAL = "9503140e-8533-4585-95e2-2b60b7187b16"
OTHER = "2a97666b-5727-42b6-8594-476274ec1676"


def test_api_rejects_large_chunked_mutations():
    with TestClient(create_app()) as client:
        response = client.post(
            "/api/v1/passes/checkout",
            content=(b"x" * 8192 for _ in range(33)),
            headers={"content-type": "application/json"},
        )
    assert response.status_code == 413


def test_limiter_caps_keys_without_evicting_active_buckets():
    from fastapi import HTTPException

    now = 0
    limiter = RateLimiter(clock=lambda: now, max_keys=1)
    limit = Limit(1, 600)
    limiter.check("test", "first", limit)
    for account in ("second", "first"):
        with pytest.raises(HTTPException) as refused:
            limiter.check("test", account, limit)
        assert refused.value.status_code == 429
    now = 3601
    limiter.check("test", "second", limit)


def test_notifications_survive_reopen_and_duplicate_delivery(tmp_path: Path):
    path = tmp_path / "queue.db"
    queue = PaymentQueue(path, lambda _: pytest.fail("Old worker must not run"))
    assert queue.submit("example-order")
    assert queue.submit("example-order")
    checked = []
    reopened = PaymentQueue(path, lambda tracking: checked.append(tracking) or True)
    assert reopened.run_one()
    assert reopened.submit("example-order")
    assert not reopened.run_one()
    assert checked == ["example-order"]


def test_upload_resource_requires_its_own_scoped_credential():
    requests = []

    async def storage(request):
        requests.append(request)
        if request.method == "POST":
            return httpx2.Response(201, headers={"location": f"/files/{ORIGINAL}"})
        return httpx2.Response(204, headers={"upload-offset": "10"})

    settings = UploadSecurity(resume_key="r" * 64)
    app = create_upload_proxy(
        settings, httpx2.MockTransport(storage), hook_secret="h" * 64
    )
    with TestClient(app) as client:
        created = client.post("/files/", headers={"Upload-Key": "test-key"})
        assert created.status_code == 201
        token = created.headers["upload-resume"]
        assert created.headers["location"] == f"/files/{ORIGINAL}"
        for method in ("HEAD", "PATCH", "DELETE"):
            assert client.request(method, f"/files/{ORIGINAL}").status_code == 401
            assert (
                client.request(
                    method, f"/files/{OTHER}", headers={"Upload-Resume": token}
                ).status_code
                == 401
            )
        assert len(requests) == 1
        for method in ("HEAD", "PATCH", "DELETE"):
            assert (
                client.request(
                    method,
                    f"/files/{ORIGINAL}",
                    headers={"Upload-Resume": token, "Content-Length": "0"},
                ).status_code
                == 204
            )
    assert all("upload-resume" not in request.headers for request in requests)


def test_resume_credential_expires():
    settings = UploadSecurity(resume_key="r" * 64)
    assert not settings.permits(ORIGINAL, settings.issue(ORIGINAL, now=0))


def test_converter_stops_a_stalled_child(tmp_path, monkeypatch):
    import sys

    from app import media_worker

    monkeypatch.setattr(media_worker, "MAX_CONVERSION_SECONDS", 0)
    with pytest.raises(media_worker.ConversionFailed, match="time limit"):
        media_worker.stream_process(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            tmp_path,
            lambda _: None,
        )


def test_payment_status_has_a_cooldown():
    from app.pesapal import PesapalClient, PesapalUnavailable
    from tests.test_pesapal import FakePesapal

    fake = FakePesapal()
    client = PesapalClient(
        "key", "secret", transport=httpx2.MockTransport(fake.handle), status_cooldown=2
    )
    fake.orders["fixture-tracking"] = {"id": "fixture-payment", "amount": 6000}
    with client:
        client.status("fixture-tracking")
        with pytest.raises(PesapalUnavailable, match="recently"):
            client.status("fixture-tracking")
