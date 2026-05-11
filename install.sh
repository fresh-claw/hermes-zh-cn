#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${XIAOMA_HERMES_BASE_URL:-https://useai.live/hermes}"
BASE_URL="${BASE_URL%/}"
PACKAGE_VERSION="2026.05.11.2"
INSTALL_HOME="${XIAOMA_HERMES_HOME:-$HOME/.xiaoma-hermes}"
HERMES_HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"
BIN_DIR="$INSTALL_HOME/bin"
RELEASES_DIR="$INSTALL_HOME/releases"
TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t xiaoma-hermes)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

say() {
  if [ "${XIAOMA_HERMES_QUIET:-0}" != "1" ]; then
    printf '%s\n' "$*"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '缺少命令：%s\n' "$1" >&2
    exit 1
  }
}

detect_hermes_version() {
  python3 - "$HOME" "$BIN_DIR/hermes" <<'PY_DETECT'
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

home = Path(sys.argv[1])
skip = Path(sys.argv[2]).expanduser()
commands = []
seen = set()

def add(cmd):
    key = tuple(cmd)
    if key not in seen:
        seen.add(key)
        commands.append(cmd)

for name in ("hermes", "hermes-agent"):
    found = shutil.which(name)
    if found and Path(found) != skip:
        add([found, "version"])
        add([found, "--version"])

legacy = home / ".hermes" / "hermes-agent" / "hermes"
if legacy.exists():
    add(["python3", str(legacy), "version"])
    add(["python3", str(legacy), "--version"])
    if legacy.stat().st_mode & 0o111:
        add([str(legacy), "version"])
        add([str(legacy), "--version"])

pattern = re.compile(r"v?(\d+(?:\.\d+){1,3})")
deadline = time.monotonic() + 4
detected = None
for cmd in commands:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        break
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=remaining)
    except Exception:
        continue
    raw = (result.stdout or "") + "\n" + (result.stderr or "")
    match = pattern.search(raw)
    if match:
        detected = match.group(1)
        break
print(detected or "legacy")
PY_DETECT
}

extract_payload() {
  local archive="$TMP_DIR/payload.tar.gz"
  local target="$TMP_DIR/payload"
  mkdir -p "$target"
  python3 - "$archive" <<'PY_PAYLOAD'
import base64
import sys
DATA = """
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
"""
with open(sys.argv[1], "wb") as f:
    f.write(base64.b64decode(DATA))
PY_PAYLOAD
  tar -xzf "$archive" -C "$target"
  printf '%s\n' "$target"
}

package_dir_for_version() {
  local payload_root="$1"
  local version="$2"
  case "$version" in
    0.13.*)
      printf '%s\n' "$payload_root/packages/0.13.x/zh-CN"
      ;;
    *)
      printf '%s\n' "$payload_root/packages/legacy/zh-CN"
      ;;
  esac
}

compat_for_version() {
  local version="$1"
  case "$version" in
    0.13.*) printf '0.13.x' ;;
    *) printf 'legacy' ;;
  esac
}

verify_package() {
  local manifest_file="$1"
  local package_file="$2"
  python3 - "$manifest_file" "$package_file" <<'PY_VERIFY'
import hashlib
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
package_path = Path(sys.argv[2])
expected = manifest.get("files", [{}])[0].get("sha256")
actual = hashlib.sha256(package_path.read_bytes()).hexdigest()
if expected and actual != expected:
    raise SystemExit(f"SHA256 校验失败：{actual} != {expected}")
PY_VERIFY
}

write_skill_from_package() {
  local package_json="$1"
  local skill_dir="$HERMES_HOME_DIR/skills/xiaoma-hermes-zh"
  mkdir -p "$skill_dir"
  python3 - "$package_json" "$skill_dir/SKILL.md" <<'PY_SKILL'
import json
import sys
from pathlib import Path

package_path, skill_path = sys.argv[1:3]
data = json.loads(Path(package_path).read_text(encoding="utf-8"))
skill = data.get("skill_markdown")
if not skill:
    raise SystemExit("中文增强包缺少 skill_markdown")
Path(skill_path).write_text(skill.rstrip() + "\n", encoding="utf-8")
PY_SKILL
}

write_config_language() {
  if [ "${XIAOMA_HERMES_SKIP_CONFIG:-0}" = "1" ]; then
    return
  fi
  mkdir -p "$HERMES_HOME_DIR"
  python3 - "$HERMES_HOME_DIR/config.yaml" <<'PY_CONFIG'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists() or not path.read_text(encoding="utf-8", errors="ignore").strip():
    path.write_text("display:\n  language: zh\n", encoding="utf-8")
    raise SystemExit

text = path.read_text(encoding="utf-8", errors="ignore")
lines = text.splitlines()
start = None
for i, line in enumerate(lines):
    if re.match(r"^display\s*:", line):
        start = i
        break

if start is None:
    if lines and lines[-1].strip():
        lines.append("")
    lines.extend(["display:", "  language: zh"])
else:
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].strip() and not lines[j].startswith((" ", "\t", "#")):
            end = j
            break
    if "{" in lines[start] and "}" in lines[start]:
        lines[start:end] = ["display:", "  language: zh"]
    else:
        replaced = False
        for j in range(start + 1, end):
            if re.match(r"^\s*language\s*:", lines[j]):
                indent = re.match(r"^(\s*)", lines[j]).group(1) or "  "
                lines[j] = f"{indent}language: zh"
                replaced = True
                break
        if not replaced:
            lines.insert(start + 1, "  language: zh")

path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY_CONFIG
}

