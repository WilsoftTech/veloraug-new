"""Upload ingress. The storage service is reachable only on its Docker network."""

import base64
import os
import re
from contextlib import asynccontextmanager
from urllib.parse import urlsplit

import httpx2
from fastapi import FastAPI, Request, Response
from starlette.responses import StreamingResponse

from app.upload_resume import RESUME_HEADER, UploadSecurity

UPLOAD_ID = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")
FORWARDED_HEADERS = (
    "content-type",
    "accept-encoding",
    "content-length",
    "origin",
    "upload-key",
    "tus-resumable",
    "upload-length",
    "upload-metadata",
    "upload-offset",
    "access-control-request-method",
    "access-control-request-headers",
)


def create_app(settings=None, transport=None, hook_secret=None):
    settings = settings or UploadSecurity()
    secret = hook_secret or os.environ.get("VELORAUG_MEDIA_HOOK_SECRET", "")
    if len(secret) < 32:
        raise ValueError("Configure VELORAUG_MEDIA_HOOK_SECRET for upload ingress")
    authorization = "Basic " + base64.b64encode(f"tusd:{secret}".encode()).decode()

    @asynccontextmanager
    async def lifespan(app):
        async with httpx2.AsyncClient(
            base_url="http://tusd-storage:8080", timeout=120, transport=transport
        ) as upstream:
            app.state.upstream = upstream
            yield

    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

    @app.api_route("/files/", methods=["OPTIONS", "POST"])
    @app.api_route("/files/{upload_id}", methods=["OPTIONS", "HEAD", "PATCH", "DELETE"])
    async def proxy(request: Request, upload_id: str | None = None):
        if upload_id is not None and not UPLOAD_ID.fullmatch(upload_id):
            return Response(status_code=404)
        origin = request.headers.get("origin")
        cors = {}
        if origin == settings.web_origin:
            cors = {"Access-Control-Allow-Origin": origin, "Vary": "Origin"}
        if request.method not in ("POST", "OPTIONS") and (
            not settings.permits(upload_id, request.headers.get(RESUME_HEADER))
        ):
            return Response(status_code=401, headers=cors)
        if request.method == "PATCH":
            length = request.headers.get("content-length", "")
            if not length.isascii() or not length.isdecimal() or len(length) > 10:
                return Response(status_code=411, headers=cors)
            if int(length) > 50 * 1024 * 1024:
                return Response(status_code=413, headers=cors)
        headers = {
            key: request.headers[key]
            for key in FORWARDED_HEADERS
            if key in request.headers
        }
        headers["accept-encoding"] = "identity"
        headers["authorization"] = authorization
        if request.method == "POST":
            headers["content-length"] = "0"
        try:
            upstream = app.state.upstream
            outgoing = upstream.build_request(
                request.method,
                request.url.path,
                headers=headers,
                content=request.stream() if request.method == "PATCH" else None,
            )
            reply = await upstream.send(outgoing, stream=True)
        except httpx2.HTTPError:
            return Response(status_code=502, headers=cors)
        headers = {
            name: value
            for name, value in reply.headers.items()
            if name
            not in ("connection", "transfer-encoding", "location", "content-encoding")
        }
        if request.method == "POST" and reply.status_code == 201:
            created = urlsplit(reply.headers.get("location", "")).path.rsplit("/", 1)[
                -1
            ]
            if not UPLOAD_ID.fullmatch(created):
                await reply.aclose()
                return Response(status_code=502, headers=cors)
            headers["location"] = f"/files/{created}"
            headers[RESUME_HEADER] = settings.issue(created)
            headers["access-control-expose-headers"] = (
                headers.get("access-control-expose-headers", "") + f", {RESUME_HEADER}"
            ).strip(", ")
        headers["cache-control"] = "no-store"

        async def data():
            try:
                async for chunk in reply.aiter_bytes():
                    yield chunk
            finally:
                await reply.aclose()

        return StreamingResponse(data(), status_code=reply.status_code, headers=headers)

    return app
