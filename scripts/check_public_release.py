#!/usr/bin/env python3
import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "web"
FILES = (
    "index.html",
    "latest.json",
    "agent.json",
    "install.ps1",
    "install.sh",
    "install.command",
    "install-windows.cmd",
    "scripts/verify-windows.ps1",
    "Hermes-zh-CN-Setup.exe",
    "hermes-macos-installer.zip",
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def comparable(name: str, data: bytes) -> bytes:
    if name == "index.html":
        cloudflare = data.find(b'<script type="module" src="https://static.cloudflareinsights.com/')
        if cloudflare >= 0:
            closing_body = data.lower().rfind(b"</body>")
            if closing_body > cloudflare:
                data = data[:cloudflare] + data[closing_body:]
        end = data.lower().find(b"</html>")
        if end >= 0:
            return data[: end + len(b"</html>")]
    return data


def fetch(url: str, timeout: int) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (release verification; +https://useai.live/hermes)"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="https://useai.live/hermes")
    parser.add_argument("--timeout", type=int, default=20)
    args = parser.parse_args()
    base = args.base_url.rstrip("/")

    rows = []
    ok = True
    combined_parts = []
    for name in FILES:
        local = (WEB / name).read_bytes()
        try:
            remote = fetch(f"{base}/{name}?verify=20260613-offline-2", args.timeout)
            error = None
        except Exception as exc:
            remote = b""
            error = str(exc)

        local_sha = digest(local)
        remote_sha = digest(remote) if remote else ""
        match = bool(remote) and comparable(name, local) == comparable(name, remote)
        ok = ok and match
        if name.endswith((".html", ".json", ".ps1", ".sh", ".cmd", ".txt")):
            combined_parts.append(remote.decode("utf-8", errors="ignore"))
        rows.append(
            {
                "file": name,
                "local_size": len(local),
                "remote_size": len(remote),
                "local_sha256": local_sha,
                "remote_sha256": remote_sha,
                "match": match,
                "error": error,
            }
        )

    combined = "\n".join(combined_parts)
    flags = {
        "has_current_windows_marker": "20260822-exe-0.20.5-1" in combined,
        "has_current_macos_marker": "20260822-mac-0.20.5-1" in combined,
        "has_main_fallback": "hermes-cn@main" in combined,
        "has_windows_git_fix": "Ensure-WindowsGitBash" in combined,
        "has_node_fixed_fallback": "node-v22.22.3-win-$Arch.zip" in combined,
        "has_old_tag": "hermes-cn@v2026.06.12.1" in combined,
        "has_old_windows_marker": "20260613-exe-git-1" in combined or "20260612-exe-3" in combined,
    }
    ok = ok and all(
        flags[key]
        for key in (
            "has_current_windows_marker",
            "has_current_macos_marker",
            "has_main_fallback",
            "has_windows_git_fix",
            "has_node_fixed_fallback",
        )
    )
    ok = ok and not flags["has_old_tag"] and not flags["has_old_windows_marker"]

    report = {"base_url": base, "ok": ok, "files": rows, "flags": flags}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
