"""Structured audit events for billing, devices, playback sessions and deletes.

One JSON line per event on the `veloraug.audit` logger. Events carry
VeloraUG's own IDs, plan IDs, amounts and times only: never an email, a
phone number, a token, a device secret, a grant, or Pesapal's keys.
"""

import json
import logging
from datetime import datetime
from uuid import UUID

logger = logging.getLogger("veloraug.audit")

# Only these fields are ever written, so a careless caller can't leak
# something else into the log.
ALLOWED = frozenset(
    {
        "payment_id",
        "user_id",
        "admin_id",
        "plan_id",
        "amount_ugx",
        "device_id",
        "session_id",
        "item_id",
        "edition_id",
        "vj_id",
        "pass_starts_at",
        "reason",
        "count",
        "for_sale",
        "featured",
        "price_ugx",
    }
)


def _plain(value: object) -> object:
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def event(name: str, **fields: object) -> dict:
    """Logs one event and answers what was logged, for tests."""
    record = {"event": name}
    for key, value in fields.items():
        if key in ALLOWED and value is not None:
            record[key] = _plain(value)
    logger.info(json.dumps(record, separators=(",", ":"), sort_keys=True))
    return record
