"""Publishing converted originals to private Cloudflare R2, and removing them.

The media worker calls this once an original is converted and 'publishing'.
Every chunk is uploaded first, then each quality's playlist, then the master
playlist, so no playlist ever names a file that isn't there yet. Every
object's size is checked in R2 before the original is marked 'ready'. Only
then are the local copies deleted. See "R2" in docs/step-07a-uploads-plan.md.

Until 19 November 2026 the original itself also went to R2, in Infrequent
Access, under originals/. It no longer does: the owner keeps their own copy,
which saves about a third of each film's storage. Removing an original still
deletes anything left under originals/.

Paths in R2 use VeloraUG's IDs only:

    movies/<item id>/<original id>/master.m3u8
    movies/<item id>/<original id>/<quality>/index.m3u8, init_N.mp4, seg_*.m4s,
        and download.mp4, the whole video as one file, since Step 12A
    originals/<original id>   (published before 19 November 2026 only)
"""

import logging
import re
import shutil
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol
from urllib.parse import urlsplit

from pydantic import SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from app.db import Database
from app.playback import DOWNLOAD_FILE

logger = logging.getLogger("veloraug.media_worker")

CONTENT_TYPES = {
    ".m3u8": "application/vnd.apple.mpegurl",
    ".m4s": "video/iso.segment",
    ".mp4": "video/mp4",
}
# Every path includes the original's ID, so a published file never changes.
IMMUTABLE = "max-age=31536000, immutable"


class PublishError(Exception):
    """Publishing can't finish. The message is shown to the owner."""


class Store(Protocol):
    def upload(
        self,
        path: Path,
        key: str,
        content_type: str,
        cache_control: str | None = None,
        infrequent: bool = False,
    ) -> None: ...

    def size(self, key: str) -> int | None: ...

    def delete_prefix(self, prefix: str) -> int: ...

    def download(self, key: str, path: Path) -> None: ...


class R2Settings(BaseSettings):
    """VELORAUG_R2_* variables, from services/api/.env.r2, which only the
    worker's container gets. All four, or none: without them the worker
    converts, and originals wait in 'publishing'."""

    model_config = SettingsConfigDict(
        env_prefix="VELORAUG_R2_", env_ignore_empty=True, hide_input_in_errors=True
    )

    endpoint: str | None = None
    bucket: str | None = None
    access_key_id: SecretStr | None = None
    secret_access_key: SecretStr | None = None

    @field_validator("endpoint")
    @classmethod
    def require_r2_endpoint(cls, url: str | None) -> str | None:
        if url is None:
            return None
        parts = urlsplit(url)
        host = parts.hostname or ""
        if parts.scheme != "https" or not host.endswith(".r2.cloudflarestorage.com"):
            raise ValueError(
                "endpoint must be https://<account ID>.r2.cloudflarestorage.com"
            )
        # Kept for now: the bucket's own name on the end, as the dashboard shows
        # the address, is removed once the bucket is known, below.
        path = parts.path.strip("/")
        return f"https://{host}" + (f"/{path}" if path else "")

    @field_validator("bucket")
    @classmethod
    def require_bucket_name(cls, bucket: str | None) -> str | None:
        if bucket is not None and not re.fullmatch(
            r"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]", bucket
        ):
            raise ValueError("bucket must be an R2 bucket name, such as veloraug-dev")
        return bucket

    @model_validator(mode="after")
    def all_or_none(self) -> "R2Settings":
        given = [
            self.endpoint,
            self.bucket,
            self.access_key_id,
            self.secret_access_key,
        ]
        if any(v is not None for v in given) and not all(v is not None for v in given):
            raise ValueError(
                "Set VELORAUG_R2_ENDPOINT, VELORAUG_R2_BUCKET, "
                "VELORAUG_R2_ACCESS_KEY_ID and VELORAUG_R2_SECRET_ACCESS_KEY "
                "together, or none of them"
            )
        if self.endpoint is not None:
            parts = urlsplit(self.endpoint)
            path = parts.path.strip("/")
            if path and path != self.bucket:
                raise ValueError(
                    "endpoint must be https://<account ID>.r2.cloudflarestorage.com, "
                    f"without /{path} on the end"
                )
            # The dashboard shows the address with the bucket on the end.
            self.endpoint = f"https://{parts.hostname}"
        return self

    @property
    def configured(self) -> bool:
        return self.endpoint is not None