run_official_config_set() {
  if [ "${XIAOMA_HERMES_SKIP_CONFIG:-0}" = "1" ]; then
    return
  fi
  if [ "${XIAOMA_HERMES_TRY_OFFICIAL_CONFIG:-0}" != "1" ]; then
    return
  fi
  python3 - "$BIN_DIR/hermes" <<'PY_SET'
import shutil
import subprocess
import sys
from pathlib import Path

skip = Path(sys.argv[1])
hermes = shutil.which("hermes")
if not hermes or Path(hermes) == skip:
    raise SystemExit
try:
    subprocess.run([hermes, "config", "set", "display.language", "zh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
except Exception:
    pass
PY_SET
}

find_real_hermes() {
  if [ -n "${XIAOMA_HERMES_REAL_HERMES:-}" ]; then
    printf '%s\n' "$XIAOMA_HERMES_REAL_HERMES"
    return
  fi
  local found=""
  found="$(command -v hermes 2>/dev/null || true)"
  if [ -n "$found" ] && [ "$found" != "$BIN_DIR/hermes" ]; then
    printf '%s\n' "$found"
    return
  fi
  if [ -f "$INSTALL_HOME/real_hermes" ]; then
    cat "$INSTALL_HOME/real_hermes"
    return
  fi
  if [ -x "$HOME/.hermes/hermes-agent/hermes" ]; then
    printf '%s\n' "$HOME/.hermes/hermes-agent/hermes"
    return
  fi
  printf '\n'
}

install_helper() {
  local payload_root="$1"
  mkdir -p "$BIN_DIR"
  cp "$payload_root/tools/xiaoma-hermes" "$BIN_DIR/xiaoma-hermes"
  chmod +x "$BIN_DIR/xiaoma-hermes"
}

install_wrapper() {
  if [ "${XIAOMA_HERMES_SKIP_WRAPPER:-0}" = "1" ]; then
    return
  fi

  local real_hermes
  real_hermes="$(find_real_hermes)"
  printf '%s\n' "$real_hermes" > "$INSTALL_HOME/real_hermes"

  cat > "$BIN_DIR/hermes" <<EOF_WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export HERMES_LANGUAGE=zh
REAL_HERMES="\$(cat "$INSTALL_HOME/real_hermes" 2>/dev/null || true)"
XIAOMA_HERMES_QUIET=1 "$BIN_DIR/xiaoma-hermes" update --quiet >/dev/null 2>&1 || true
if [ -n "\$REAL_HERMES" ] && [ -x "\$REAL_HERMES" ]; then
  exec "\$REAL_HERMES" "\$@"
fi
if [ -f "\$HOME/.hermes/hermes-agent/hermes" ]; then
  exec python3 "\$HOME/.hermes/hermes-agent/hermes" "\$@"
fi
printf '未找到原版 Hermes，请先安装 Hermes Agent。\\n' >&2
exit 127
EOF_WRAPPER
  chmod +x "$BIN_DIR/hermes"
}

ensure_path_hint() {
  if [ "${XIAOMA_HERMES_SKIP_PATH:-0}" = "1" ]; then
    return
  fi

  local shell_name profile
  shell_name="$(basename "${SHELL:-}")"
  case "$shell_name" in
    zsh) profile="$HOME/.zshrc" ;;
    bash) profile="$HOME/.bashrc" ;;
    *) profile="$HOME/.profile" ;;
  esac

  mkdir -p "$(dirname "$profile")"
  touch "$profile"
  if ! grep -F 'xiaoma hermes zh' "$profile" >/dev/null 2>&1; then
    {
      printf '\n# >>> xiaoma hermes zh\n'
      printf 'export PATH="$HOME/.xiaoma-hermes/bin:$PATH"\n'
      printf 'export HERMES_LANGUAGE=zh\n'
      printf '# <<< xiaoma hermes zh\n'
    } >> "$profile"
  elif ! grep -F 'export HERMES_LANGUAGE=zh' "$profile" >/dev/null 2>&1; then
    printf '\nexport HERMES_LANGUAGE=zh\n' >> "$profile"
  fi
}

main() {
  need_cmd python3
  need_cmd tar

  mkdir -p "$INSTALL_HOME" "$RELEASES_DIR" "$HERMES_HOME_DIR"

  local hermes_version compat payload_root package_dir manifest_file package_file release_dir
  hermes_version="$(detect_hermes_version)"
  compat="$(compat_for_version "$hermes_version")"
  payload_root="$(extract_payload)"
  package_dir="$(package_dir_for_version "$payload_root" "$hermes_version")"
  manifest_file="$package_dir/manifest.json"
  package_file="$package_dir/zh-cn.min.json"

  verify_package "$manifest_file" "$package_file"

  release_dir="$RELEASES_DIR/$PACKAGE_VERSION"
  mkdir -p "$release_dir"
  cp "$manifest_file" "$release_dir/manifest.json"
  cp "$package_file" "$release_dir/zh-cn.min.json"
  printf '%s\n' "$PACKAGE_VERSION" > "$release_dir/VERSION"
  rm -rf "$INSTALL_HOME/current"
  ln -s "$release_dir" "$INSTALL_HOME/current"

  write_skill_from_package "$package_file"
  write_config_language
  run_official_config_set
  install_helper "$payload_root"
  install_wrapper
  ensure_path_hint

  say "小马AI Hermes 中文增强已安装"
  say "中文包版本：${PACKAGE_VERSION}"
  say "Hermes 匹配：${compat}，本机检测：${hermes_version}"
  say "新开终端后，Hermes 会在启动前检查中文内容更新。"
}

main "$@"
