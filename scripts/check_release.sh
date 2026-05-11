#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/web/install.sh"
bash -n "$ROOT/web/tools/xiaoma-hermes"

python3 -m json.tool "$ROOT/web/agent.json" >/dev/null
python3 -m json.tool "$ROOT/web/latest.json" >/dev/null
python3 -m json.tool "$ROOT/web/api/resolve" >/dev/null
python3 -m json.tool "$ROOT/web/api/resolve.sample.json" >/dev/null
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
resolve = json.loads((root / "web/api/resolve.sample.json").read_text(encoding="utf-8"))

for idx, compat in enumerate(("0.13.x", "legacy")):
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
if resolve["legacy_sha256"] != latest["packages"][1]["sha256"]:
    raise SystemExit("resolve legacy_sha256 不一致")

skill = json.loads((root / "web/packages/0.13.x/zh-CN/zh-cn.min.json").read_text(encoding="utf-8")).get("skill_markdown", "")
if "name: xiaoma-hermes-zh" not in skill:
    raise SystemExit("skill_markdown 缺少名称")
if "cat ... | python3" not in skill:
    raise SystemExit("skill_markdown 缺少危险命令规避说明")
PY

printf 'release ok\n'
