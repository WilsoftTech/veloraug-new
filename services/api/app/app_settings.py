"""Settings admins change in the app, Step 13H Phase 5: support contacts,
maintenance mode, the payment timeout, pass reminders and the default
language of new drafts.

Stored in public.app_settings, one JSON value per key; a key with no row
has its default. Every value is checked here before it is written. Nothing
secret is a setting: keys for Pesapal, TMDB and R2 stay in the environment.
"""

import re
from collections.abc import Callable
from dataclasses import dataclass
from datetime import timedelta
from typing import Any
from uuid import UUID

import psycopg
from psycopg.types.json import Jsonb


class SettingError(ValueError):
    """A value an admin can fix. The message is safe to show."""


_EMAIL = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,255}\.[^@\s]{2,}$")
_PHONE = re.compile(r"^\+[0-9]{9,15}$")


def _contact(pattern: re.Pattern, what: str) -> Callable[[Any], str]:
    def check(value: Any) -> str:
        if not isinstance(value, str):
            raise SettingError(f"The {what} is text")
        text = " ".join(value.split())
        if what != "email address":
            text = text.replace(" ", "").replace("-", "")
        if text and not pattern.match(text):
            raise SettingError(
                f"That isn't a {what}"
                + ("" if what == "email address" else ": start with +256…")
            )
        return text

    return check


def _flag(value: Any) -> bool:
    if not isinstance(value, bool):
        raise SettingError("This is on or off")
    return value


def _text(limit: int) -> Callable[[Any], str]:
    def check(value: Any) -> str:
        if not isinstance(value, str):
            raise SettingError("This is text")
        text = value.strip()
        if len(text) > limit:
            raise SettingError(f"At most {limit} characters")
        return text

    return check


def _number(low: int, high: int) -> Callable[[Any], int]:
    def check(value: Any) -> int:
        if isinstance(value, bool) or not isinstance(value, int):
            raise SettingError("This is a whole number")
        if not low <= value <= high:
            raise SettingError(f"From {low} to {high}")
        return value

    return check


def _language(value: Any) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[a-z]{2,3}", value):
        raise SettingError("Choose a language")
    return value


@dataclass(frozen=True)
class Setting:
    key: str
    default: Any
    check: Callable[[Any], Any]


SETTINGS: dict[str, Setting] = {
    s.key: s
    for s in (
        Setting("support_email", "", _contact(_EMAIL, "email address")),
        Setting("support_phone", "", _contact(_PHONE, "phone number")),
        Setting("support_whatsapp", "", _contact(_PHONE, "WhatsApp number")),
        Setting("maintenance", False, _flag),
        Setting("maintenance_message", "", _text(300)),
        # None: the server's VELORAUG_PAYMENT_TIMEOUT_MINUTES.
        Setting("payment_timeout_minutes", None, _number(5, 1440)),
        Setting("pass_reminder_days", 3, _number(1, 14)),
        Setting("default_language", "lg", _language),
    )
}


def read(conn: psycopg.Connection) -> dict[str, Any]:
    """Every setting: stored, or its default. Any role that can read them."""
    stored = dict(conn.execute("select key, value from public.app_settings").fetchall())
    return {
        key: stored[key] if key in stored else setting.default
        for key, setting in SETTINGS.items()
    }


def safe_read(conn: psycopg.Connection) -> dict[str, Any]:
    """As read, or the defaults when the table can't be read, such as on a
    database not yet migrated. Settings never stop the app."""
    try:
        with conn.transaction():
            return read(conn)
    except psycopg.Error:
        return {key: s.default for key, s in SETTINGS.items()}


def write(
    conn: psycopg.Connection, changes: dict[str, Any], admin_id: UUID
) -> list[str]:
    """Checks and saves the changes. A value of None returns a setting to
    its default. Answers the keys changed. Nothing is saved if any is wrong."""
    checked: dict[str, Any] = {}
    errors: dict[str, str] = {}
    for key, value in changes.items():
        setting = SETTINGS.get(key)
        if setting is None:
            errors[key] = "There's no such setting"
            continue
        if value is None:
            checked[key] = None
            continue
        try:
            checked[key] = setting.check(value)
        except SettingError as error:
            errors[key] = str(error)
    if errors:
        raise SettingErrors(errors)
    if "default_language" in checked and checked["default_language"] is not None:
        if not conn.execute(
            "select 1 from public.languages where code = %s",
            (checked["default_language"],),
        ).fetchone():
            raise SettingErrors({"default_language": "No such language. Add it first"})
    for key, value in checked.items():
        if value is None:
            conn.execute("delete from public.app_settings where key = %s", (key,))
        else:
            conn.execute(
                """
                insert into public.app_settings (key, value, updated_by, updated_at)
                values (%s, %s, %s, now())
                on conflict (key) do update set value = excluded.value,
                  updated_by = excluded.updated_by, updated_at = now()
                """,
                (key, Jsonb(value), admin_id),
            )
    return sorted(checked)


class SettingErrors(SettingError):
    """Each wrong setting, and why."""

    def __init__(self, errors: dict[str, str]) -> None:
        super().__init__("; ".join(f"{k}: {v}" for k, v in errors.items()))
        self.errors = errors


def payment_timeout(values: dict[str, Any], server_minutes: int) -> timedelta:
    """The stored timeout, or the server's when none is stored."""
    minutes = values.get("payment_timeout_minutes") or server_minutes
    return timedelta(minutes=minutes)
