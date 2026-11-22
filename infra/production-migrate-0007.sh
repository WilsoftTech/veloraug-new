#!/usr/bin/env bash
# Milestone 10: migration 0007 on production's database, from the server, in
# a throwaway container. Run by the owner over SSH, in a terminal, after the
# backup branch in docs/step-10h-live-runbook.md:
#
#   bash /opt/veloraug/repo/infra/production-migrate-0007.sh
#
# It asks once for the owner connection string of Neon's default branch,
# direct (not pooled), hidden as you paste. Then:
#   1. runs the read-only preflight, and stops if anything fails;
#   2. migrates to 0007 only if you type MIGRATE;
#   3. checks the database as veloraug_app.
#
# Unlike production-database.sh, it never touches the roles' passwords. The
# scripts refuse any branch but the one whose Neon Auth URL is in api.env.
set -euo pipefail

ROOT=/opt/veloraug
[ -t 0 ] || { echo "Run this in an SSH terminal: it asks questions." >&2; exit 1; }
grep -q '^VELORAUG_NEON_AUTH_URL=https://' "$ROOT/env/api.env" ||
  { echo "VELORAUG_NEON_AUTH_URL isn't in $ROOT/env/api.env" >&2; exit 1; }

docker run --rm -it \
  -v "$ROOT/repo:/repo:ro" \
  -v "$ROOT/env:/env:ro" \
  python:3.13-slim-trixie bash -c '
set -euo pipefail
cp -r /repo/services/api /work && cd /work
echo "Installing the migration tools..."
pip install -q --disable-pip-version-check --root-user-action=ignore \
  -r requirements-migrate.txt
setting() { sed -n "s/^$1=//p" "$2" | tail -1; }
export VELORAUG_NEON_AUTH_URL=$(setting VELORAUG_NEON_AUTH_URL /env/api.env)
echo
echo "Production sign-in: $VELORAUG_NEON_AUTH_URL"
read -rsp "Owner connection string of the default branch, direct (hidden): " url
echo
export VELORAUG_MIGRATION_DATABASE_URL="$url"
unset url

echo; echo "== 1. Preflight (read-only)"
python scripts/preflight_0007.py

echo
read -rp "Backup branch made and listed in the Neon Console? Type MIGRATE to run 0007: " answer
[ "$answer" = MIGRATE ] || { echo "Stopped. Nothing changed."; exit 1; }

echo; echo "== 2. Migration 0007"
python -m alembic upgrade 0007
python -m alembic current
unset VELORAUG_MIGRATION_DATABASE_URL

echo; echo "== 3. Check, as veloraug_app"
export VELORAUG_DATABASE_URL=$(setting VELORAUG_DATABASE_URL /env/api.env)
python scripts/check_database.py
'
echo
echo "Done. Next: bash $ROOT/repo/infra/deploy.sh --migrated"
