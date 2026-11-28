"""Durable Pesapal notification queue for the single API service."""

import logging
import sqlite3
import threading
import time
from contextlib import closing
from pathlib import Path

logger = logging.getLogger("veloraug.payments")
MAX_JOBS = 10000
RETRY_SECONDS = 30


class PaymentQueue:
    def __init__(self, path: Path, check):
        self.path = path
        self.check = check
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._run)
        with closing(self._connect()) as db, db:
            db.execute("""
                create table if not exists notifications (
                    tracking_id text primary key, due integer not null,
                    generation integer not null default 0
                )
            """)
            db.execute(
                "create index if not exists notifications_due on notifications (due)"
            )

    def _connect(self):
        return sqlite3.connect(self.path, timeout=2)

    def submit(self, tracking_id: str) -> bool:
        with closing(self._connect()) as db, db:
            db.execute("begin immediate")
            updated = db.execute(
                """
                update notifications set generation = generation + 1
                where tracking_id = ?
            """,
                (tracking_id,),
            )
            if updated.rowcount:
                return True
            if (
                db.execute("select count(*) from notifications").fetchone()[0]
                >= MAX_JOBS
            ):
                return False
            db.execute(
                "insert into notifications (tracking_id, due) values (?, ?)",
                (tracking_id, int(time.time())),
            )
            return True

    def run_one(self) -> bool:
        now = int(time.time())
        with closing(self._connect()) as db, db:
            db.execute("begin immediate")
            job = db.execute(
                """
                select tracking_id, generation from notifications
                where due <= ? order by due limit 1
            """,
                (now,),
            ).fetchone()
            if job is None:
                return False
            tracking_id, generation = job
            db.execute(
                "update notifications set due = ? where tracking_id = ?",
                (now + RETRY_SECONDS, tracking_id),
            )
        try:
            done = self.check(tracking_id)
        except Exception as error:
            logger.warning(
                "Payment notification check failed (%s)", type(error).__name__
            )
            return True
        if done:
            # Keep a cooldown row, even if another notification arrives just
            # after success. A later generation must still be processed.
            with closing(self._connect()) as db, db:
                db.execute(
                    """
                    update notifications set generation = -1
                    where tracking_id = ? and generation = ?
                """,
                    (tracking_id, generation),
                )
        return True

    def _run(self):
        while not self.stop.is_set():
            try:
                with closing(self._connect()) as db, db:
                    db.execute(
                        "delete from notifications where generation = -1 and due <= ?",
                        (int(time.time()),),
                    )
                if self.run_one():
                    continue
            except sqlite3.Error as error:
                logger.warning(
                    "Payment notification queue unavailable (%s)", type(error).__name__
                )
            self.stop.wait(1)

    def close(self):
        self.stop.set()
        self.thread.join()
