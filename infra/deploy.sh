#!/usr/bin/env bash
# Deploys main to the Oracle server, decision 17 of
# docs/step-11a-pilot-deployment-plan.md. Run by the owner over SSH:
#
#   bash /opt/veloraug/repo/infra/deploy.sh             # pull main, build, restart
#   bash /opt/veloraug/repo/infra/deploy.sh --migrated  # the same, once a new
#                                                       # migration has been run
#   bash /opt/veloraug/repo/infra/deploy.sh --no-pull   # rebuild what's checked out
#
# It stops, changing nothing that is running, if the settings files are
# missing or readable by others, or if the pull brings a migration and
# --migrated wasn't given. Migrations are never run here: the owner runs them
# from their own terminal, as before. It ends with the health checks.
set -euo pipefail

ROOT=/opt/veloraug
REPO="$ROOT/repo"
COMPOSE=(docker compose -f "$REPO/infra/compose.prod.yaml")
PUBLIC_HEALTH=https://api.veloraug.com/health

migrated=false
pull=true
for arg in "$@"; do
  case "$arg" in
    --migrated) migrated=true ;;
    --no-pull) pull=false ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

fail() { echo "STOPPED: $*" >&2; exit 1; }
say() { printf '\n== %s\n' "$*"; }

say "Settings files"
for name in api media r2 tunnel; do
  file="$ROOT/env/$name.env"
  [ -s "$file" ] || fail "$file is missing or empty"
  mode=$(stat -c %a "$file")
  [ "$mode" = 600 ] || fail "$file is mode $mode; run: chmod 600 $file"
  echo "ok  $file"
done

cd "$REPO"
# The commit last deployed, written at the end of a successful run. Comparing
# with it, not with what was checked out, means a pull that stopped for a
# migration still stops on the next run, until --migrated is given.
DEPLOYED_FILE="$ROOT/deployed-commit"
before=$(cat "$DEPLOYED_FILE" 2>/dev/null || git rev-parse HEAD)
if $pull; then
  say "Pulling main"
  [ -z "$(git status --porcelain)" ] || fail "the checkout has local changes; see git status"
  # GitHub's Ed25519 host key, pinned (VUG-SEC-012). Published with its
  # fingerprint, SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU, at
  # https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
  # Kept in its own file, so an older trust-on-first-use entry in known_hosts
  # can't vouch for another key. Git then refuses any host that differs.
  GITHUB_HOST_KEY='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
  GITHUB_HOSTS="$HOME/.ssh/veloraug_github_hosts"
  install -d -m 700 "$HOME/.ssh"
  printf '%s\n' "$GITHUB_HOST_KEY" >"$GITHUB_HOSTS"
  chmod 600 "$GITHUB_HOSTS"
  export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o HostKeyAlgorithms=ssh-ed25519 -o UserKnownHostsFile=$GITHUB_HOSTS -o GlobalKnownHostsFile=/dev/null -o UpdateHostKeys=no"
  git fetch --quiet origin main
  git checkout --quiet main
  git merge --ff-only --quiet origin/main
fi
after=$(git rev-parse HEAD)
echo "$(git log -1 --format='%h %s')"

if [ "$before" != "$after" ]; then
  new_migrations=$(git diff --name-only --diff-filter=A "$before" "$after" -- \
    services/api/migrations/versions)
  if [ -n "$new_migrations" ] && ! $migrated; then
    echo "$new_migrations"
    fail "this brings a new migration. Run it on production first, from your own
terminal, then run this again with --migrated. The code is pulled, but the
running services are unchanged."
  fi
fi

say "Building"
"${COMPOSE[@]}" build --pull

say "Checking API settings before restart"
"${COMPOSE[@]}" run --rm --no-deps -T api python -c 'from app.config import Settings; Settings()' \
  || fail "the API refuses its settings (above); nothing was restarted"

say "Starting"
"${COMPOSE[@]}" up -d --remove-orphans

say "Waiting for the API to be healthy"
for _ in $(seq 1 30); do
  state=$(docker inspect --format '{{.State.Health.Status}}' veloraug-api-1 2>/dev/null || true)
  [ "$state" = healthy ] && break
  sleep 3
done
[ "$state" = healthy ] || {
  "${COMPOSE[@]}" logs --tail 40 api
  fail "the API isn't healthy ($state). Its last log lines are above"
}
echo "api: healthy"

say "Services"
"${COMPOSE[@]}" ps --format 'table {{.Service}}\t{{.Status}}'

say "Through the tunnel"
if code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$PUBLIC_HEALTH"); then
  if [ "$code" = 200 ]; then
    echo "$PUBLIC_HEALTH: 200"
  else
    echo "WARNING: $PUBLIC_HEALTH answered $code. Check the tunnel's public hostname"
  fi
else
  echo "WARNING: $PUBLIC_HEALTH didn't answer. Is the tunnel set up yet (Step 11D)?"
fi

echo "$after" >"$DEPLOYED_FILE"
say "Deployed $(git log -1 --format='%h')"
docker image prune -f >/dev/null
