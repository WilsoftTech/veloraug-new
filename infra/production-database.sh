#!/usr/bin/env bash
# Step 11E: sets up production's database from the server, in a throwaway
# container. Run by the owner over SSH, in a terminal (it asks questions):
#
#   bash /opt/veloraug/repo/infra/production-database.sh
#
# It asks once for the owner connection string of Neon's default branch,
# direct (not pooled), hidden as you paste. Then:
#   1. creates veloraug_app, which the first migration needs;
#   2. runs the migrations to head, then gives veloraug_editor and veloraug_media
#      logins, writing their pooled connection strings straight into
#      /opt/veloraug/env/api.env and media.env;
#   3. checks the database as veloraug_app.
#
# The scripts refuse any branch but the one whose Neon Auth URL is in
# api.env, so development can't be changed by mistake. Run it again to
# give the roles new passwords: the migrations are skipped when done.
set -euo pipefail

ROOT=/opt/veloraug
[ -t 0 ] || { echo "Run this in an SSH terminal: it asks questions." >&2; exit 1; }
grep -q '^VELORAUG_NEON_AUTH_URL=https://' "$ROOT/env/api.env" ||
  { echo "VELORAUG_NEON_AUTH_URL isn't in $ROOT/env/api.env" >&2; exit 1; }

docker run --rm -it \
  -v "$ROOT/repo:/repo:ro" \
  -v "$ROOT/env:/env" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
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

echo; echo "== 1. The API role, which the first migration needs"
python scripts/create_app_role.py --env-file /env/api.env

echo; echo "== 2. Migrations"
python -m alembic upgrade head
python -m alembic current

echo; echo "== 3. Logins for the roles the migrations made"
python scripts/create_app_role.py --role editor --env-file /env/api.env
python scripts/create_app_role.py --role media --env-file /env/media.env
unset VELORAUG_MIGRATION_DATABASE_URL
chown "$HOST_UID:$HOST_GID" /env/api.env /env/media.env
chmod 600 /env/api.env /env/media.env

echo; echo "== 4. Check, as veloraug_app"
export VELORAUG_DATABASE_URL=$(setting VELORAUG_DATABASE_URL /env/api.env)
python scripts/check_database.py
'
echo
echo "Done. Next: bash $ROOT/repo/infra/deploy.sh"