class R2Store:
    """The bucket, through R2's S3-compatible API, with boto3."""

    def __init__(self, settings: R2Settings) -> None:
        import boto3
        from boto3.s3.transfer import TransferConfig
        from botocore.config import Config

        self.bucket = settings.bucket
        self.client = boto3.client(
            "s3",
            endpoint_url=settings.endpoint,
            aws_access_key_id=settings.access_key_id.get_secret_value(),
            aws_secret_access_key=settings.secret_access_key.get_secret_value(),
            region_name="auto",
            config=Config(
                # Only the checksums S3 requires, so newer boto3 defaults
                # can't send headers R2 doesn't accept.
                request_checksum_calculation="when_required",
                response_checksum_validation="when_required",
                retries={"max_attempts": 5, "mode": "standard"},
                connect_timeout=10,
                read_timeout=120,
            ),
        )
        # Originals up to 50 GB go up in 64 MB parts, 4 at a time.
        self.transfer = TransferConfig(
            multipart_threshold=64 * 1024**2,
            multipart_chunksize=64 * 1024**2,
            max_concurrency=4,
        )

    def upload(
        self,
        path: Path,
        key: str,
        content_type: str,
        cache_control: str | None = None,
        infrequent: bool = False,
    ) -> None:
        extra = {"ContentType": content_type}
        if cache_control:
            extra["CacheControl"] = cache_control
        if infrequent:
            extra["StorageClass"] = "STANDARD_IA"
        self.client.upload_file(
            str(path), self.bucket, key, ExtraArgs=extra, Config=self.transfer
        )

    def size(self, key: str) -> int | None:
        from botocore.exceptions import ClientError

        try:
            return self.client.head_object(Bucket=self.bucket, Key=key)["ContentLength"]
        except ClientError as error:
            if error.response.get("Error", {}).get("Code") in ("404", "NoSuchKey"):
                return None
            raise

    def download(self, key: str, path: Path) -> None:
        self.client.download_file(self.bucket, key, str(path), Config=self.transfer)

    def storage_class(self, key: str) -> str:
        head = self.client.head_object(Bucket=self.bucket, Key=key)
        return head.get("StorageClass", "STANDARD")

    def delete_prefix(self, prefix: str) -> int:
        deleted = 0
        pages = self.client.get_paginator("list_objects_v2").paginate(
            Bucket=self.bucket, Prefix=prefix
        )
        for page in pages:
            keys = [{"Key": item["Key"]} for item in page.get("Contents", [])]
            if keys:
                self.client.delete_objects(
                    Bucket=self.bucket, Delete={"Objects": keys, "Quiet": True}
                )
                deleted += len(keys)
        return deleted


@dataclass(frozen=True)
class Quality:
    name: str
    width: int
    height: int
    bandwidth: int


_STREAM = re.compile(r"#EXT-X-STREAM-INF:(?P<attrs>.*)")


def read_master(path: Path) -> list[Quality]:
    """The qualities a master playlist lists, from FFmpeg's own figures."""
    lines = path.read_text(encoding="utf-8").splitlines()
    qualities = []
    for index, line in enumerate(lines):
        match = _STREAM.match(line)
        if not match:
            continue
        attrs = dict(re.findall(r'([A-Z-]+)=("[^"]*"|[^,]*)', match.group("attrs")))
        width, height = (int(n) for n in attrs["RESOLUTION"].split("x"))
        playlist = next(x for x in lines[index + 1 :] if x and not x.startswith("#"))
        qualities.append(
            Quality(playlist.split("/")[0], width, height, int(attrs["BANDWIDTH"]))
        )
    return qualities


def ladder_height(quality: Quality) -> int:
    """The quality's rung, 360 to 1080, from its folder name."""
    return int(quality.name.rstrip("p"))


