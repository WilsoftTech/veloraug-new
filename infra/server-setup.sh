#!/usr/bin/env bash
# One-time setup of the Oracle server, Step 11B. Run as the ubuntu user, who
# can use sudo, after Docker is installed:
#
#   bash server-setup.sh
#
# Safe to run again: it only creates what is missing, and never overwrites a
# secret. It prints what the owner still has to do.
set -euo pipefail

ROOT=/opt/veloraug
REPO_URL=git@github.com:WilsoftTech/veloraug-new.git
DEPLOY_KEY="$HOME/.ssh/github_deploy"

say() { printf '\n== %s\n' "$*"; }

say "Folders"
sudo install -d -o "$USER" -g "$USER" -m 755 "$ROOT"
# Secrets: readable by the deploy account only.
install -d -m 700 "$ROOT/env"
# tusd and the media worker run as 1000:1000 (infra/compose.prod.yaml).
sudo install -d -o 1000 -g 1000 -m 750 "$ROOT/uploads" "$ROOT/output"
ls -ld "$ROOT" "$ROOT/env" "$ROOT/uploads" "$ROOT/output"

say "Empty settings files, mode 600"
for name in api media r2 tunnel; do
  file="$ROOT/env/$name.env"
  if [ ! -e "$file" ]; then
    install -m 600 /dev/null "$file"
    echo "created $file (empty)"
  else
    chmod 600 "$file"
    echo "kept $file"
  fi
done

say "Packages"
sudo apt-get install -y --no-install-recommends git unattended-upgrades >/dev/null
echo "git and unattended-upgrades installed"

say "Docker starts at boot"
sudo systemctl enable docker containerd >/dev/null
systemctl is-enabled docker

say "Deploy key for GitHub, read-only"
if [ ! -e "$DEPLOY_KEY" ]; then
  ssh-keygen -q -t ed25519 -N "" -C "veloraug-server deploy" -f "$DEPLOY_KEY"
fi
if ! grep -q "Host github.com" "$HOME/.ssh/config" 2>/dev/null; then
  cat >>"$HOME/.ssh/config" <<EOF
Host github.com
  IdentityFile $DEPLOY_KEY
  IdentitiesOnly yes
EOF
  chmod 600 "$HOME/.ssh/config"
fi
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

say "The repository"
if [ -d "$ROOT/repo/.git" ]; then
  echo "already cloned in $ROOT/repo"
elif git ls-remote "$REPO_URL" >/dev/null 2>&1; then
  git clone --branch main "$REPO_URL" "$ROOT/repo"
else
  echo "GitHub doesn't accept the deploy key yet. Add this public key to"
  echo "github.com/WilsoftTech/veloraug-new, Settings, Deploy keys, Add deploy key,"
  echo "with 'Allow write access' OFF, then run this script again:"
  echo
  cat "$DEPLOY_KEY.pub"
fi

say "Still to do"
echo "1. Fill in $ROOT/env/*.env (see infra/README.md, Production)."
echo "2. Run: bash $ROOT/repo/infra/deploy.sh"
