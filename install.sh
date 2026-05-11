#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${XIAOMA_HERMES_BASE_URL:-https://useai.live/hermes}"
BASE_URL="${BASE_URL%/}"
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

fetch() {
  local url="$1"
  local target="$2"
  curl -fsSL "$url" -o "$target"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    printf '缺少 SHA256 校验命令\n' >&2
    exit 1
  fi
}

detect_hermes_version() {
  if ! command -v hermes >/dev/null 2>&1; then
    printf 'unknown'
    return
  fi

  local raw
  raw="$(hermes version 2>/dev/null || hermes --version 2>/dev/null || true)"
  raw="$(printf '%s\n' "$raw" | sed -nE 's/.*v?([0-9]+([.][0-9]+){1,3}).*/\1/p' | head -1)"
  if [ -n "$raw" ]; then
    printf '%s' "$raw"
  else
    printf 'unknown'
  fi
}

resolve_package() {
  local latest_json="$1"
  local hermes_version="$2"
  local base_url="$3"

  python3 - "$latest_json" "$hermes_version" "$base_url" <<'PY'
import json
import sys
from urllib.parse import urljoin

latest_path, hermes_version, base_url = sys.argv[1:4]
with open(latest_path, "r", encoding="utf-8") as f:
    data = json.load(f)

packages = data.get("packages") or []
if not packages:
    raise SystemExit("latest.json 中没有 packages")

def match(pkg):
    compat = str(pkg.get("hermes", ""))
    if hermes_version == "unknown":
        return compat.endswith(".x") or compat
    if compat.endswith(".x"):
        return hermes_version.startswith(compat[:-1])
    return hermes_version == compat

chosen = next((pkg for pkg in packages if match(pkg)), packages[0])

def absolute(value):
    value = str(value)
    if value.startswith(("http://", "https://", "file://")):
        return value
    return urljoin(base_url.rstrip("/") + "/", value.lstrip("/"))

print("\t".join([
    str(chosen.get("version", "")),
    absolute(chosen.get("manifest", "")),
    absolute(chosen.get("package", "")),
    str(chosen.get("sha256", "")),
    str(chosen.get("hermes", "")),
]))
PY
}

write_skill_from_package() {
  local package_json="$1"
  local skill_dir="$HERMES_HOME_DIR/skills/xiaoma-hermes-zh"
  mkdir -p "$skill_dir"

  python3 - "$package_json" "$skill_dir/SKILL.md" <<'PY'
import json
import sys
from pathlib import Path

package_path, skill_path = sys.argv[1:3]
with open(package_path, "r", encoding="utf-8") as f:
    data = json.load(f)
skill = data.get("skill_markdown")
if not skill:
    raise SystemExit("中文增强包缺少 skill_markdown")
Path(skill_path).write_text(skill.rstrip() + "\n", encoding="utf-8")
PY
}

set_hermes_language() {
  if [ "${XIAOMA_HERMES_SKIP_CONFIG:-0}" = "1" ]; then
    return
  fi
  if command -v hermes >/dev/null 2>&1; then
    hermes config set display.language zh >/dev/null 2>&1 || true
  fi
}

install_helper() {
  mkdir -p "$BIN_DIR"
  fetch "$BASE_URL/tools/xiaoma-hermes" "$BIN_DIR/xiaoma-hermes"
  chmod +x "$BIN_DIR/xiaoma-hermes"
}

install_wrapper() {
  if [ "${XIAOMA_HERMES_SKIP_WRAPPER:-0}" = "1" ]; then
    return
  fi

  local real_hermes
  real_hermes="${XIAOMA_HERMES_REAL_HERMES:-$(command -v hermes 2>/dev/null || true)}"
  if [ "$real_hermes" = "$BIN_DIR/hermes" ] && [ -f "$INSTALL_HOME/real_hermes" ]; then
    real_hermes="$(cat "$INSTALL_HOME/real_hermes")"
  fi
  printf '%s\n' "$real_hermes" > "$INSTALL_HOME/real_hermes"

  cat > "$BIN_DIR/hermes" <<EOF
#!/usr/bin/env bash
set -euo pipefail
REAL_HERMES="\$(cat "$INSTALL_HOME/real_hermes" 2>/dev/null || true)"
if [ -n "\$REAL_HERMES" ] && [ -x "\$REAL_HERMES" ]; then
  XIAOMA_HERMES_QUIET=1 "$BIN_DIR/xiaoma-hermes" update --quiet >/dev/null 2>&1 || true
  exec "\$REAL_HERMES" "\$@"
fi
printf '未找到原版 Hermes，请先安装 Hermes Agent。\\n' >&2
exit 127
EOF
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
      printf '# <<< xiaoma hermes zh\n'
    } >> "$profile"
  fi
}

main() {
  need_cmd curl
  need_cmd python3

  mkdir -p "$INSTALL_HOME" "$RELEASES_DIR" "$HERMES_HOME_DIR"

  local hermes_version latest_json package_info package_version manifest_url package_url package_sha compat
  hermes_version="$(detect_hermes_version)"
  latest_json="$TMP_DIR/latest.json"
  fetch "$BASE_URL/latest.json" "$latest_json"
  package_info="$(resolve_package "$latest_json" "$hermes_version" "$BASE_URL")"
  IFS=$'\t' read -r package_version manifest_url package_url package_sha compat <<< "$package_info"

  local manifest_file package_file actual_sha release_dir
  manifest_file="$TMP_DIR/manifest.json"
  package_file="$TMP_DIR/zh-cn.min.json"
  fetch "$manifest_url" "$manifest_file"
  fetch "$package_url" "$package_file"

  if [ -n "$package_sha" ] && [ "$package_sha" != "pending" ]; then
    actual_sha="$(sha256_file "$package_file")"
    if [ "$actual_sha" != "$package_sha" ]; then
      printf 'SHA256 校验失败：%s\n' "$package_url" >&2
      exit 1
    fi
  fi

  release_dir="$RELEASES_DIR/$package_version"
  mkdir -p "$release_dir"
  cp "$manifest_file" "$release_dir/manifest.json"
  cp "$package_file" "$release_dir/zh-cn.min.json"
  printf '%s\n' "$package_version" > "$release_dir/VERSION"
  ln -sfn "$release_dir" "$INSTALL_HOME/current"

  write_skill_from_package "$package_file"
  set_hermes_language
  install_helper
  install_wrapper
  ensure_path_hint

  say "小马AI Hermes 中文增强已安装"
  say "中文包版本：${package_version}"
  say "Hermes 匹配：${compat}，本机检测：${hermes_version}"
  say "新开终端后，hermes 会在启动前检查中文内容更新。"
}

main "$@"