class Publisher:
    def __init__(
        self, database: Database, store: Store, upload_dir: Path, output_dir: Path
    ) -> None:
        self.database = database
        self.store = store
        self.upload_dir = upload_dir
        self.output_dir = output_dir

    def _item(self, original_id: uuid.UUID) -> uuid.UUID:
        """The item the original belongs to. Its R2 folder is still called
        movies/, so files published before items existed keep their paths."""
        with self.database.anonymous() as conn:
            (item_id,) = conn.execute(
                "select item_id from public.media_originals where id = %s",
                (original_id,),
            ).fetchone()
        return item_id

    def publish(self, original_id: uuid.UUID) -> None:
        item_id = self._item(original_id)
        out = self.output_dir / str(original_id)
        source = self.upload_dir / str(original_id)
        if not (out / "master.m3u8").is_file() or not source.is_file():
            raise PublishError("The converted files or the original are missing.")
        qualities = read_master(out / "master.m3u8")
        prefix = f"movies/{item_id}/{original_id}"

        sent: dict[str, int] = {}

        def send(path: Path, key: str, content_type: str, **options) -> None:
            self.store.upload(path, key, content_type, **options)
            sent[key] = path.stat().st_size

        for quality in qualities:
            folder = out / quality.name
            files = sorted(p for p in folder.iterdir() if p.name != "index.m3u8")
            for path in [*files, folder / "index.m3u8"]:
                send(
                    path,
                    f"{prefix}/{quality.name}/{path.name}",
                    CONTENT_TYPES[path.suffix],
                    cache_control=IMMUTABLE,
                )
        send(
            out / "master.m3u8",
            f"{prefix}/master.m3u8",
            CONTENT_TYPES[".m3u8"],
            cache_control=IMMUTABLE,
        )
        # Since 19 November 2026 the original isn't sent: the owner keeps
        # their own copy, and 1080p is close enough to convert again from.

        for key, expected in sent.items():
            found = self.store.size(key)
            if found != expected:
                raise PublishError(
                    f"R2 has {found} bytes for {key.rsplit('/', 2)[-2:]} "
                    f"instead of {expected}."
                )

        with self.database.anonymous() as conn:
            for quality in qualities:
                # The streamed chunks only: the download file is the same
                # video again.
                size = sum(
                    p.stat().st_size
                    for p in (out / quality.name).iterdir()
                    if p.name != DOWNLOAD_FILE
                )
                conn.execute(
                    """
                    insert into public.media_renditions
                      (original_id, height, width, bandwidth, size_bytes)
                    values (%s, %s, %s, %s, %s)
                    on conflict (original_id, height) do nothing
                    """,
                    (
                        original_id,
                        ladder_height(quality),
                        quality.width,
                        quality.bandwidth,
                        size,
                    ),
                )
            # The new original takes over. The old one is removed next.
            replaced = conn.execute(
                """
                update public.media_originals
                set state = 'removing', updated_at = now()
                where item_id = %s and state = 'ready' and id <> %s
                returning id
                """,
                (item_id, original_id),
            ).fetchall()
            conn.execute(
                """
                update public.media_originals
                set state = 'ready', ready_at = now(), updated_at = now(), reason = null
                where id = %s
                """,
                (original_id,),
            )
        for (old,) in replaced:
            logger.info("original %s replaced by %s", old, original_id)

        shutil.rmtree(out, ignore_errors=True)
        source.unlink(missing_ok=True)
        source.with_name(source.name + ".info").unlink(missing_ok=True)
        logger.info(
            "original %s published: %s objects, %s",
            original_id,
            len(sent),
            ", ".join(q.name for q in qualities),
        )

    def remove(self, original_id: uuid.UUID) -> int:
        """Deletes an original's files from R2 and this computer, and marks it
        'removed'. Infrequent Access still bills an original for 30 days."""
        item_id = self._item(original_id)
        deleted = self.store.delete_prefix(f"movies/{item_id}/{original_id}/")
        deleted += self.store.delete_prefix(f"originals/{original_id}")
        with self.database.anonymous() as conn:
            conn.execute(
                "delete from public.media_renditions where original_id = %s",
                (original_id,),
            )
            conn.execute(
                """
                update public.media_originals set state = 'removed', updated_at = now()
                where id = %s
                """,
                (original_id,),
            )
        shutil.rmtree(self.output_dir / str(original_id), ignore_errors=True)
        source = self.upload_dir / str(original_id)
        source.unlink(missing_ok=True)
        source.with_name(source.name + ".info").unlink(missing_ok=True)
        logger.info("original %s removed: %s objects deleted", original_id, deleted)
        return deleted
