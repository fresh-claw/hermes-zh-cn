#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${XIAOMA_HERMES_BASE_URL:-https://raw.githubusercontent.com/fresh-claw/hermes-desktop-zh-cn/main}"
BASE_URL="${BASE_URL%/}"
export XIAOMA_HERMES_ENTRYPOINT="macos-command"

if ! command -v curl >/dev/null 2>&1; then
  printf '%s\n' "缺少 curl，无法下载安装器。"
  exit 1
fi

curl -fsSL "$BASE_URL/install.sh" | bash
printf '%s\n' ""
printf '%s\n' "Hermes 中文增强已完成。可以关闭此窗口。"
