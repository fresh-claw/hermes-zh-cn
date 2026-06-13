#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/web/install.sh"
bash -n "$ROOT/web/install.command"
bash -n "$ROOT/web/tools/xiaoma-hermes"

python3 -m json.tool "$ROOT/web/agent.json" >/dev/null
python3 -m json.tool "$ROOT/web/latest.json" >/dev/null
python3 -m json.tool "$ROOT/web/platforms.json" >/dev/null
python3 -m json.tool "$ROOT/web/api/resolve" >/dev/null
python3 -m json.tool "$ROOT/web/api/resolve.sample.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/0.16.x/zh-CN/manifest.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/0.16.x/zh-CN/zh-cn.min.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/0.15.x/zh-CN/manifest.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/0.15.x/zh-CN/zh-cn.min.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/0.14.x/zh-CN/manifest.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/0.14.x/zh-CN/zh-cn.min.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/0.13.x/zh-CN/manifest.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/0.13.x/zh-CN/zh-cn.min.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/legacy/zh-CN/manifest.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/legacy/zh-CN/zh-cn.min.json" >/dev/null

python3 - "$ROOT" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
latest = json.loads((root / "web/latest.json").read_text(encoding="utf-8"))
platforms = json.loads((root / "web/platforms.json").read_text(encoding="utf-8"))
resolve = json.loads((root / "web/api/resolve.sample.json").read_text(encoding="utf-8"))

compats = ("0.16.x", "0.15.x", "0.14.x", "0.13.x", "legacy")
for idx, compat in enumerate(compats):
    pkg = root / f"web/packages/{compat}/zh-CN/zh-cn.min.json"
    manifest = json.loads((root / f"web/packages/{compat}/zh-CN/manifest.json").read_text(encoding="utf-8"))
    expected = hashlib.sha256(pkg.read_bytes()).hexdigest()
    checks = [
        latest["packages"][idx]["sha256"],
        manifest["files"][0]["sha256"],
    ]
    if any(value != expected for value in checks):
        raise SystemExit(f"{compat} sha256 不一致")

if resolve["sha256"] != latest["packages"][0]["sha256"]:
    raise SystemExit("resolve sha256 不一致")
if resolve["legacy_sha256"] != latest["packages"][-1]["sha256"]:
    raise SystemExit("resolve legacy_sha256 不一致")

windows_command = platforms["platforms"][0]["command"]
if "install.ps1" not in windows_command or "iex" not in windows_command:
    raise SystemExit("Windows 一键命令缺失")
if platforms["upstream"]["agent_version"] != "0.16.0":
    raise SystemExit("官方版本记录需为 0.16.0")
if not (root / "web/install.ps1").exists():
    raise SystemExit("缺少 install.ps1")

combined = "\n".join(
    (root / path).read_text(encoding="utf-8", errors="ignore")
    for path in (
        "web/index.html",
        "web/details.html",
        "web/app.js",
        "web/llms.txt",
        "web/llms-full.txt",
        "web/robots.txt",
        "web/sitemap.xml",
        "web/latest.json",
        "web/agent.json",
        "web/install-windows.cmd",
    )
)
if "useai.live" in combined:
    raise SystemExit("仍存在旧域名 useai.live")
if "20260612-exe-3" in combined:
    raise SystemExit("仍存在旧 Windows 安装器版本号")
if "fresh-claw/hermes-cn@v2026.06.12.1" in combined:
    raise SystemExit("仍存在旧固定标签备用地址")
if "20260613-exe-offline-3" not in latest["install_windows_exe"]:
    raise SystemExit("Windows 安装器缓存参数不是当前版本")
if "20260613-mac-main-1" not in latest["install_macos_zip"]:
    raise SystemExit("macOS 安装包缓存参数不是当前版本")

install_ps1 = (root / "web/install.ps1").read_text(encoding="utf-8", errors="ignore")
install_sh = (root / "web/install.sh").read_text(encoding="utf-8", errors="ignore")
install_command = (root / "web/install.command").read_text(encoding="utf-8", errors="ignore")
install_windows_cmd = (root / "web/install-windows.cmd").read_text(encoding="utf-8", errors="ignore")
verify_windows = (root / "web/scripts/verify-windows.ps1").read_text(encoding="utf-8", errors="ignore")
exe_bytes = (root / "web/Hermes-zh-CN-Setup.exe").read_bytes()
for name, text in (
    ("install.ps1", install_ps1),
    ("install.sh", install_sh),
    ("install.command", install_command),
    ("install-windows.cmd", install_windows_cmd),
):
    if "fresh-claw/hermes-cn@v2026.06.12.1" in text:
        raise SystemExit(f"{name} 仍使用旧固定标签备用地址")
if "Start-Process -FilePath python" in verify_windows or "python -m http.server" in verify_windows:
    raise SystemExit("Windows 自检仍依赖 Python HTTP 服务")
if "Start-LocalFileServer" not in verify_windows:
    raise SystemExit("Windows 自检缺少 PowerShell 本地文件服务")
for marker in (
    "Ensure-WindowsNode",
    "Get-LocalInstallerAssetPaths",
    "XIAOMA_HERMES_EXE_DIR",
    "Copy-OrDownloadInstallerFile",
    "Invoke-CurlDownload",
    "curl.exe",
    "node-v22.22.3-win-$Arch.zip",
    "Ensure-WindowsGitBash",
    "registry.npmmirror.com/-/binary/git-for-windows/",
    "MinGit-2.54.0-64-bit.zip",
):
    if marker not in install_ps1:
        raise SystemExit(f"install.ps1 缺少 {marker}")
    if marker.encode() not in exe_bytes:
        raise SystemExit(f"Windows EXE 缺少 {marker}")

skill = json.loads((root / "web/packages/0.15.x/zh-CN/zh-cn.min.json").read_text(encoding="utf-8")).get("skill_markdown", "")
if "name: xiaoma-hermes-zh" not in skill:
    raise SystemExit("skill_markdown 缺少名称")
if "cat ... | python3" not in skill:
    raise SystemExit("skill_markdown 缺少危险命令规避说明")
if "0.15.x" not in skill:
    raise SystemExit("skill_markdown 缺少 0.15.x 覆盖说明")
PY

printf 'release ok\n'
