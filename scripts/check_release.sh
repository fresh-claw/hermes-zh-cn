#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/web/install.sh"
bash -n "$ROOT/web/tools/xiaoma-hermes"

python3 -m json.tool "$ROOT/web/agent.json" >/dev/null
python3 -m json.tool "$ROOT/web/latest.json" >/dev/null
python3 -m json.tool "$ROOT/web/api/resolve.sample.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/0.13.x/zh-CN/manifest.json" >/dev/null
python3 -m json.tool "$ROOT/web/packages/0.13.x/zh-CN/zh-cn.min.json" >/dev/null

python3 - "$ROOT" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
pkg = root / "web/packages/0.13.x/zh-CN/zh-cn.min.json"
expected = hashlib.sha256(pkg.read_bytes()).hexdigest()

latest = json.loads((root / "web/latest.json").read_text(encoding="utf-8"))
manifest = json.loads((root / "web/packages/0.13.x/zh-CN/manifest.json").read_text(encoding="utf-8"))
resolve = json.loads((root / "web/api/resolve.sample.json").read_text(encoding="utf-8"))

checks = [
    latest["packages"][0]["sha256"],
    manifest["files"][0]["sha256"],
    resolve["sha256"],
]
if any(value != expected for value in checks):
    raise SystemExit("sha256 不一致")

skill = json.loads(pkg.read_text(encoding="utf-8")).get("skill_markdown", "")
if "name: xiaoma-hermes-zh" not in skill:
    raise SystemExit("skill_markdown 缺少名称")
PY

printf 'release ok\n'

