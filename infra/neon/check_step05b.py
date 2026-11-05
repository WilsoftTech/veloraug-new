"""Read-only checks of the real Step 5B configuration. Changes nothing.

Run from anywhere with: python infra/neon/check_step05b.py

Each line is PASS, FAIL or SKIP. It prints only public values, and exits with 1
if any check fails.
"""

import json
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from email.message import Message
from pathlib import Path

PROJECT_ID = "rapid-violet-90573131"
BRANCH = "development"
NEON = ["npx", "--yes", "neon@8.17.1"]
PACKAGE = "com.example.veloraug"
DEBUG_CERT = (
    "50:2F:52:2C:26:FC:C5:DB:38:A0:C5:48:8E:33:DF:A4:"
    "D5:BF:C2:03:C4:CA:B5:04:86:04:C8:92:57:E8:87:D1"
)
PAGES_URL = "https://veloraug-auth-dev.pages.dev"
RESOURCE = "https://api-dev.veloraug.invalid"
WEB_CALLBACK = "http://localhost:8765/auth.html"
ANDROID_CALLBACK = f"{PAGES_URL}/auth/callback/android"
ADB = Path.home() / "AppData/Local/Android/Sdk/platform-tools/adb.exe"
REPO = Path(__file__).resolve().parents[2]

failures = 0


def report(result: str, name: str, detail: object = "") -> None:
    global failures
    if result == "FAIL":
        failures += 1
    print(f"{result:<5}{name}{f': {detail}' if detail != '' else ''}", flush=True)


def check(name: str, passed: bool, detail: object = "") -> bool:
    report("PASS" if passed else "FAIL", name, detail)
    return passed


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def fetch(url: str) -> tuple[int, Message, bytes]:
    """Returns the status, headers and body, without following a redirect.

    The headers stay in urllib's own object, because header names are not case
    sensitive and Cloudflare Pages sends those from _headers in lower case.
    """
    opener = urllib.request.build_opener(_NoRedirect)
    request = urllib.request.Request(url, headers={"User-Agent": "veloraug-check"})
    try:
        with opener.open(request, timeout=25) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read()


def denies_framing(headers: Message) -> bool:
    return "frame-ancestors 'none'" in headers.get("Content-Security-Policy", "")


def neon(*args: str) -> str | None:
    command = [*NEON, *args, "--project-id", PROJECT_ID, "--branch", BRANCH]
    executable = shutil.which(command[0])
    if executable is None:
        return None
    done = subprocess.run(
        [executable, *command[1:]], capture_output=True, text=True, timeout=180
    )
    return done.stdout if done.returncode == 0 else None


def check_auth_url(auth_url: str) -> None:
    print("\nAuth server (G1)")
    try:
        status, _, body = fetch(f"{auth_url}/.well-known/oauth-authorization-server")
        check("metadata reachable", status == 200, status)
        if status == 200:
            metadata = json.loads(body)
            check("issuer equals the Auth URL", metadata.get("issuer") == auth_url)
            for key in ("authorization_endpoint", "token_endpoint", "revocation_endpoint"):
                check(f"lists {key}", key in metadata)
            check(
                "S256 offered",
                "S256" in metadata.get("code_challenge_methods_supported", []),
            )
        status, _, body = fetch(f"{auth_url}/.well-known/jwks.json")
        keys = json.loads(body).get("keys", []) if status == 200 else []
        check(
            "JWKS lists an Ed25519 key",
            any(k.get("crv") == "Ed25519" and k.get("kty") == "OKP" for k in keys),
        )
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        check("auth server readable", False, type(error).__name__)


def check_clients(defines: dict) -> None:
    print("\nRegistered OAuth clients (exact callbacks)")
    output = neon("neon-auth", "oauth-client", "list", "--output", "json")
    if output is None:
        report("FAIL", "could not read the clients. Is the OAuth provider enabled?")
        return
    clients = json.loads(output)
    if isinstance(clients, dict):
        clients = clients.get("clients", [])
    by_id = {client.get("client_id"): client for client in clients}
    for label, key, callback in (
        ("web", "NEON_AUTH_WEB_CLIENT_ID", WEB_CALLBACK),
        ("Android", "NEON_AUTH_ANDROID_CLIENT_ID", ANDROID_CALLBACK),
    ):
        client = by_id.get(defines.get(key))
        if not check(f"{label} client exists", client is not None):
            continue
        check(f"{label} client is public", client.get("type") == "public")
        check(f"{label} consent is not skipped", not client.get("skip_consent"))
        check(
            f"{label} callback is exact",
            client.get("redirect_uris") == [callback],
            client.get("redirect_uris"),
        )
        check(
            f"{label} resource is exact",
            client.get("resources") == [RESOURCE],
            client.get("resources"),
        )


