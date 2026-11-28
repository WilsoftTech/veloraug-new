"""Bound the body before FastAPI parses an API mutation."""

from starlette.responses import JSONResponse


class RequestBudget:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["method"] not in (
            "POST",
            "PUT",
            "PATCH",
            "DELETE",
        ):
            await self.app(scope, receive, send)
            return
        body = bytearray()
        more = True
        while more:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            if len(chunk) > (256 * 1024) - len(body):
                await JSONResponse({"detail": "Request body is too large."}, 413)(
                    scope, receive, send
                )
                return
            body.extend(chunk)
            more = message.get("more_body", False)

        async def replay():
            nonlocal body
            if body is None:
                return await receive()
            message = {"type": "http.request", "body": bytes(body), "more_body": False}
            body = None
            return message

        await self.app(scope, replay, send)
