"""A small in-memory rate limiter, per signed-in account and action.

The API runs as one process on the pilot server, so memory is enough. It
complements, and doesn't replace, Cloudflare's rate-limiting rule in front
of the API. Keys are VeloraUG's account IDs, never an address or a token.
"""

import threading
import time
from collections import OrderedDict, deque
from dataclasses import dataclass

from fastapi import HTTPException, status


@dataclass(frozen=True)
class Limit:
    count: int
    seconds: float


# Starting a payment with Pesapal: a few retries, not a flood of orders.
CHECKOUT = Limit(6, 10 * 60)
# Checking a payment: the app asks every 3 seconds while the viewer pays.
PAYMENT_STATUS = Limit(60, 60)
# Registering a device, and asking for playback.
DEVICE_REGISTER = Limit(10, 60 * 60)
PLAYBACK = Limit(30, 60)

TOO_MANY = "Too many attempts. Wait a moment and try again."


class RateLimiter:
    def __init__(self, clock=time.monotonic, max_keys: int = 50_000) -> None:
        self._clock = clock
        self._retention = 3600.0
        self._hits: OrderedDict[tuple[str, str], deque[float]] = OrderedDict()
        self._lock = threading.Lock()
        if max_keys < 1:
            raise ValueError("max_keys must be positive")
        self._max_keys = max_keys

    def check(self, action: str, key: str, limit: Limit) -> None:
        """Counts one attempt, or raises 429 with Retry-After."""
        now = self._clock()
        with self._lock:
            self._retention = max(self._retention, limit.seconds)
            bucket = (action, key)
            hits = self._hits.get(bucket)
            if hits is None:
                if len(self._hits) >= self._max_keys:
                    oldest = next(iter(self._hits))
                    wait = int(self._hits[oldest][-1] + self._retention - now) + 1
                    if wait > 0:
                        raise HTTPException(
                            status.HTTP_429_TOO_MANY_REQUESTS,
                            TOO_MANY,
                            headers={"Retry-After": str(wait)},
                        )
                    self._hits.popitem(last=False)
                hits = self._hits[bucket] = deque()
            while hits and hits[0] <= now - limit.seconds:
                hits.popleft()
            if len(hits) >= limit.count:
                wait = max(1, int(hits[0] + limit.seconds - now) + 1)
                raise HTTPException(
                    status.HTTP_429_TOO_MANY_REQUESTS,
                    TOO_MANY,
                    headers={"Retry-After": str(wait)},
                )
            hits.append(now)
            self._hits.move_to_end(bucket)
