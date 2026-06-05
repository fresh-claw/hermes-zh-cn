#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${XIAOMA_HERMES_BASE_URL:-https://useai.live/hermes}"
BASE_URL="${BASE_URL%/}"
FALLBACK_BASE_URL="${XIAOMA_HERMES_FALLBACK_BASE_URL:-https://cdn.jsdelivr.net/gh/fresh-claw/hermes-cn@v2026.06.05.2}"
FALLBACK_BASE_URL="${FALLBACK_BASE_URL%/}"
export XIAOMA_HERMES_ENTRYPOINT="macos-command"

if ! command -v curl >/dev/null 2>&1; then
  printf '%s\n' "缺少 curl，无法下载安装器。"
  exit 1
fi

run_installer() {
  local base_url="$1"
  curl -fsSL "$base_url/install.sh" | XIAOMA_HERMES_BASE_URL="$base_url" bash -s -- --include-desktop
}

if ! run_installer "$BASE_URL"; then
  printf '%s\n' "网站下载受限，改用备用入口。"
  run_installer "$FALLBACK_BASE_URL"
fi
printf '%s\n' ""
printf '%s\n' "Hermes 中文增强已完成。可以关闭此窗口。"
