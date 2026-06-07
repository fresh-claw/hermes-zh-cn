#!/usr/bin/env bash
set -euo pipefail

export XIAOMA_HERMES_ENTRYPOINT="macos-command"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_INSTALLER="$SCRIPT_DIR/install.sh"
PINNED_VERSION="${XIAOMA_HERMES_PINNED_VERSION:-v2026.06.07.3}"
CURL_CONNECT_TIMEOUT="${XIAOMA_HERMES_CONNECT_TIMEOUT:-8}"
CURL_MAX_TIME="${XIAOMA_HERMES_MAX_TIME:-180}"
CURL_SPEED_LIMIT="${XIAOMA_HERMES_SPEED_LIMIT:-1024}"
CURL_SPEED_TIME="${XIAOMA_HERMES_SPEED_TIME:-20}"

if ! command -v curl >/dev/null 2>&1; then
  printf '%s\n' "缺少 curl，无法下载安装器。"
  exit 1
fi

if [ -f "$LOCAL_INSTALLER" ]; then
  printf '%s\n' "正在使用本地安装脚本。"
  bash "$LOCAL_INSTALLER" --include-desktop
  printf '%s\n' ""
  printf '%s\n' "Hermes 中文增强已完成。可以关闭此窗口。"
  exit 0
fi

append_source() {
  local value="$1"
  if [ -n "$value" ]; then
    printf '%s\n' "${value%/}"
  fi
}

installer_sources() {
  if [ -n "${XIAOMA_HERMES_BASE_URLS:-}" ]; then
    printf '%s\n' "$XIAOMA_HERMES_BASE_URLS" | tr ',' '\n' | while IFS= read -r item; do
      append_source "$item"
    done
    return
  fi
  append_source "${XIAOMA_HERMES_BASE_URL:-http://47.121.138.43/hermes}"
  append_source "https://useai.live/hermes"
  append_source "${XIAOMA_HERMES_FALLBACK_BASE_URL:-https://cdn.jsdelivr.net/gh/fresh-claw/hermes-cn@${PINNED_VERSION}}"
  append_source "https://fastly.jsdelivr.net/gh/fresh-claw/hermes-cn@${PINNED_VERSION}"
  append_source "https://gcore.jsdelivr.net/gh/fresh-claw/hermes-cn@${PINNED_VERSION}"
  append_source "https://raw.githubusercontent.com/fresh-claw/hermes-cn/${PINNED_VERSION}/install.sh"
}

download_installer() {
  local base_url="$1"
  local out_file="$2"
  local url
  if [ "${base_url##*/}" = "install.sh" ]; then
    url="$base_url"
  else
    url="${base_url%/}/install.sh"
  fi
  printf '正在尝试下载：%s\n' "$url"
  curl -fsSL \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    --speed-limit "$CURL_SPEED_LIMIT" \
    --speed-time "$CURL_SPEED_TIME" \
    "$url" -o "$out_file"
  if ! head -n 1 "$out_file" | grep -Eq '^#!.*bash'; then
    printf '这个入口返回的不是安装脚本：%s\n' "$url" >&2
    return 1
  fi
}

TMP_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/xiaoma-hermes-install.XXXXXX.sh")"
trap 'rm -f "$TMP_INSTALLER"' EXIT

ACTIVE_SOURCE=""
while IFS= read -r source_url; do
  if [ -z "$source_url" ]; then
    continue
  fi
  if download_installer "$source_url" "$TMP_INSTALLER"; then
    ACTIVE_SOURCE="$source_url"
    break
  fi
  printf '%s\n' "当前入口不可用或过慢，正在切换下一个入口。"
done <<EOF_SOURCES
$(installer_sources)
EOF_SOURCES

if [ -z "$ACTIVE_SOURCE" ]; then
  printf '%s\n' "所有下载入口都失败，请稍后重试。"
  exit 1
fi

if [ "${ACTIVE_SOURCE##*/}" = "install.sh" ]; then
  ACTIVE_BASE="${ACTIVE_SOURCE%/install.sh}"
else
  ACTIVE_BASE="${ACTIVE_SOURCE%/}"
fi
printf '已选择下载入口：%s\n' "$ACTIVE_SOURCE"
XIAOMA_HERMES_BASE_URL="$ACTIVE_BASE" bash "$TMP_INSTALLER" --include-desktop
printf '%s\n' ""
printf '%s\n' "Hermes 中文增强已完成。可以关闭此窗口。"