def check_settings(defines: dict) -> None:
    print("\nLocal settings against the code")
    check("AUTH_PAGES_URL", defines.get("AUTH_PAGES_URL") == PAGES_URL)
    check("API_RESOURCE", defines.get("API_RESOURCE") == RESOURCE)
    joined = json.dumps(defines).lower()
    check(
        "no secret-like value",
        not re.search(r"secret|password|postgres|npg_|napi_", joined),
    )
    manifest = (
        REPO / "apps/client/android/app/src/debug/AndroidManifest.xml"
    ).read_text(encoding="utf8")
    parts = urllib.parse.urlsplit(ANDROID_CALLBACK)
    check("manifest host matches", f'android:host="{parts.hostname}"' in manifest)
    check("manifest path matches", f'android:path="{parts.path}"' in manifest)


def check_site() -> None:
    print("\nDeployed pages")
    try:
        status, headers, body = fetch(f"{PAGES_URL}/.well-known/assetlinks.json")
        check("assetlinks.json is 200 with no redirect", status == 200, status)
        if status == 200:
            check(
                "assetlinks.json is JSON",
                headers.get("Content-Type", "").startswith("application/json"),
                headers.get("Content-Type"),
            )
            target = json.loads(body)[0]["target"]
            check("package ID is the app's", target.get("package_name") == PACKAGE)
            check(
                "certificate is the debug certificate",
                DEBUG_CERT in target.get("sha256_cert_fingerprints", []),
            )
        for path in ("/login", "/consent", "/auth/callback/android"):
            status, headers, _ = fetch(f"{PAGES_URL}{path}")
            check(f"{path} is 200 with no redirect", status == 200, status)
            check(f"{path} sends frame-ancestors", denies_framing(headers))
        query = urllib.parse.urlencode(
            {
                "source.web.site": PAGES_URL,
                "relation": "delegate_permission/common.handle_all_urls",
                "target.android_app.package_name": PACKAGE,
                "target.android_app.certificate.sha256_fingerprint": DEBUG_CERT,
            }
        )
        status, _, body = fetch(
            f"https://digitalassetlinks.googleapis.com/v1/assetlinks:check?{query}"
        )
        check(
            "Google's Digital Asset Links service confirms the link",
            status == 200 and json.loads(body).get("linked") is True,
            status,
        )
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        check("site readable", False, type(error).__name__)


def check_phone() -> None:
    print("\nPhone (G6: this is the proof that a pages.dev address can't give)")
    if not ADB.exists():
        report("SKIP", "adb not found")
        return
    devices = subprocess.run(
        [str(ADB), "devices"], capture_output=True, text=True, timeout=30
    ).stdout
    if not re.search(r"\tdevice$", devices, re.M):
        report("SKIP", "no phone connected")
        return
    links = subprocess.run(
        [str(ADB), "shell", "pm", "get-app-links", PACKAGE],
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout
    if PACKAGE not in links:
        report("SKIP", "the app is not installed on the phone")
        return
    host = urllib.parse.urlsplit(PAGES_URL).hostname
    match = re.search(rf"{re.escape(host)}:\s*(\S+)", links)
    state = match.group(1) if match else "host not listed"
    check("Android verified the domain", state == "verified", state)


def main() -> int:
    defines_path = REPO / "apps/client/dart_defines.local.json"
    if defines_path.exists():
        defines = json.loads(defines_path.read_text(encoding="utf8"))
        auth_url = defines.get("NEON_AUTH_URL", "")
        check_auth_url(auth_url)
        check_clients(defines)
        check_settings(defines)
    else:
        report("FAIL", "apps/client/dart_defines.local.json is missing")
    check_site()
    check_phone()
    print(f"\n{'All checks that ran passed.' if not failures else f'{failures} failed.'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
