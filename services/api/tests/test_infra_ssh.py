"""VUG-SEC-012: the server trusts only GitHub's published host key.

infra/server-setup.sh and infra/deploy.sh pin GitHub's Ed25519 key instead
of accepting whatever ssh-keyscan is handed on the network. These checks
read the scripts; the pinned file they write is checked by running that part
of each script with a throwaway HOME.
"""

import base64
import hashlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

INFRA = Path(__file__).resolve().parents[3] / "infra"
SCRIPTS = ("server-setup.sh", "deploy.sh")
# From https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
GITHUB_ED25519_FINGERPRINT = "+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"
PINNED = re.compile(
    r"^\s*GITHUB_HOST_KEY='github\.com ssh-ed25519 ([A-Za-z0-9+/=]+)'$", re.M
)


def text(name: str) -> str:
    return (INFRA / name).read_text(encoding="utf-8")


@pytest.mark.parametrize("name", SCRIPTS)
def test_the_pinned_key_is_githubs_published_one(name):
    (key,) = PINNED.findall(text(name))
    digest = hashlib.sha256(base64.b64decode(key)).digest()
    assert base64.b64encode(digest).decode().rstrip("=") == GITHUB_ED25519_FINGERPRINT


@pytest.mark.parametrize("name", SCRIPTS)
def test_git_refuses_any_other_host_key(name):
    script = text(name)
    assert "ssh-keyscan" not in script
    assert "StrictHostKeyChecking=no" not in script
    assert "accept-new" not in script
    (command,) = re.findall(r'export GIT_SSH_COMMAND="([^"]*)"', script)
    for option in (
        "StrictHostKeyChecking=yes",
        "UserKnownHostsFile=$GITHUB_HOSTS",
        "GlobalKnownHostsFile=/dev/null",
        "UpdateHostKeys=no",
        "BatchMode=yes",
    ):
        assert f"-o {option}" in command


def test_setup_pins_the_key_before_it_first_reaches_github():
    script = text("server-setup.sh")
    pinned = script.index("export GIT_SSH_COMMAND=")
    assert pinned < script.index("git ls-remote")
    assert pinned < script.index("git clone")


def test_deploy_pins_the_key_before_it_fetches():
    script = text("deploy.sh")
    assert script.index("export GIT_SSH_COMMAND=") < script.index("git fetch")


@pytest.mark.skipif(
    shutil.which("bash") is None or sys.platform == "win32",
    reason="needs bash on Linux, as on the server",
)
@pytest.mark.parametrize("name", SCRIPTS)
def test_the_known_hosts_file_holds_only_the_pinned_key(name, tmp_path):
    script = text(name)
    start = script.index("GITHUB_HOST_KEY=")
    end = script.index("\n", script.index("export GIT_SSH_COMMAND=")) + 1
    part = "".join(line.strip() + "\n" for line in script[start:end].splitlines())
    home = tmp_path.as_posix()
    (tmp_path / ".ssh").mkdir()
    # An old trust-on-first-use entry for some other key stays where it was.
    (tmp_path / ".ssh" / "known_hosts").write_text("github.com ssh-ed25519 AAAAother\n")
    result = subprocess.run(
        ["bash", "-c", part + 'printf "%s" "$GIT_SSH_COMMAND"'],
        env={"HOME": home, "PATH": "/usr/bin:/bin"},
        capture_output=True,
        text=True,
        check=True,
    )
    hosts = tmp_path / ".ssh" / "veloraug_github_hosts"
    (key,) = PINNED.findall(script)
    assert hosts.read_text() == f"github.com ssh-ed25519 {key}\n"
    assert f"UserKnownHostsFile={home}/.ssh/veloraug_github_hosts" in result.stdout
