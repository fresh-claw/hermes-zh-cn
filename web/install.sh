#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${XIAOMA_HERMES_BASE_URL:-http://47.121.138.43/hermes}"
BASE_URL="${BASE_URL%/}"
PACKAGE_VERSION="2026.06.08.1"
PINNED_VERSION="${XIAOMA_HERMES_PINNED_VERSION:-v2026.06.08.1}"
OFFICIAL_HERMES_INSTALL_URL="${XIAOMA_HERMES_OFFICIAL_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"
INSTALL_HOME="${XIAOMA_HERMES_HOME:-$HOME/.xiaoma-hermes}"
HERMES_HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"
BIN_DIR="$INSTALL_HOME/bin"
RELEASES_DIR="$INSTALL_HOME/releases"
TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t xiaoma-hermes)"
INCLUDE_DESKTOP="${XIAOMA_HERMES_INCLUDE_DESKTOP:-0}"
CURL_CONNECT_TIMEOUT="${XIAOMA_HERMES_CONNECT_TIMEOUT:-8}"
CURL_MAX_TIME="${XIAOMA_HERMES_MAX_TIME:-180}"
CURL_SPEED_LIMIT="${XIAOMA_HERMES_SPEED_LIMIT:-1024}"
CURL_SPEED_TIME="${XIAOMA_HERMES_SPEED_TIME:-20}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --include-desktop|--desktop)
      INCLUDE_DESKTOP="1"
      ;;
    --no-desktop)
      INCLUDE_DESKTOP="0"
      ;;
    *)
      printf '未知参数：%s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

say() {
  if [ "${XIAOMA_HERMES_QUIET:-0}" != "1" ]; then
    printf '%s\n' "$*"
  fi
}

record_metric() {
  local event="$1"
  command -v curl >/dev/null 2>&1 || return 0
  curl -fsS --max-time 2 "$BASE_URL/api/metrics.php?event=${event}" >/dev/null 2>&1 || true
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '缺少命令：%s\n' "$1" >&2
    exit 1
  }
}

append_url_once() {
  local url="$1"
  local seen_file="$2"
  url="${url%/}"
  if [ -z "$url" ]; then
    return
  fi
  if ! grep -Fx "$url" "$seen_file" >/dev/null 2>&1; then
    printf '%s\n' "$url" >> "$seen_file"
    printf '%s\n' "$url"
  fi
}

installer_base_urls() {
  local seen_file="$TMP_DIR/installer-url-seen"
  : > "$seen_file"
  if [ -n "${XIAOMA_HERMES_BASE_URLS:-}" ]; then
    printf '%s\n' "$XIAOMA_HERMES_BASE_URLS" | tr ',' '\n' | while IFS= read -r item; do
      append_url_once "$item" "$seen_file"
    done
    return
  fi
  append_url_once "$BASE_URL" "$seen_file"
  append_url_once "https://useai.live/hermes" "$seen_file"
  append_url_once "${XIAOMA_HERMES_FALLBACK_BASE_URL:-https://cdn.jsdelivr.net/gh/fresh-claw/hermes-cn@${PINNED_VERSION}}" "$seen_file"
  append_url_once "https://fastly.jsdelivr.net/gh/fresh-claw/hermes-cn@${PINNED_VERSION}" "$seen_file"
  append_url_once "https://gcore.jsdelivr.net/gh/fresh-claw/hermes-cn@${PINNED_VERSION}" "$seen_file"
  append_url_once "https://raw.githubusercontent.com/fresh-claw/hermes-cn/${PINNED_VERSION}" "$seen_file"
}

official_install_urls() {
  local seen_file="$TMP_DIR/official-url-seen"
  : > "$seen_file"
  if [ -n "${XIAOMA_HERMES_OFFICIAL_INSTALL_URLS:-}" ]; then
    printf '%s\n' "$XIAOMA_HERMES_OFFICIAL_INSTALL_URLS" | tr ',' '\n' | while IFS= read -r item; do
      append_url_once "$item" "$seen_file"
    done
    return
  fi
  append_url_once "$BASE_URL/official-hermes-install.sh" "$seen_file"
  append_url_once "https://useai.live/hermes/official-hermes-install.sh" "$seen_file"
  append_url_once "${XIAOMA_HERMES_FALLBACK_BASE_URL:-https://cdn.jsdelivr.net/gh/fresh-claw/hermes-cn@${PINNED_VERSION}}/official-hermes-install.sh" "$seen_file"
  append_url_once "https://fastly.jsdelivr.net/gh/fresh-claw/hermes-cn@${PINNED_VERSION}/official-hermes-install.sh" "$seen_file"
  append_url_once "https://gcore.jsdelivr.net/gh/fresh-claw/hermes-cn@${PINNED_VERSION}/official-hermes-install.sh" "$seen_file"
  append_url_once "https://raw.githubusercontent.com/fresh-claw/hermes-cn/${PINNED_VERSION}/official-hermes-install.sh" "$seen_file"
  append_url_once "$OFFICIAL_HERMES_INSTALL_URL" "$seen_file"
  append_url_once "https://cdn.jsdelivr.net/gh/NousResearch/hermes-agent@main/scripts/install.sh" "$seen_file"
  append_url_once "https://fastly.jsdelivr.net/gh/NousResearch/hermes-agent@main/scripts/install.sh" "$seen_file"
  append_url_once "https://gcore.jsdelivr.net/gh/NousResearch/hermes-agent@main/scripts/install.sh" "$seen_file"
}

curl_to_file() {
  local url="$1"
  local out_file="$2"
  curl -fsSL \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    --speed-limit "$CURL_SPEED_LIMIT" \
    --speed-time "$CURL_SPEED_TIME" \
    "$url" -o "$out_file"
}

download_script_from_urls() {
  local out_file="$1"
  shift
  local label="$1"
  shift
  local url
  for url in "$@"; do
    if [ -z "$url" ]; then
      continue
    fi
    say "正在下载${label}：$url"
    if curl_to_file "$url" "$out_file" && head -n 1 "$out_file" | grep -Eq '^#!.*(bash|sh)'; then
      printf '%s\n' "$url"
      return 0
    fi
    say "当前入口不可用或过慢，正在切换下一个入口。"
  done
  return 1
}

download_install_sh() {
  local out_file="$1"
  local urls=()
  local base_url
  while IFS= read -r base_url; do
    if [ -z "$base_url" ]; then
      continue
    fi
    if [ "${base_url##*/}" = "install.sh" ]; then
      urls+=("$base_url")
    else
      urls+=("${base_url%/}/install.sh")
    fi
  done <<EOF_INSTALLER_URLS
$(installer_base_urls)
EOF_INSTALLER_URLS
  download_script_from_urls "$out_file" "中文增强安装器" "${urls[@]}"
}

download_official_installer() {
  local out_file="$1"
  local urls=()
  local url
  while IFS= read -r url; do
    urls+=("$url")
  done <<EOF_OFFICIAL_URLS
$(official_install_urls)
EOF_OFFICIAL_URLS
  download_script_from_urls "$out_file" "官方 Hermes 安装器" "${urls[@]}"
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
  if [ -x "/usr/local/bin/hermes" ]; then
    printf '%s\n' "/usr/local/bin/hermes"
    return
  fi
  printf '\n'
}

find_hermes_desktop() {
  case "$(uname -s)" in
    Darwin)
      for item in \
        "/Applications/Hermes.app" \
        "$HOME/Applications/Hermes.app" \
        "$HERMES_HOME_DIR/hermes-agent/apps/desktop/release/mac-arm64/Hermes.app" \
        "$HERMES_HOME_DIR/hermes-agent/apps/desktop/release/mac/Hermes.app" \
        "$HOME/.hermes/hermes-agent/apps/desktop/release/mac-arm64/Hermes.app" \
        "$HOME/.hermes/hermes-agent/apps/desktop/release/mac/Hermes.app"; do
        if [ -d "$item" ]; then
          printf '%s\n' "$item"
          return
        fi
      done
      ;;
    Linux)
      for item in \
        "$HERMES_HOME_DIR/hermes-agent/apps/desktop/release/linux-unpacked/Hermes" \
        "$HERMES_HOME_DIR/hermes-agent/apps/desktop/release/linux-unpacked/hermes" \
        "$HOME/.hermes/hermes-agent/apps/desktop/release/linux-unpacked/Hermes" \
        "$HOME/.hermes/hermes-agent/apps/desktop/release/linux-unpacked/hermes"; do
        if [ -x "$item" ]; then
          printf '%s\n' "$item"
          return
        fi
      done
      ;;
  esac
  printf '\n'
}

find_hermes_desktops() {
  case "$(uname -s)" in
    Darwin)
      for item in \
        "/Applications/Hermes.app" \
        "$HOME/Applications/Hermes.app" \
        "$HERMES_HOME_DIR/hermes-agent/apps/desktop/release/mac-arm64/Hermes.app" \
        "$HERMES_HOME_DIR/hermes-agent/apps/desktop/release/mac/Hermes.app" \
        "$HOME/.hermes/hermes-agent/apps/desktop/release/mac-arm64/Hermes.app" \
        "$HOME/.hermes/hermes-agent/apps/desktop/release/mac/Hermes.app"; do
        if [ -d "$item" ]; then
          printf '%s\n' "$item"
        fi
      done | awk '!seen[$0]++'
      ;;
    Linux)
      for item in \
        "$HERMES_HOME_DIR/hermes-agent/apps/desktop/release/linux-unpacked/Hermes" \
        "$HERMES_HOME_DIR/hermes-agent/apps/desktop/release/linux-unpacked/hermes" \
        "$HOME/.hermes/hermes-agent/apps/desktop/release/linux-unpacked/Hermes" \
        "$HOME/.hermes/hermes-agent/apps/desktop/release/linux-unpacked/hermes"; do
        if [ -x "$item" ]; then
          printf '%s\n' "$item"
        fi
      done | awk '!seen[$0]++'
      ;;
  esac
}

ensure_official_hermes() {
  if [ -n "${XIAOMA_HERMES_SOURCE_ROOT:-}" ]; then
    return
  fi
  local real_hermes desktop_app
  real_hermes="$(find_real_hermes)"
  desktop_app="$(find_hermes_desktop)"
  if [ -n "$real_hermes" ] && { [ "$INCLUDE_DESKTOP" != "1" ] || [ -n "$desktop_app" ]; }; then
    return
  fi
  if [ "${XIAOMA_HERMES_SKIP_OFFICIAL_INSTALL:-0}" = "1" ]; then
    return
  fi

  need_cmd curl
  if [ "$INCLUDE_DESKTOP" = "1" ]; then
    if [ -n "$real_hermes" ]; then
      say "检测到 Hermes 命令行，正在补官方桌面端。"
    else
      say "未检测到 Hermes，正在安装官方 Hermes 桌面端。"
    fi
    local official_installer="$TMP_DIR/official-hermes-install.sh"
    if ! download_official_installer "$official_installer" >/dev/null; then
      printf '官方 Hermes 安装器下载失败，请稍后重试。\\n' >&2
      exit 1
    fi
    bash "$official_installer" --include-desktop
  else
    say "未检测到 Hermes，正在先安装官方 Hermes Agent。"
    local official_installer="$TMP_DIR/official-hermes-install.sh"
    if ! download_official_installer "$official_installer" >/dev/null; then
      printf '官方 Hermes 安装器下载失败，请稍后重试。\\n' >&2
      exit 1
    fi
    bash "$official_installer"
  fi

  if [ -z "$(find_real_hermes)" ]; then
    printf '官方 Hermes 安装后仍未检测到 hermes 命令，请打开新终端后重试。\\n' >&2
    exit 1
  fi
  if [ "$INCLUDE_DESKTOP" = "1" ] && [ -z "$(find_hermes_desktop)" ]; then
    printf '官方 Hermes 桌面端未生成，请确认 Node.js 可用后重试。\\n' >&2
    exit 1
  fi
}

extract_payload() {
  local archive="$TMP_DIR/payload.tar.gz"
  local target="$TMP_DIR/payload"
  mkdir -p "$target"
  python3 - "$archive" <<'PY_PAYLOAD'
import base64
import sys
DATA = """
	H4sIAGsqJmoAA+1ceXcTV5bvv/0p3qgXYAbtq+mhz7jTTIdpkjCYTM9MkiOXVCW7GkmllkqAQzPHDhjbYANZ2IJJxwQCySQ26SQsNst36bgk+a98hbn3vVelKm2WGeJA962TYEn11ru9e+9771dSsoeUUa0S/MkP94RCoWQ8zvjfhPgLj/1XfAnHI+FwLBIPx6MsFI4kQqGfsPgPOCbnqVZMpQxD0d+u9ix3ZEzT8j3eeyfFnukYf8CnZPM/FAhHA0d/EDHYPP+jsUiS+L8Vj8P/vDaqZMefE/7HQrEY8X8rHrf+x54j/Y+S/d+Sx83/+PPE/zDxfyseN/8TzxP/I8T/rXha+f/2mP+lV5+xFDzF+h+Nk/5vydOZ//Bvthgo6MXAHypG8f/bB9AjEYt1438sEo238j8ZQv6HnsUEN3r+zvl/zFfJjmkFxbfLN2aapcquYLBa0RQ9kNcPa8ExrVwA2RBFgkd1xSgofvGjX0pO4HCYC4lvp6+gmdDOMV9RKWjQnrc4FykolCkrRRXeWnfOrX/2xdDe+uwM/Jo3skoeK3H5gx8Oa+WKDq3u8kVCkUQgBP+lAmF4IZpLZ41CSTHhtZBbeFEtVcyyphTwVUHHV9FsJBrWMtHB5KCSGczGk2o8qybUUCQXVuPJpBLNJMOpTCwKlRW1ktaKSiavwdhySr6iHYcfsyYMoeLb9cYxnzlewuHpRRCXfD5t5HJ6VlfyaTkckI5iuqBXKnpxFJrLGkVVN8X4+dTYy7wcw7HB/IMVo1rOaqxomCxnVIEgWIe/ghrZajnP/LnK8D5m86SsHAmM6uZYNQPcKUPzplY0A1Al+KpRrRzQgGXl7Jjklx/YUjSDBUUvAuvKesmsBOXAA5Ux9ieWUSpj0CNQq8KHWP/gdm3mXu0vi7WFWWtptvHJlD3e2qW73z+cs6ZmxM/W0uXaxQfyJb44NV9fvVVf/VK+ljxdu/9l7eJ0Y/Hm2v3J7ybe8R3f6RAQhp7TR9MVzfRMecwmD75l8JapeqWUV8YDeaU4WoUJsbdxyMCafAYED6r8TzAgxVPUCowrhXxbtd282iFtHGq0vkMxU/JVIXZueljnl4EkNg3EpOtLE2uP3hczW792pTYxWb8wt37t+vcPr9Yu3QIptt59tLZ6Y+3+vHUOawPl6le/qZ29WYN/L95Zn5qvP1qCumurd1tIAnKcHUubVT0tpAJGAj+Nodz5xBAEdetXl6xHF4K2AuT1YEYpFrVyoDQOVXqXrBzSiyDgo3pR66e4qZcq/ZQrZEtpSf0+Skt299UyDDifr6RB4PsqbSpmta92VSNrGv2RTDOrpf6m1S8BlKo51l+LJT1vmOl+y6Om98VWw8hXNmIYFOz6rlwtprlx6VpCmB5b03qXApukj46Z3fkminFrd9TkJr+sVSo92DeqmNoRZRzH2bUMKppdDmzp4R4KVNX9UDpYKWdtVTMrG5Y0Ya3U+ikorXgQKJXVxoy8CkveZurByDObqjBmmGAI+6xSKBlFqFQJ8gUbljWodnQz9ca0fOllHURlk/XMMb146Cn6K5Xhs1nZbDWlVHoNKAnSuumqwka9DCZqsxVBisE52K9nD3GZ2lTlgqFq+aerahqqsV8pavnNVvxjVatq6iswbIwVnoLE+5Rxo7ppUeD6X5Hs6asydBXMwjpuar8VKr7nMDTxMkhwvj/tbTYwnAcvaZM1K1jHWefgQ7kvS9ChqhSRp6xtlPrS8o794qr3dHVVLVMd7bduVR82N0EecHuHBUn26TktO57N909ZnBIyEpz2fuuY1XLxJTCbZSO/CfbDIPcWS1Vb3vrmAU6umuHhQw+WuxZyuX715RtoBaM8nu7bmynlq+AlwueCuuEyWzG5GUpnFQgQNywN65yZM8oFsENaXhstK4VNVAFRyx7aRPmcplfGqt2dAPSEuPtq9HSyRDnpjFbGi9m+3LdqWenlZCrQraIqJVMrb+SBuIuCISv3cKncJSH4TINglQ2Ib/qqwee5CfIqJYhWeg9dCpKH7QpWFV1uWE8IbhC8AZW7icF0Wi/CvNK9maX18CczPNIC57BX1OTSTTnvl/K6xv2YDSvk9QzMslzQi0p+eDOWFCzAK+DED5W613Crv6H04JbtNcsYAkM0MYEN3WxMuiiYtkjnDaO7tWjlkFHMjhk94wbX2I9omc1Ljo5k6lNumrVGDWM0r6WzY4q5YW23MpSQg9wWb0YlIOaB9b670XTbWEUvo4e7WdURv/NER78V8xDxP009pPiG1ezk0hGgcAXE2J8p6+qoFhR/An/YWJIzVVwp+841lITb21f0Dl6cyT/31bgO65HZfQ0TKsLXgfRGY5Zl+QBkSgeiKN08opRVrXtc2s6Dopkb7593egE6TkPfwUPgv/ZfDxQyeFTRPRXe2unDLFu1JPJsnkxuULypBH92TCZpjwfdyTORDXMSiAuf106fts4vW6dv125/bj2Y+m5isvbF9caTs43lL/HzufP1Gyvy88WF2rWPRSKtsfxN7fJZ+NG6d9Oautd4ctVa+RS+ikRa/fTdGnxe/BZ+qT9615r6unFuwZq/gOWXFmuzD2pzs+vvLcHX14ZgfWe1szO1ayfga+Obb+or90Xj1ntztYt3cLAHX9/Lahena4sztbPQ2822NCLmOkWK88rttYcfWjem11YfWefPWisf1D+43ZLvhKbuWNc/YnxLPczqH57kHVjvT9Zn53CapycaJx5Zc0iKV17azwRD4MuvbSGBz0eH9rLGk8n6rVX4gpIAf34HRGYwaoYva+cX6t9c75FqtXPVXGplUtGTNxVuTbA1Tx8c/t3effsCBdXN1cbSZzZLG8ur1rmL3lwvTNd6uAJTgskKQuE8eeYTxtt4/KB+Yc7maMdBVksq6F/6SBnMiFb2jLZF+vSiVFyP0EE/DyfqqzP1/10GtgC75GCF5Fmz87VPJmp/vtkyWjFCPiQQebDfOKZjPju7jxnYtjy0SJ9B5+snblszp0R22J0RRu0RY8b6L4EDo1U0JifKl1f+pVyV2wvOZgcraxUjD18Y7qQAPRTcGeHnsvxiv0PP5J2WOJUE2RjmWvh3uzfOWjZa1VWlyDPKuMsF/ggTeaydTDVMU1OZqZt5bSeDeIUZZX0U/RZ/xRyHXrQC9FVgPDmN9THUs7cvmKoJ04+DtkuAW2XqBY2B1zmKaTqYBE8XOAWke8Y7E+PLwthHwYWw1c0pKrwj3h30gNm/5kDQrZIJX5nNZYf1CqeMUTUh+nKK2my0BTdjGCbQXSkx3K5hze0aXoGBrwzk4nM6ooPN2D908KWX08MHhw6+PozDhwHZcyxDpKvnVT6VZjWHW5LK/HUOWO7QzeaintdNXAZwh+kw51aRGcB4WDc1QR/gsGY3A7GuUgRbDGOQgdNOJr0NURhjIyY4VNCKVRjeqI4T9fBHeiwoZCgLLG/H0bgLpQOlvMWFc8fbh5WXcbIzkWNraxL9OT2rMcEVXsfuBRbXpgA4oxcj5uThcRqzg5XWHnh0xjJl40gF6QlfQEzfliP1FpXBKKjHHzSuWbx9sVhLgaswDOFaKyJjM3kDKqsOozizxrTsoZKhF00GnAExa6knpUocnGNyO5SVQQiFVA2BaZcuJfOqD/6P2oBUquZNr4AfRFevSZAsLAjOu6H9e5lwnp0CdqbIHqM9ODtsYpKRHRmIy5LNRBEkCIZDKIId2Ay1i4MoA1uZvdPKmnYLZREFwsARy1k2BcwzP2GzgURMWJKcgiTgWU05SE/xl0Qcw5Cacohipp5Siir2W1GCpP/EwJgX/Uo2i7YIllXepUNIaK3p5sME/ljFmWWqpunSgWEU0+BBKbbB3widC/5ri8yqWlbnzXiGZNMVTLVxJA/6yOcrXf/O7HCGLnyx3kqHG8F+2/LZthYsxSG3zW3KaLyjjLrfh7mXAiJZglUJzZI0P17zyw230Cqu3Fye0eN1L2reOujjgHVR8gYwQCipPW5POcf9YcPCe2evKEVou8w8Rp/rsKciukNQXi9rql8IkvDnO1gJ9KRYX3TmzhZ3qhl6vJrUW+wLXGYmdtztFjotiE3aJjrSfrhazilZXEyAa7BmQxuHTAOUDmycma0KeZELvPSL2hYQZ4kb1gslUDgdbJjtA9jtOZ4L7p6B8RBrFTgpYPcxOC6O4qGHN3yCcsBKDUMhnG3lCCi4XLlZWTkiF1hpiHAvCbwGJg44oDiynA6Bke+t42iNUcwr6E1hCGYfPwCaquOu0x8ef+zeX8TGO/pjO3k1MfsAt8RINHD0vvzEWrjtceZOTVlLD5qenLdmtVwG2cQeH70PXiD0Ubu8XFuYgMLu6s2KnHsBoDbYGjyZADohvGscHvf2RVluhALSAgaqxUq1VAK+8ToQUtQWvsBBfnvGuvFV45ubtUt31x49wUMF0kOwph5CtzwGwNbscw0B2wvDqULoNPvYmrnjxFIr5+sfT4poARt8cq1+4Yp19s/1D/5cu/wYoijrwd366hVrekWERyK0ap2adLp0YBRQhQdX61dPYSwkwpKZU/WvVmV79/4iiTR3sa0ZmfXnznczbENvXwRXPepKNwr7n7lm3TrDi0yiTDXunOAU9kR99S9nG0/ONxbnxIR6tQxruYgG7KjOun+/cWty44rOsSQeL0Bgub54Fx18kJcPHqzdX0Eyz85A8NmY/QvEOH+dWKjPfAUivLZ6obawglHhyspfJ67V33mwfvlb68tLGDDe+3Tt8S3r6mPr0XVsZ/K6dWO+2dQnZ2sfPxTlax9PN5ZPff/wqifGPHUFI1EZ/bw9BnHkUuOdG8Bja2a6Nn9dCLT4EXprfHqqfvUiBN8QjdQWT8EQaktnQD5aJ8ptHUxUxNEYPnNZQZLPraIkcdUCAgjKNR6/D/LUmXK28bG1W2ooiK2QfEdyYXhCbzsfJGJDuH60DtTlV0P4KVRQ1D1/FshT+3hx/fM5mVj4eHr9+mVMDnCmOUzgcoRMcJMZf3SRDr6inEgB4+dzQIatJ/9bm79Xm5t2ZSK8wxN6jBLDNRnMfIThjMHcRzDkR044+Y5Lt9wNoq5duiWSDnzk9dX3ax+dbOMUmDxsX8iBJ2wvOlH722M8Y4Pi9uBu7fRpJ3PBY4rG0mNgMshcU4xae5HuRBoDBzR30tmBUUt3Bz5xP4hPimu6SLVsrOZ20zIWQMPIUzXr0/PAN6QLVwkgB/CzsXxNHCXbWFfllhaEJTwxccd6cqq2MG+dXhTTxQQJuhzChKBIX5jZuFF7sDKWcQYrWkY5m1xACeNjB4tkPZ7CjirjFVMrqMG8Ui1mx1Tmtry9urOdx4qX5pzS2M0nH609+LTJBCS+Nf/V+pXPhJmtLy41lm4I6UFx4tmuXv3xQAr6kumwb881bs2AnXHyYtbVj8D2Nu5OwcLC5fNjkcyon122rp/YeD4y+sLpiBQbtgmaaWfcal+D8t/cWGZEihVdPC76U3hoTqxL58GG3HSySvBBrH/i7OLakyWw08CWvpaItAj3+GhRC7HspY9rX1+ozd4CK7C2cmNt5T3r4TlBa+yTG0WwIvWHF61z97DwhRn8/fai9dEZaY/5Qt/XEBQuuRiDCOmClv4bHC5r6TpMBTNYdr9ShNE8LABXoPfG43cl73m6sudEMZDk4oUBZbv0WPOL9dnp3kJq7/LhcGF5FsMFWRQK62Rb0WIun1p/7+b6B1cay8sbU8DZ1YOGm6Gq0GV5VLIvRkqtlXwUGussaI0nH2E6l/MFjcz9VSnTfeqodO7SoXBMphhFUhfDfXCTat9OwpLtXsLYYf42xKSvJ8vaHUy12RyDO3p8Pw+zwKDPzuBrH74jLI6wipzUc7WZ8zCR9esn60uXNh6/E2nj6M/erp8/hV42z6KLr8LLQ3OzehlFikuzY0SRrzdOYjFeuL7658bSYm+X0NlyhB7dgbubE8gY28wIMepXaOywLS2Ceuhj74GXoLnf8n0+iHsU09kOsB5O1D543Fh6sn4JRWn91HsbKGTatetnK+e1E+tXzjeW79W+ekdaWPBun3wAtrL/9cQJ/50VxZqabCzdt87Pi/0KEHdr+YHQI+Tyg6+tc3f61YEmSez1JK1qGpK/ZfVGN6e5zIjlRfQprEv/E+JnMXPVPEouqNT69XfXJ98XJEbq3wK7vCjmBMEKTujGh4LNyGnupYkpCplwGCbXWZBuUXdpEWXuy1lh361zy+jGb2jzmiob96hsvKfKYu6jqbLxXiqLRkc0Di7p+qPz7tSJ9f48RIi4bvCdnvrqSX7Ye9IdWNlbPlzNUcn4aiaoLzpti0x4rgW9nbTYU3T67ryPtD4xWzvzGazt7g2ltoyKs4skdJ5vNLljpc5jwexJGrcX00cVvUkDnlQRXHV2qSDsOXEOXHVczmRfwGiIK8S+Ve3ce0AcIebCK+jcY5OhCQ9DEz0ZmvDY4ESTofbGT5vbIXIxspv1iXdgZLwqs7M0B0SWBnqTcXfbrYDaIl9c5K2AOR6Mo+kGIjlbYjIMuPgApMS9Q4abpryiNbVgrVxoHd4RWCKNIxXwpE1wfPFGTCgRSsFIfy9eMCdwXJ+chijEG16N6qZIZhtVU+R2naQEjLO5nfnwHZAAd5IBptCY/hzj4en5xvIFsXXnwzyZgYkd74UZ3CMyTLy1wPM/3I8rKOVDMD4MY/x+/5tFvBm0i7VuOL5ZdKXPdjE7N2QPv511wiY0Pp0Ew9yy24gfwFNbOOOuVZu5WPtqFsyF61qLEA9o7M0iH9qbxZ/27BlLQNxom6N31ycm/zqxAIuDWGNY260pyRPRsYhf/zqBLpN73N6e6rMzGCrDaBe+qC2siAs53qs48k6J8FPvg+t5SbKeO3bfP/wQxzkyMoJXfN4sbu9wlaj9epf7btCfWIcqWRUvAqoaVCoHipoZHB0L5iCqG/Nn88oR+9ZRtvgv/MpRs7kd8q4RHxEn8U+ZGHrj1klr5gr+5Ie5zwNJrKkZEYOzkTFNUUeAUCNHsvxPadwcM4pR5i8wvGkWwHQkfyEJ7fdLKzHC0P0+ex2TD5Ie3pQK96AcgvIshZAAOQhpM0ayiskCgQAMX/Y9whq3Pql9dB4YYy3cYf82/Nqr0Pb6wgQyUwQHwqm8dNeeRceda88vcntlRA7B+vQdXIjbWd9y+ECopKCjV9FFqcbJD6GRZiXhNoIlFuG1FB3PsYFm91DHmrotvYHplfrZO5hbAinnNhqnL645OfmptnlyzjjZCvsbTxK7Nu+9pdxXuEaE7XSfshDRnTNLnvMR5rJpUj2pGk/6EJcf1wEPnuJBTTp5F5puLH0mb7/xSBipf23RrVKSOu0pXcePBX21hyZKNR6fwOyPuDrnYlyXDLD7Bh3vjesJcBl641bHlfXqRvSgTHQH3ZvWKFiCq2wERU0bQTGvXV5mIzK/PcJw8CNKnufl0/avMG4h2mD3waYKiW4jilBnbnXxi/fAxdyUUxiHvXDbOYgB7eBpiU7HMQT5oPHGkwXwG8RX69xlMKCCmnIk50F+J9buf+4QV4zCndDHa3lch6SDBQYfNJwnM9evX7NuXHTy/ja9ef60MXfCuvqNsEvui6cMRNC6Mc+a6203veu62qIGfnjSvZ6C81K/fUYOwdVfMhBnXTwd6Zl0dHjaPJW5zXoqoPZrj68+hbPinkA8EBkEgnXxvdEZmnKWvY4npFr95qfxb+UBKrd32+UYVbtT6jiiLbNKwEiFw7vFYU+XAYUHAxEm6dkMV52Db/Zudcsmdnvo14yZOwam9rYOTKg9Nu0+tLA9NJ7dcFIOIrvQMeUAP7pyBjxgxUOvzfSQ6Ng9lPYov9eAOmdwUPybVLS7lftRTn6uNUkltw3cGSfBRIxnnkyDXreMRMzRFnxRkI10uK7suAPc1HfaKBV64WxL8MJyjbAPu3FVbTyesk5/JsyS4+astJzP5CrfsiYJc3Zv2Xp80m6/ZSkecZ/htW8hu3yyDpeOW9/KO8atP7suCbe1Z9/ybX3hXOptqyFvvfDfxVFg/tF9j5X/0HptdYTbh5HmKX1cOr8EOyUMn9uVcCjLLavYN7U3EbttE6I16LIL6Dgv61dPtecORvi1Shid94xs2xEVsWPj3qhxtFzsYNh7w5PundVup23lOVvXmduWvUKpDe4EAiqQO8EtstDuzLNHxUQOsIOiObah85ZOqyHl+zROErXbbof7FDB+vXdb2hPX2WGMHYQKPrgrAQFa92J7bLsKu4K0Xl1hrRuMLq+Dn4xtxkH8aK20/csPRIodifQ7bRxdNZj/2qOFFrmbB4WUGxFXPwInxeEiiJh164xweqBy/Ysv1u7P4nIuecwTmSCzjnXgJSZALBHF4KsLQF4w2taDJy5fCQzZmZuO3zM/XV+5JUiwtnLK0Q3hYFun5jv7a2JFmQeCLwsHU5yr8EYjz3BX9c2i7/iPjbPyvD6d8X/AAus5rWI+E/ifDfB/QuF4LNmG/5Mg/J8teY4NMCYBe1hnxB4sIE/HMC9qD76xgXuYjdyDP9orsMToYQ5ID750kH1YC7QPvmwD8WGbQPHBBsQJtF3sDfjC2DH+L/wsbhPwQbqArXgV/r4ypkTiCSyhgvRl4plUJJGKpmKxeEqJxJSomlJiai4XySTj8F9EGUxGMplIJBPXIqoWSYZjyUgqnlJzUaXZZmbc5EMJJxOxkPNrqVouGRVOsbbEpn3A5fRtsPK4FkofzePvTSIxOVwjx+zkwL1B23/jPi1vqFfMJ+JCLMYdlSDYzKCwykFnkQ+KZTUIi3hQLItBvpoGxdoZbNmVF7uXjpvf4uB7XXtYs866vRDb8E+KMbrDTmeHRCYU+KrglPdG44J4IrQWRVz81d/WbFbw347Dv29xiZHpbCkrzaQ2E1lt8atMbbM33oLvx3k956BkWsg4CrM/BP+lDoZCu/h//xRKwb++geMDP7aad31a8T+fG/w/wn/dkqcz/7cU/y8UT8ba8f8StP5vxfOi4P+JrKKvI/5fvAv+n5YMK5GMGg5nktFoLprRktnc4KCqKTlVA5FMZKOxqBpLRHyE/0f4fz7C/2vLzW18bZ7w/wj/rwP4AeH/Ef4f4f8R/h/h/xH+H+H/9TU5wv8j/L/eRQn/j/D/CP+P8P8I/4/w/wj/j/D/CP+P8P8I/4/w/wj/j/D/CP+P8P8I/+95wv8jfD3C1yN8PcLXI3w9wtcjfD3C1yN8PcLXI3w97wpE+HqEr0f4eoSvR/h6W4qvRxhuhOFGGG6E4UYYbt8RhtvfA4YbQZIRJBlBkhEkGUGSESQZQZIRJNnzAUn2XIDCdMb/2FL8r0g4HG3D/4gR/seWPFuG/xXviv9lQ3t0wf/qH8XjmeB/xZJaPDYYy+VUNa6GIqlUKqzmQDCTWlgNJzO5yOBgNhpOxFNqYjAeVrRINKVlNTUR08JRJRUa7ID/lUikos8W/6sb6tfzBeflPgYg9vBwYeNLaBCXTnv3/Kx7uXRvHjktNWMJJ2hpCRfcgQKOhwcK7rDAaeuHjpScjjyZ62dy9B8m5jr63w3jDMXtB8U4i/sjgy8Sxhk93R/3+h97jvDfYknCf9uKpzP/nwP8tzj5f1vx/C3gv8W64L/FI1o0k8tGcrFYLBROJZKJqJJMxULZUEZLJAaVSCI+mE2oqo/w3wj/zUf4b22J0L7uZBP+G+G/Ef4b4b8R/lv/FQn/jfDfCP+N8N8I/63fKoT/RvhvhP9G+G+E/0b4b4T/RvhvhP9G+G+E/0b4b4T/RvhvhP9G+G+E/0b4b4T/RvhvhP9G+G+E/0b4b4T/9h3hvxH+G+G/Ef4b4b8R/hvhvxH+G+G/Ef4b4b8R/hvhvxH+G+G/Ef4b4b8R/hvhvxH+mxR8wn8j/DfCfyP8N8J/+3vFf4s9T/hvhP+xJc+W4b/Fnhb/rX8Uj2eC/xaPKdpgIqQltZyq5BQtHFFSyZASi6UySiibS2hhLZzRotFwTsvFB1MJLaHFk7GUGlIiijqY0wj/jfDfCP+NnhfkcdZ/YUueF/w3MPKE/7YVT2f+/+j4b7FkmPy/rXheePw3eU6Q8N8I/43w3wj/jfDferGV8N8I/43w3wj/jfDfCP+N8N8I/43w3wj/jfDfCP+N8N8I/43w3wj/jfDfCP+N8N8I/43w3wj/jfDfCP+N8N8I/43w3wj/jfDfCP+N8N8I/43w3wj/jfDfCP+N8N8I/43w3wj/jfDfviP8N8J/I/w3wn8j/DfCfyP8N8J/I/w3wn8j/DfCfyP8N8J/I/w3wn8j/DfCf3sR8N88+B8/Ov5bLEH4H1vybA3+mw3S8QLgvymxRDQUjody4WwuMpjKxQe1bDISzyXUXDwTTWQSoehgKJsIxaFcSlNAosNqIpJTwrHBuKJGcoT/RvhvhP9GzwvyuPFfow7+67Pt4ynw36KxBOG/bcXTmf8/Ov4bLK/k/23F88Ljvwm59RH+G+G/Ef4b4b8R/lsvthL+G+G/Ef4b4b8R/hvhvxH+G+G/Ef4b4b8R/hvhvxH+G+G/Ef4b4b8R/hvhvxH+G+G/Ef4b4b8R/hvhvxH+G+G/Ef4b4b8R/hvhvxH+G+G/Ef4b4b8R/hvhvxH+G+G/Ef4b4b8R/tt3hP9G+G+E/0b4b4T/RvhvhP9G+G+E/0b4b4T/RvhvhP9G+G+E/0b4b4T/RvhvLwL+mwf/40fHfwvFCP9jS56twX+zQTpeAPy3bCqqqrnBWFLLRQYz2bCSig4mopFsJJJIZdRUQomnEglVUcOKmkzEcqlUKqNEVQ2KRlNqLJEi/DfCfyP8N3pekEdccP1h+9g8/lsknIgQ/ttWPIL/noX/mfexAf/jsVi8Ff8vEU+S/7cVz0//IVitlHlSXyse5js9A3hJx69VDVbSS1pO0fMDA78eGt6Tfv3Avt2+nx37z71Dr70ylH55z4FX9gyn7Te7/F03p477PPXtzz8Pwou9rw4fHNq3L/3ya6/saW8cf93l/xn+aUmWY5t7X03/Zu8BqOVuBKfiGxiQufS09Da37+Brn55jbzB/jrVUsRPv/7HnwPDe1171sbd+ycwxrcjXRdxH2qA8lNNgHeXFS2Udlmy2rWgUtW3wS06HpXGgrBUMU2sZjbMnBu3bRAmKOxbCPWX//M/b9v/XtgG9gEef+caZ/bkyXhnIwarOquV8Xs8E7BsM8jX8itcfBgb4TSb5bTtUCijl0cNvhN/ayfCEsFE1d8d2MKViH/vXdvFJ4N0ztlvs1OUNRd1uv94xwOe3HQsERjVzu7wT4tsJvnvxUBH3iXfsGNj/X3zS1WJabiTKGYuj7GahBJ/hX2Dd9sIhUyuUWORXQVU7HCxW83ncwJS/+k3vRvMOJDW/wbWtXBCMhGZ829iBPQdfP/AqvHTtfLqI2tzO9DG/IWtB6c6ivLtZ08febCs2/Lu9+9P7hw6+vDvc7e3vDwzt37/nQMcC//763j0H20Wd/7zLHzouukRFtMcJpMwWVKwS3uUXGUcQ/6xS0aAEvPExHUVVvNnhkcLeu+HbPGXFvqjYsPn+4Yc/r0AB6GB7iypxHrh6cN0pdtVy64uo0EX3wK+1URS9eufqguclnY1U18jaVdPdnBwpaGCP/jtturUNxKWofVTmWiu/9VZeDEtBe22t3Q9fBwbkpSuX+lW24xu3+u7gNz34WaHtWjFrIEDXbl/VzPlTqH98pxBakOlprqj8N4+eDgBJZMndzOdcyWiyd3uueT0D6O7c0Pj+4cyxPNqTZvPb+AEWTd22E+KHHTuOg6R9bqfdZqErLe/tzLtb6em0tU/nQkl7M5VDeqm0QfXGva8bT6Z5Xdu8dShYW/hczK1JFptwZcMwfTu8ZBGy6Ej9MVH+jW1Ydttbx31oAqUEuGXwl7+EP+LqjNDTP1Z1zdwdagooKHlklx+MAMzO7+evW6VR1Am72+V21VbQ3V11VthqdznvutRqhW0FlBKzbYfPPVBva3zEtmixt7B6l0I/84y2dXZYSU4byoZlU44p6HnLyGUbvH3ItrWjuslCbsJt0Nu5d+tnPT2IXSzeD/P/inXurX3avK/Oy4Ds3bVWNiVFHHoXkgJrkvB3vM66T4oTk8LCXByM/OoXYZyOWa4K30Q7ys2MHMG+oVd/+/rQb/fsfnusfwPNfvELLHW0L/PbwlrtqJbtrx5owb/sihz32G9eWx668bznpPpH77qH+xVfo2Z2OqzD/mQT7U+SxMjFX/0iMuAIScRuWasoWcps0EMPPX+Lz/8BffobXQCoAQA=
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
    0.16.*)
      printf '%s\n' "$payload_root/packages/0.16.x/zh-CN"
      ;;
    0.15.*)
      printf '%s\n' "$payload_root/packages/0.15.x/zh-CN"
      ;;
    0.14.*)
      printf '%s\n' "$payload_root/packages/0.14.x/zh-CN"
      ;;
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
    0.16.*) printf '0.16.x' ;;
    0.15.*) printf '0.15.x' ;;
    0.14.*) printf '0.14.x' ;;
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
printf '未找到原版 Hermes，请重新执行：(curl -fsSL http://47.121.138.43/hermes/install.sh || curl -fsSL https://cdn.jsdelivr.net/gh/fresh-claw/hermes-cn@main/install.sh) | bash\\n' >&2
exit 127
EOF_WRAPPER
  chmod +x "$BIN_DIR/hermes"
}

apply_tui_source_patch() {
  if [ "${XIAOMA_HERMES_SKIP_TUI_PATCH:-0}" = "1" ]; then
    printf '{"state":"skipped"}\n' > "$INSTALL_HOME/current/PATCH_STATUS"
    return
  fi

  local real_hermes="$1"
  python3 - "$real_hermes" "$INSTALL_HOME" "$PACKAGE_VERSION" "$INSTALL_HOME/current/PATCH_STATUS" "$HERMES_HOME_DIR" <<'PY_PATCH'
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

real_hermes = sys.argv[1].strip()
install_home = Path(sys.argv[2]).expanduser()
package_version = sys.argv[3]
status_path = Path(sys.argv[4]).expanduser()
hermes_home = Path(sys.argv[5]).expanduser()
home = Path.home()
seen = set()
candidates = []


def add_candidate(path):
    if not path:
        return
    try:
        root = Path(path).expanduser().resolve()
    except Exception:
        return
    if root in seen:
        return
    seen.add(root)
    candidates.append(root)


def add_from_python(python_bin):
    if not python_bin:
        return
    try:
        result = subprocess.run(
            [
                python_bin,
                "-c",
                "import pathlib, hermes_cli; print(pathlib.Path(hermes_cli.__file__).resolve().parent.parent)",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=3,
        )
    except Exception:
        return
    if result.returncode == 0 and result.stdout.strip():
        add_candidate(result.stdout.strip())


env_root = os.environ.get("XIAOMA_HERMES_SOURCE_ROOT", "").strip()
add_candidate(env_root)

if real_hermes:
    hermes_path = Path(real_hermes).expanduser()
    try:
        resolved = hermes_path.resolve()
    except Exception:
        resolved = hermes_path
    for parent in [resolved.parent, *resolved.parents]:
        add_candidate(parent)
    try:
        first_line = resolved.read_text(encoding="utf-8", errors="ignore").splitlines()[0]
    except Exception:
        first_line = ""
    if first_line.startswith("#!"):
        add_from_python(first_line[2:].strip().split()[0])

add_candidate(home / ".hermes" / "hermes-agent")
add_candidate(hermes_home / "hermes-agent")
add_candidate(Path("/usr/local/lib/hermes-agent"))
add_candidate(Path("/opt/hermes-agent"))
add_candidate(Path("/usr/local/hermes-agent"))

for exe_name in ("hermes", "hermes-agent"):
    found = shutil.which(exe_name)
    if found:
        exe = Path(found)
        try:
            resolved = exe.resolve()
        except Exception:
            resolved = exe
        for parent in [resolved.parent, *resolved.parents]:
            add_candidate(parent)
        try:
            first_line = resolved.read_text(encoding="utf-8", errors="ignore").splitlines()[0]
        except Exception:
            first_line = ""
        if first_line.startswith("#!"):
            add_from_python(first_line[2:].strip().split()[0])

try:
    import hermes_cli
    add_candidate(Path(hermes_cli.__file__).resolve().parent.parent)
except Exception:
    pass

root = None
for candidate in candidates:
    if (candidate / "hermes_cli").is_dir():
        root = candidate
        break

if root is None:
    status = {
        "state": "not_found",
        "version": package_version,
        "real_hermes": real_hermes,
        "candidates": [str(c) for c in candidates[:40]],
        "message": "未找到 Hermes 源码目录，启动界面补丁未应用。",
    }
    status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(status["message"])
    raise SystemExit(0)

backup_root = install_home / "backups" / package_version / root.name

banner_display_helpers = '''def _display_toolset_name(toolset_name: str) -> str:
    """Normalize internal/legacy toolset identifiers for banner display."""
    if not toolset_name:
        return "未知"
    normalized = (
        toolset_name[:-6]
        if toolset_name.endswith("_tools")
        else toolset_name
    )
    mapping = {
        "browser": "浏览器",
        "browser-cdp": "浏览器 CDP",
        "clarify": "澄清",
        "code_execution": "代码执行",
        "cronjob": "定时任务",
        "delegation": "任务委派",
        "discord": "Discord",
        "discord_admin": "Discord 管理",
        "terminal": "终端",
        "web": "网页",
        "file": "文件",
        "memory": "记忆",
        "skills": "技能",
        "todo": "待办",
        "session_search": "会话搜索",
        "image_gen": "图像生成",
        "vision": "视觉",
        "computer_use": "电脑操作",
        "feishu_doc": "飞书文档",
        "feishu_drive": "飞书云文档",
        "google_meet": "Google Meet",
        "homeassistant": "Home Assistant",
        "messaging": "消息",
        "moa": "多模型协作",
        "spotify": "Spotify",
        "tts": "语音",
        "video": "视频",
        "other": "其他",
        "builtin": "内置",
        "core": "核心",
    }
    if normalized.startswith("mcp-"):
        return "MCP " + normalized[4:]
    if normalized.startswith("hermes-"):
        return "Hermes " + normalized[7:].replace("-", " ")
    return mapping.get(normalized, normalized.replace("_", " " ).replace("-", " "))


def _display_skill_category_name(category: str) -> str:
    if not category:
        return "通用"
    mapping = {
        "autonomous-ai-agents": "自主智能体",
        "creative": "创作",
        "data-science": "数据科学",
        "devops": "运维",
        "email": "邮件",
        "gaming": "游戏",
        "general": "通用",
        "github": "GitHub",
        "mcp": "MCP",
        "media": "媒体",
        "mlops": "机器学习工程",
        "note-taking": "笔记",
        "productivity": "效率",
        "red-teaming": "安全测试",
        "research": "研究",
        "smart-home": "智能家居",
        "social-media": "社交媒体",
        "software-development": "软件开发",
    }
    return mapping.get(category, category.replace("_", " " ).replace("-", " "))
'''

command_localization_helpers = '''_ZH_COMMAND_DESCRIPTIONS = {
    "new": "新建会话（新的会话 ID 和历史）",
    "topic": "启用或查看 Telegram 私信主题会话",
    "clear": "清屏并新建会话",
    "redraw": "强制刷新界面（修复终端显示错位）",
    "history": "查看对话历史",
    "save": "保存当前对话",
    "retry": "重试上一条消息（重新发送给 Agent）",
    "undo": "移除上一轮用户和助手对话",
    "title": "设置当前会话标题",
    "handoff": "将此会话转交到消息平台（Telegram、Discord 等）",
    "branch": "从当前会话创建分支（尝试另一条思路）",
    "compress": "手动压缩对话上下文",
    "rollback": "列出或恢复文件检查点",
    "snapshot": "创建或恢复 Hermes 配置和状态快照",
    "stop": "结束所有后台进程",
    "approve": "批准待处理的危险命令",
    "deny": "拒绝待处理的危险命令",
    "background": "在后台执行提示词",
    "agents": "查看活跃 Agent 和运行任务",
    "queue": "将提示词加入下一轮队列（不打断当前任务）",
    "steer": "在下一次工具调用后插入消息，不打断当前任务",
    "goal": "设置持续目标，Hermes 会跨轮执行直到完成",
    "subgoal": "添加或管理当前目标的清单项",
    "status": "查看会话信息",
    "whoami": "查看当前斜杠命令权限（管理员/用户）",
    "profile": "查看当前配置档名称和主目录",
    "sethome": "将当前聊天设为主频道",
    "resume": "继续之前命名的会话",
    "sessions": "浏览并继续之前的会话",
    "config": "查看当前配置",
    "model": "切换本会话模型",
    "gquota": "查看 Google Gemini Code Assist 配额",
    "personality": "设置预设人格",
    "statusbar": "切换上下文/模型状态栏",
    "verbose": "切换工具进度显示：关闭、新调用、全部、详细",
    "footer": "切换网关最终回复中的运行元信息页脚",
    "yolo": "切换 YOLO 模式（跳过危险命令确认）",
    "reasoning": "管理推理强度和显示方式",
    "fast": "切换快速模式（普通/快速）",
    "skin": "查看或切换显示主题",
    "indicator": "选择 TUI 忙碌指示器样式",
    "voice": "切换语音模式",
    "busy": "控制 Hermes 忙碌时按 Enter 的行为",
    "tools": "管理工具",
    "toolsets": "列出可用工具集",
    "skills": "搜索、安装、查看或管理技能",
    "cron": "管理定时任务",
    "curator": "后台技能维护（状态、运行、固定、归档、列出归档）",
    "kanban": "多配置协作看板（任务、链接、评论）",
    "reload": "重新读取 .env 变量",
    "reload-mcp": "重新读取 MCP 服务配置",
    "reload-skills": "重新扫描 ~/.hermes/skills/ 中的技能",
    "browser": "通过 CDP 连接本机 Chrome 浏览器工具",
    "plugins": "列出已安装插件及状态",
    "commands": "分页浏览全部命令和技能",
    "help": "查看可用命令",
    "restart": "当前运行完成后平滑重启网关",
    "usage": "查看当前会话的 token 用量和速率限制",
    "insights": "查看用量分析",
    "platforms": "查看网关/消息平台状态",
    "copy": "复制上一条助手回复",
    "paste": "附加剪贴板图片",
    "image": "为下一条提示附加本地图片",
    "update": "将 Hermes Agent 更新到最新版",
    "debug": "上传调试报告（系统信息和日志），获得分享链接",
    "quit": "退出 CLI",
}

_ZH_COMMAND_CATEGORIES = {
    "Session": "会话",
    "Info": "信息",
    "Configuration": "配置",
    "Tools & Skills": "工具与技能",
    "Exit": "退出",
}

_ZH_ARGS_HINTS = {
    "new": "[名称]",
    "topic": "[off|help|会话ID]",
    "title": "[名称]",
    "handoff": "<平台>",
    "branch": "[名称]",
    "compress": "[主题]",
    "rollback": "[编号]",
    "snapshot": "[create|restore <ID>|prune]",
    "approve": "[session|always]",
    "background": "<提示词>",
    "queue": "<提示词>",
    "steer": "<提示词>",
    "goal": "[文本 | pause | resume | clear | status]",
    "subgoal": "[文本 | complete N | impossible N | undo N | remove N | clear]",
    "model": "[模型] [--provider 名称] [--global]",
    "footer": "[on|off|status]",
    "reasoning": "[级别|show|hide]",
    "fast": "[normal|fast|status]",
    "skin": "[名称]",
    "indicator": "[kaomoji|emoji|unicode|ascii]",
    "voice": "[on|off|tts|status]",
    "busy": "[queue|steer|interrupt|status]",
    "tools": "[list|disable|enable] [名称...]",
    "cron": "[子命令]",
    "curator": "[子命令]",
    "kanban": "[子命令]",
    "commands": "[页码]",
    "insights": "[天数]",
    "copy": "[编号]",
    "image": "<路径>",
}


def _zh_command_description(cmd: CommandDef) -> str:
    return _ZH_COMMAND_DESCRIPTIONS.get(cmd.name, cmd.description)


def _zh_command_category(category: str) -> str:
    return _ZH_COMMAND_CATEGORIES.get(category, category)


def _zh_command_args_hint(cmd: CommandDef) -> str:
    return _ZH_ARGS_HINTS.get(cmd.name, cmd.args_hint)

'''

zh_banner_logo = """[bold #FFD700]      ⣀⣀⣀⣀                  ⢀⡀  ⢀⣀      ⢠⡄           ⣀⣀⣀⣀ ⣀⣀⣀⣀       ⢀⣀⡀[/]
[bold #FFD700]⠘⢛⣿⠛⠻⣿⠉⢉⣯⠍⠁   ⠛⠛⠛⠛⠛⠛⢻⣿     ⢀⣿⠋  ⢸⣿    ⢀⣀⣸⣇⣀⡀⣿⠛⠛⣿⡇    ⣿⣉⣉⣿ ⣿⣉⣉⣿       ⢸⣿[/]
[#FFBF00]⣶⠶⠿⠶⢶⣷⠶⠿⠷⢶⡆    ⢸⡏   ⢸⡿    ⢀⣾⡏⠰⠶⠶⢾⣿⠶⠶⠶⠆⠈⠋⣻⡟⠙⠁⣿  ⣿⡇   ⣀⣉⣉⣉⣉⣤⣉⣹⣏⣉⡀      ⢸⣿⡀[/]
[#FFBF00]⠉⠷⠶⢶⡾⠷⠶⠶⠶⠎⠁    ⣸⣧⣤⣤⣤⣼⣧⣤⡄ ⠐⠿⢹⡇   ⢸⣿     ⣰⣿⡗⢷⡀⣿  ⣿⡇   ⠙⣛⣉⣩⡿⠛⢿⣍⣉⣛⣋     ⢀⣿⠻⣧[/]
[#CD7F32] ⣀⣴⢿⣗⠒⠒⣶⡶⠂   ⢀⣀⣀⣀⣀⣀⣀⣀⡀⢸⡇   ⢸⡇   ⢸⣿    ⠰⡟⢸⡇⠈⢀⣿  ⣿⡇   ⠙⣿⠯⢴⣦⠠⣶⠮⠿⣿⠋    ⣠⡿⠃ ⠹⣷⣄[/]
[#CD7F32]⠙⣋⣀⣀⣽⡷⢿⣯⣤⣤⣀  ⠈⠉⠉⠉⠉⠉⠉⢉⣁⣿⡇   ⢸⡇ ⣶⣶⣾⣿⣶⣶⣶   ⢸⡇⢀⣾⠇  ⣿⣧⣼⠆  ⣿⣤⣤⣿ ⣿⣤⣤⣿   ⣴⡾⠟⠁   ⠈⠻⣷⡦[/]
[#8B5A2B] ⠙⠉⠉    ⠉⠉⠁         ⠈⠛⠉    ⠘⠃           ⠘⠃⠙⠃   ⠈⠉⠁   ⠉  ⠉⠈⠉  ⠉   ⠈         ⠁[/]"""

zh_horse_head = """[#CD7F32]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡀⠀⣀⣀⠀⢀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
[#CD7F32]⠀⠀⠀⠀⠀⠀⢀⣠⣴⣾⣿⣿⣇⠸⣿⣿⠇⣸⣿⣿⣷⣦⣄⡀⠀⠀⠀⠀⠀⠀[/]
[#FFBF00]⠀⢀⣠⣴⣶⠿⠋⣩⡿⣿⡿⠻⣿⡇⢠⡄⢸⣿⠟⢿⣿⢿⣍⠙⠿⣶⣦⣄⡀⠀[/]
[#FFBF00]⠀⠀⠉⠉⠁⠶⠟⠋⠀⠉⠀⢀⣈⣁⡈⢁⣈⣁⡀⠀⠉⠀⠙⠻⠶⠈⠉⠉⠀⠀[/]
[#FFD700]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣴⣿⡿⠛⢁⡈⠛⢿⣿⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
[#FFD700]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠿⣿⣦⣤⣈⠁⢠⣴⣿⠿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
[#FFBF00]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠻⢿⣿⣦⡉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
[#FFBF00]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⢷⣦⣈⠛⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
[#CD7F32]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣴⠦⠈⠙⠿⣦⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
[#CD7F32]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿⣤⡈⠁⢤⣿⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
[#B8860B]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠛⠷⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
[#B8860B]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⠑⢶⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
[#B8860B]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⠁⢰⡆⠈⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
[#B8860B]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠳⠈⣡⠞⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
[#B8860B]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]"""

zh_banner_logo_plain = [line.split("]", 1)[1].rsplit("[/", 1)[0] for line in zh_banner_logo.splitlines()]
zh_horse_head_plain = [line.split("]", 1)[1].rsplit("[/", 1)[0] for line in zh_horse_head.splitlines()]

xiaoma_skin_state = {"state": "skipped"}

def yaml_block(value: str, indent: str = "  ") -> str:
    return "\n".join(indent + line for line in value.splitlines())


def update_display_config(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = path.read_text(encoding="utf-8", errors="ignore") if path.exists() else ""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(r"^display\s*:", line):
            start = i
            break

    wanted = {"language": "zh", "skin": "xiaoma-zh"}
    if start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend(["display:", "  language: zh", "  skin: xiaoma-zh"])
        path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
        return

    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].strip() and not lines[j].startswith((" ", "\t", "#")):
            end = j
            break

    if "{" in lines[start] and "}" in lines[start]:
        lines[start:end] = ["display:", "  language: zh", "  skin: xiaoma-zh"]
        path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
        return

    found = set()
    j = start + 1
    while j < end:
        m = re.match(r"^(\s*)(language|skin)\s*:", lines[j])
        if m:
            indent = m.group(1) or "  "
            key = m.group(2)
            lines[j] = f"{indent}{key}: {wanted[key]}"
            found.add(key)
        j += 1

    insert_at = start + 1
    for key in ("language", "skin"):
        if key not in found:
            lines.insert(insert_at, f"  {key}: {wanted[key]}")
            insert_at += 1
            end += 1

    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


if os.environ.get("XIAOMA_HERMES_SKIP_CONFIG", "0") != "1":
    try:
        skin_dir = hermes_home / "skins"
        skin_dir.mkdir(parents=True, exist_ok=True)
        skin_path = skin_dir / "xiaoma-zh.yaml"
        skin_text = f"""name: xiaoma-zh
description: 小马AI Hermes 中文增强
colors:
  banner_border: "#CD7F32"
  banner_title: "#FFD700"
  banner_accent: "#FFBF00"
  banner_dim: "#B8860B"
  banner_text: "#FFF8DC"
  ui_accent: "#FFBF00"
  ui_label: "#DAA520"
  prompt: "#FFF8DC"
  input_rule: "#CD7F32"
branding:
  agent_name: 爱马仕机器人
  prompt_symbol: "›"
  help_header: 爱马仕机器人命令
  goodbye: 已退出爱马仕机器人。
banner_logo: |
{yaml_block(zh_banner_logo)}
banner_hero: |
{yaml_block(zh_horse_head)}
"""
        skin_path.write_text(skin_text, encoding="utf-8")
        update_display_config(hermes_home / "config.yaml")
        xiaoma_skin_state = {
            "state": "applied",
            "path": str(skin_path),
            "config": str(hermes_home / "config.yaml"),
        }
    except Exception as exc:
        xiaoma_skin_state = {"state": "failed", "message": str(exc)}

basic_replacements = {
    "hermes_cli/banner.py": [
        ('base = f"Hermes Agent v{VERSION} ({RELEASE_DATE})"', 'base = f"爱马仕机器人 v{VERSION} ({RELEASE_DATE})"'),
        ('line1 = "⚕ NOUS HERMES - AI Agent Framework"', 'line1 = "♞ 爱马仕机器人 - AI Agent 框架"'),
        ('tiny_line = "⚕ NOUS HERMES"', 'tiny_line = "♞ 爱马仕机器人"'),
        ('_skin.get_branding("agent_name", "Hermes Agent")', '_skin.get_branding("agent_name", "爱马仕机器人")'),
        ('if _skin else "Hermes Agent"', 'if _skin else "爱马仕机器人"'),
        ('left_lines.append(f"[dim {session_color}]Session: {session_id}[/]")', 'left_lines.append(f"[dim {session_color}]会话：{session_id}[/]")'),
        ('right_lines = [f"[bold {accent}]Available Tools[/]"]', 'right_lines = [f"[bold {accent}]可用工具[/]"]'),
        ('right_lines.append(f"[dim {dim}](and {remaining_toolsets} more toolsets...)[/]")', 'right_lines.append(f"[dim {dim}]（另有 {remaining_toolsets} 个工具集...）[/]")'),
        ('right_lines.append(f"[bold {accent}]MCP Servers[/]")', 'right_lines.append(f"[bold {accent}]MCP 服务[/]")'),
        ('f"[dim {dim}]—[/] [{text}]{srv[\'tools\']} tool(s)[/]"', 'f"[dim {dim}]—[/] [{text}]{srv[\'tools\']} 个工具[/]"'),
        ('f"[red]— failed[/]"', 'f"[red]— 失败[/]"'),
        ('right_lines.append(f"[bold {accent}]Available Skills[/]")', 'right_lines.append(f"[bold {accent}]可用技能[/]")'),
        ('skills_str = ", ".join(display_names) + f" +{len(skill_names) - 8} more"', 'skills_str = ", ".join(display_names) + f" +{len(skill_names) - 8} 项"'),
        ('right_lines.append(f"[dim {dim}]No skills installed[/]")', 'right_lines.append(f"[dim {dim}]未安装技能[/]")'),
        ('summary_parts = [f"{len(tools)} tools", f"{total_skills} skills"]', 'summary_parts = [f"{len(tools)} 个工具", f"{total_skills} 个技能"]'),
        ('summary_parts.append(f"{mcp_connected} MCP servers")', 'summary_parts.append(f"{mcp_connected} 个 MCP 服务")'),
        ('summary_parts.append("/help for commands")', 'summary_parts.append("/help 查看命令")'),
        ('agent_name = _skin_branding("agent_name", "Hermes Agent")', 'agent_name = _skin_branding("agent_name", "爱马仕机器人")'),
        ('[#FFBF00]⚕ NOUS HERMES[/] [dim #B8860B]- AI Agent Framework[/]', '[#FFBF00]♞ 爱马仕机器人[/] [dim #B8860B]- AI Agent 框架[/]'),
        ('[#CD7F32]Messenger of the Digital Gods[/]    [dim #B8860B]Nous Research[/]', '[#CD7F32]中文增强版[/]                 [dim #B8860B]Nous Research[/]'),
    ],
	    "hermes_cli/skin_engine.py": [
		        ('"agent_name": "Hermes Agent"', '"agent_name": "爱马仕机器人"'),
		        ("Welcome to Hermes Agent! Type your message or /help for commands.", "欢迎使用爱马仕机器人！输入消息，或输入 /help 查看命令。"),
	        ("Welcome to Ares Agent! Type your message or /help for commands.", "欢迎使用 Ares Agent！输入消息，或输入 /help 查看命令。"),
	        ("Welcome to Poseidon Agent! Type your message or /help for commands.", "欢迎使用 Poseidon Agent！输入消息，或输入 /help 查看命令。"),
	        ("Welcome to Sisyphus Agent! Type your message or /help for commands.", "欢迎使用 Sisyphus Agent！输入消息，或输入 /help 查看命令。"),
	        ("Welcome to Charizard Agent! Type your message or /help for commands.", "欢迎使用 Charizard Agent！输入消息，或输入 /help 查看命令。"),
	        ("Goodbye! ⚕", "再见！⚕"),
	        ("(^_^)? Available Commands", "(^_^)? 可用命令"),
	        ("(⚔) Available Commands", "(⚔) 可用命令"),
	        ("[?] Available Commands", "[?] 可用命令"),
	        ("(Ψ) Available Commands", "(Ψ) 可用命令"),
	        ("(◉) Available Commands", "(◉) 可用命令"),
	        ("(✦) Available Commands", "(✦) 可用命令"),
	        ("(^_^)? Commands", "(^_^)? 命令"),
	    ],
	    "hermes_cli/mcp_config.py": [
	        ('print(color("  MCP Servers:", Colors.CYAN + Colors.BOLD))', 'print(color("  MCP 服务:", Colors.CYAN + Colors.BOLD))'),
	        ('_success(f"Saved \'{name}\' to {display_hermes_home()}/config.yaml ({tool_count}/{total} tools enabled)")', '_success(f"已保存 \'{name}\' 到 {display_hermes_home()}/config.yaml（已启用 {tool_count}/{total} 个工具）")'),
	        ('_info("Start a new session to use these tools.")', '_info("请新建会话后使用这些工具。")'),
	        ('_success(f"Updated config: {new_count}/{total} tools enabled")', '_success(f"配置已更新：已启用 {new_count}/{total} 个工具")'),
	        ('_info("Start a new session for changes to take effect.")', '_info("请新建会话后使改动生效。")'),
	    ],
	    "hermes_cli/memory_setup.py": [
	        ('print(f"\\n  Memory provider \'{provider_name}\' not found.")', 'print(f"\\n  未找到记忆服务 \'{provider_name}\'。")'),
	        ('print("  Run \'hermes memory setup\' to see available providers.\\n")', 'print("  运行 \'hermes memory setup\' 查看可用服务。\\n")'),
	        ('print("\\n  No memory provider plugins detected.")', 'print("\\n  未检测到记忆服务插件。")'),
	        ('print("  Install a plugin to ~/.hermes/plugins/ and try again.\\n")', 'print("  请安装插件到 ~/.hermes/plugins/ 后重试。\\n")'),
	        ('items.append(("Built-in only", "— MEMORY.md / USER.md (default)"))', 'items.append(("仅使用内置记忆", "— MEMORY.md / USER.md（默认）"))'),
	        ('selected = _curses_select("Memory provider setup", items, default=builtin_idx)', 'selected = _curses_select("记忆服务设置", items, default=builtin_idx)'),
	        ('print("\\n  ✓ Memory provider: built-in only")', 'print("\\n  ✓ 记忆服务：仅使用内置记忆")'),
	        ('print(f"  Failed to write provider config: {e}")', 'print(f"  写入记忆服务配置失败：{e}")'),
	        ('print(f"\\n  Memory provider: {name}")', 'print(f"\\n  记忆服务：{name}")'),
	        ('print(f"  Activation saved to config.yaml")', 'print(f"  启用状态已保存到 config.yaml")'),
	        ('print(f"  Provider config saved")', 'print(f"  服务配置已保存")'),
	        ('print(f"  API keys saved to .env")', 'print(f"  API Key 已保存到 .env")'),
	        ('print(f"\\n  Start a new session to activate.\\n")', 'print(f"\\n  请新建会话后启用。\\n")'),
	    ],
	    "hermes_cli/commands.py": [
	        ('"Start a new session (fresh session ID + history)"', '"新建会话（新的会话 ID 和历史）"'),
	        ('"Enable or inspect Telegram DM topic sessions"', '"启用或查看 Telegram 私信主题会话"'),
	        ('"Clear screen and start a new session"', '"清屏并新建会话"'),
	        ('"Force a full UI repaint (recovers from terminal drift)"', '"强制刷新界面（修复终端显示错位）"'),
	        ('"Show conversation history"', '"查看对话历史"'),
	        ('"Save the current conversation"', '"保存当前对话"'),
	        ('"Retry the last message (resend to agent)"', '"重试上一条消息（重新发送给 Agent）"'),
	        ('"Remove the last user/assistant exchange"', '"移除上一轮用户和助手对话"'),
	        ('"Set a title for the current session"', '"设置当前会话标题"'),
	        ('"Hand off this session to a messaging platform (Telegram, Discord, etc.)"', '"将此会话转交到消息平台（Telegram、Discord 等）"'),
	        ('"Branch the current session (explore a different path)"', '"从当前会话创建分支（尝试另一条思路）"'),
	        ('"Manually compress conversation context"', '"手动压缩对话上下文"'),
	        ('"List or restore filesystem checkpoints"', '"列出或恢复文件检查点"'),
	        ('"Create or restore state snapshots of Hermes config/state"', '"创建或恢复 Hermes 配置和状态快照"'),
	        ('"Kill all running background processes"', '"结束所有后台进程"'),
	        ('"Approve a pending dangerous command"', '"批准待处理的危险命令"'),
	        ('"Deny a pending dangerous command"', '"拒绝待处理的危险命令"'),
	        ('"Run a prompt in the background"', '"在后台执行提示词"'),
	        ('"Show active agents and running tasks"', '"查看活跃 Agent 和运行任务"'),
	        ('"Queue a prompt for the next turn (doesn\'t interrupt)"', '"将提示词加入下一轮队列（不打断当前任务）"'),
	        ('"Inject a message after the next tool call without interrupting"', '"在下一次工具调用后插入消息，不打断当前任务"'),
	        ('"Set a standing goal Hermes works on across turns until achieved"', '"设置持续目标，Hermes 会跨轮执行直到完成"'),
	        ('"Add or manage checklist items on the active goal"', '"添加或管理当前目标的清单项"'),
	        ('"Show session info"', '"查看会话信息"'),
	        ('"Show your slash command access (admin / user)"', '"查看当前斜杠命令权限（管理员/用户）"'),
	        ('"Show active profile name and home directory"', '"查看当前配置档名称和主目录"'),
	        ('"Set this chat as the home channel"', '"将当前聊天设为主频道"'),
	        ('"Resume a previously-named session"', '"继续之前命名的会话"'),
	        ('"Browse and resume previous sessions"', '"浏览并继续之前的会话"'),
	        ('"Show current configuration"', '"查看当前配置"'),
	        ('"Switch model for this session"', '"切换本会话模型"'),
	        ('"Show Google Gemini Code Assist quota usage"', '"查看 Google Gemini Code Assist 配额"'),
	        ('"Set a predefined personality"', '"设置预设人格"'),
	        ('"Toggle the context/model status bar"', '"切换上下文/模型状态栏"'),
	        ('"Cycle tool progress display: off -> new -> all -> verbose"', '"切换工具进度显示：关闭、新调用、全部、详细"'),
	        ('"Toggle gateway runtime-metadata footer on final replies"', '"切换网关最终回复中的运行元信息页脚"'),
	        ('"Toggle YOLO mode (skip all dangerous command approvals)"', '"切换 YOLO 模式（跳过危险命令确认）"'),
	        ('"Manage reasoning effort and display"', '"管理推理强度和显示方式"'),
	        ('"Toggle fast mode — OpenAI Priority Processing / Anthropic Fast Mode (Normal/Fast)"', '"切换快速模式（普通/快速）"'),
	        ('"Show or change the display skin/theme"', '"查看或切换显示主题"'),
	        ('"Pick the TUI busy-indicator style"', '"选择 TUI 忙碌指示器样式"'),
	        ('"Toggle voice mode"', '"切换语音模式"'),
	        ('"Control what Enter does while Hermes is working"', '"控制 Hermes 忙碌时按 Enter 的行为"'),
	        ('"Manage tools: /tools [list|disable|enable] [name...]"', '"管理工具：/tools [list|disable|enable] [名称...]"'),
	        ('"List available toolsets"', '"列出可用工具集"'),
	        ('"Search, install, inspect, or manage skills"', '"搜索、安装、查看或管理技能"'),
	        ('"Manage scheduled tasks"', '"管理定时任务"'),
	        ('"Background skill maintenance (status, run, pin, archive, list-archived)"', '"后台技能维护（状态、运行、固定、归档、列出归档）"'),
	        ('"Multi-profile collaboration board (tasks, links, comments)"', '"多配置协作看板（任务、链接、评论）"'),
	        ('"Reload .env variables into the running session"', '"重新读取 .env 变量"'),
	        ('"Reload MCP servers from config"', '"重新读取 MCP 服务配置"'),
	        ('"Re-scan ~/.hermes/skills/ for newly installed or removed skills"', '"重新扫描 ~/.hermes/skills/ 中的技能"'),
	        ('"Connect browser tools to your live Chrome via CDP"', '"通过 CDP 连接本机 Chrome 浏览器工具"'),
	        ('"List installed plugins and their status"', '"列出已安装插件及状态"'),
	        ('"Browse all commands and skills (paginated)"', '"分页浏览全部命令和技能"'),
	        ('"Show available commands"', '"查看可用命令"'),
	        ('"Gracefully restart the gateway after draining active runs"', '"当前运行完成后平滑重启网关"'),
	        ('"Show token usage and rate limits for the current session"', '"查看当前会话的 token 用量和速率限制"'),
	        ('"Show usage insights and analytics"', '"查看用量分析"'),
	        ('"Show gateway/messaging platform status"', '"查看网关/消息平台状态"'),
	        ('"Copy the last assistant response to clipboard"', '"复制上一条助手回复"'),
	        ('"Attach clipboard image from your clipboard"', '"附加剪贴板图片"'),
	        ('"Attach a local image file for your next prompt"', '"为下一条提示附加本地图片"'),
	        ('"Update Hermes Agent to the latest version"', '"将 Hermes Agent 更新到最新版"'),
	        ('"Upload debug report (system info + logs) and get shareable links"', '"上传调试报告（系统信息和日志），获得分享链接"'),
	        ('"Exit the CLI"', '"退出 CLI"'),
	    ],
	    "agent/display.py": [
	        ('"pondering", "contemplating", "musing", "cogitating", "ruminating",\n        "deliberating", "mulling", "reflecting", "processing", "reasoning",\n        "analyzing", "computing", "synthesizing", "formulating", "brainstorming",', '"思考中", "分析中", "整理中", "推理中", "处理中",\n        "规划中", "检索中", "生成中", "归纳中", "判断中",\n        "计算中", "汇总中", "构思中", "准备中", "推进中",'),
	        ("return verbs", 'return ["思考中", "分析中", "整理中", "推理中", "处理中", "规划中", "生成中"]'),
	        ('self._write(f"  [tool] {self.message}", flush=True)', 'self._write(f"  [工具] {self.message}", flush=True)'),
	        ('self._write(f"  [done] {final_message}{elapsed}", flush=True)', 'self._write(f"  [完成] {final_message}{elapsed}", flush=True)'),
	        ('f"┊ 🔍 search    {_trunc(args.get(\'query\', \'\'), 42)}  {dur}"', 'f"┊ 🔍 搜索      {_trunc(args.get(\'query\', \'\'), 42)}  {dur}"'),
	        ('f"┊ 📄 fetch     {_trunc(domain, 35)}{extra}  {dur}"', 'f"┊ 📄 获取      {_trunc(domain, 35)}{extra}  {dur}"'),
	        ('f"┊ 📄 fetch     pages  {dur}"', 'f"┊ 📄 获取      页面  {dur}"'),
	        ('f"┊ 🕸️  crawl     {_trunc(domain, 35)}  {dur}"', 'f"┊ 🕸️  抓取      {_trunc(domain, 35)}  {dur}"'),
	        ('"list": "ls processes", "poll": f"poll {sid}", "log": f"log {sid}",\n                  "wait": f"wait {sid}", "kill": f"kill {sid}", "write": f"write {sid}", "submit": f"submit {sid}"', '"list": "列出进程", "poll": f"轮询 {sid}", "log": f"日志 {sid}",\n                  "wait": f"等待 {sid}", "kill": f"结束 {sid}", "write": f"写入 {sid}", "submit": f"提交 {sid}"'),
	        ('f"┊ ⚙️  proc      {labels.get(action, f\'{action} {sid}\')}  {dur}"', 'f"┊ ⚙️  进程      {labels.get(action, f\'{action} {sid}\')}  {dur}"'),
	        ('f"┊ 📖 read      {_path(args.get(\'path\', \'\'))}  {dur}"', 'f"┊ 📖 读取      {_path(args.get(\'path\', \'\'))}  {dur}"'),
	        ('f"┊ ✍️  write     {_path(args.get(\'path\', \'\'))}  {dur}"', 'f"┊ ✍️  写入      {_path(args.get(\'path\', \'\'))}  {dur}"'),
	        ('f"┊ 🔧 patch     {_path(args.get(\'path\', \'\'))}  {dur}"', 'f"┊ 🔧 修改      {_path(args.get(\'path\', \'\'))}  {dur}"'),
	        ('verb = "find" if target == "files" else "grep"', 'verb = "查文件" if target == "files" else "查内容"'),
	        ('f"┊ 🌐 navigate  {_trunc(domain, 35)}  {dur}"', 'f"┊ 🌐 打开      {_trunc(domain, 35)}  {dur}"'),
	        ('mode = "full" if args.get("full") else "compact"', 'mode = "完整" if args.get("full") else "简略"'),
	        ('f"┊ 📸 snapshot  {mode}  {dur}"', 'f"┊ 📸 快照      {mode}  {dur}"'),
	        ('f"┊ 👆 click     {args.get(\'ref\', \'?\')}  {dur}"', 'f"┊ 👆 点击      {args.get(\'ref\', \'?\')}  {dur}"'),
	        ('f"┊ ⌨️  type      \\"{_trunc(args.get(\'text\', \'\'), 30)}\\"  {dur}"', 'f"┊ ⌨️  输入      \\"{_trunc(args.get(\'text\', \'\'), 30)}\\"  {dur}"'),
	        ('f"┊ {arrow}  scroll    {d}  {dur}"', 'f"┊ {arrow}  滚动      {d}  {dur}"'),
	        ('f"┊ ◀️  back      {dur}"', 'f"┊ ◀️  返回      {dur}"'),
	        ('f"┊ ⌨️  press     {args.get(\'key\', \'?\')}  {dur}"', 'f"┊ ⌨️  按键      {args.get(\'key\', \'?\')}  {dur}"'),
	        ('f"┊ 🖼️  images    extracting  {dur}"', 'f"┊ 🖼️  图片      提取中  {dur}"'),
	        ('f"┊ 👁️  vision    analyzing page  {dur}"', 'f"┊ 👁️  视觉      分析页面  {dur}"'),
	        ('f"┊ 📋 plan      reading tasks  {dur}"', 'f"┊ 📋 计划      读取任务  {dur}"'),
	        ('f"┊ 📋 plan      update {len(todos_arg)} task(s)  {dur}"', 'f"┊ 📋 计划      更新 {len(todos_arg)} 项任务  {dur}"'),
	        ('f"┊ 📋 plan      {len(todos_arg)} task(s)  {dur}"', 'f"┊ 📋 计划      {len(todos_arg)} 项任务  {dur}"'),
	        ('f"┊ 🔍 recall    \\"{_trunc(args.get(\'query\', \'\'), 35)}\\"  {dur}"', 'f"┊ 🔍 回忆      \\"{_trunc(args.get(\'query\', \'\'), 35)}\\"  {dur}"'),
	        ('f"┊ 🧠 memory    +{target}: \\"{_trunc(args.get(\'content\', \'\'), 30)}\\"  {dur}"', 'f"┊ 🧠 记忆      +{target}: \\"{_trunc(args.get(\'content\', \'\'), 30)}\\"  {dur}"'),
	        ('f"┊ 🧠 memory    ~{target}: \\"{_trunc(old, 20)}\\"  {dur}"', 'f"┊ 🧠 记忆      ~{target}: \\"{_trunc(old, 20)}\\"  {dur}"'),
	        ('f"┊ 🧠 memory    -{target}: \\"{_trunc(old, 20)}\\"  {dur}"', 'f"┊ 🧠 记忆      -{target}: \\"{_trunc(old, 20)}\\"  {dur}"'),
	        ('old = old if old else "<missing old_text>"', 'old = old if old else "<缺少 old_text>"'),
	        ('f"┊ 🧠 memory    {action}  {dur}"', 'f"┊ 🧠 记忆      {action}  {dur}"'),
	        ('f"┊ 📚 skills    list {args.get(\'category\', \'all\')}  {dur}"', 'f"┊ 📚 技能      列出 {args.get(\'category\', \'all\')}  {dur}"'),
	        ('f"┊ 📚 skill     {_trunc(args.get(\'name\', \'\'), 30)}  {dur}"', 'f"┊ 📚 技能      {_trunc(args.get(\'name\', \'\'), 30)}  {dur}"'),
	        ('f"┊ 🎨 create    {_trunc(args.get(\'prompt\', \'\'), 35)}  {dur}"', 'f"┊ 🎨 生成      {_trunc(args.get(\'prompt\', \'\'), 35)}  {dur}"'),
	        ('f"┊ 🔊 speak     {_trunc(args.get(\'text\', \'\'), 30)}  {dur}"', 'f"┊ 🔊 朗读      {_trunc(args.get(\'text\', \'\'), 30)}  {dur}"'),
	        ('f"┊ 🧠 reason    {_trunc(args.get(\'user_prompt\', \'\'), 30)}  {dur}"', 'f"┊ 🧠 推理      {_trunc(args.get(\'user_prompt\', \'\'), 30)}  {dur}"'),
	        ('f"┊ 📨 send      {args.get(\'target\', \'?\')}: \\"{_trunc(args.get(\'message\', \'\'), 25)}\\"  {dur}"', 'f"┊ 📨 发送      {args.get(\'target\', \'?\')}: \\"{_trunc(args.get(\'message\', \'\'), 25)}\\"  {dur}"'),
	        ('f"┊ ⏰ cron      create {_trunc(label, 24)}  {dur}"', 'f"┊ ⏰ 定时      创建 {_trunc(label, 24)}  {dur}"'),
	        ('f"┊ ⏰ cron      listing  {dur}"', 'f"┊ ⏰ 定时      列表  {dur}"'),
	        ('f"┊ ⏰ cron      {action} {args.get(\'job_id\', \'\')}  {dur}"', 'f"┊ ⏰ 定时      {action} {args.get(\'job_id\', \'\')}  {dur}"'),
	        ('"rl_list_environments": "list envs", "rl_select_environment": f"select {args.get(\'name\', \'\')}",\n            "rl_get_current_config": "get config", "rl_edit_config": f"set {args.get(\'field\', \'?\')}",\n            "rl_start_training": "start training", "rl_check_status": f"status {args.get(\'run_id\', \'?\')[:12]}",\n            "rl_stop_training": f"stop {args.get(\'run_id\', \'?\')[:12]}", "rl_get_results": f"results {args.get(\'run_id\', \'?\')[:12]}",\n            "rl_list_runs": "list runs", "rl_test_inference": "test inference",', '"rl_list_environments": "环境列表", "rl_select_environment": f"选择 {args.get(\'name\', \'\')}",\n            "rl_get_current_config": "获取配置", "rl_edit_config": f"设置 {args.get(\'field\', \'?\')}",\n            "rl_start_training": "开始训练", "rl_check_status": f"状态 {args.get(\'run_id\', \'?\')[:12]}",\n            "rl_stop_training": f"停止 {args.get(\'run_id\', \'?\')[:12]}", "rl_get_results": f"结果 {args.get(\'run_id\', \'?\')[:12]}",\n            "rl_list_runs": "运行列表", "rl_test_inference": "测试推理",'),
	        ('f"┊ 🐍 exec      {_trunc(first_line, 35)}  {dur}"', 'f"┊ 🐍 执行      {_trunc(first_line, 35)}  {dur}"'),
	        ('f"┊ 🔀 delegate  {len(tasks)} parallel tasks  {dur}"', 'f"┊ 🔀 委派      {len(tasks)} 个并行任务  {dur}"'),
	        ('f"┊ 🔀 delegate  {_trunc(args.get(\'goal\', \'\'), 35)}  {dur}"', 'f"┊ 🔀 委派      {_trunc(args.get(\'goal\', \'\'), 35)}  {dur}"'),
	    ],
	    "cli.py": [
		        ('line1 = "⚕ NOUS HERMES - AI Agent Framework"', 'line1 = "♞ 爱马仕机器人 - AI Agent 框架"'),
		        ('tiny_line = "⚕ NOUS HERMES"', 'tiny_line = "♞ 爱马仕机器人"'),
		        ('_skin.get_branding("agent_name", "Hermes Agent")', '_skin.get_branding("agent_name", "爱马仕机器人")'),
		        ('if _skin else "Hermes Agent"', 'if _skin else "爱马仕机器人"'),
		        ('agent_name = get_active_skin().get_branding("agent_name", "Hermes Agent")', 'agent_name = get_active_skin().get_branding("agent_name", "爱马仕机器人")'),
		        ('f"{agent_name} - AI Agent Framework"', 'f"{agent_name} - AI Agent 框架"'),
		        ('f"Title: {title}"', 'f"标题：{title}"'),
	        ('f"Model: {model} ({provider})"', 'f"模型：{model} ({provider})"'),
	        ('f"Created: {created_at.strftime(\'%Y-%m-%d %H:%M\')}"', 'f"创建时间：{created_at.strftime(\'%Y-%m-%d %H:%M\')}"'),
	        ('f"Last Activity: {updated_at.strftime(\'%Y-%m-%d %H:%M\')}"', 'f"最近活动：{updated_at.strftime(\'%Y-%m-%d %H:%M\')}"'),
	        ('f"Tokens: {total_tokens:,}"', 'f"Token：{total_tokens:,}"'),
	        ('f"Agent Running: {\'Yes\' if is_running else \'No\'}"', 'f"Agent 运行中：{\'是\' if is_running else \'否\'}"'),
	        ('get_active_help_header("(^_^)? Available Commands")', 'get_active_help_header("(^_^)? 可用命令")'),
	        ('header = "(^_^)? Available Commands"', 'header = "(^_^)? 可用命令"'),
	        ('or "(^_^)? Available Commands"', 'or "(^_^)? 可用命令"'),
	        ('Skill Commands', '技能命令'),
	        ('installed):', '已安装):'),
	        ('Tip: Just type your message to chat with Hermes!', '提示：直接输入消息即可与 Hermes 对话！'),
	        ('Tip: type your next message, or run hermes chat -q --image', '提示：输入下一条消息，或运行 hermes chat -q --image'),
	        ('Tip:   Use /history or `hermes sessions list` to find sessions.', '提示：使用 /history 或 `hermes sessions list` 查找会话。'),
	        ('Multi-line: Alt+Enter for a new line', '多行输入：Alt+Enter 换行'),
	        ('Draft editor: Ctrl+G (Alt+G in VSCode/Cursor)', '草稿编辑器：Ctrl+G（VSCode/Cursor 中为 Alt+G）'),
	        ('Attach image: /image ', '附加图片：/image '),
	        (' or start your prompt with a local image path', '，也可在提示词开头输入本地图片路径'),
	        ('Paste image: Alt+V (or /paste)', '粘贴图片：Alt+V（或 /paste）'),
	        ('(;_;) No tools available', '(;_;) 无可用工具'),
	        ('(^_^)/ Available Tools', '(^_^)/ 可用工具'),
	        ('(^_^)b Available Toolsets', '(^_^)b 可用工具集'),
	        ('Tip: Use \'all\' or \'*\' to enable all toolsets', '提示：用 all 或 * 启用全部工具集'),
	        ('Running processes:', '运行进程：'),
		        ('Initializing agent...', '正在初始化爱马仕机器人...'),
		        ('Type /help for available commands', '输入 /help 查看可用命令'),
		        ('Loading skill:', '正在加载技能：'),
		        ('return "Loading skills..."', 'return "正在加载技能..."'),
		        ('return "Processing skills command..."', 'return "正在处理技能命令..."'),
		        ('return "Processing command..."', 'return "正在处理命令..."'),
		        ('"Processing command..."', '"正在处理命令..."'),
		        ('title = "⚠️  Dangerous Command"', 'title = "⚠️  危险命令"'),
		        ('"once": "Allow once"', '"once": "允许一次"'),
		        ('"session": "Allow for this session"', '"session": "本会话允许"'),
		        ('"always": "Add to permanent allowlist"', '"always": "加入永久允许列表"'),
		        ('"deny": "Deny"', '"deny": "拒绝"'),
		        ('"view": "Show full command"', '"view": "显示完整命令"'),
		        ('"… (command truncated — use /logs or /debug for full text)"', '"…（命令已截断，可用 /logs 或 /debug 查看完整文本）"'),
		        ('"… (description truncated)"', '"…（说明已截断）"'),
		        ('return f"recording... {_label} to stop, Ctrl+C to cancel"', 'return f"录音中... 按 {_label} 停止，Ctrl+C 取消"'),
		        ('return "transcribing..."', 'return "正在转写..."'),
		        ('return "type password (hidden), Enter to submit · ESC to skip"', 'return "输入密码（隐藏），Enter 提交 · ESC 跳过"'),
		        ('return "type secret (hidden), Enter to submit · ESC to skip"', 'return "输入密钥（隐藏），Enter 提交 · ESC 跳过"'),
		        ('return "type your answer here and press Enter"', 'return "在这里输入回答并按 Enter"'),
		        ('return "msg=interrupt · /queue · /bg · /steer · Ctrl+C cancel"', 'return "消息=中断 · /queue · /bg · /steer · Ctrl+C 取消"'),
		        ('return f"type or {_label} to record"', 'return f"输入文字或按 {_label} 录音"'),
		        ('Primary auth failed — switching to fallback:', '主认证失败，正在切换到备用模型：'),
		        ('Provider resolution failed.', '模型服务解析失败。'),
		        ('Session not found:', '未找到会话：'),
		        ('Starting fresh.', '已开始新会话。'),
		        ('Session title applied:', '会话标题已应用：'),
		        ('Unknown command:', '未知命令：'),
		        ('Note: banner colors will update on next session start.', '提示：横幅颜色将在下次启动后更新。'),
		        ('Welcome to Hermes Agent! Type your message or /help for commands.', '欢迎使用爱马仕机器人！输入消息，或输入 /help 查看命令。'),
		        ('Goodbye! ⚕', '再见！⚕'),
		        ('_cprint(f"  {_DIM}Steer failed ({exc}) — queued for next turn.{_RST}")', '_cprint(f"  {_DIM}插入消息失败（{exc}），已加入下一轮队列。{_RST}")'),
		        ('_cprint(f"  {_ACCENT}⏩ Steered: \'{preview}\'{_RST}")', '_cprint(f"  {_ACCENT}⏩ 已插入消息：\'{preview}\'{_RST}")'),
		        ('_cprint(f"  Queued for the next turn: {preview[:80]}{\'...\' if len(preview) > 80 else \'\'}")', '_cprint(f"  已加入下一轮队列：{preview[:80]}{\'...\' if len(preview) > 80 else \'\'}")'),
		    ],
	    "toolsets.py": [
	        ('print("\\nAvailable Toolsets:")', 'print("\\n可用工具集：")'),
	        ('print(f"     Tools: {len(info[\'resolved_tools\'])} total")', 'print(f"     工具：共 {len(info[\'resolved_tools\'])} 个")'),
	        ('print("\\nToolset Resolution Examples:")', 'print("\\n工具集解析示例：")'),
	    ],
	    "batch_runner.py": [
	        ('print("📊 Available Toolset Distributions")', 'print("📊 可用工具集分组")'),
	    ],
	    "run_agent.py": [
	        ('print("📋 Available Tools & Toolsets:")', 'print("📋 可用工具与工具集：")'),
	        ('print(f"🤖 AI Agent initialized with model: {self.model} (AWS Bedrock + AnthropicBedrock SDK, {_br_region})")', 'print(f"🤖 AI Agent 已初始化，模型：{self.model} (AWS Bedrock + AnthropicBedrock SDK, {_br_region})")'),
	        ('print(f"🤖 AI Agent initialized with model: {self.model} (Anthropic native)")', 'print(f"🤖 AI Agent 已初始化，模型：{self.model} (Anthropic native)")'),
	        ('print(f"🔑 Using token: {effective_key[:8]}...{effective_key[-4:]}")', 'print(f"🔑 使用 token：{effective_key[:8]}...{effective_key[-4:]}")'),
	        ('print(f"🤖 AI Agent initialized with model: {self.model} (AWS Bedrock, {self._bedrock_region}{_gr_label})")', 'print(f"🤖 AI Agent 已初始化，模型：{self.model} (AWS Bedrock, {self._bedrock_region}{_gr_label})")'),
	        ('print(f"🤖 AI Agent initialized with model: {self.model}")', 'print(f"🤖 AI Agent 已初始化，模型：{self.model}")'),
	        ('print(f"🔗 Using custom base URL: {base_url}")', 'print(f"🔗 使用自定义 base URL：{base_url}")'),
	        ('print(f"🔑 Using API key: {key_used[:8]}...{key_used[-4:]}")', 'print(f"🔑 使用 API key：{key_used[:8]}...{key_used[-4:]}")'),
	        ('print(f"⚠️  Warning: API key appears invalid or missing (got: \'{key_used[:20] if key_used else \'none\'}...\')")', 'print(f"⚠️  警告：API key 看起来无效或缺失（当前：\'{key_used[:20] if key_used else \'none\'}...\'）")'),
	        ('print(f"🔄 Fallback model: {fb[\'model\']} ({fb[\'provider\']})")', 'print(f"🔄 备用模型：{fb[\'model\']} ({fb[\'provider\']})")'),
	        ('print(f"🔄 Fallback chain ({len(self._fallback_chain)} providers): " +', 'print(f"🔄 备用链路（{len(self._fallback_chain)} 个服务商）： " +'),
	        ('print(f"🛠️  Loaded {len(self.tools)} tools: {\', \'.join(tool_names)}")', 'print(f"🛠️  已加载 {len(self.tools)} 个工具：{\', \'.join(tool_names)}")'),
	        ('print(f"   ✅ Enabled toolsets: {\', \'.join(enabled_toolsets)}")', 'print(f"   ✅ 已启用工具集：{\', \'.join(enabled_toolsets)}")'),
	        ('print(f"   ❌ Disabled toolsets: {\', \'.join(disabled_toolsets)}")', 'print(f"   ❌ 已禁用工具集：{\', \'.join(disabled_toolsets)}")'),
	        ('print("🛠️  No tools loaded (all tools filtered out or unavailable)")', 'print("🛠️  未加载工具（全部被过滤或不可用）")'),
	        ('print(f"⚠️  Some tools may not work due to missing requirements: {missing_reqs}")', 'print(f"⚠️  部分工具可能因依赖缺失无法工作：{missing_reqs}")'),
	        ('print("📝 Trajectory saving enabled")', 'print("📝 轨迹保存已启用")'),
	        ('print(f"🔒 Ephemeral system prompt: \'{prompt_preview}\' (not saved to trajectories)")', 'print(f"🔒 临时系统提示：\'{prompt_preview}\'（不保存到轨迹）")'),
	        ('print(f"💾 Prompt caching: ENABLED ({source}, {self._cache_ttl} TTL)")', 'print(f"💾 提示词缓存：已启用（{source}，TTL {self._cache_ttl}）")'),
	        ('self._vprint(f"\\n{self.log_prefix}🔄 Making API call #{api_call_count}/{self.max_iterations}...")', 'self._vprint(f"\\n{self.log_prefix}🔄 正在调用 API #{api_call_count}/{self.max_iterations}...")'),
	        ('self._vprint(f"{self.log_prefix}   📊 Request size: {len(api_messages)} messages, ~{approx_tokens:,} tokens (~{total_chars:,} chars)")', 'self._vprint(f"{self.log_prefix}   📊 请求规模：{len(api_messages)} 条消息，约 {approx_tokens:,} token（约 {total_chars:,} 字符）")'),
	        ('self._vprint(f"{self.log_prefix}   🔧 Available tools: {len(self.tools) if self.tools else 0}")', 'self._vprint(f"{self.log_prefix}   🔧 可用工具：{len(self.tools) if self.tools else 0}")'),
	        ('self._vprint(f"{self.log_prefix}⏱️  API call completed in {api_duration:.2f}s")', 'self._vprint(f"{self.log_prefix}⏱️  API 调用完成，用时 {api_duration:.2f}s")'),
	        ('self._vprint(f"{self.log_prefix}🔧 Processing {len(assistant_message.tool_calls)} tool call(s)...")', 'self._vprint(f"{self.log_prefix}🔧 正在处理 {len(assistant_message.tool_calls)} 个工具调用...")'),
	        ('print(f"{self.log_prefix}🔧 Auto-repaired tool name: \'{tc.function.name}\' -> \'{repaired}\'")', 'print(f"{self.log_prefix}🔧 已自动修正工具名：\'{tc.function.name}\' -> \'{repaired}\'")'),
	        ('self._vprint(f"{self.log_prefix}⚠️  Unknown tool \'{invalid_preview}\' — sending error to model for self-correction ({self._invalid_tool_retries}/3)")', 'self._vprint(f"{self.log_prefix}⚠️  未知工具 \'{invalid_preview}\'，正在把错误发回模型以便自我修正（{self._invalid_tool_retries}/3）")'),
	        ('self._vprint(f"{self.log_prefix}❌ Max retries (3) for invalid tool calls exceeded. Stopping as partial.", force=True)', 'self._vprint(f"{self.log_prefix}❌ 无效工具调用已达到最大重试次数（3）。以部分完成状态停止。", force=True)'),
	        ('self._vprint(f"{self.log_prefix}⚠️  Invalid JSON in tool call arguments for \'{tool_name}\': {error_msg}")', 'self._vprint(f"{self.log_prefix}⚠️  工具 \'{tool_name}\' 的参数 JSON 无效：{error_msg}")'),
	        ('self._vprint(f"{self.log_prefix}🔄 Retrying API call ({self._invalid_json_retries}/3)...")', 'self._vprint(f"{self.log_prefix}🔄 正在重试 API 调用（{self._invalid_json_retries}/3）...")'),
	        ('self._vprint(f"{self.log_prefix}⚠️  Injecting recovery tool results for invalid JSON...")', 'self._vprint(f"{self.log_prefix}⚠️  正在为无效 JSON 注入恢复用工具结果...")'),
	        ('self._safe_print(f"🎉 Conversation completed after {api_call_count} OpenAI-compatible API call(s)")', 'self._safe_print(f"🎉 对话完成，共调用 {api_call_count} 次 OpenAI 兼容 API")'),
		        ('error_msg = f"Error during OpenAI-compatible API call #{api_call_count}: {str(e)}"', 'error_msg = f"OpenAI 兼容 API 调用 #{api_call_count} 出错：{str(e)}"'),
		        ('"⚠️ **Thinking Budget Exhausted**\\n\\n"', '"⚠️ **思考预算已耗尽**\\n\\n"'),
		        ('"The model used all its output tokens on reasoning "', '"模型把全部输出 token 用在了推理上，"'),
		        ('"and had none left for the actual response.\\n\\n"', '"没有剩余 token 生成正式回复。\\n\\n"'),
		        ('"To fix this:\\n"', '"处理方法：\\n"'),
		        ('"→ Lower reasoning effort: `/thinkon low` or `/thinkon minimal`\\n"', '"→ 降低推理强度：`/thinkon low` 或 `/thinkon minimal`\\n"'),
		        ('"→ Or switch to a larger/non-reasoning model with `/model`"', '"→ 或用 `/model` 切换到更大模型/非推理模型"'),
		        ('"Thinking-only response (no visible content) — "', '"仅收到思考内容（没有可见回复）— "'),
		        ('"prefilling to continue (%d/2)"', '"正在预填继续（%d/2）"'),
		        ('f"↻ Thinking-only response — prefilling to continue "', 'f"↻ 仅收到思考内容，正在预填继续 "'),
		    ],
	    "ui-tui/src/theme.ts": [
		        ("name: 'Hermes Agent'", "name: '爱马仕机器人'"),
		        ("icon: '⚕'", "icon: '♞'"),
		        ("welcome: 'Type your message or /help for commands.'", "welcome: '输入消息，或输入 /help 查看命令。'"),
	        ("goodbye: 'Goodbye! ⚕'", "goodbye: '再见！⚕'"),
	        ("helpHeader: '(^_^)? Commands'", "helpHeader: '(^_^)? 命令'"),
	    ],
	    "ui-tui/src/content/placeholders.ts": [
	        ("'Ask me anything…'", "'可以直接输入问题…'"),
	        ("'Try \"explain this codebase\"'", "'试试“解释这个项目”'"),
	        ("'Try \"write a test for…\"'", "'试试“为这个功能写测试”'"),
	        ("'Try \"refactor the auth module\"'", "'试试“重构认证模块”'"),
	        ("'Try \"/help\" for commands'", "'输入 /help 查看命令'"),
	        ("'Try \"fix the lint errors\"'", "'试试“修复 lint 错误”'"),
	        ("'Try \"how does the config loader work?\"'", "'试试“配置加载器如何工作？”'"),
	    ],
	    "ui-tui/src/content/verbs.ts": [
	        ("browser: 'browsing'", "browser: '浏览中'"),
	        ("clarify: 'asking'", "clarify: '询问中'"),
	        ("create_file: 'creating'", "create_file: '创建中'"),
	        ("delegate_task: 'delegating'", "delegate_task: '委派中'"),
	        ("delete_file: 'deleting'", "delete_file: '删除中'"),
	        ("execute_code: 'executing'", "execute_code: '执行中'"),
	        ("image_generate: 'generating'", "image_generate: '生成中'"),
	        ("list_files: 'listing'", "list_files: '列出中'"),
	        ("memory: 'remembering'", "memory: '记忆中'"),
	        ("patch: 'patching'", "patch: '修改中'"),
	        ("read_file: 'reading'", "read_file: '读取中'"),
	        ("run_command: 'running'", "run_command: '运行中'"),
	        ("search_code: 'searching'", "search_code: '搜索中'"),
	        ("search_files: 'searching'", "search_files: '搜索中'"),
	        ("terminal: 'terminal'", "terminal: '终端'"),
	        ("web_extract: 'extracting'", "web_extract: '提取中'"),
	        ("web_search: 'searching'", "web_search: '搜索中'"),
	        ("write_file: 'writing'", "write_file: '写入中'"),
	        ("'pondering'", "'思考中'"),
	        ("'contemplating'", "'分析中'"),
	        ("'musing'", "'整理中'"),
	        ("'cogitating'", "'推理中'"),
	        ("'ruminating'", "'处理中'"),
	        ("'deliberating'", "'规划中'"),
	        ("'mulling'", "'检索中'"),
	        ("'reflecting'", "'回顾中'"),
	        ("'processing'", "'处理中'"),
	        ("'reasoning'", "'推理中'"),
	        ("'analyzing'", "'分析中'"),
	        ("'computing'", "'计算中'"),
	        ("'synthesizing'", "'归纳中'"),
	        ("'formulating'", "'构思中'"),
	        ("'brainstorming'", "'发散中'"),
	    ],
	    "ui-tui/src/components/branding.tsx": [
		        ("const TAG_FULL = 'Nous Research · Messenger of the Digital Gods'", "const TAG_FULL = '爱马仕机器人 · 中文增强版'"),
		        ("const TAG_MID = 'Messenger of the Digital Gods'", "const TAG_MID = '中文增强版'"),
		        ("const TAG_TINY = 'Nous Research'", "const TAG_TINY = '爱马仕机器人'"),
		        ('{t.brand.icon} NOUS HERMES', '{t.brand.icon} 爱马仕机器人'),
		        ('{t.brand.icon} Nous Research · Messenger of the Digital Gods', '{t.brand.icon} 爱马仕机器人 · 中文增强版'),
		        ('<Text color={t.color.muted}> · Nous Research</Text>', '<Text color={t.color.muted}> · Nous Research</Text>'),
		        ('Available {title}', "{title === 'Tools' ? '可用工具' : title === 'Skills' ? '可用技能' : `可用 ${title}`}"),
		        ("label={title === 'Tools' ? 'discovering tools' : 'scanning skills'}", "label={title === 'Tools' ? '正在发现工具' : '正在扫描技能'}"),
		        ("'more toolsets…'", "'个工具集…'"),
		        ("'more…'", "'项…'"),
		        ("suffix={skillsCatCount > 0 ? `in ${skillsCatCount} categor${skillsCatCount === 1 ? 'y' : 'ies'}` : undefined}", "suffix={skillsCatCount > 0 ? `共 ${skillsCatCount} 个分类` : undefined}"),
		        ('title="System Prompt"', 'title="系统提示词"'),
		        ('suffix={`— ${sysPromptLen.toLocaleString()} chars`}', 'suffix={`— ${sysPromptLen.toLocaleString()} 字符`}'),
		        ('title="MCP Servers"', 'title="MCP 服务"'),
		        ('suffix="connected"', 'suffix="已连接"'),
		        ('No system prompt loaded.', '未加载系统提示词。'),
		        ('label="scanning skills"', 'label="正在扫描技能"'),
		        ('(and {overflow} more categories…)', '（另有 {overflow} 个分类…）'),
		        ('(and {overflow} more toolsets…)', '（另有 {overflow} 个工具集…）'),
		        ('{s.tools} tool{s.tools === 1 ? \'\' : \'s\'}', '{s.tools} 个工具'),
		        ('failed', '失败'),
		        ("{toolsTotal} tools", "{toolsTotal} 个工具"),
		        ("{skillsTotal} skills", "{skillsTotal} 个技能"),
		        ("! {info.update_behind} {info.update_behind === 1 ? 'commit' : 'commits'} behind", "! 落后 {info.update_behind} {info.update_behind === 1 ? '次提交' : '次提交'}"),
		        ("'commit' : 'commits'", "'次提交' : '次提交'"),
		        ("! {info.update_behind} {info.update_behind === 1 ? '次提交' : '次提交'} behind", "! 落后 {info.update_behind} {info.update_behind === 1 ? '次提交' : '次提交'}"),
		        ("- run", "- 运行"),
		        ("to update", "更新"),
		        ('title="Available Tools"', 'title="可用工具"'),
		        ('title="Available Skills"', 'title="可用技能"'),
		        ('/help for commands', '/help 查看命令'),
		    ],
		    "ui-tui/src/components/helpHint.tsx": [
		        ("'full list of commands + hotkeys'", "'完整命令与快捷键列表'"),
		        ("'start a new session'", "'开始新会话'"),
		        ("'resume a prior session'", "'继续之前的会话'"),
		        ("'control transcript detail level'", "'控制记录详细程度'"),
		        ("'copy selection or last assistant message'", "'复制选中内容或上一条助手回复'"),
		        ("'exit hermes'", "'退出 Hermes'"),
		        ("? quick help", "？快速帮助"),
		        ("type /help for the full panel", "输入 /help 查看完整面板"),
		        ("backspace to dismiss", "Backspace 关闭"),
		        ("Common commands", "常用命令"),
		    ],
		    "ui-tui/src/content/hotkeys.ts": [
		        ("'copy selection'", "'复制选中内容'"),
		        ("'interrupt / clear draft / exit'", "'中断 / 清空草稿 / 退出'"),
		        ("'copy selection when forwarded by the terminal'", "'终端转发时复制选中内容'"),
		        ("'copy selection / interrupt / clear draft / exit'", "'复制选中内容 / 中断 / 清空草稿 / 退出'"),
		        ("'exit'", "'退出'"),
		        ("'open $EDITOR (Alt+G fallback for VSCode/Cursor)'", "'打开 $EDITOR（VSCode/Cursor 可用 Alt+G）'"),
		        ("'redraw / repaint'", "'刷新 / 重绘'"),
		        ("'paste text; /paste attaches clipboard image'", "'粘贴文本；/paste 附加剪贴板图片'"),
		        ("'apply completion'", "'应用补全'"),
		        ("'completions / queue edit / history'", "'补全 / 队列编辑 / 历史'"),
		        ("'delete the queued message you’re editing (Esc cancels edit)'", "'删除正在编辑的队列消息（Esc 取消编辑）'"),
		        ("'home / end of line'", "'行首 / 行尾'"),
		        ("'undo / redo input edits'", "'撤销 / 重做输入编辑'"),
		        ("'delete word'", "'删除单词'"),
		        ("'delete to start / end'", "'删除到行首 / 行尾'"),
		        ("'jump word'", "'按单词跳转'"),
		        ("'start / end of line'", "'行首 / 行尾'"),
		        ("'insert newline'", "'插入换行'"),
		        ("'multi-line continuation (fallback)'", "'多行续写（备用）'"),
		        ("'run a shell command (e.g. !ls, !git status)'", "'运行 Shell 命令（如 !ls、!git status）'"),
		        ("'interpolate shell output inline (e.g. \"branch is {!git branch --show-current}\")'", "'把 Shell 输出插入文本中（如 “分支是 {!git branch --show-current}”）'"),
		    ],
	    "ui-tui/src/components/thinking.tsx": [
		        ('title="Thinking"', 'title="思考过程"'),
		        ('title="Tool calls"', 'title="工具调用"'),
		        ('title="Progress"', 'title="进度"'),
		        ('title="Spawned"', 'title="子 Agent"'),
		        ('title="Spawn tree"', 'title="子 Agent 树"'),
		        ('title="Activity"', 'title="活动"'),
		        ('~${fmtK(tokenCount)} tokens', '~${fmtK(tokenCount)} token'),
		        ('~${fmtK(toolTokens)} tokens', '~${fmtK(toolTokens)} token'),
		        ('~${fmtK(totalTokenCount)} total', '~${fmtK(totalTokenCount)} 合计'),
		        ('<Text bold color={t.color.text}>\n                Thinking\n              </Text>', '<Text bold color={t.color.text}>\n                思考过程\n              </Text>'),
		        ('<Text color={t.color.muted} dim>\n                Thinking\n              </Text>', '<Text color={t.color.muted} dim>\n                思考过程\n              </Text>'),
		        ("const goalLabel = item.goal || `Subagent ${item.index + 1}`", "const goalLabel = item.goal || `子 Agent ${item.index + 1}`"),
		        ("const statusLabel = item.status === 'queued' ? 'queued' : item.status === 'running' ? 'running' : String(item.status)", "const statusLabel = item.status === 'queued' ? '排队中' : item.status === 'running' ? '运行中' : item.status === 'failed' ? '失败' : item.status === 'completed' ? '已完成' : item.status === 'interrupted' ? '已中断' : String(item.status)"),
		    ],
		    "ui-tui/src/banner.ts": [],
		    "ui-tui/src/components/prompts.tsx": [
		        ("{ always: 'Always allow', deny: 'Deny', once: 'Allow once', session: 'Allow this session' }", "{ always: '始终允许', deny: '拒绝', once: '允许一次', session: '本会话允许' }"),
		        ('⚠ approval required ·', '⚠ 需要确认 ·'),
		        ("more line{overflow === 1 ? '' : 's'} (full text above)", "行未显示（完整内容见上方）"),
		        ('↑/↓ select · Enter confirm · 1-4 quick pick · Ctrl+C deny', '↑/↓ 选择 · Enter 确认 · 1-4 快选 · Ctrl+C 拒绝'),
		        ('<Text color={t.color.accent}>ask</Text>', '<Text color={t.color.accent}>提问</Text>'),
		        ('Enter send · Esc', 'Enter 发送 · Esc'),
		        ("'back' : 'cancel'", "'返回' : '取消'"),
		        ('Cmd+C copy · Cmd+V paste · Ctrl+C cancel', 'Cmd+C 复制 · Cmd+V 粘贴 · Ctrl+C 取消'),
		        ('Ctrl+C cancel', 'Ctrl+C 取消'),
		        ('Other (type your answer)', '其他（输入你的回答）'),
		        ('↑/↓ select · Enter confirm · 1-{choices.length} quick pick · Esc/Ctrl+C cancel', '↑/↓ 选择 · Enter 确认 · 1-{choices.length} 快选 · Esc/Ctrl+C 取消'),
		        ('↑/↓ select · Enter confirm · 1-{choices.length} quick pick · Esc/Ctrl+C 取消', '↑/↓ 选择 · Enter 确认 · 1-{choices.length} 快选 · Esc/Ctrl+C 取消'),
		        ("req.cancelLabel ?? 'No'", "req.cancelLabel ?? '否'"),
		        ("req.confirmLabel ?? 'Yes'", "req.confirmLabel ?? '是'"),
		        ('↑/↓ select · Enter confirm · Y/N quick · Esc cancel', '↑/↓ 选择 · Enter 确认 · Y/N 快选 · Esc 取消'),
		    ],
		    "ui-tui/src/components/appOverlays.tsx": [
		        ('label="sudo password required"', 'label="需要 sudo 密码"'),
		        ('sub={`for ${overlay.secret.envVar}`}', 'sub={`用于 ${overlay.secret.envVar}`}'),
		        ('↑↓/jk line · Enter/Space/PgDn page · b/PgUp back · g/G top/bottom · Esc/q close', '↑↓/jk 移动 · Enter/Space/PgDn 翻页 · b/PgUp 返回 · g/G 顶部/底部 · Esc/q 关闭'),
		        ('end · ↑↓/jk · b/PgUp back · g top · Esc/q close', '已结束 · ↑↓/jk · b/PgUp 返回 · g 顶部 · Esc/q 关闭'),
		        (' lines)', ' 行)'),
		    ],
		    "ui-tui/src/components/skillsHub.tsx": [
		        ('loading skills…', '正在加载技能…'),
		        ('error: {err}', '错误：{err}'),
		        ('Esc/q cancel', 'Esc/q 取消'),
		        ('no skills available', '暂无可用技能'),
		        ('Skills Hub', '技能中心'),
		        ('select a category', '选择分类'),
		        ('more</Text>', '更多</Text>'),
		        ('↑/↓ select · Enter open · 1-9,0 quick · Esc/q 取消', '↑/↓ 选择 · Enter 打开 · 1-9,0 快选 · Esc/q 取消'),
		        ('↑/↓ select · Enter open · 1-9,0 quick · Esc/q cancel', '↑/↓ 选择 · Enter 打开 · 1-9,0 快选 · Esc/q 取消'),
		        ('{skills.length} skill(s)', '{skills.length} 个技能'),
		        ('no skills in this category', '此分类暂无技能'),
		        ("'↑/↓ select · Enter open · 1-9,0 quick · Esc back · q close' : 'Esc back · q close'", "'↑/↓ 选择 · Enter 打开 · 1-9,0 快选 · Esc 返回 · q 关闭' : 'Esc 返回 · q 关闭'"),
		        ('path: {info.path}', '路径：{info.path}'),
		        ('loading…', '加载中…'),
		        ('installing…', '安装中…'),
		        ('i reinspect · x reinstall · Enter/Esc back · q close', 'i 重新检查 · x 重新安装 · Enter/Esc 返回 · q 关闭'),
		    ],
		    "ui-tui/src/components/sessionPicker.tsx": [
		        ("return 'today'", "return '今天'"),
		        ("return 'yesterday'", "return '昨天'"),
		        ('return `${Math.floor(d)}d ago`', 'return `${Math.floor(d)} 天前`'),
		        ("setErr('invalid response: session.list')", "setErr('session.list 返回无效响应')"),
		        ("setErr('invalid response: session.delete')", "setErr('session.delete 返回无效响应')"),
		        ('loading sessions…', '正在加载会话…'),
		        ('error: {err}', '错误：{err}'),
		        ('Esc/q cancel', 'Esc/q 取消'),
		        ('no previous sessions', '暂无历史会话'),
		        ('Resume Session', '继续会话'),
		        ('more</Text>', '更多</Text>'),
		        ('msgs,', '条消息,'),
		        ('press d again to delete', '再次按 d 删除'),
		        ('(untitled)', '(无标题)'),
		        ('deleting…', '删除中…'),
		        ('↑/↓ select · Enter resume · 1-9 quick · d delete · Esc/q cancel', '↑/↓ 选择 · Enter 继续 · 1-9 快选 · d 删除 · Esc/q 取消'),
		        ('↑/↓ select · Enter resume · 1-9 quick · d delete · Esc/q 取消', '↑/↓ 选择 · Enter 继续 · 1-9 快选 · d 删除 · Esc/q 取消'),
		    ],
		    "ui-tui/src/components/modelPicker.tsx": [
		        ("setErr('invalid response: model.options')", "setErr('model.options 返回无效响应')"),
		        ("setKeyError('failed to save key')", "setKeyError('保存密钥失败')"),
		        ("? `paste ${p.key_env} to activate` : 'run `hermes model` to configure'", "? `粘贴 ${p.key_env} 以启用` : '运行 `hermes model` 配置'"),
		        ('loading models…', '正在加载模型…'),
		        ('error: {err}', '错误：{err}'),
		        ('Esc/q cancel', 'Esc/q 取消'),
		        ('no providers available', '暂无可用模型服务'),
		        ('Configure {provider.name}', '配置 {provider.name}'),
		        ('Paste your API key below (saved to ~/.hermes/.env)', '在下方粘贴 API key（保存到 ~/.hermes/.env）'),
		        ('(empty)', '(空)'),
		        ('error: {keyError}', '错误：{keyError}'),
		        ('saving…', '保存中…'),
		        ('Enter save · Ctrl+U clear · Esc back', 'Enter 保存 · Ctrl+U 清空 · Esc 返回'),
		        ('Disconnect {provider.name}?', '断开 {provider.name}？'),
		        ('This removes saved credentials for {provider.name}.', '这会移除 {provider.name} 已保存的凭据。'),
		        ('You can re-authenticate later by selecting it again.', '之后再次选择即可重新认证。'),
		        ('disconnecting…', '正在断开…'),
		        ('y/Enter confirm · n/Esc cancel', 'y/Enter 确认 · n/Esc 取消'),
		        ("'(no key)' : '(needs setup)'", "'(无密钥)' : '(需要设置)'"),
		        ('`${modelCount} models`', '`${modelCount} 个模型`'),
		        ('Select provider (step 1/2)', '选择模型服务（第 1/2 步）'),
		        ('Full model IDs on the next step · Enter to continue', '下一步显示完整模型 ID · Enter 继续'),
		        ("Current: {currentModel || '(unknown)'}", "当前：{currentModel || '(未知)'}"),
		        ('`warning: ${provider.warning}`', '`警告：${provider.warning}`'),
		        ('` ↑ ${offset} more`', '` ↑ ${offset} 更多`'),
		        ('` ↓ ${rows.length - offset - VISIBLE} more`', '` ↓ ${rows.length - offset - VISIBLE} 更多`'),
		        ('` ↓ ${models.length - offset - VISIBLE} more`', '` ↓ ${models.length - offset - VISIBLE} 更多`'),
		        ('persist: {persistGlobal ? \'global\' : \'session\'} · g toggle', '保存范围：{persistGlobal ? \'全局\' : \'当前会话\'} · g 切换'),
		        ('↑/↓ select · Enter choose · d disconnect · Esc/q cancel', '↑/↓ 选择 · Enter 选择 · d 断开 · Esc/q 取消'),
		        ('↑/↓ select · Enter choose · d disconnect · Esc/q 取消', '↑/↓ 选择 · Enter 选择 · d 断开 · Esc/q 取消'),
		        ('Select model (step 2/2)', '选择模型（第 2/2 步）'),
		        ("'(unknown provider)'", "'(未知模型服务)'"),
		        ('Esc back', 'Esc 返回'),
		        ('no models listed for this provider', '此模型服务暂无模型列表'),
		        ("'↑/↓ select · Enter switch · Esc 返回 · q close' : 'Enter/Esc 返回 · q close'", "'↑/↓ 选择 · Enter 切换 · Esc 返回 · q 关闭' : 'Enter/Esc 返回 · q 关闭'"),
		        ("'↑/↓ select · Enter switch · Esc back · q close' : 'Enter/Esc back · q close'", "'↑/↓ 选择 · Enter 切换 · Esc 返回 · q 关闭' : 'Enter/Esc 返回 · q 关闭'"),
		    ],
		    "ui-tui/src/components/todoPanel.tsx": [
		        ('countPending待办s', 'countPendingTodos'),
		        ('import type { 待办Item }', 'import type { TodoItem }'),
		        ('待办Item[', 'TodoItem['),
		        ('export const 待办Panel = memo(function 待办Panel', 'export const TodoPanel = memo(function TodoPanel'),
		        ('todos: 待办Item[]', 'todos: TodoItem[]'),
		        ('Live 待办Panel', 'Live TodoPanel'),
		        ('<Text bold color={t.color.text}>\n            Todo\n          </Text>', '<Text bold color={t.color.text}>\n            待办\n          </Text>'),
		        ("· incomplete · {pending} still {pending === 1 ? 'pending' : 'pending/in_progress'}", "· 未完成 · 还有 {pending} 项处理中"),
		    ],
		    "ui-tui/src/components/queuedMessages.tsx": [
		        ('queued (${queued.length})', '队列（${queued.length}）'),
		        ('editing ${queueEditIdx + 1} · Ctrl+X delete · Esc cancel', '正在编辑 ${queueEditIdx + 1} · Ctrl+X 删除 · Esc 取消'),
		        ('…and {queued.length - q.end} more', '…另有 {queued.length - q.end} 条'),
		    ],
		    "ui-tui/src/components/appLayout.tsx": [
		        ("{ui.bgTasks.size} background {ui.bgTasks.size === 1 ? 'task' : 'tasks'} running", "{ui.bgTasks.size} 个后台任务运行中"),
		        ("'Ctrl+C to interrupt…'", "'Ctrl+C 中断…'"),
		    ],
		    "ui-tui/src/components/agentsOverlay.tsx": [
		        ("'spawn order'", "'创建顺序'"),
		        ("'slowest'", "'最慢'"),
		        ("status: 'status'", "status: '状态'"),
		        ("'busiest'", "'最忙'"),
		        ("all: 'all'", "all: '全部'"),
		        ("failed: 'failed'", "failed: '失败'"),
		        ("leaf: 'leaves'", "leaf: '末端'"),
		        ("running: 'running'", "running: '运行中'"),
		        ('Timeline ·', '时间线 ·'),
		        ('name="depth"', 'name="深度"'),
		        ('name="model"', 'name="模型"'),
		        ('name="toolsets"', 'name="工具集"'),
		        ('name="tools"', 'name="工具"'),
		        ('name="subtree"', 'name="子树"'),
		        ('name="elapsed"', 'name="耗时"'),
		        ('name="iteration"', 'name="轮次"'),
		        ('name="api calls"', 'name="API 调用"'),
		        ('title="Budget"', 'title="预算"'),
		        ('name="tokens"', 'name="token"'),
		        (' in · ', ' 输入 · '),
		        ('输出putTokens', 'outputTokens'),
		        ('输出putTail', 'outputTail'),
		        (' out', ' out'),
		        ('{fmtTokens(inputTokens)} in · {fmtTokens(outputTokens)} out', '{fmtTokens(inputTokens)} 输入 · {fmtTokens(outputTokens)} 输出'),
		        (' reasoning', ' 推理'),
		        ('name="cost"', 'name="费用"'),
		        ('subtree +', '子树 +'),
		        ('name="subtree tokens"', 'name="子树 token"'),
		        ('value={`${item.toolCount ?? 0} (subtree ${agg.totalTools})`}', 'value={`${item.toolCount ?? 0}（子树 ${agg.totalTools}）`}'),
		        ("value={`${agg.descendantCount} agent${agg.descendantCount === 1 ? '' : 's'} · d${agg.maxDepthFromHere} · ⚡${agg.activeCount}`}", "value={`${agg.descendantCount} 个 Agent · d${agg.maxDepthFromHere} · ⚡${agg.activeCount}`}"),
		        ('title="Files"', 'title="文件"'),
		        ('…+{filesOverflow} more', '…另有 {filesOverflow} 项'),
		        ('title="Tool calls"', 'title="工具调用"'),
		        ('title="Output"', 'title="输出"'),
		        ('title="Progress"', 'title="进度"'),
		        ('title="Summary"', 'title="总结"'),
		        ("'subagent'", "'子 Agent'"),
		        ('Replay diff', '回放差异'),
		        ('baseline vs candidate · esc/q close', '基线对比候选 · esc/q 关闭'),
		        ('A · baseline', 'A · 基线'),
		        ('B · candidate', 'B · 候选'),
		        ("diffMetricLine('agents'", "diffMetricLine('Agent 数'"),
		        ("diffMetricLine('tools'", "diffMetricLine('工具数'"),
		        ("diffMetricLine('depth'", "diffMetricLine('深度'"),
		        ("diffMetricLine('duration'", "diffMetricLine('耗时'"),
		        ("diffMetricLine('tokens'", "diffMetricLine('token'"),
		        ("diffMetricLine('cost'", "diffMetricLine('费用'"),
		        ("setFlash('turn finished · inspect freely · q to close')", "setFlash('本轮完成 · 可查看详情 · q 关闭')"),
		        ("setFlash('replay mode — controls disabled')", "setFlash('回放模式，控制项已禁用')"),
		        ('`killing ${id}`', '`正在结束 ${id}`'),
		        ('`not found: ${id}`', '`未找到：${id}`'),
		        ('`kill failed: ${id}`', '`结束失败：${id}`'),
		        ('`killing subtree · ${ids.length} node${ids.length === 1 ? \'\' : \'s\'}`', '`正在结束子树 · ${ids.length} 个节点`'),
		        ("'spawning paused' : 'spawning resumed'", "'创建已暂停' : '创建已恢复'"),
		        ("setFlash('pause failed')", "setFlash('暂停失败')"),
		        ("const 历史 = useStore($spawnHistory)", "const history = useStore($spawnHistory)"),
		        ("next === 0 ? 'live turn' : `replay · ${next}/${history.length}`", "next === 0 ? '当前轮' : `回放 · ${next}/${history.length}`"),
		        ("? `${historyIndex > 0 ? `Replay ${historyIndex}/${history.length}` : 'Last turn'} · finished ${new Date(", "? `${historyIndex > 0 ? `回放 ${historyIndex}/${history.length}` : '上一轮'} · 完成于 ${new Date("),
		        (": `Spawn tree${delegation.paused ? ' · ⏸ paused' : ''}`", ": `子 Agent 树${delegation.paused ? ' · ⏸ 已暂停' : ''}`"),
		        ("' · controls locked'", "' · 控制已锁定'"),
		        ("` · x kill · X subtree · p ${delegation.paused ? 'resume' : 'pause'}`", "` · x 结束 · X 子树 · p ${delegation.paused ? '恢复' : '暂停'}`"),
		        ('No subagents this turn. Trigger delegate_task to populate the tree.', '本轮没有子 Agent。触发 delegate_task 后会显示在这里。'),
		        ('↑↓/jk move · g/G top/bottom · Enter/→ open detail', '↑↓/jk 移动 · g/G 顶部/底部 · Enter/→ 打开详情'),
		        (' · s sort:', ' · s 排序:'),
		        (' · f filter:', ' · f 筛选:'),
		        (' · q close', ' · q 关闭'),
		        ('↑↓/jk scroll · PgUp/PgDn page · g/G top/bottom · Esc/← back to list', '↑↓/jk 滚动 · PgUp/PgDn 翻页 · g/G 顶部/底部 · Esc/← 返回列表'),
		    ],
		    "ui-tui/src/app/createGatewayEventHandler.ts": [
		        ("getUiState().busy ? 'running…' : 'ready'", "getUiState().busy ? '运行中…' : '就绪'"),
		        ('`command catalog unavailable: ${rpcErrorMessage(e)}`', '`命令目录不可用：${rpcErrorMessage(e)}`'),
		        ("String(ev.payload.description ?? 'dangerous command')", "String(ev.payload.description ?? '危险命令')"),
		        ("sys('startup query skipped: no active session')", "sys('启动查询已跳过：没有活跃会话')"),
		        ("sys(`startup image attach failed: ${rpcErrorMessage(e)}`)", "sys(`启动图片附加失败：${rpcErrorMessage(e)}`)"),
		        ("patchUiState({ status: 'resuming…' })", "patchUiState({ status: '正在继续…' })"),
		        ("patchUiState({ status: 'forging session…' })", "patchUiState({ status: '正在创建会话…' })"),
		        ("patchUiState({ status: 'resuming most recent…' })", "patchUiState({ status: '正在继续最近会话…' })"),
		        ("state.status === 'starting agent…' ? 'ready' : state.status", "state.status === '正在启动 Agent…' ? '就绪' : state.status"),
		        ("setStatus('gateway startup timeout')", "setStatus('网关启动超时')"),
		        ("setStatus('protocol warning')", "setStatus('协议警告')"),
		        ("setStatus('waiting for input…')", "setStatus('等待输入…')"),
		        ("setStatus('approval needed')", "setStatus('需要确认')"),
		        ("setStatus('sudo password needed')", "setStatus('需要 sudo 密码')"),
		        ("setStatus('secret input needed')", "setStatus('需要输入密钥')"),
		        ("setStatus('ready')", "setStatus('就绪')"),
		        ("setStatus('setup required')", "setStatus('需要配置')"),
		    ],
			    "ui-tui/src/app/createSlashHandler.ts": [
		        ("`ambiguous command: ${matches.slice(0, 6).join(', ')}${matches.length > 6 ? ', …' : ''}`", "`命令不明确：${matches.slice(0, 6).join(', ')}${matches.length > 6 ? ', …' : ''}`"),
			        ("'error: invalid response: command.dispatch'", "'错误：command.dispatch 返回无效响应'"),
			    ],
			    "ui-tui/src/app/slash/commands/core.ts": [
			        ("'usage: /details [hidden|collapsed|expanded|cycle]  or  /details <section> [hidden|collapsed|expanded|reset]'", "'用法：/details [hidden|collapsed|expanded|cycle]  或  /details <section> [hidden|collapsed|expanded|reset]'"),
			        ("'usage: /details <section> [hidden|collapsed|expanded|reset]'", "'用法：/details <section> [hidden|collapsed|expanded|reset]'"),
			        ("help: 'list commands + hotkeys'", "help: '列出命令和快捷键'"),
			        ("`${ctx.local.catalog.skillCount} skill commands available — /skills to browse`", "`${ctx.local.catalog.skillCount} 个技能命令可用，可用 /skills 浏览`"),
			        ("'set global agent detail visibility mode'", "'设置 Agent 细节显示模式'"),
			        ("'override one section (thinking/tools/subagents/activity)'", "'单独设置某个区域（思考/工具/子 Agent/活动）'"),
			        ("'show a random or daily local fortune'", "'显示随机或每日提示'"),
			        ("title: 'TUI'", "title: 'TUI'"),
			        ("title: 'Hotkeys'", "title: '快捷键'"),
			        ("help: 'exit hermes'", "help: '退出 Hermes'"),
			        ("help: 'toggle mouse/wheel tracking [on|off|toggle]'", "help: '切换鼠标/滚轮跟踪 [on|off|toggle]'"),
			        ("'usage: /mouse [on|off|toggle]'", "'用法：/mouse [on|off|toggle]'"),
			        ("`mouse tracking ${next ? 'on' : 'off'}`", "`${next ? '已开启' : '已关闭'}鼠标跟踪`"),
			        ("help: 'start a new session'", "help: '开始新会话'"),
			        ("patchUiState({ status: 'forging session…' })", "patchUiState({ status: '正在创建会话…' })"),
			        ("ctx.session.newSession(isNew ? 'new session started' : undefined, requestedTitle || undefined)", "ctx.session.newSession(isNew ? '新会话已开始' : undefined, requestedTitle || undefined)"),
			        ("cancelLabel: 'No, keep going'", "cancelLabel: '否，继续当前会话'"),
			        ("confirmLabel: isNew ? 'Yes, start a new session' : 'Yes, clear the session'", "confirmLabel: isNew ? '是，开始新会话' : '是，清空当前会话'"),
			        ("detail: 'This ends the current conversation and clears the transcript.'", "detail: '这会结束当前对话并清空记录。'"),
			        ("title: isNew ? 'Start a new session?' : 'Clear the current session?'", "title: isNew ? '开始新会话？' : '清空当前会话？'"),
			        ("help: 'force a full UI repaint'", "help: '强制刷新界面'"),
			        ("'ui redrawn'", "'界面已刷新'"),
			        ("help: 'show live session info'", "help: '显示当前会话信息'"),
			        ("'no active session'", "'没有活跃会话'"),
			        ("'(no status)'", "'（无状态）'"),
			        ("'Status'", "'状态'"),
			        ("help: 'resume a prior session'", "help: '继续历史会话'"),
			        ("help: 'set or show current session title'", "help: '设置或显示当前会话标题'"),
			        ("`title: ${current}`", "`标题：${current}`"),
			        ("'no title set'", "'未设置标题'"),
			        ("'usage: /title <your session title>'", "'用法：/title <会话标题>'"),
			        ("' (queued while session initializes)'", "'（会话初始化后生效）'"),
			        ("`session title set: ${next}${suffix}`", "`会话标题已设置：${next}${suffix}`"),
			        ("help: 'toggle compact transcript'", "help: '切换紧凑记录模式'"),
			        ("'usage: /compact [on|off|toggle]'", "'用法：/compact [on|off|toggle]'"),
			        ("`compact ${next ? 'on' : 'off'}`", "`紧凑模式 ${next ? '开启' : '关闭'}`"),
			        ("help: 'control agent detail visibility (global or per-section)'", "help: '控制 Agent 细节显示'"),
			        ("`details: ${mode}${overrides ? `  (${overrides})` : ''}`", "`细节：${mode}${overrides ? `  (${overrides})` : ''}`"),
			        ("`details ${first}: ${mode ?? 'reset'}`", "`细节 ${first}: ${mode ?? '重置'}`"),
			        ("`details: ${next}`", "`细节：${next}`"),
			        ("help: 'local fortune'", "help: '本地提示'"),
			        ("'usage: /fortune [random|daily]'", "'用法：/fortune [random|daily]'"),
			        ("help: 'copy selection or assistant message'", "help: '复制选中内容或助手消息'"),
			        ("`copied ${text.length} characters`", "`已复制 ${text.length} 个字符`"),
			        ("'clipboard copy failed — try HERMES_TUI_FORCE_OSC52=1 to force the escape sequence; HERMES_TUI_DEBUG_CLIPBOARD=1 for details'", "'剪贴板复制失败；可尝试设置 HERMES_TUI_FORCE_OSC52=1 强制使用转义序列，或设置 HERMES_TUI_DEBUG_CLIPBOARD=1 查看详情'"),
			        ("'usage: /copy [number]'", "'用法：/copy [编号]'"),
			        ("'nothing to copy — start a conversation first'", "'没有可复制内容，请先开始对话'"),
			        ("'copied to clipboard'", "'已复制到剪贴板'"),
			        ("'sent OSC52 copy sequence (terminal support required)'", "'已发送 OSC52 复制序列（需要终端支持）'"),
			        ("`copy failed: ${String(error)}`", "`复制失败：${String(error)}`"),
			        ("help: 'attach clipboard image'", "help: '附加剪贴板图片'"),
			        ("'usage: /paste'", "'用法：/paste'"),
			        ("help: 'configure IDE terminal keybindings for multiline + undo/redo'", "help: '配置 IDE 终端快捷键'"),
			        ("'usage: /terminal-setup [auto|vscode|cursor|windsurf]'", "'用法：/terminal-setup [auto|vscode|cursor|windsurf]'"),
			        ("'restart the IDE terminal for the new keybindings to take effect'", "'重启 IDE 终端后快捷键生效'"),
			        ("`terminal setup failed: ${String(error)}`", "`终端配置失败：${String(error)}`"),
			        ("help: 'view gateway logs'", "help: '查看网关日志'"),
			        ("'Logs'", "'日志'"),
			        ("'no gateway logs'", "'没有网关日志'"),
			        ("help: 'view current transcript (user + assistant messages)'", "help: '查看当前对话记录'"),
			        ("'no conversation yet'", "'还没有对话'"),
			        ("`You #${i + 1}` : `Hermes #${i + 1}`", "`你 #${i + 1}` : `Hermes #${i + 1}`"),
			        ("'History'", "'历史记录'"),
			        ("help: 'save the current transcript to JSON'", "help: '保存当前对话为 JSON'"),
			        ("'no active session — nothing to save'", "'没有活跃会话，无内容可保存'"),
			        ("`conversation saved to: ${file}`", "`对话已保存到：${file}`"),
			        ("'failed to save'", "'保存失败'"),
			        ("help: 'status bar position (on|off|top|bottom)'", "help: '状态栏位置 [on|off|top|bottom]'"),
			        ("'usage: /statusbar [on|off|top|bottom|toggle]'", "'用法：/statusbar [on|off|top|bottom|toggle]'"),
			        ("`status bar ${next}`", "`状态栏：${next}`"),
			        ("help: 'inspect or enqueue a message'", "help: '查看或加入消息队列'"),
			        ("`${ctx.composer.queueRef.current.length} queued message(s)`", "`${ctx.composer.queueRef.current.length} 条排队消息`"),
			        ("`queued: \"${arg.slice(0, 50)}${arg.length > 50 ? '…' : ''}\"`", "`已加入队列：\"${arg.slice(0, 50)}${arg.length > 50 ? '…' : ''}\"`"),
			        ("help: 'inject a message after the next tool call (no interrupt)'", "help: '在下一次工具调用后插入消息'"),
			        ("'usage: /steer <prompt>'", "'用法：/steer <提示词>'"),
			        ("`no active turn — queued for next: \"${payload.slice(0, 50)}${payload.length > 50 ? '…' : ''}\"`", "`当前没有运行中的回合，已加入下一轮队列：\"${payload.slice(0, 50)}${payload.length > 50 ? '…' : ''}\"`"),
			        ("`steer queued — arrives after next tool call: \"${payload.slice(0, 50)}${payload.length > 50 ? '…' : ''}\"`", "`插入消息已排队，将在下一次工具调用后生效：\"${payload.slice(0, 50)}${payload.length > 50 ? '…' : ''}\"`"),
			        ("'steer rejected'", "'插入消息被拒绝'"),
			        ("help: 'undo last exchange'", "help: '撤销上一轮对话'"),
			        ("'nothing to undo'", "'没有可撤销内容'"),
			        ("`undid ${r.removed} messages`", "`已撤销 ${r.removed} 条消息`"),
			        ("help: 'retry last user message'", "help: '重试上一条用户消息'"),
			        ("'nothing to retry'", "'没有可重试内容'"),
			    ],
			    "ui-tui/src/app/slash/commands/session.ts": [
			        ("help: 'launch a background prompt'", "help: '启动后台提示词'"),
			        ("`bg ${r.task_id} started`", "`后台任务 ${r.task_id} 已启动`"),
			        ("help: 'change or show model'", "help: '切换或显示模型'"),
			        ("ctx.session.guardBusySessionSwitch('change models')", "ctx.session.guardBusySessionSwitch('切换模型')"),
			        ("'error: invalid response: model switch'", "'错误：模型切换返回无效响应'"),
			        ("`model → ${r.value}`", "`模型 → ${r.value}`"),
			        ("help: 'browse and resume previous sessions'", "help: '浏览并继续历史会话'"),
			        ("ctx.session.guardBusySessionSwitch('switch sessions')", "ctx.session.guardBusySessionSwitch('切换会话')"),
			        ("help: 'attach an image'", "help: '附加图片'"),
			        ("help: 'switch personality for this session'", "help: '切换当前会话人格'"),
			        ("`personality: ${r.value || 'default'}${r.history_reset ? ' · transcript cleared' : ''}`", "`人格：${r.value || '默认'}${r.history_reset ? ' · 对话记录已清空' : ''}`"),
			        ("help: 'compress transcript'", "help: '压缩对话记录'"),
			        ("'nothing to compress'", "'没有需要压缩的内容'"),
			        ("`compressed ${r.removed} messages${r.usage?.total ? ` · ${fmtK(r.usage.total)} tok` : ''}`", "`已压缩 ${r.removed} 条消息${r.usage?.total ? ` · ${fmtK(r.usage.total)} token` : ''}`"),
			        ("help: 'branch the session'", "help: '创建会话分支'"),
			        ("`branched → ${r.title ?? ''}`", "`已创建分支 → ${r.title ?? ''}`"),
			        ("help: 'voice mode: [on|off|tts|status]'", "help: '语音模式 [on|off|tts|status]'"),
			        ("'Voice Mode Status'", "'语音模式状态'"),
			        ("`  Mode:       ${mode}`", "`  模式：       ${mode}`"),
			        ("`  Record key: ${recordKeyLabel}`", "`  录音键：     ${recordKeyLabel}`"),
			        ("'  Requirements:'", "'  需求项：'"),
			        ("`Voice TTS ${r.tts ? 'enabled' : 'disabled'}.`", "`语音播报已${r.tts ? '开启' : '关闭'}。`"),
			        ("`Voice mode enabled${tts}`", "`语音模式已开启${tts}`"),
			        ("`  ${recordKeyLabel} to start/stop recording`", "`  按 ${recordKeyLabel} 开始/停止录音`"),
			        ("'  /voice tts  to toggle speech output'", "'  /voice tts  切换语音播报'"),
			        ("'  /voice off  to disable voice mode'", "'  /voice off  关闭语音模式'"),
			        ("'Voice mode disabled.'", "'语音模式已关闭。'"),
			        ("help: 'switch theme skin (fires skin.changed)'", "help: '切换主题皮肤'"),
			        ("`skin: ${r.value || 'default'}`", "`皮肤：${r.value || '默认'}`"),
			        ("`skin → ${r.value}`", "`皮肤 → ${r.value}`"),
			        ("help: 'pick the busy indicator: kaomoji (default), emoji, unicode (braille), or ascii'", "help: '选择忙碌指示样式：kaomoji、emoji、unicode 或 ascii'"),
			        ("`indicator: ${r.value || DEFAULT_INDICATOR_STYLE}`", "`指示样式：${r.value || DEFAULT_INDICATOR_STYLE}`"),
			        ("`usage: /indicator [${INDICATOR_STYLES.join('|')}]`", "`用法：/indicator [${INDICATOR_STYLES.join('|')}]`"),
			        ("`indicator → ${r.value}`", "`指示样式 → ${r.value}`"),
			        ("help: 'toggle yolo mode (per-session approvals)'", "help: '切换 yolo 模式（当前会话审批）'"),
			        ("`yolo ${r.value === '1' ? 'on' : 'off'}`", "`yolo ${r.value === '1' ? '开启' : '关闭'}`"),
			        ("help: 'inspect or set reasoning effort (updates live agent)'", "help: '查看或设置推理强度'"),
			        ("`reasoning: ${r.value} · display ${r.display || 'hide'}`", "`推理：${r.value} · 显示 ${r.display || '隐藏'}`"),
			        ("`reasoning: ${r.value}`", "`推理：${r.value}`"),
			        ("help: 'toggle fast mode [normal|fast|status|on|off|toggle]'", "help: '切换快速模式 [normal|fast|status|on|off|toggle]'"),
			        ("'usage: /fast [normal|fast|status|on|off|toggle]'", "'用法：/fast [normal|fast|status|on|off|toggle]'"),
			        ("`fast mode: ${r.value === 'fast' ? 'fast' : 'normal'}`", "`快速模式：${r.value === 'fast' ? '快速' : '普通'}`"),
			        ("`fast mode: ${next}`", "`快速模式：${next}`"),
			        ("help: 'control busy enter mode [queue|steer|interrupt|status]'", "help: '控制忙碌时回车行为 [queue|steer|interrupt|status]'"),
			        ("'usage: /busy [queue|steer|interrupt|status]'", "'用法：/busy [queue|steer|interrupt|status]'"),
			        ("`busy input mode: ${current}`", "`忙碌输入模式：${current}`"),
			        ("`busy input mode: ${next}`", "`忙碌输入模式：${next}`"),
			        ("help: 'cycle verbose tool-output mode (updates live agent)'", "help: '切换详细工具输出模式'"),
			        ("`verbose: ${r.value}`", "`详细输出：${r.value}`"),
			        ("help: 'session usage (live counts — worker sees zeros)'", "help: '会话用量统计'"),
			        ("'no API calls yet'", "'还没有 API 调用'"),
			        ("['Model', r.model ?? '']", "['模型', r.model ?? '']"),
			        ("['Input tokens', f(r.input)]", "['输入 token', f(r.input)]"),
			        ("['Cache read tokens', f(r.cache_read)]", "['缓存读取 token', f(r.cache_read)]"),
			        ("['Cache write tokens', f(r.cache_write)]", "['缓存写入 token', f(r.cache_write)]"),
			        ("['Output tokens', f(r.output)]", "['输出 token', f(r.output)]"),
			        ("['Total tokens', f(r.total)]", "['总 token', f(r.total)]"),
			        ("['API calls', f(r.calls)]", "['API 调用', f(r.calls)]"),
			        ("['Cost', cost]", "['费用', cost]"),
			        ("`Context: ${f(r.context_used)} / ${f(r.context_max)} (${r.context_percent}%)`", "`上下文：${f(r.context_used)} / ${f(r.context_max)} (${r.context_percent}%)`"),
			        ("`Compressions: ${r.compressions}`", "`压缩次数：${r.compressions}`"),
			        ("ctx.transcript.panel('Usage', sections)", "ctx.transcript.panel('用量', sections)"),
			    ],
			    "ui-tui/src/app/slash/commands/ops.ts": [
			        ("help: 'stop background processes'", "help: '停止后台进程'"),
			        ("const noun = killed === 1 ? 'process' : 'processes'", "const noun = '进程'"),
			        ("`stopped ${killed} background ${noun}`", "`已停止 ${killed} 个后台${noun}`"),
			        ("help: 'reload MCP servers in the live session (warns about prompt cache invalidation)'", "help: '重新加载当前会话的 MCP 服务'"),
			        ("r.message || '/reload-mcp requires confirmation'", "r.message || '/reload-mcp 需要确认'"),
			        ("'MCP servers reloaded · future /reload-mcp will run without confirmation'", "'MCP 服务已重新加载，后续 /reload-mcp 不再要求确认'"),
			        ("'MCP servers reloaded'", "'MCP 服务已重新加载'"),
			        ("'reload complete'", "'重新加载完成'"),
			        ("help: 're-read ~/.hermes/.env into the running gateway (CLI parity)'", "help: '重新读取 ~/.hermes/.env 到运行中的网关'"),
			        ("const noun = n === 1 ? 'var' : 'vars'", "const noun = '变量'"),
			        ("`reloaded .env (${n} ${noun} updated)`", "`已重新读取 .env（更新 ${n} 个${noun}）`"),
			        ("help: 'manage browser CDP connection [connect|disconnect|status]'", "help: '管理浏览器 CDP 连接 [connect|disconnect|status]'"),
			        ("'usage: /browser [connect|disconnect|status] [url] · persistent: set browser.cdp_url in config.yaml'", "'用法：/browser [connect|disconnect|status] [url] · 持久配置：在 config.yaml 设置 browser.cdp_url'"),
			        ("`checking Chrome remote debugging at ${url}...`", "`正在检查 Chrome 远程调试地址 ${url}...`"),
			        ("`browser connected: ${r.url || '(url unavailable)'}`", "`浏览器已连接：${r.url || '（地址不可用）'}`"),
			        ("'browser not connected (try /browser connect <url> or set browser.cdp_url in config.yaml)'", "'浏览器未连接（尝试 /browser connect <url> 或在 config.yaml 设置 browser.cdp_url）'"),
			        ("'browser disconnected'", "'浏览器已断开'"),
			        ("'Browser connected to live Chrome via CDP'", "'浏览器已通过 CDP 连接到当前 Chrome'"),
			        ("`Endpoint: ${r.url || '(url unavailable)'}`", "`端点：${r.url || '（地址不可用）'}`"),
			        ("'next browser tool call will use this CDP endpoint'", "'下一次浏览器工具调用将使用这个 CDP 端点'"),
			        ("help: 'list, diff, or restore checkpoints'", "help: '列出、对比或恢复检查点'"),
			        ("'no active session — nothing to rollback'", "'没有活跃会话，无法恢复'"),
			        ("'checkpoints are not enabled'", "'检查点未启用'"),
			        ("'no checkpoints found'", "'没有找到检查点'"),
			        ("ctx.transcript.panel('Rollback checkpoints'", "ctx.transcript.panel('恢复检查点'"),
			        ("'(no metadata)'", "'（无元数据）'"),
			        ("'usage: /rollback diff <checkpoint>'", "'用法：/rollback diff <检查点>'"),
			        ("'no changes since this checkpoint'", "'从该检查点起没有变化'"),
			        ("'Rollback diff'", "'恢复差异'"),
			        ("`rollback failed: ${r.error || r.message || 'unknown error'}`", "`恢复失败：${r.error || r.message || '未知错误'}`"),
			        ("const target = filePath || 'workspace'", "const target = filePath || '工作区'"),
			        ("const detail = r.reason || r.message || r.restored_to || 'restored'", "const detail = r.reason || r.message || r.restored_to || '已恢复'"),
			        ("`rollback restored ${target}: ${detail}`", "`已恢复 ${target}：${detail}`"),
			        ("help: 'open the spawn-tree dashboard (live audit + kill/pause controls)'", "help: '打开子 Agent 树面板'"),
			        ("`delegation · ${r?.paused ? 'paused' : 'resumed'}`", "`委派 · ${r?.paused ? '已暂停' : '已恢复'}`"),
			        ("`delegation · ${d.paused ? 'paused' : 'active'} · caps d${d.maxSpawnDepth ?? '?'}/${d.maxConcurrentChildren ?? '?'}`", "`委派 · ${d.paused ? '已暂停' : '活跃'} · 限制 d${d.maxSpawnDepth ?? '?'}/${d.maxConcurrentChildren ?? '?'}`"),
			        ("help: 'replay a completed spawn tree · `/replay [N|last|list|load <path>]`'", "help: '回放已完成的子 Agent 树 · `/replay [N|last|list|load <path>]`'"),
			        ("'no archived spawn trees on disk for this session'", "'当前会话没有已归档的子 Agent 树'"),
			        ("`${e.count} subagents`", "`${e.count} 个子 Agent`"),
			        ("ctx.transcript.panel('Archived spawn trees'", "ctx.transcript.panel('已归档的子 Agent 树'"),
			        ("'usage: /replay load <path>'", "'用法：/replay load <路径>'"),
			        ("'snapshot empty or unreadable'", "'快照为空或无法读取'"),
			        ("'no completed spawn trees this session · try /replay list'", "'当前会话没有已完成的子 Agent 树，可试试 /replay list'"),
			        ("`replay: index out of range 1..${history.length} · use /replay list for disk`", "`回放：序号超出范围 1..${history.length} · 使用 /replay list 查看历史`"),
			        ("help: 'diff two completed spawn trees · `/replay-diff <baseline> <candidate>` (indexes from /replay list or history N)'", "help: '对比两个已完成的子 Agent 树 · `/replay-diff <baseline> <candidate>`'"),
			        ("'usage: /replay-diff <a> <b>  (e.g. /replay-diff 1 2 for last two)'", "'用法：/replay-diff <a> <b>  （例如 /replay-diff 1 2 对比最近两次）'"),
			        ("`replay-diff: could not resolve indices · history has ${history.length} entries`", "`回放差异：无法解析序号 · 历史中有 ${history.length} 条`"),
			        ("help: 're-scan installed skills in the live TUI gateway'", "help: '在当前 TUI 网关重新扫描已安装技能'"),
			        ("r.output || 'skills reloaded'", "r.output || '技能已重新加载'"),
			        ("'Reload Skills'", "'重新加载技能'"),
			        ("help: 'browse, inspect, install skills'", "help: '浏览、查看、安装技能'"),
			        ("const body = r?.output || '/skills: no output'", "const body = r?.output || '/skills：无输出'"),
			        ("`warning: ${r.warning}\\n${body}`", "`警告：${r.warning}\\n${body}`"),
			        ("'no skills available'", "'没有可用技能'"),
			        ("'Skills'", "'技能'"),
			        ("'usage: /skills inspect <name>'", "'用法：/skills inspect <名称>'"),
			        ("`unknown skill: ${query}`", "`未知技能：${query}`"),
			        ("['Name', String(info.name)]", "['名称', String(info.name)]"),
			        ("['Category', String(info.category ?? '')]", "['分类', String(info.category ?? '')]"),
			        ("['Path', String(info.path ?? '')]", "['路径', String(info.path ?? '')]"),
			        ("panel('Skill', sections)", "panel('技能', sections)"),
			        ("'usage: /skills search <query>'", "'用法：/skills search <关键词>'"),
			        ("`no results for: ${query}`", "`没有搜索结果：${query}`"),
			        ("`Search: ${query}`", "`搜索：${query}`"),
			        ("'usage: /skills install <name or url>'", "'用法：/skills install <名称或网址>'"),
			        ("`installing ${query}…`", "`正在安装 ${query}…`"),
			        ("`installed ${r.name ?? query}`", "`已安装 ${r.name ?? query}`"),
			        ("'install failed'", "'安装失败'"),
			        ("'usage: /skills browse [page]  (page must be a positive number)'", "'用法：/skills browse [页码]（页码必须为正数）'"),
			        ("'fetching community skills (scans 6 sources, may take ~15s)…'", "'正在获取社区技能（扫描 6 个来源，可能需要约 15 秒）…'"),
			        ("`no skills on page ${pageNum}${r.total ? ` (total ${r.total})` : ''}`", "`第 ${pageNum} 页没有技能${r.total ? `（共 ${r.total} 个）` : ''}`"),
			        ("`page ${r.page} of ${r.total_pages}`", "`第 ${r.page}/${r.total_pages} 页`"),
			        ("`${r.total} skills total`", "`共 ${r.total} 个技能`"),
			        ("`/skills browse ${r.page + 1} for more`", "`/skills browse ${r.page + 1} 查看更多`"),
			        ("`Browse Skills${pageNum > 1 ? ` — p${pageNum}` : ''}`", "`浏览技能${pageNum > 1 ? ` — 第 ${pageNum} 页` : ''}`"),
			        ("help: 'enable or disable tools (client-side history reset on change)'", "help: '启用或禁用工具'"),
			        ("const body = r?.output || '/tools: no output'", "const body = r?.output || '/tools：无输出'"),
			        ("`usage: /tools ${subcommand} <name> [name ...]`", "`用法：/tools ${subcommand} <名称> [名称 ...]`"),
			        ("`built-in toolset: /tools ${subcommand} web`", "`内置工具集：/tools ${subcommand} web`"),
			        ("`MCP tool: /tools ${subcommand} github:create_issue`", "`MCP 工具：/tools ${subcommand} github:create_issue`"),
			        ("`${subcommand === 'disable' ? 'disabled' : 'enabled'}: ${r.changed.join(', ')}`", "`${subcommand === 'disable' ? '已禁用' : '已启用'}：${r.changed.join(', ')}`"),
			        ("`unknown toolsets: ${r.unknown.join(', ')}`", "`未知工具集：${r.unknown.join(', ')}`"),
			        ("`missing MCP servers: ${r.missing_servers.join(', ')}`", "`缺少 MCP 服务：${r.missing_servers.join(', ')}`"),
			        ("'session reset. new tool configuration is active.'", "'会话已重置，新工具配置已生效。'"),
			    ],
			    "ui-tui/src/app/slash/commands/setup.ts": [
			        ("help: 'run full setup wizard (launches `hermes setup`)'", "help: '运行完整配置向导（启动 `hermes setup`）'"),
			    ],
			    "ui-tui/src/app/slash/commands/debug.ts": [
			        ("help: 'write a V8 heap snapshot + memory diagnostics (see HERMES_HEAPDUMP_DIR)'", "help: '写入 V8 堆快照和内存诊断（见 HERMES_HEAPDUMP_DIR）'"),
			        ("help: 'print live V8 heap + rss numbers'", "help: '打印当前 V8 堆和 RSS 数值'"),
			    ],
			    "ui-tui/src/app/uiStore.ts": [
			        ("status: 'summoning hermes…'", "status: '正在启动 Hermes…'"),
			    ],
			    "ui-tui/src/app/useSessionLifecycle.ts": [
			        ("patchUiState({ status: 'setup required' })", "patchUiState({ status: '需要配置' })"),
			        ("return patchUiState({ status: 'ready' })", "return patchUiState({ status: '就绪' })"),
			        ("status: info?.version ? 'ready' : 'starting agent…'", "status: info?.version ? '就绪' : '正在启动 Agent…'"),
			        ("patchUiState({ status: 'resuming…' })", "patchUiState({ status: '正在继续…' })"),
			        ("status: 'ready'", "status: '就绪'"),
			    ],
			    "ui-tui/src/app/setupHandoff.ts": [
			        ("patchUiState({ status: 'setup running…' })", "patchUiState({ status: '正在配置…' })"),
			        ("patchUiState({ status: 'setup required' })", "patchUiState({ status: '需要配置' })"),
			        ("transcript.sys(`launching \\`hermes ${args.join(' ')}\\`…`)", "transcript.sys(`正在启动 \\`hermes ${args.join(' ')}\\`…`)"),
			        ("transcript.sys(`error launching hermes: ${result.error}`)", "transcript.sys(`启动 Hermes 出错：${result.error}`)"),
			        ("transcript.sys(`hermes ${args[0]} exited with code ${result.code}`)", "transcript.sys(`hermes ${args[0]} 退出，代码 ${result.code}`)"),
			        ("transcript.sys('still no provider configured')", "transcript.sys('仍未配置模型服务')"),
			    ],
			    "ui-tui/src/app/useMainApp.ts": [
			        ("patchUiState({ status: 'running…' })", "patchUiState({ status: '运行中…' })"),
			        ("patchUiState({ busy: true, status: 'running…' })", "patchUiState({ busy: true, status: '运行中…' })"),
			        ("patchUiState({ busy: false, sid: null, status: 'gateway exited' })", "patchUiState({ busy: false, sid: null, status: '网关已退出' })"),
			    ],
			    "ui-tui/src/app/turnController.ts": [
			        ("sys('interrupted')", "sys('已中断')"),
			        ("patchUiState({ status: 'interrupted' })", "patchUiState({ status: '已中断' })"),
			        ("patchUiState({ status: 'ready' })", "patchUiState({ status: '就绪' })"),
			    ],
			    "ui-tui/src/app/useInputHandlers.ts": [
			        ("`failed to open editor: ${err.message}`", "`打开编辑器失败：${err.message}`"),
			        ("'failed to open editor'", "'打开编辑器失败'"),
			        ("'failed to toggle yolo'", "'切换 yolo 失败'"),
			    ],
			    "ui-tui/src/app/useSubmission.ts": [
			        ("patchUiState({ busy: false, status: 'ready' })", "patchUiState({ busy: false, status: '就绪' })"),
			        ("return sys('session not ready yet')", "return sys('会话还没准备好')"),
			        ("patchUiState({ busy: true, status: 'running…' })", "patchUiState({ busy: true, status: '运行中…' })"),
			        ("patchUiState({ busy: true, status: 'queued for next turn' })", "patchUiState({ busy: true, status: '已加入下一轮队列' })"),
			        ("patchUiState({ status: 'interpolating…' })", "patchUiState({ status: '正在整理…' })"),
			        ("'error: invalid response: shell.exec'", "'错误：shell.exec 返回无效响应'"),
			        ("fallback('steer rejected — message queued for next turn')", "fallback('插入消息被拒绝，已加入下一轮队列')"),
			        ("fallback('steer failed — message queued for next turn')", "fallback('插入消息失败，已加入下一轮队列')"),
			    ],
			    "ui-tui/src/gatewayClient.ts": [
			        ("new Error('gateway restarting')", "new Error('网关正在重启')"),
			        ("this.pushLog(`[startup] timed out waiting for gateway.ready (python=${python}, cwd=${cwd})`)", "this.pushLog(`[启动] 等待 gateway.ready 超时（python=${python}, cwd=${cwd}）`)"),
			        ("this.pushLog(`[sidecar] failed to connect ${redactUrl(this.sidecarUrl)} (constructor error)`)", "this.pushLog(`[边车] 连接失败 ${redactUrl(this.sidecarUrl)}（构造错误）`)"),
			        ("reject(new Error('gateway websocket connection failed'))", "reject(new Error('网关 websocket 连接失败'))"),
			        ("this.pushLog(`[startup] failed to connect websocket gateway ${safeAttachUrl} (constructor error)`)", "this.pushLog(`[启动] 无法连接 websocket 网关 ${safeAttachUrl}（构造错误）`)"),
			        ("this.handleTransportExit(1, 'gateway websocket startup failed')", "this.handleTransportExit(1, '网关 websocket 启动失败')"),
			        ("return new Error(typeof err?.message === 'string' ? err.message : typeof err === 'string' && err.trim() ? err : 'request failed')", "return new Error(typeof err?.message === 'string' ? err.message : typeof err === 'string' && err.trim() ? err : '请求失败')"),
			    ],
			    "ui-tui/src/lib/terminalSetup.ts": [
			        ("message: `${meta.label} terminal keybindings already configured.`", "message: `${meta.label} 终端快捷键已配置。`"),
			    ],
			    "tui_gateway/server.py": [
		        ('f"Agent Running: {\'Yes\' if session.get(\'running\') else \'No\'}"', 'f"Agent 运行中：{\'是\' if session.get(\'running\') else \'否\'}"'),
		        ('return "`hermes gateway` is long-running — run it in another terminal"', 'return "`hermes gateway` 是长期运行服务，请在另一个终端运行"'),
		        ('return f"session busy — /interrupt the current turn before running /{name}"', 'return f"会话忙碌，请先用 /interrupt 中断当前轮，再运行 /{name}"'),
		        ('"session busy — /interrupt the current turn before /undo"', '"会话忙碌，请先用 /interrupt 中断当前轮，再运行 /undo"'),
		        ('"session busy — /interrupt the current turn before /compress"', '"会话忙碌，请先用 /interrupt 中断当前轮，再运行 /compress"'),
		        ('"session busy — /interrupt the current turn before switching models"', '"会话忙碌，请先用 /interrupt 中断当前轮，再切换模型"'),
		        ('"session busy — /interrupt the current turn before /retry"', '"会话忙碌，请先用 /interrupt 中断当前轮，再运行 /retry"'),
		        ('"session busy — /interrupt the current turn before full rollback.restore"', '"会话忙碌，请先用 /interrupt 中断当前轮，再执行完整恢复"'),
		        ('"session busy"', '"会话忙碌"'),
		        ('"Chrome isn\\\'t running with remote debugging — attempting to launch..."', '"Chrome 未启用远程调试，正在尝试启动..."'),
		        ('announce(f"Chrome is already listening on port {port}")', 'announce(f"Chrome 已在端口 {port} 监听")'),
		        ('"agent initialization failed"', '"Agent 初始化失败"'),
		        ('f"agent init failed: {e}"', 'f"Agent 初始化失败：{e}"'),
		        ('"session_id required"', '"需要 session_id"'),
		        ('f"resume failed: {e}"', 'f"继续会话失败：{e}"'),
		        ('"cannot delete an active session"', '"不能删除活跃会话"'),
		        ('f"delete failed: {e}"', 'f"删除失败：{e}"'),
		        ('"title required"', '"需要标题"'),
		        ('f"branch failed: {e}"', 'f"创建分支失败：{e}"'),
		        ('f"agent init failed on branch: {e}"', 'f"分支中的 Agent 初始化失败：{e}"'),
		        ('"subagent_id required"', '"需要 subagent_id"'),
		        ('"subagents list required"', '"需要子 Agent 列表"'),
		        ('"path required"', '"需要路径"'),
		        ('"text is required"', '"需要文本"'),
		        ('f"steer failed: {exc}"', 'f"插入消息失败：{exc}"'),
		        ('"queued" if accepted else "rejected"', '"已排队" if accepted else "已拒绝"'),
		        ('"model value required"', '"需要模型值"'),
		        ('"text required"', '"需要文本"'),
		        ('"slug and api_key are required"', '"需要 slug 和 api_key"'),
		        ('"slug is required"', '"需要 slug"'),
		        ('f"live session sync failed: {e}"', 'f"实时会话同步失败：{e}"'),
		        ('f"Plugin command error: {e}"', 'f"插件命令出错：{e}"'),
		        ('f"slash worker start failed: {e}"', 'f"斜杠命令工作进程启动失败：{e}"'),
		        ('"names required"', '"需要名称"'),
		        ('"hash required"', '"需要 hash"'),
		        ('"Start Chrome with remote debugging, then retry /browser connect:"', '"请先以远程调试方式启动 Chrome，然后重试 /browser connect："'),
		        ('"Browser not connected — start Chrome with remote debugging and retry /browser connect"', '"浏览器未连接，请以远程调试方式启动 Chrome 后重试 /browser connect"'),
		        ('f"Model: {model} ({provider})"', 'f"模型：{model} ({provider})"'),
		        ('["Toolsets", ", ".join(cfg.get("enabled_toolsets", [])) or "all"]', '["工具集", ", ".join(cfg.get("enabled_toolsets", [])) or "all"]'),
		    ],
		    "gateway/run.py": [
		        ('message = "♻️ Gateway online — Hermes is back and ready."', 'message = "♻️ 网关已上线，Hermes 已恢复并就绪。"'),
		        ('_INTERRUPT_REASON_GATEWAY_RESTART = "Gateway restarting"', '_INTERRUPT_REASON_GATEWAY_RESTART = "网关正在重启"'),
		        ('action = "restarting" if self._restart_requested else "shutting down"', 'action = "正在重启" if self._restart_requested else "正在关闭"'),
		        ('"Your current task will be interrupted. "\n            "Send any message after restart and I\'ll try to resume where you left off."', '"当前任务会被中断。"\n            "重启后发送任意消息，我会尝试从中断处继续。"'),
		        ('else "Your current task will be interrupted."', 'else "当前任务会被中断。"'),
		        ('msg = f"⚠️ Gateway {action} — {hint}"', 'msg = f"⚠️ 网关{action}：{hint}"'),
		        ('"♻ Gateway restarted successfully. Your session continues."', '"♻ 网关已成功重启，当前会话继续。"'),
		        ('f"⚠️ **Dangerous command requires approval:**\\n"', 'f"⚠️ **危险命令需要确认：**\\n"'),
		        ('f"**Command:**\\n```\\n{cmd}\\n```\\n"', 'f"**命令：**\\n```\\n{cmd}\\n```\\n"'),
		        ('f"**Reason:** {desc}\\n\\n"', 'f"**原因：** {desc}\\n\\n"'),
		        ('"Reply `/approve` to allow once, `/approve always` to remember, or `/deny` to reject."', '"回复 `/approve` 允许一次，`/approve always` 记住选择，或 `/deny` 拒绝。"'),
		        ('f"\\n❌ Gateway already running (PID {existing_pid}).\\n"', 'f"\\n❌ 网关已在运行（PID {existing_pid}）。\\n"'),
		        ('f"[Background process {session_id} is still running~ "', 'f"[后台进程 {session_id} 仍在运行~ "'),
		        ('running: {current_tool}', '运行中：{current_tool}'),
		        ('running: {_a[\'current_tool\']}', '运行中：{_a[\'current_tool\']}'),
		        ('"Gateway drain timed out after %.1fs with %d active agent(s); interrupting remaining work."', '"网关等待 %.1f 秒后仍有 %d 个 Agent 在运行；正在中断剩余任务。"'),
		        ('"a gateway restart"', '"网关重启"'),
		        ('"a gateway shutdown"', '"网关关闭"'),
		        ('"a gateway interruption"', '"网关中断"'),
		        ('f"[System note: Your previous turn in this session was interrupted "\n                    f"by {_reason_phrase}. The conversation history below is intact. "\n                    f"If it contains unfinished tool result(s), process them first and "\n                    f"summarize what was accomplished, then address the user\'s new "\n                    f"message below.]\\n\\n"', 'f"[系统提示：本会话上一轮因{_reason_phrase}被中断。下面的对话历史仍然完整。若其中包含尚未处理的工具结果，请先处理并总结已完成内容，再回应用户的新消息。]\\n\\n"'),
		        ('"[System note: Your previous turn was interrupted before you could "\n                    "process the last tool result(s). The conversation history contains "\n                    "tool outputs you haven\'t responded to yet. Please finish processing "\n                    "those results and summarize what was accomplished, then address the "\n                    "user\'s new message below.]\\n\\n"', '"[系统提示：上一轮在处理最后的工具结果前被中断。对话历史里有尚未回应的工具输出，请先处理并总结已完成内容，再回应用户的新消息。]\\n\\n"'),
		        ('f"\\n❌ Gateway already running (PID {existing_pid}).\\n"\n                f"   Use \'hermes gateway restart\' to replace it,\\n"\n                f"   or \'hermes gateway stop\' to kill it first.\\n"\n                f"   Or use \'hermes gateway run --replace\' to auto-replace.\\n"', 'f"\\n❌ 网关已在运行（PID {existing_pid}）。\\n"\n                f"   可运行 \'hermes gateway restart\' 替换它，\\n"\n                f"   或先运行 \'hermes gateway stop\' 停止它。\\n"\n                f"   也可运行 \'hermes gateway run --replace\' 自动替换。\\n"'),
		    ],
		    "hermes_cli/gateway.py": [
		        ('print(f"✓ {scope_label} service restarted (PID {new_pid})")', 'print(f"✓ {scope_label} 服务已重启（PID {new_pid}）")'),
		        ('print(f"⚠ {scope_label} service process restarted (PID {new_pid}), but gateway startup failed: {reason}")', 'print(f"⚠ {scope_label} 服务进程已重启（PID {new_pid}），但网关启动失败：{reason}")'),
		        ('print(f"⏳ {scope_label} service process started (PID {new_pid}); waiting for gateway runtime...")', 'print(f"⏳ {scope_label} 服务进程已启动（PID {new_pid}），正在等待网关运行...")'),
		        ('f"⚠ {scope_label} service did not become active within {int(timeout)}s.\\n"\n        f"  Check status: {\'sudo \' if system else \'\'}hermes gateway status\\n"\n        f"  Check logs:   journalctl {\'--user \' if not system else \'\'}-u {svc} -l --since \'2 min ago\'"', 'f"⚠ {scope_label} 服务在 {int(timeout)} 秒内没有变为可用。\\n"\n        f"  查看状态：{\'sudo \' if system else \'\'}hermes gateway status\\n"\n        f"  查看日志：journalctl {\'--user \' if not system else \'\'}-u {svc} -l --since \'2 min ago\'"'),
		        ('print(f"⏳ {scope_label} service is temporarily rate-limited by systemd.")', 'print(f"⏳ {scope_label} 服务被 systemd 临时限流。")'),
		        ('print("  systemd is refusing another immediate start after repeated exits.")', 'print("  因多次退出，systemd 暂时拒绝立即再次启动。")'),
		        ('print(f"  Wait for the start-limit window to expire, then run: {\'sudo \' if system else \'\'}hermes gateway restart{scope_flag}")', 'print(f"  等待限流窗口结束后运行：{\'sudo \' if system else \'\'}hermes gateway restart{scope_flag}")'),
		        ('print(f"  Or clear the failed state manually: {systemctl_prefix}reset-failed {svc}")', 'print(f"  或手动清除失败状态：{systemctl_prefix}reset-failed {svc}")'),
		        ('print(f"  Check logs: {journal_prefix}-u {svc} -l --since \'5 min ago\'")', 'print(f"  查看日志：{journal_prefix}-u {svc} -l --since \'5 min ago\'")'),
		        ('print("⏳ Service restart already pending — waiting for systemd relaunch...")', 'print("⏳ 服务重启已在等待中，正在等待 systemd 重新拉起...")'),
		        ('print(f"↻ Clearing failed state for pending {scope_label.lower()} service restart...")', 'print(f"↻ 正在清除待重启 {scope_label.lower()} 服务的失败状态...")'),
		        ('print("⚠ Gateway process is running for this profile, but the service is not active")', 'print("⚠ 当前配置档已有网关进程在运行，但服务未处于活动状态")'),
		        ('print("  This is usually a manual foreground/tmux/nohup run, so `hermes gateway`")', 'print("  这通常是手动前台、tmux 或 nohup 运行，因此 `hermes gateway`")'),
		        ('print("  can refuse to start another copy until this process stops.")', 'print("  在该进程停止前可能拒绝启动另一份实例。")'),
		        ('print("Other profiles:")', 'print("其他配置档：")'),
		        ('print("Unable to list profiles.")', 'print("无法列出配置档。")'),
		        ('print("No profiles found.")', 'print("未找到配置档。")'),
		        ('print("Gateways:")', 'print("网关：")'),
		        ('print("⏳ {scope_label} service restarting gracefully (PID {pid})...")', 'print(f"⏳ {scope_label} 服务正在平滑重启（PID {pid}）...")'),
		        ('f"⚠ Graceful restart did not complete within {int(drain_timeout + 5)}s; "\n            "forcing a service restart..."', 'f"⚠ 平滑重启在 {int(drain_timeout + 5)} 秒内未完成；"\n            "正在强制重启服务..."'),
		        ('f"Gateway {label} service is still restarting after 90s; "\n                "check `hermes gateway status` or logs for final state."', 'f"网关 {label} 服务 90 秒后仍在重启；"\n                "请用 `hermes gateway status` 或日志查看最终状态。"'),
		        ('print(f"⚠ Gateway PID {remaining_pid} still running after {timeout}s — restart may fail")', 'print(f"⚠ 网关 PID {remaining_pid} 在 {timeout} 秒后仍在运行，重启可能失败")'),
		        ('print("✓ Service restart requested")', 'print("✓ 服务重启请求已发送")'),
		        ('print(f"⚠ Gateway drain timed out after {drain_timeout:.0f}s — forcing launchd restart")', 'print(f"⚠ 网关等待 {drain_timeout:.0f} 秒后仍未结束，正在强制重启 launchd 服务")'),
		        ('print("✓ Service restarted")', 'print("✓ 服务已重启")'),
		        ('print("↻ launchd job was unloaded; reloading")', 'print("↻ launchd 任务未加载，正在重新加载")'),
		    ],
		    "hermes_cli/plugins_cmd.py": [
		        ('f"[green]\\u2713[/green] Memory provider: [bold]{new_memory}[/bold]  "', 'f"[green]\\u2713[/green] 记忆服务：[bold]{new_memory}[/bold]  "'),
		    ],
		    "gateway/platforms/discord.py": [
		        ('description="Start a new conversation"', 'description="开始新会话"'),
		        ('description="Reset your Hermes session"', 'description="重置 Hermes 会话"'),
		        ('description="Show or change the model"', 'description="查看或切换模型"'),
		        ('description="Show or change reasoning effort"', 'description="查看或切换推理强度"'),
		        ('description="Set a personality"', 'description="设置人格"'),
		        ('description="Retry your last message"', 'description="重试上一条消息"'),
		        ('description="Remove the last exchange"', 'description="移除上一轮对话"'),
		        ('description="Show Hermes session status"', 'description="查看 Hermes 会话状态"'),
		        ('description="Set this chat as the home channel"', 'description="将当前聊天设为主频道"'),
		        ('description="Stop the running Hermes agent"', 'description="停止运行中的 Hermes Agent"'),
		        ('description="Inject a message after the next tool call (no interrupt)"', 'description="在下一次工具调用后插入消息（不打断）"'),
		        ('description="Compress conversation context"', 'description="压缩对话上下文"'),
		        ('description="Set or show the session title"', 'description="设置或查看会话标题"'),
		        ('description="Resume a previously-named session"', 'description="继续之前命名的会话"'),
		        ('description="Show token usage for this session"', 'description="查看当前会话 token 用量"'),
		        ('description="Show available commands"', 'description="查看可用命令"'),
		        ('description="Show usage insights and analytics"', 'description="查看用量分析"'),
		        ('description="Reload MCP servers from config"', 'description="从配置重新读取 MCP 服务"'),
		        ('description="Re-scan ~/.hermes/skills/ for new or removed skills"', 'description="重新扫描新增或移除的技能"'),
		        ('description="Toggle voice reply mode"', 'description="切换语音回复模式"'),
		        ('description="Update Hermes Agent to the latest version"', 'description="将 Hermes Agent 更新到最新版"'),
		        ('description="Gracefully restart the Hermes gateway"', 'description="平滑重启 Hermes 网关"'),
		        ('description="Approve a pending dangerous command"', 'description="批准待处理的危险命令"'),
		        ('description="Deny a pending dangerous command"', 'description="拒绝待处理的危险命令"'),
		        ('description="Create a new thread and start a Hermes session in it"', 'description="创建新话题并启动 Hermes 会话"'),
		        ('description="Queue a prompt for the next turn (doesn\'t interrupt)"', 'description="将提示词加入下一轮队列（不打断当前任务）"'),
		        ('description="Run a prompt in the background"', 'description="在后台执行提示词"'),
		        ('name="Model name (e.g. anthropic/claude-sonnet-4). Leave empty to see current."', 'name="模型名称（例如 anthropic/claude-sonnet-4），留空则查看当前模型。"'),
		        ('effort="Reasoning effort: none, minimal, low, medium, high, or xhigh."', 'effort="推理强度：none、minimal、low、medium、high 或 xhigh。"'),
		        ('name="Personality name. Leave empty to list available."', 'name="人格名称，留空则列出可用项。"'),
		        ('prompt="Text to inject into the agent\\\'s next tool result"', 'prompt="要插入到下一次工具结果后的文本"'),
		        ('name="Session title. Leave empty to show current."', 'name="会话标题，留空则查看当前标题。"'),
		        ('name="Session name to resume. Leave empty to list sessions."', 'name="要继续的会话名，留空则列出会话。"'),
		        ('days="Number of days to analyze (default: 7)"', 'days="要分析的天数（默认 7）"'),
		        ('mode="Voice mode: join, channel, leave, on, tts, off, or status"', 'mode="语音模式：join、channel、leave、on、tts、off 或 status"'),
		        ("scope=\"Optional: 'all', 'session', 'always', 'all session', 'all always'\"", 'scope="可选：all、session、always、all session、all always"'),
		        ("scope=\"Optional: 'all' to deny all pending commands\"", 'scope="可选：all 表示拒绝全部待处理命令"'),
		        ('name="Thread name"', 'name="话题名称"'),
		        ('message="Optional first message to send to Hermes in the thread"', 'message="可选：发给 Hermes 的第一条消息"'),
		        ('prompt="The prompt to queue"', 'prompt="要加入队列的提示词"'),
		        ('prompt="The prompt to run in the background"', 'prompt="要在后台执行的提示词"'),
		        ('"New conversation started~"', '"新会话已开始~"'),
		        ('"Session reset~"', '"会话已重置~"'),
		        ('"Retrying~"', '"正在重试~"'),
		        ('"Status sent~"', '"状态已发送~"'),
		        ('"Stop requested~"', '"已请求停止~"'),
		        ('"Update initiated~"', '"已开始更新~"'),
		        ('"Restart requested~"', '"已请求重启~"'),
		        ('"Queued for the next turn."', '"已加入下一轮队列。"'),
		        ('"Background task started~"', '"后台任务已启动~"'),
		    ],
		    "acp_adapter/permissions.py": [
		        ('name="Allow once"', 'name="允许一次"'),
		        ('name="Allow always"', 'name="始终允许"'),
		        ('name="Deny"', 'name="拒绝"'),
		        ('Permission request timed out or failed: %s', '权限请求超时或失败：%s'),
		    ],
		    "plugins/platforms/teams/adapter.py": [
		        ('TextBlock(text="⚠️ Approval already resolved or expired.", wrap=True)', 'TextBlock(text="⚠️ 确认请求已处理或已过期。", wrap=True)'),
		        ('"once": "✅ Allowed (once)"', '"once": "✅ 已允许一次"'),
		        ('"session": "✅ Allowed (session)"', '"session": "✅ 本会话已允许"'),
		        ('"always": "✅ Always allowed"', '"always": "✅ 已始终允许"'),
		        ('"deny": "❌ Denied"', '"deny": "❌ 已拒绝"'),
		        ('TextBlock(text="⚠️ Command Approval Required", wrap=True, weight="Bolder")', 'TextBlock(text="⚠️ 命令需要确认", wrap=True, weight="Bolder")'),
		        ('TextBlock(text=f"Reason: {desc}", wrap=True, isSubtle=True)', 'TextBlock(text=f"原因：{desc}", wrap=True, isSubtle=True)'),
		        ('TextBlock(text=f"Reason: {description}", wrap=True, isSubtle=True)', 'TextBlock(text=f"原因：{description}", wrap=True, isSubtle=True)'),
		        ('description: str = "dangerous command"', 'description: str = "危险命令"'),
		        ('return SendResult(success=False, error="Teams app not initialized")', 'return SendResult(success=False, error="Teams 应用尚未初始化")'),
		        ('title="Allow Once"', 'title="允许一次"'),
		        ('title="Allow Session"', 'title="本会话允许"'),
		        ('title="Always Allow"', 'title="始终允许"'),
		        ('title="Deny"', 'title="拒绝"'),
		    ],
		    "plugins/memory/hindsight/__init__.py": [
		        ('print(f"\\n  ✓ Hindsight memory configured ({mode} mode)")', 'print(f"\\n  ✓ Hindsight 记忆已配置（{mode} 模式）")'),
		        ('print("  API keys saved to .env")', 'print("  API Key 已保存到 .env")'),
		        ('print("\\n  Start a new session to activate.\\n")', 'print("\\n  请新建会话后启用。\\n")'),
		        ('"description": "Connection mode"', '"description": "连接模式"'),
		        ('"description": "Hindsight Cloud API URL"', '"description": "Hindsight Cloud API 地址"'),
		        ('"description": "Hindsight Cloud API key"', '"description": "Hindsight Cloud API Key"'),
		        ('"description": "Hindsight API URL"', '"description": "Hindsight API 地址"'),
		        ('"description": "API key (optional)"', '"description": "API Key（可选）"'),
		    ],
		    "acp_adapter/server.py": [
		        ('return f"Hermes Agent v{HERMES_VERSION}"', 'return f"爱马仕机器人 v{HERMES_VERSION}"'),
		        ('Tip: run /compact to compress manually before the threshold.', '提示：达到阈值前，可运行 /compact 手动压缩上下文。'),
		        ('description="Ask before edits."', 'description="修改文件前询问。"'),
		        ('description="Auto-allow workspace and /tmp edits; still asks for sensitive paths."', 'description="自动允许工作目录和 /tmp 修改；敏感路径仍会询问。"'),
		        ('description="Auto-allow file edits for this session except sensitive paths."', 'description="本会话自动允许文件修改，敏感路径除外。"'),
		        ('name="Default"', 'name="默认"'),
		        ('name="Accept Edits"', 'name="接受修改"'),
		        ('name="Don\\\'t Ask"', 'name="不再询问"'),
		        ('"help": "Show available commands"', '"help": "查看可用命令"'),
		        ('return f"Error executing /{cmd}: {e}"', 'return f"执行 /{cmd} 出错：{e}"'),
		        ('lines = ["Available commands:", ""]', 'lines = ["可用命令：", ""]'),
		        ('lines.append("Unrecognized /commands are sent to the model as normal messages.")', 'lines.append("未识别的 /命令会作为普通消息发给模型。")'),
		        ('return f"Current model: {model}\\nProvider: {provider}"', 'return f"当前模型：{model}\\n模型服务：{provider}"'),
		        ('return f"Model switched to: {new_model}\\nProvider: {provider_label}"', 'return f"模型已切换到：{new_model}\\n模型服务：{provider_label}"'),
		        ('return "No tools available."', 'return "没有可用工具。"'),
		        ('lines = [f"Available tools ({len(tools)}):"]', 'lines = [f"可用工具（{len(tools)} 个）："]'),
		        ('return f"Could not list tools: {e}"', 'return f"无法列出工具：{e}"'),
		        ('f"Conversation: {n_messages} messages"', 'f"对话：{n_messages} 条消息"'),
		        ('else "Conversation is empty (no messages yet)."', 'else "对话为空（还没有消息）。"'),
		        ('f"  user: {roles.get(\\\'user\\\', 0)}, assistant: {roles.get(\\\'assistant\\\', 0)}, "\n            f"tool: {roles.get(\\\'tool\\\', 0)}, system: {roles.get(\\\'system\\\', 0)}"', 'f"  用户：{roles.get(\\\'user\\\', 0)}，助手：{roles.get(\\\'assistant\\\', 0)}，"\n            f"工具：{roles.get(\\\'tool\\\', 0)}，系统：{roles.get(\\\'system\\\', 0)}"'),
		        ('lines.append(f"Model: {model}")', 'lines.append(f"模型：{model}")'),
		        ('lines.append(f"Provider: {provider}")', 'lines.append(f"模型服务：{provider}")'),
		        ('f"Context usage: ~{approx_tokens:,} / {context_length:,} tokens ({usage_pct:.1f}%)"', 'f"上下文用量：约 {approx_tokens:,} / {context_length:,} token（{usage_pct:.1f}%）"'),
		        ('lines.append(f"Context usage: ~{approx_tokens:,} tokens")', 'lines.append(f"上下文用量：约 {approx_tokens:,} token")'),
		        ('f"Compression: due now (threshold ~{threshold_tokens:,}"', 'f"压缩：现在应压缩（阈值约 {threshold_tokens:,}"'),
		        ('+ "). Run /compact."', '+ "）。运行 /compact。"'),
		        ('f"Compression: ~{remaining:,} tokens until threshold "', 'f"压缩：距离阈值约剩余 {remaining:,} token "'),
		        ('lines.append(f"Compression threshold: ~{threshold_tokens:,} tokens")', 'lines.append(f"压缩阈值：约 {threshold_tokens:,} token")'),
		        ('lines.append("Compression is disabled for this agent.")', 'lines.append("当前 Agent 已关闭上下文压缩。")'),
		        ('return "Conversation history cleared."', 'return "对话历史已清空。"'),
		        ('return "Nothing to compress — conversation is empty."', 'return "没有可压缩内容，对话为空。"'),
		        ('return "Context compression is disabled for this agent."', 'return "当前 Agent 已关闭上下文压缩。"'),
		        ('return "Context compression not available for this agent."', 'return "当前 Agent 不支持上下文压缩。"'),
		        ('f"Context compressed: {original_count} -> {new_count} messages\\n"', 'f"上下文已压缩：{original_count} -> {new_count} 条消息\\n"'),
		        ('f"~{approx_tokens:,} -> ~{new_tokens:,} tokens"', 'f"约 {approx_tokens:,} -> 约 {new_tokens:,} token"'),
		        ('return f"Compression failed: {e}"', 'return f"压缩失败：{e}"'),
		        ('return "Usage: /steer <guidance>"', 'return "用法：/steer <引导语>"'),
		        ('return f"⏩ Steer queued for the active turn: {preview}"', 'return f"⏩ 插入消息已加入当前回合：{preview}"'),
		        ('return f"⚠️ Steer failed: {exc}"', 'return f"⚠️ 插入消息失败：{exc}"'),
		        ('return f"No active turn — queued for the next turn. ({depth} queued)"', 'return f"当前没有运行中的回合，已加入下一轮队列。（当前 {depth} 条）"'),
		        ('return "Usage: /queue <prompt>"', 'return "用法：/queue <提示词>"'),
		        ('return f"Queued for the next turn. ({depth} queued)"', 'return f"已加入下一轮队列。（当前 {depth} 条）"'),
		    ],
		    "acp_adapter/entry.py": [
		        ('description="Run Hermes Agent as an ACP stdio server."', 'description="以 ACP stdio 服务方式运行爱马仕机器人。"'),
		        ('help="Print Hermes version and exit"', 'help="打印 Hermes 版本后退出"'),
		        ('help="Verify ACP dependencies and adapter imports, then exit"', 'help="检查 ACP 依赖和适配器导入后退出"'),
		        ('help="Run interactive Hermes provider/model setup for ACP terminal auth"', 'help="为 ACP 终端授权运行 Hermes 模型服务配置"'),
		        ('help="Install agent-browser + Playwright Chromium into ~/.hermes/node/ "\n             "for browser tool support. Idempotent."', 'help="安装浏览器工具所需的 agent-browser 和 Playwright Chromium 到 ~/.hermes/node/。可重复运行。"'),
		        ('help="Accept all prompts (currently used by --setup-browser to skip the "\n             "~400 MB Chromium download confirmation)."', 'help="自动确认提示（当前用于 --setup-browser，跳过约 400 MB Chromium 下载确认）。"'),
		        ('print("Hermes ACP check OK")', 'print("Hermes ACP 检查通过")'),
		        ('"\\nInstall browser tools? Downloads agent-browser (npm) and "\n            "optionally Playwright Chromium (~400 MB). [y/N] "', '"\\n是否安装浏览器工具？会下载 agent-browser（npm），并可选下载 Playwright Chromium（约 400 MB）。[y/N] "'),
		        ('print("Node.js installation failed — cannot proceed with browser tools.",', 'print("Node.js 安装失败，无法继续安装浏览器工具。",'),
		        ('print("Browser tools installation failed.", file=sys.stderr)', 'print("浏览器工具安装失败。", file=sys.stderr)'),
		        ('print(f"Browser bootstrap failed: {exc}", file=sys.stderr)', 'print(f"浏览器启动依赖安装失败：{exc}", file=sys.stderr)'),
		    ],
		    "acp_adapter/edit_approval.py": [
		        ('PermissionOption(option_id="deny", kind="reject_once", name="Deny")', 'PermissionOption(option_id="deny", kind="reject_once", name="拒绝")'),
		        ('title=f"Approve edit: {proposal.path}"', 'title=f"确认修改：{proposal.path}"'),
		        ('logger.warning("Edit approval request timed out or failed: %s", exc)', 'logger.warning("修改确认请求超时或失败：%s", exc)'),
		    ],
		    "acp_adapter/tools.py": [
		        ('return f"terminal: {cmd}"', 'return f"终端：{cmd}"'),
		        ('return f"read: {args.get(\\\'path\\\', \\\'?\\\')}"', 'return f"读取：{args.get(\\\'path\\\', \\\'?\\\')}"'),
		        ('return f"write: {args.get(\\\'path\\\', \\\'?\\\')}"', 'return f"写入：{args.get(\\\'path\\\', \\\'?\\\')}"'),
		        ('return f"patch ({mode}): {path}"', 'return f"修改（{mode}）：{path}"'),
		        ('return f"search: {args.get(\\\'pattern\\\', \\\'?\\\')}"', 'return f"搜索：{args.get(\\\'pattern\\\', \\\'?\\\')}"'),
		        ('return f"web search: {args.get(\\\'query\\\', \\\'?\\\')}"', 'return f"网页搜索：{args.get(\\\'query\\\', \\\'?\\\')}"'),
		        ('return f"extract: {urls[0]}" + (f" (+{len(urls)-1})" if len(urls) > 1 else "")', 'return f"提取：{urls[0]}" + (f"（另 {len(urls)-1} 个）" if len(urls) > 1 else "")'),
		        ('return "web extract"', 'return "网页提取"'),
		        ('return f"process {action}: {sid}" if sid else f"process {action}"', 'return f"进程 {action}：{sid}" if sid else f"进程 {action}"'),
		        ('return f"delegate batch ({len(tasks)} tasks)"', 'return f"批量委派（{len(tasks)} 个任务）"'),
		        ('return f"delegate: {goal}" if goal else "delegate task"', 'return f"委派：{goal}" if goal else "委派任务"'),
		        ('return f"session search: {query}" if query else "recent sessions"', 'return f"会话搜索：{query}" if query else "最近会话"'),
		        ('return f"memory {action}: {target}"', 'return f"记忆 {action}：{target}"'),
		        ('return f"python: {first_line}"', 'return f"Python：{first_line}"'),
		        ('return "python code"', 'return "Python 代码"'),
		        ('return f"todo ({len(items)} item{\\\'s\\\' if len(items) != 1 else \\\'\\\'})"', 'return f"待办（{len(items)} 项）"'),
		        ('return "todo"', 'return "待办"'),
		        ('return f"skill view ({name}{suffix})"', 'return f"技能查看（{name}{suffix}）"'),
		        ('return f"skills list ({category})" if category else "skills list"', 'return f"技能列表（{category}）" if category else "技能列表"'),
		        ('return f"skill {action}: {target}"', 'return f"技能 {action}：{target}"'),
		        ('return f"navigate: {args.get(\\\'url\\\', \\\'?\\\')}"', 'return f"打开：{args.get(\\\'url\\\', \\\'?\\\')}"'),
		        ('return "browser snapshot"', 'return "浏览器快照"'),
		        ('return f"browser vision: {str(args.get(\\\'question\\\', \\\'?\\\'))[:50]}"', 'return f"浏览器视觉：{str(args.get(\\\'question\\\', \\\'?\\\'))[:50]}"'),
		        ('return "browser images"', 'return "浏览器图片"'),
		        ('return f"analyze image: {str(args.get(\\\'question\\\', \\\'?\\\'))[:50]}"', 'return f"分析图片：{str(args.get(\\\'question\\\', \\\'?\\\'))[:50]}"'),
		        ('return f"generate image: {prompt[:50]}" if prompt else "generate image"', 'return f"生成图片：{prompt[:50]}" if prompt else "生成图片"'),
		        ('return f"cron {action}: {job_id}" if job_id else f"cron {action}"', 'return f"定时 {action}：{job_id}" if job_id else f"定时 {action}"'),
		        ('return f"Read failed: {data.get(\\\'error\\\')}"', 'return f"读取失败：{data.get(\\\'error\\\')}"'),
		        ('range_bits.append(f"from line {offset}")', 'range_bits.append(f"从第 {offset} 行")'),
		        ('range_bits.append(f"limit {limit}")', 'range_bits.append(f"限制 {limit} 行")'),
		        ('header = f"Read {path}{suffix}"', 'header = f"读取 {path}{suffix}"'),
		        ('header += f" — {data.get(\\\'total_lines\\\')} total lines"', 'header += f" — 共 {data.get(\\\'total_lines\\\')} 行"'),
		        ('"Search results"', '"搜索结果"'),
		        ('f"Found {total} match{\\\'es\\\' if total != 1 else \\\'\\\'}; showing {shown}."', 'f"找到 {total} 项匹配；显示 {shown} 项。"'),
		        ('"Results truncated. Narrow the search, add file_glob, or use offset to page."', '"结果已截断。请缩小搜索范围、添加 file_glob，或使用 offset 翻页。"'),
		        ('parts = [f"Exit code: {exit_code}" if exit_code is not None else "Execution complete"]', 'parts = [f"退出码：{exit_code}" if exit_code is not None else "执行完成"]'),
		        ('parts.extend(["", "Output:", output])', 'parts.extend(["", "输出：", output])'),
		        ('parts.extend(["", "Error:", error])', 'parts.extend(["", "错误：", error])'),
		        ('return f"Skill view failed: {data.get(\\\'error\\\', \\\'unknown error\\\')}"', 'return f"技能查看失败：{data.get(\\\'error\\\', \\\'未知错误\\\')}"'),
		        ('lines = ["**Skill loaded**", "", f"- **Name:** `{name}`", f"- **File:** `{file_path}`"]', 'lines = ["**技能已加载**", "", f"- **名称：** `{name}`", f"- **文件：** `{file_path}`"]'),
		        ('lines.append(f"- **Description:** {description}")', 'lines.append(f"- **说明：** {description}")'),
		        ('lines.append(f"- **Content:** {len(content):,} chars loaded into agent context")', 'lines.append(f"- **内容：** {len(content):,} 个字符已加入 Agent 上下文")'),
		        ('lines.append(f"- **Linked files:** {linked_count}")', 'lines.append(f"- **关联文件：** {linked_count}")'),
		        ('lines.extend(["", "**Sections**"])', 'lines.extend(["", "**章节**"])'),
		        ('"_Full skill content is available to the agent but hidden here to keep ACP readable._"', '"_完整技能内容已提供给 Agent，这里隐藏以保持 ACP 界面简洁。_"'),
		        ('status = "✅ Skill updated" if success is not False else "✗ Skill update failed"', 'status = "✅ 技能已更新" if success is not False else "✗ 技能更新失败"'),
		        ('lines = [f"**{status}**", "", f"- **Action:** `{action}`", f"- **Skill:** `{name}`"]', 'lines = [f"**{status}**", "", f"- **操作：** `{action}`", f"- **技能：** `{name}`"]'),
		        ('lines.append(f"- **File:** `{file_path}`")', 'lines.append(f"- **文件：** `{file_path}`")'),
		        ('lines.append(f"- **Result:** {message}")', 'lines.append(f"- **结果：** {message}")'),
		        ('lines.append(f"- **Replacements:** {replacements}")', 'lines.append(f"- **替换数量：** {replacements}")'),
		        ('lines.append(f"- **Path:** `{path}`")', 'lines.append(f"- **路径：** `{path}`")'),
		        ('lines = [f"Web results: {len(web)}"]', 'lines = [f"网页结果：{len(web)}"]'),
		        ('return f"Web extract failed: {data.get(\\\'error\\\')}"', 'return f"网页提取失败：{data.get(\\\'error\\\')}"'),
		        ('title = str(item.get("title") or url or "Untitled").strip()', 'title = str(item.get("title") or url or "未命名").strip()'),
		        ('f"\\n  Error: {_truncate_text(error, limit=500)}"', 'f"\\n  错误：{_truncate_text(error, limit=500)}"'),
		        ('lines = [f"Web extract failed for {len(failures)} URL{\\\'s\\\' if len(failures) != 1 else \\\'\\\'}"]', 'lines = [f"{len(failures)} 个 URL 网页提取失败"]'),
		        ('return f"Process error: {data.get(\\\'error\\\')}"', 'return f"进程错误：{data.get(\\\'error\\\')}"'),
		        ('lines = [f"Processes: {len(processes)}"]', 'lines = [f"进程：{len(processes)} 个"]'),
		        ('if len(processes) > 20:\n            lines.append(f"... {len(processes) - 20} more process(es)")', 'if len(processes) > 20:\n            lines.append(f"... 另有 {len(processes) - 20} 个进程")'),
		        ('lines = [f"Process {action}: {status}" + (f" (`{sid}`)" if sid else "")]', 'lines = [f"进程 {action}：{status}" + (f" (`{sid}`)" if sid else "")]'),
		        ('("command", "Command"), ("pid", "PID"), ("exit_code", "Exit code"), ("returncode", "Exit code"), ("lines", "Lines")', '("command", "命令"), ("pid", "PID"), ("exit_code", "退出码"), ("returncode", "退出码"), ("lines", "行数")'),
		        ('lines.extend(["", "Output:", _truncate_text(str(output), limit=5000)])', 'lines.extend(["", "输出：", _truncate_text(str(output), limit=5000)])'),
		        ('lines.extend(["", "Error:", _truncate_text(str(error), limit=2000)])', 'lines.extend(["", "错误：", _truncate_text(str(error), limit=2000)])'),
		        ('return f"Delegation failed: {data.get(\\\'error\\\')}"', 'return f"委派失败：{data.get(\\\'error\\\')}"'),
		        ('lines = [f"Delegation results: {len(results)} task{\\\'s\\\' if len(results) != 1 else \\\'\\\'}" + (f" in {total}s" if total is not None else "")]', 'lines = [f"委派结果：{len(results)} 个任务" + (f"，用时 {total}s" if total is not None else "")]'),
		        ('header = f"{icon.get(status, \\\'•\\\')} Task {idx + 1 if isinstance(idx, int) else \\\'?\\\'}: {status}"', 'header = f"{icon.get(status, \\\'•\\\')} 任务 {idx + 1 if isinstance(idx, int) else \\\'?\\\'}：{status}"'),
		        ('bits.append(f"role={role}")', 'bits.append(f"角色={role}")'),
		        ('lines.append("Error: " + _truncate_text(error, limit=800))', 'lines.append("错误：" + _truncate_text(error, limit=800))'),
		        ('lines.append("Tools: " + ", ".join(names[:12]) + (f" (+{len(names)-12})" if len(names) > 12 else ""))', 'lines.append("工具：" + ", ".join(names[:12]) + (f"（另 {len(names)-12} 个）" if len(names) > 12 else ""))'),
		        ('return f"Session search failed: {data.get(\\\'error\\\', \\\'unknown error\\\')}"', 'return f"会话搜索失败：{data.get(\\\'error\\\', \\\'未知错误\\\')}"'),
		        ('lines = ["Recent sessions" if mode == "recent" else f"Session search results" + (f" for `{query}`" if query else "")]', 'lines = ["最近会话" if mode == "recent" else f"会话搜索结果" + (f"：`{query}`" if query else "")]'),
		        ('lines.append(str(data.get("message") or "No matching sessions found."))', 'lines.append(str(data.get("message") or "没有找到匹配会话。"))'),
		        ('title = str(item.get("title") or item.get("when") or "Untitled session").strip()', 'title = str(item.get("title") or item.get("when") or "未命名会话").strip()'),
		        ('f"{count} msgs" if count is not None else ""', 'f"{count} 条消息" if count is not None else ""'),
		        ('lines = [f"✗ Memory {action} failed ({target})", str(data.get("error") or "unknown error")]', 'lines = [f"✗ 记忆 {action} 失败（{target}）", str(data.get("error") or "未知错误")]'),
		        ('lines.append("Matches:")', 'lines.append("匹配项：")'),
		        ('lines = [f"✅ Memory {action} saved ({target})"]', 'lines = [f"✅ 记忆 {action} 已保存（{target}）"]'),
		        ('lines.append(f"Entries: {data.get(\\\'entry_count\\\')}")', 'lines.append(f"条目：{data.get(\\\'entry_count\\\')}")'),
		        ('lines.append(f"Usage: {data.get(\\\'usage\\\')}")', 'lines.append(f"用量：{data.get(\\\'usage\\\')}")'),
		        ('lines.append("Preview: " + _truncate_text(preview, limit=300))', 'lines.append("预览：" + _truncate_text(preview, limit=300))'),
		        ('return f"{tool_name} failed for {path}: {data.get(\\\'error\\\', \\\'unknown error\\\')}"', 'return f"{tool_name} 对 {path} 执行失败：{data.get(\\\'error\\\', \\\'未知错误\\\')}"'),
		        ('lines = [f"✅ {tool_name} completed" + (f" for `{path}`" if path else "")]', 'lines = [f"✅ {tool_name} 已完成" + (f"：`{path}`" if path else "")]'),
		        ('lines.append(f"Replacements: {replacements}")', 'lines.append(f"替换数量：{replacements}")'),
		        ('lines.append("Files: " + ", ".join(f"`{f}`" for f in files[:8]))', 'lines.append("文件：" + ", ".join(f"`{f}`" for f in files[:8]))'),
		        ('return f"✅ {tool_name} completed" + (f" for `{path}`" if path else "")', 'return f"✅ {tool_name} 已完成" + (f"：`{path}`" if path else "")'),
		        ('return f"{tool_name} failed: {data.get(\\\'error\\\', \\\'unknown error\\\')}"', 'return f"{tool_name} 失败：{data.get(\\\'error\\\', \\\'未知错误\\\')}"'),
		        ('lines = [f"Images found: {len(images)}"]', 'lines = [f"找到图片：{len(images)} 张"]'),
		        ('return f"read: {args.get(\'path\', \'?\')}"', 'return f"读取：{args.get(\'path\', \'?\')}"'),
		        ('return f"write: {args.get(\'path\', \'?\')}"', 'return f"写入：{args.get(\'path\', \'?\')}"'),
		        ('return f"search: {args.get(\'pattern\', \'?\')}"', 'return f"搜索：{args.get(\'pattern\', \'?\')}"'),
		        ('return f"web search: {args.get(\'query\', \'?\')}"', 'return f"网页搜索：{args.get(\'query\', \'?\')}"'),
		        ('return f"navigate: {args.get(\'url\', \'?\')}"', 'return f"打开：{args.get(\'url\', \'?\')}"'),
		        ('return f"browser vision: {str(args.get(\'question\', \'?\'))[:50]}"', 'return f"浏览器视觉：{str(args.get(\'question\', \'?\'))[:50]}"'),
		        ('return f"analyze image: {str(args.get(\'question\', \'?\'))[:50]}"', 'return f"分析图片：{str(args.get(\'question\', \'?\'))[:50]}"'),
		        ('return f"todo ({len(items)} item{\'s\' if len(items) != 1 else \'\'})"', 'return f"待办（{len(items)} 项）"'),
		        ('return f"Read failed: {data.get(\'error\')}"', 'return f"读取失败：{data.get(\'error\')}"'),
		        ('return f"Skill view failed: {data.get(\'error\', \'unknown error\')}"', 'return f"技能查看失败：{data.get(\'error\', \'未知错误\')}"'),
		        ('return f"Web extract failed: {data.get(\'error\')}"', 'return f"网页提取失败：{data.get(\'error\')}"'),
		        ('return f"Process error: {data.get(\'error\')}"', 'return f"进程错误：{data.get(\'error\')}"'),
		        ('return f"Delegation failed: {data.get(\'error\')}"', 'return f"委派失败：{data.get(\'error\')}"'),
		        ('return f"Session search failed: {data.get(\'error\', \'unknown error\')}"', 'return f"会话搜索失败：{data.get(\'error\', \'未知错误\')}"'),
		        ('return f"{tool_name} failed for {path}: {data.get(\'error\', \'unknown error\')}"', 'return f"{tool_name} 对 {path} 执行失败：{data.get(\'error\', \'未知错误\')}"'),
		        ('return f"{tool_name} failed: {data.get(\'error\', \'unknown error\')}"', 'return f"{tool_name} 失败：{data.get(\'error\', \'未知错误\')}"'),
		    ],
		    "hermes_cli/skills_hub.py": [
		        ('[bold]Searching registries...', '[bold]正在搜索注册源...'),
		        ('[dim]No skills found matching your query.[/]\\n', '[dim]没有找到匹配的技能。[/]\\n'),
		        ('Skills Hub — {len(results)} result(s)', '技能中心 — {len(results)} 个结果'),
		        ('table.add_column("Name", style="bold cyan")', 'table.add_column("名称", style="bold cyan")'),
		        ('table.add_column("Description", max_width=60)', 'table.add_column("说明", max_width=60)'),
		        ('table.add_column("Source", style="dim")', 'table.add_column("来源", style="dim")'),
		        ('table.add_column("Name", style="bold cyan", max_width=25)', 'table.add_column("名称", style="bold cyan", max_width=25)'),
		        ('table.add_column("Source", style="dim", width=12)', 'table.add_column("来源", style="dim", width=12)'),
		        ('table.add_column("Trust", style="dim")', 'table.add_column("可信度", style="dim")'),
		        ('table.add_column("Identifier", style="dim")', 'table.add_column("标识", style="dim")'),
		        ('"official" if r.source == "official" else r.trust_level', '"官方" if r.source == "official" else r.trust_level'),
		        ('"★ official" if r.source == "official" else r.trust_level', '"★ 官方" if r.source == "official" else r.trust_level'),
		        ('f"[cyan]--page {page - 1}[/] ← prev"', 'f"[cyan]--page {page - 1}[/] ← 上一页"'),
		        ('f"[cyan]--page {page + 1}[/] → next"', 'f"[cyan]--page {page + 1}[/] → 下一页"'),
		        ('Sources: {\', \'.join(parts)}', '来源：{\', \'.join(parts)}'),
		        ('⚡ Slow sources skipped: {\', \'.join(timed_out)} "', '⚡ 已跳过响应慢的来源：{\', \'.join(timed_out)} "'),
		        ('— run again for cached results', '— 再运行一次可使用缓存结果'),
		        ("[dim]Tip: 'hermes skills search <query>' searches deeper across all registries[/]\\n", "[dim]提示：'hermes skills search <query>' 会更深入搜索全部注册源[/]\\n"),
		        ('[dim]Use: hermes skills inspect <identifier> to preview, ', '[dim]用法：hermes skills inspect <标识> 预览，'),
		        ('hermes skills install <identifier> to install[/]\\n', 'hermes skills install <标识> 安装[/]\\n'),
		        ('[bold]Fetching skills from registries...', '[bold]正在从注册源获取技能...'),
		        ('[dim]No skills found in the Skills Hub.[/]\\n', '[dim]技能中心没有可用技能。[/]\\n'),
		        ('"— all sources"', '"— 全部来源"'),
		        ('loaded_label = f"{total} skills loaded"', 'loaded_label = f"已加载 {total} 个技能"'),
		        ('loaded_label += f", {len(timed_out)} source(s) still loading"', 'loaded_label += f"，{len(timed_out)} 个来源仍在加载"'),
		        ('Skills Hub — Browse {source_label}', '技能中心 — 浏览 {source_label}'),
		        ('page {page}/{total_pages}', '第 {page}/{total_pages} 页'),
		        ('official optional skill(s) from Nous Research', '个 Nous Research 官方可选技能'),
		        ('table.add_column("Description", max_width=50)', 'table.add_column("说明", max_width=50)'),
		        ('table.add_column("Trust", width=10)', 'table.add_column("可信度", width=10)'),
		        ('Unknown action:', '未知操作：'),
		        ('[bold]Skills Hub Commands:[/]\\n\\n', '[bold]技能中心命令：[/]\\n\\n'),
		        ('Browse all available skills (paginated)', '分页浏览全部可用技能'),
		        ('Search registries for skills', '搜索技能注册源'),
		        ('Install a skill (with security scan)', '安装技能（含安全扫描）'),
		        ('Preview a skill without installing', '预览技能，不安装'),
		        ("List installed skills; --enabled-only filters to the active profile's live set", '列出已安装技能；--enabled-only 过滤为当前配置中启用的技能'),
		        ('Check hub skills for upstream updates', '检查技能中心的上游更新'),
		        ('Update hub skills with upstream changes', '按上游变更更新技能'),
		        ('Re-scan hub skills for security', '重新安全扫描技能'),
		        ('Remove a hub-installed skill', '移除通过技能中心安装的技能'),
		        ("Reset bundled-skill tracking (fix 'user-modified' flag)", "重置内置技能跟踪状态（修复 'user-modified' 标记）"),
		        ('Publish a skill to GitHub via PR', '通过 PR 发布技能到 GitHub'),
		        ('Submitting the `{skill_name}` skill via Hermes Skills Hub.', '通过 Hermes 技能中心提交 `{skill_name}` 技能。'),
		    ],
			    "hermes_cli/status.py": [
			        ('except Auth错误：', 'except AuthError:'),
			        ('except Auth错误:', 'except AuthError:'),
			        ('⚕ Hermes Agent Status', '♞ 爱马仕机器人状态'),
			        ('◆ Environment', '◆ 环境'),
			        ('  Project:      {PROJECT_ROOT}', '  项目：        {PROJECT_ROOT}'),
			        ("  Python:       {sys.version.split()[0]}", "  Python：      {sys.version.split()[0]}"),
			        ('  .env file:    {check_mark(env_path.exists())} {\'exists\' if env_path.exists() else \'not found\'}', '  .env 文件：   {check_mark(env_path.exists())} {\'存在\' if env_path.exists() else \'未找到\'}'),
			        ('  Model:        {_configured_model_label(config)}', '  模型：        {_configured_model_label(config)}'),
			        ('  Provider:     {_effective_provider_label()}', '  模型服务：    {_effective_provider_label()}'),
			        ('◆ API Keys', '◆ API 密钥'),
			        ('◆ Auth Providers', '◆ 授权服务'),
				        ("not logged in (run: hermes auth add nous --type oauth)", "未登录（运行：hermes auth add nous --type oauth）"),
				        ("not logged in (run: hermes model)", "未登录（运行：hermes model）"),
				        ("not logged in (run: qwen auth qwen-oauth)", "未登录（运行：qwen auth qwen-oauth）"),
				        ("not logged in (run: hermes auth add minimax-oauth)", "未登录（运行：hermes auth add minimax-oauth）"),
				        ("logged in", "已登录"),
			        ('Portal URL:', '门户地址：'),
			        ('Access exp:', '访问过期：'),
			        ('Key exp:', '密钥过期：'),
			        ('Refresh:', '刷新：'),
				        ('print(f"    Error:      {nous_error}")', 'print(f"    错误：      {nous_error}")'),
				        ('print(f"    Error:      {codex_status.get(\'error\')}")', 'print(f"    错误：      {codex_status.get(\'error\')}")'),
				        ('print(f"    Error:      {qwen_status.get(\'error\')}")', 'print(f"    错误：      {qwen_status.get(\'error\')}")'),
				        ('print(f"    Error:      {minimax_status.get(\'error\')}")', 'print(f"    错误：      {minimax_status.get(\'error\')}")'),
			        ('Region:', '区域：'),
			        ('◆ Nous Tool Gateway', '◆ Nous 工具网关'),
			        ('  Nous Portal   ✗ not logged in', '  Nous Portal   ✗ 未登录'),
			        ('  Nous Portal   ✓ managed tools available', '  Nous Portal   ✓ 托管工具可用'),
			        ('active via Nous subscription', '通过 Nous 订阅启用'),
			        ('configured provider', '已配置模型服务'),
			        ('included by subscription, not currently selected', '订阅已包含，当前未选择'),
			        ('available via subscription (optional)', '订阅可用（可选）'),
			        ('  Your free-tier Nous account does not include Tool Gateway access.', '  当前 Nous 免费账户不包含 Tool Gateway 权限。'),
			        ('  Upgrade your subscription to unlock managed web, image, TTS, and browser tools.', '  升级订阅后可使用托管网页、图片、TTS 和浏览器工具。'),
			        ('  Upgrade:', '  升级：'),
			        ('◆ API-Key Providers', '◆ API-Key 模型服务'),
				        ('label = "configured" if configured else "not configured (run: hermes model)"', 'label = "已配置" if configured else "未配置（运行：hermes model）"'),
			        ('unreachable at', '无法连接：'),
			        ('reachable (', '可连接（'),
			        ('model(s)) at', '个模型）地址：'),
			        ('auth rejected — set LM_API_KEY', '授权被拒绝，请设置 LM_API_KEY'),
			        ('◆ Terminal Backend', '◆ 终端后端'),
			        ('  Backend:', '  后端：'),
			        ('  SSH Host:', '  SSH 主机：'),
			        ('  SSH User:', '  SSH 用户：'),
			        ('  Docker Image:', '  Docker 镜像：'),
			        ('  Daytona Image:', '  Daytona 镜像：'),
			        ('  Runtime:', '  运行时：'),
			        ('  SDK:', '  SDK：'),
			        ('  Auth:', '  授权：'),
			        ('  Auth detail:', '  授权详情：'),
			        ('  Persistence:', '  持久化：'),
			        ('snapshot filesystem', '快照文件系统'),
			        ('ephemeral filesystem', '临时文件系统'),
			        ('  Processes:    live processes do not survive cleanup, snapshots, or sandbox recreation', '  进程：        清理、快照或沙盒重建后实时进程不会保留'),
				        ('print(f"  Sudo:         {check_mark(bool(sudo_password))} {\'enabled\' if sudo_password else \'disabled\'}")', 'print(f"  Sudo：        {check_mark(bool(sudo_password))} {\'已启用\' if sudo_password else \'已禁用\'}")'),
			        ('◆ Messaging Platforms', '◆ 消息平台'),
			        ('◆ Gateway Service', '◆ 网关服务'),
			        ("'running' if is_running else 'stopped'", "'运行中' if is_running else '已停止'"),
			        ('  Manager:', '  管理器：'),
			        ('  PID(s):', '  PID：'),
			        ('  Service:      installed but not managing the current running gateway', '  服务：        已安装，但未管理当前运行的网关'),
			        ('  Start with:   hermes gateway', '  启动命令：    hermes gateway'),
			        ('  Note:         Android may stop background jobs when Termux is suspended', '  提示：        Termux 暂停时 Android 可能停止后台任务'),
			        ('  Service:      installed but stopped', '  服务：        已安装但已停止'),
			        ('  Manager:      Termux / manual process', '  管理器：      Termux / 手动进程'),
			        ('  Manager:      systemd/manual', '  管理器：      systemd/手动'),
			        ('  Manager:      launchd', '  管理器：      launchd'),
			        ('  Manager:      (not supported on this platform)', '  管理器：      （当前平台不支持）'),
			        ('◆ Scheduled Jobs', '◆ 定时任务'),
				        ('print(f"  Jobs:         {len(enabled_jobs)} active, {len(jobs)} total")', 'print(f"  任务：        {len(enabled_jobs)} 个活跃，{len(jobs)} 个总计")'),
				        ('print("  Jobs:         (error reading jobs file)")', 'print("  任务：        （读取任务文件出错）")'),
				        ('print("  Jobs:         0")', 'print("  任务：        0")'),
			        ('(error reading jobs file)', '（读取任务文件出错）'),
			        ('◆ Sessions', '◆ 会话'),
				        ('print(f"  Active:       {len(data)} session(s)")', 'print(f"  活跃：        {len(data)} 个会话")'),
				        ('print("  Active:       (error reading sessions file)")', 'print("  活跃：        （读取会话文件出错）")'),
				        ('print("  Active:       0")', 'print("  活跃：        0")'),
			        ('◆ Deep Checks', '◆ 深度检查'),
				        ('print(f"  OpenRouter:   {check_mark(ok)} {\'reachable\' if ok else f\'error ({response.status_code})\'}")', 'print(f"  OpenRouter：  {check_mark(ok)} {\'可连接\' if ok else f\'错误（{response.status_code}）\'}")'),
				        ('print(f"  OpenRouter:   {check_mark(False)} error: {e}")', 'print(f"  OpenRouter：  {check_mark(False)} 错误：{e}")'),
				        ('print(f"  Port 18789:   {\'in use\' if port_in_use else \'available\'}")', 'print(f"  端口 18789：  {\'使用中\' if port_in_use else \'可用\'}")'),
			        ("  Run 'hermes doctor' for detailed diagnostics", "  运行 'hermes doctor' 查看详细诊断"),
			        ("  Run 'hermes setup' to configure", "  运行 'hermes setup' 进行配置"),
			        ('(unknown)', '(未知)'),
			        ('(not set)', '(未设置)'),
			    ],
			    "hermes_cli/doctor.py": [
			        ('Run \'hermes setup\' to configure missing API keys for full tool access', '运行 hermes setup 配置缺失的 API 密钥，以启用完整工具能力'),
			        ('Could not check tool availability', '无法检查工具可用性'),
			        ('◆ Skills Hub', '◆ 技能中心'),
			        ('Skills Hub directory exists', '技能中心目录存在'),
			        ('Lock file OK ({count} hub-installed skill(s))', '锁文件正常（{count} 个通过技能中心安装的技能）'),
			        ('Lock file", "(corrupted or unreadable)', '锁文件", "（损坏或无法读取）'),
			        ('skill(s) in quarantine", "(pending review)', '个技能在隔离区", "（待审核）'),
			        ('Skills Hub directory not initialized', '技能中心目录未初始化'),
			        ('(run: hermes skills list)', '（运行：hermes skills list）'),
			    ],
			    "hermes_cli/setup.py": [
			        ('⚕ Hermes Setup — Non-interactive mode', '♞ 爱马仕机器人配置 — 非交互模式'),
			        ('Browser Automation', '浏览器自动化'),
			        ('Local browser', '本地浏览器'),
			        ('Skills Hub (GitHub)', '技能中心（GitHub）'),
			        ('Terminal/Commands', '终端/命令'),
			        ('📁 All your files are in {_dhh()}/:', '📁 所有文件位于 {_dhh()}/：'),
			        ('Settings:', '设置：'),
			        ('API Keys:', 'API 密钥：'),
			        ('📝 To edit your configuration:', '📝 修改配置：'),
			        ('Re-run the full wizard', '重新运行完整向导'),
			        ('Change model/provider', '更改模型/模型服务'),
			        ('Change terminal backend', '更改终端后端'),
			        ('Configure messaging', '配置消息服务'),
			        ('Configure tool providers', '配置工具服务'),
			        ('View current settings', '查看当前设置'),
			        ('Set a specific value', '设置指定值'),
			        ('Or edit the files directly:', '也可以直接编辑文件：'),
			        ('🚀 Ready to go!', '🚀 已准备好！'),
			        ('Start chatting', '开始对话'),
			        ('Start messaging gateway', '启动消息网关'),
			        ('Check for issues', '检查问题'),
			        ('Inference Provider', '推理模型服务'),
			        ('Provider setup skipped.', '已跳过模型服务配置。'),
			        ('Provider setup encountered an error:', '模型服务配置出错：'),
			        ('Same-Provider Fallback & Rotation', '同模型服务备用与轮换'),
			        ('Provider pool now has {entry_count} credential(s).', '模型服务凭据池现在有 {entry_count} 个凭据。'),
			        ('Text-to-Speech Provider (optional)', '文本转语音服务（可选）'),
			        ('Model & Provider', '模型与模型服务'),
			        ('Available sections:', '可用配置项：'),
			        ('⚕ Hermes Setup — {label:<34s}', '♞ 爱马仕机器人配置 — {label:<34s}'),
			        ('Would import:', '将导入：'),
			        ('Would overwrite (conflicts with existing Hermes config):', '将覆盖（与现有 Hermes 配置冲突）：'),
			        ('Would skip:', '将跳过：'),
			        ('── Warnings ──', '── 警告 ──'),
			        ('Note: OpenClaw config values may have different semantics in Hermes.', '提示：OpenClaw 配置值在 Hermes 中可能语义不同。'),
			        ('For example, OpenClaw\\\'s tool_call_execution: "auto" ≠ Hermes\\\'s yolo mode.', '例如，OpenClaw 的 tool_call_execution: "auto" 不等于 Hermes 的 yolo 模式。'),
			        ('Instruction files (.md) from OpenClaw may contain incompatible procedures.', 'OpenClaw 的说明文件（.md）可能包含不兼容流程。'),
			    ],
			    "hermes_cli/config.py": [
			        ('GitHub token for Skills Hub (higher API rate limits, skill publish)', '技能中心使用的 GitHub token（提高 API 额度，用于技能发布）'),
			        ('print("Available commands:")', 'print("可用命令：")'),
			        ('print(f"  Model:        {config.get(\'model\', \'not set\')}")', 'print(f"  模型：        {config.get(\'model\', \'未设置\')}")'),
			        ('print(f"  Model:        {_sm}")', 'print(f"  模型：        {_sm}")'),
			        ('print(f"  Provider:     {comp_provider}")', 'print(f"  模型服务：    {comp_provider}")'),
			    ],
			    "hermes_cli/auth.py": [
			        ('print("  1. Open this URL in your browser:")', 'print("  1. 在浏览器中打开这个地址：")'),
			    ],
			    "hermes_cli/copilot_auth.py": [
			        ('print(f"  Open this URL in your browser: {verification_uri}")', 'print(f"  在浏览器中打开这个地址：{verification_uri}")'),
			    ],
			    "hermes_cli/main.py": [
		        ('_curses_prompt_choice("Select provider:", choices, default)', '_curses_prompt_choice("选择模型服务：", choices, default)'),
		        ('print("Select provider:")', 'print("选择模型服务：")'),
		        ('title="Select provider to remove:"', 'title="选择要移除的模型服务："'),
		        ('print(f"Hermes Agent v{__version__} ({__release_date__})")', 'print(f"爱马仕机器人 v{__version__} ({__release_date__})")'),
		        ('print("\\n  ✓ Memory provider: built-in only")', 'print("\\n  ✓ 记忆服务：仅使用内置记忆")'),
		        ('print("  Saved to config.yaml\\n")', 'print("  已保存到 config.yaml\\n")'),
		        ('# Select provider and model', '# 选择模型服务和模型'),
		    ],
		    "hermes_cli/tools_config.py": [
		        ('_prompt_choice("  Select provider:", provider_choices, default_idx)', '_prompt_choice("  选择模型服务：", provider_choices, default_idx)'),
		    ],
		    "agent/insights.py": [
		        ('Tool calls:', '工具调用：'),
		        ('User messages:', '用户消息：'),
		        ('**Sessions:**', '**会话数：**'),
		        ('**Messages:**', '**消息数：**'),
		    ],
		    "agent/context_compressor.py": [
		        ('[Tool calls:\\n', '[工具调用：\\n'),
		    ],
		}

deep_replacements = {
    "hermes_cli/commands.py": [
        ('"Background skill maintenance (status, run, pin, archive)"', '"后台技能维护（状态、运行、固定、归档）"'),
    ],
    "tui_gateway/server.py": [
        ("return f\"No API key configured for provider '{provider}'. First message will fail.\"", "return f\"模型服务 '{provider}' 未配置 API Key，第一条消息会失败。\""),
        ('raise ValueError(f"Invalid checkpoint number. Use 1-{len(checkpoints)}.")', 'raise ValueError(f"检查点编号无效。请输入 1-{len(checkpoints)}。")'),
        ('return "bare `hermes` is interactive — use `/hermes chat -q …` or run `hermes` in another terminal"', 'return "直接运行 `hermes` 需要交互终端；请用 `/hermes chat -q …`，或在另一个终端运行 `hermes`"'),
        ('return "`hermes setup` needs a full terminal — run it outside the TUI"', 'return "`hermes setup` 需要完整终端，请在 TUI 外运行"'),
        ('return "`hermes sessions browse` is interactive — use /resume here, or run browse in another terminal"', 'return "`hermes sessions browse` 需要交互终端；这里请用 /resume，或在另一个终端浏览会话"'),
        ('return "`hermes config edit` needs $EDITOR in a real terminal"', 'return "`hermes config edit` 需要真实终端里的 $EDITOR"'),
        ('raise ValueError(result.error_message or "model switch failed")', 'raise ValueError(result.error_message or "模型切换失败")'),
    ],
    "gateway/sticker_cache.py": [
        ('return f"[The user sent a sticker{context}~ It shows: \\"{description}\\" (=^.w.^=)]"', 'return f"[用户发送了一个贴纸{context}。画面内容：\\"{description}\\" (=^.w.^=)]"'),
        ('f"[The user sent an animated sticker {emoji}~ "\n            f"I can\\\'t see animated ones yet, but the emoji suggests: {emoji}]"', 'f"[用户发送了一个动态贴纸 {emoji}。我暂时无法查看动态贴纸，但 emoji 可能表示：{emoji}]"'),
        ('return "[The user sent an animated sticker~ I can\\\'t see animated ones yet]"', 'return "[用户发送了一个动态贴纸。我暂时无法查看动态贴纸]"'),
    ],
    "tools/mcp_oauth.py": [
        ('f"  Open this URL in your browser:\\n\\n"', 'f"  请在浏览器中打开这个地址：\\n\\n"'),
        ('print("  (Browser opened automatically.)\\n", file=sys.stderr)', 'print("  （已自动打开浏览器。）\\n", file=sys.stderr)'),
        ('print("  (Could not open browser — please open the URL manually.)\\n", file=sys.stderr)', 'print("  （无法自动打开浏览器，请手动打开上面的地址。）\\n", file=sys.stderr)'),
        ('print("  (Headless environment detected — open the URL manually.)\\n", file=sys.stderr)', 'print("  （检测到无界面环境，请手动打开上面的地址。）\\n", file=sys.stderr)'),
        ('"OAuth callback port not set — build_oauth_auth must be called "\n            "before _wait_for_oauth_callback"', '"OAuth 回调端口未设置：必须先调用 build_oauth_auth，"\n            "再调用 _wait_for_oauth_callback"'),
        ('"OAuth callback timed out — could not bind callback port. "\n            "Complete the authorization in a browser first, then retry."', '"OAuth 回调超时，无法绑定回调端口。"\n            "请先在浏览器中完成授权，然后重试。"'),
        ('raise RuntimeError(f"OAuth authorization failed: {result[\'error\']}")', 'raise RuntimeError(f"OAuth 授权失败：{result[\'error\']}")'),
        ('"OAuth callback timed out — no authorization code received. "\n            "Ensure you completed the browser authorization flow."', '"OAuth 回调超时，未收到授权码。"\n            "请确认已经在浏览器中完成授权流程。"'),
    ],
    "tools/skills_sync.py": [
        ('print("Syncing bundled skills into ~/.hermes/skills/ ...")', 'print("正在同步内置技能到 ~/.hermes/skills/ ...")'),
        ('f"{len(result[\'copied\'])} new"', 'f"{len(result[\'copied\'])} 个新增"'),
        ('f"{len(result[\'updated\'])} updated"', 'f"{len(result[\'updated\'])} 个更新"'),
        ('f"{result[\'skipped\']} unchanged"', 'f"{result[\'skipped\']} 个未变更"'),
        ('parts.append(f"{len(result[\'user_modified\'])} user-modified (kept)")', 'parts.append(f"{len(result[\'user_modified\'])} 个用户修改项（已保留）")'),
        ('parts.append(f"{len(result[\'cleaned\'])} cleaned from manifest")', 'parts.append(f"{len(result[\'cleaned\'])} 个清单项已清理")'),
        ('print(f"\\nDone: {\', \'.join(parts)}. {result[\'total_bundled\']} total bundled.")', 'print(f"\\n完成：{\', \'.join(parts)}。内置技能共 {result[\'total_bundled\']} 个。")'),
    ],
    "gateway/platforms/feishu.py": [
        ('default_message="image upload failed"', 'default_message="图片上传失败"'),
        ('default_message="file upload failed"', 'default_message="文件上传失败"'),
    ],
    "gateway/platforms/api_server.py": [
        ('{"error": {"message": "Invalid session key", "type": "invalid_request_error"}}', '{"error": {"message": "无效的 session key", "type": "invalid_request_error"}}'),
        ('{"error": {"message": "Invalid session ID", "type": "invalid_request_error"}}', '{"error": {"message": "无效的 session ID", "type": "invalid_request_error"}}'),
        ('"Invalid approval choice; expected one of: once, session, always, deny"', '"无效的确认选项；应为 once、session、always 或 deny"'),
        ('f"Run has no active approval session: {run_id}"', 'f"该运行没有活跃确认会话：{run_id}"'),
        ('"No API key configured. Set API_SERVER_KEY or platforms.api_server.key to prevent "\n                    "unauthorized access to sessions, responses, and cron jobs."', '"未配置 API Key。请设置 API_SERVER_KEY 或 platforms.api_server.key，防止未授权访问会话、响应和定时任务。"'),
    ],
    "gateway/platforms/discord.py": [
        ('return SendResult(success=False, error="Not connected")', 'return SendResult(success=False, error="未连接")'),
        ('title="⚠️ Command Approval Required"', 'title="⚠️ 命令需要确认"'),
        ('embed.add_field(name="Reason", value=description, inline=False)', 'embed.add_field(name="原因", value=description, inline=False)'),
        ('title=title or "Confirm"', 'title=title or "确认"'),
        ('title="⚕ Update Needs Your Input"', 'title="⚕ 更新需要你确认"'),
        ('default_hint = f" (default: {default})" if default else ""', 'default_hint = f"（默认：{default}）" if default else ""'),
        ('description="Run a Hermes skill"', 'description="运行 Hermes 技能"'),
        ('title="⚙ Model Configuration"', 'title="⚙ 模型配置"'),
        ('title="⚙ Switching Model"', 'title="⚙ 正在切换模型"'),
        ('description=f"Switching to `{model_id}`..."', 'description=f"正在切换到 `{model_id}`..."'),
        ('result_text = f"Error switching model: {exc}"', 'result_text = f"切换模型出错：{exc}"'),
        ('title="⚙ Model Switched"', 'title="⚙ 模型已切换"'),
        ('"You\\\'re not authorized~"', '"你没有权限~"'),
        ('f"Current model: `{self.current_model or \'unknown\'}`\\n"', 'f"当前模型：`{self.current_model or \'未知\'}`\\n"'),
        ('f"Provider: {provider_label}\\n\\n"', 'f"模型服务：{provider_label}\\n\\n"'),
        ('f"Select a provider:"', 'f"选择模型服务："'),
        ('description="Model selection cancelled."', 'description="已取消模型选择。"'),
        ('@discord.ui.button(label="Allow Once", style=discord.ButtonStyle.green)', '@discord.ui.button(label="允许一次", style=discord.ButtonStyle.green)'),
        ('@discord.ui.button(label="Allow Session", style=discord.ButtonStyle.grey)', '@discord.ui.button(label="本会话允许", style=discord.ButtonStyle.grey)'),
        ('@discord.ui.button(label="Always Allow", style=discord.ButtonStyle.blurple)', '@discord.ui.button(label="始终允许", style=discord.ButtonStyle.blurple)'),
        ('@discord.ui.button(label="Deny", style=discord.ButtonStyle.red)', '@discord.ui.button(label="拒绝", style=discord.ButtonStyle.red)'),
        ('@discord.ui.button(label="Approve Once", style=discord.ButtonStyle.green)', '@discord.ui.button(label="批准一次", style=discord.ButtonStyle.green)'),
        ('@discord.ui.button(label="Always Approve", style=discord.ButtonStyle.blurple)', '@discord.ui.button(label="始终批准", style=discord.ButtonStyle.blurple)'),
        ('@discord.ui.button(label="Cancel", style=discord.ButtonStyle.red)', '@discord.ui.button(label="取消", style=discord.ButtonStyle.red)'),
        ('await self._resolve(interaction, "once", discord.Color.green(), "Approved once")', 'await self._resolve(interaction, "once", discord.Color.green(), "已批准一次")'),
        ('await self._resolve(interaction, "session", discord.Color.blue(), "Approved for session")', 'await self._resolve(interaction, "session", discord.Color.blue(), "本会话已批准")'),
        ('await self._resolve(interaction, "always", discord.Color.purple(), "Approved permanently")', 'await self._resolve(interaction, "always", discord.Color.purple(), "已永久批准")'),
        ('await self._resolve(interaction, "always", discord.Color.purple(), "Always approved")', 'await self._resolve(interaction, "always", discord.Color.purple(), "已始终批准")'),
    ],
    "run_agent.py": [
        ('raise RuntimeError(f"Failed to initialize OpenAI client: {e}")', 'raise RuntimeError(f"初始化 OpenAI 客户端失败：{e}")'),
        ('logger.info("Memory provider \\\'%s\\\' activated", _mem_provider_name)', 'logger.info("记忆服务 \\\'%s\\\' 已启用", _mem_provider_name)'),
        ('logger.warning("Memory provider plugin init failed: %s", _mpe)', 'logger.warning("记忆服务插件初始化失败：%s", _mpe)'),
        ('return "Unknown error"', 'return "未知错误"'),
        ('return "Service temporarily unavailable (HTML error page returned)"', 'return "服务暂时不可用（返回 HTML 错误页）"'),
        ('print("\\n⚡ Interrupt requested" + (f": \'{message[:40]}...\'" if message and len(message) > 40 else f": \'{message}\'" if message else ""))', 'print("\\n⚡ 已请求中断" + (f"：\'{message[:40]}...\'" if message and len(message) > 40 else f"：\'{message}\'" if message else ""))'),
        ('print(f"{self.log_prefix}⚡ Interrupt: skipping {num_tools} tool call(s)")', 'print(f"{self.log_prefix}⚡ 已中断：跳过 {num_tools} 次工具调用")'),
        ('print(f"  ⚡ Concurrent: {num_tools} tool calls — {tool_names_str}")', 'print(f"  ⚡ 并发：{num_tools} 次工具调用 — {tool_names_str}")'),
        ('print(f"{self.log_prefix}⚡ Interrupt: skipping {len(remaining_calls)} tool call(s)", force=True)', 'print(f"{self.log_prefix}⚡ 已中断：跳过 {len(remaining_calls)} 次工具调用", force=True)'),
        ('self._vprint(f"{self.log_prefix}⚡ Interrupt: skipping {remaining} remaining tool call(s)", force=True)', 'self._vprint(f"{self.log_prefix}⚡ 已中断：跳过剩余 {remaining} 次工具调用", force=True)'),
        ('print(f"⚠️  Reached maximum iterations ({self.max_iterations}). Requesting summary...")', 'print(f"⚠️  已达到最大迭代次数（{self.max_iterations}）。正在请求总结...")'),
        ('self._safe_print(f"💬 Starting conversation: \'{_print_preview[:60]}{\'...\' if len(_print_preview) > 60 else \'\'}\'")', 'self._safe_print(f"💬 开始对话：\'{_print_preview[:60]}{\'...\' if len(_print_preview) > 60 else \'\'}\'")'),
        ('return "[A multimodal message was converted to text for Anthropic compatibility.]"', 'return "[为兼容 Anthropic，多模态消息已转换为文本。]"'),
    ],
    "hermes_cli/main.py": [
        ('help="Run Hermes Agent as an ACP (Agent Client Protocol) server"', 'help="以 ACP（Agent Client Protocol）服务方式运行爱马仕机器人"'),
        ('title="Select reasoning effort:"', 'title="选择推理强度："'),
        ('help="Select default model and provider"', 'help="选择默认模型和模型服务"'),
        ('description="Interactively select your inference provider and default model"', 'description="交互式选择推理模型服务和默认模型"'),
        ('help="Messaging gateway management"', 'help="消息网关管理"'),
        ('description="Manage the messaging gateway (Telegram, Discord, WhatsApp)"', 'description="管理消息网关（Telegram、Discord、WhatsApp）"'),
        ('"run", help="Run gateway in foreground (recommended for WSL, Docker, Termux)"', '"run", help="在前台运行网关（推荐用于 WSL、Docker、Termux）"'),
        ('help="Increase stderr log verbosity (-v=INFO, -vv=DEBUG)"', 'help="提高错误日志详细程度（-v=INFO，-vv=DEBUG）"'),
        ('"-q", "--quiet", action="store_true", help="Suppress all stderr log output"', '"-q", "--quiet", action="store_true", help="关闭错误日志输出"'),
        ('help="Replace any existing gateway instance (useful for systemd)"', 'help="替换现有网关实例（适用于 systemd）"'),
        ('"start", help="Start the installed systemd/launchd background service"', '"start", help="启动已安装的 systemd/launchd 后台服务"'),
        ('help="Target the Linux system-level gateway service"', 'help="目标为 Linux 系统级网关服务"'),
        ('help="Kill ALL stale gateway processes across all profiles before starting"', 'help="启动前结束所有配置档里的旧网关进程"'),
        ('gateway_stop = gateway_subparsers.add_parser("stop", help="Stop gateway service")', 'gateway_stop = gateway_subparsers.add_parser("stop", help="停止网关服务")'),
        ('help="Stop ALL gateway processes across all profiles"', 'help="停止所有配置档里的网关进程"'),
        ('"restart", help="Restart gateway service"', '"restart", help="重启网关服务"'),
        ('help="Kill ALL gateway processes across all profiles before restarting"', 'help="重启前结束所有配置档里的网关进程"'),
        ('gateway_status = gateway_subparsers.add_parser("status", help="Show gateway status")', 'gateway_status = gateway_subparsers.add_parser("status", help="查看网关状态")'),
        ('gateway_status.add_argument("--deep", action="store_true", help="Deep status check")', 'gateway_status.add_argument("--deep", action="store_true", help="深度状态检查")'),
        ('help="Show full, untruncated service/log output where supported"', 'help="支持时显示完整服务/日志输出"'),
        ('"install", help="Install gateway as a systemd/launchd background service"', '"install", help="将网关安装为 systemd/launchd 后台服务"'),
        ('gateway_install.add_argument("--force", action="store_true", help="Force reinstall")', 'gateway_install.add_argument("--force", action="store_true", help="强制重新安装")'),
        ('help="Install as a Linux system-level service (starts at boot)"', 'help="安装为 Linux 系统级服务（开机启动）"'),
        ('help="User account the Linux system service should run as"', 'help="Linux 系统服务运行所用用户"'),
        ('"uninstall", help="Uninstall gateway service"', '"uninstall", help="卸载网关服务"'),
        ('gateway_subparsers.add_parser("setup", help="Configure messaging platforms")', 'gateway_subparsers.add_parser("setup", help="配置消息平台")'),
        ('help="Remove legacy hermes.service units from pre-rename installs"', 'help="移除旧安装中遗留的 hermes.service 单元"'),
        ('help="List what would be removed without doing it"', 'help="列出将移除内容，但不执行"'),
        ('help="Skip the confirmation prompt"', 'help="跳过确认提示"'),
        ('help="Interactive setup wizard"', 'help="交互式配置向导"'),
        ('description="Configure Hermes Agent with an interactive wizard. "', 'description="通过交互式向导配置 Hermes Agent。"'),
        ('help="Run a specific setup section instead of the full wizard"', 'help="运行指定配置项，而不是完整向导"'),
        ('help="Non-interactive mode (use defaults/env vars)"', 'help="非交互模式（使用默认值/环境变量）"'),
        ('"--reset", action="store_true", help="Reset configuration to defaults"', '"--reset", action="store_true", help="将配置重置为默认值"'),
        ('help="Set up WhatsApp integration"', 'help="设置 WhatsApp 集成"'),
        ('description="Configure WhatsApp and pair via QR code"', 'description="配置 WhatsApp，并通过二维码配对"'),
        ('help="Authenticate with an inference provider"', 'help="登录推理模型服务"'),
        ('description="Run OAuth device authorization flow for Hermes CLI"', 'description="为 Hermes CLI 运行 OAuth 设备授权流程"'),
        ('help="Provider to authenticate with (default: nous)"', 'help="要登录的模型服务（默认：nous）"'),
        ('help="Do not attempt to open the browser automatically"', 'help="不要自动打开浏览器"'),
        ('help="HTTP request timeout in seconds (default: 15)"', 'help="HTTP 请求超时时间，单位秒（默认：15）"'),
        ('"--ca-bundle", help="Path to CA bundle PEM file for TLS verification"', '"--ca-bundle", help="用于 TLS 验证的 CA bundle PEM 文件路径"'),
        ('help="Disable TLS verification (testing only)"', 'help="关闭 TLS 验证（仅测试使用）"'),
        ('help="Show status of all components"', 'help="查看所有组件状态"'),
        ('description="Display status of Hermes Agent components"', 'description="显示 Hermes Agent 组件状态"'),
        ('"--all", action="store_true", help="Show all details (redacted for sharing)"', '"--all", action="store_true", help="显示全部详情（分享时会脱敏）"'),
        ('"--deep", action="store_true", help="Run deep checks (may take longer)"', '"--deep", action="store_true", help="运行深度检查（可能更耗时）"'),
        ('"cron", help="Cron job management", description="Manage scheduled tasks"', '"cron", help="定时任务管理", description="管理定时任务"'),
        ('cron_list = cron_subparsers.add_parser("list", help="List scheduled jobs")', 'cron_list = cron_subparsers.add_parser("list", help="列出定时任务")'),
        ('cron_list.add_argument("--all", action="store_true", help="Include disabled jobs")', 'cron_list.add_argument("--all", action="store_true", help="包含已禁用任务")'),
        ('"create", aliases=["add"], help="Create a scheduled job"', '"create", aliases=["add"], help="创建定时任务"'),
        ('"edit", help="Edit an existing scheduled job"', '"edit", help="编辑已有定时任务"'),
        ('help="Pause a scheduled job"', 'help="暂停定时任务"'),
        ('help="Resume a paused job"', 'help="恢复已暂停任务"'),
        ('"run", help="Run a job on the next scheduler tick"', '"run", help="在下一次调度时运行任务"'),
        ('"remove", aliases=["rm", "delete"], help="Remove a scheduled job"', '"remove", aliases=["rm", "delete"], help="移除定时任务"'),
        ('cron_subparsers.add_parser("status", help="Check if cron scheduler is running")', 'cron_subparsers.add_parser("status", help="检查定时任务调度器是否运行")'),
        ('cron_tick = cron_subparsers.add_parser("tick", help="Run due jobs once and exit")', 'cron_tick = cron_subparsers.add_parser("tick", help="运行一次到期任务后退出")'),
    ],
    "hermes_cli/curator.py": [
        ('help="Show curator status and skill stats"', 'help="查看技能维护状态和技能统计"'),
        ('help="Trigger a curator review now"', 'help="立即触发一次技能维护检查"'),
        ('help="Wait for the LLM review pass to finish (default: background thread)"', 'help="等待 LLM 检查完成（默认在后台线程执行）"'),
        ('help="Pause the curator until resumed"', 'help="暂停技能维护，直到恢复"'),
        ('help="Resume a paused curator"', 'help="恢复已暂停的技能维护"'),
        ('help="Pin a skill so the curator never auto-transitions it"', 'help="固定技能，使维护器不自动改变它"'),
        ('help="Skill name"', 'help="技能名称"'),
        ('help="Restore an archived skill"', 'help="恢复已归档技能"'),
        ('help="List available snapshots and exit without restoring"', 'help="列出可用快照，不执行恢复"'),
        ('help="Skip confirmation prompt"', 'help="跳过确认提示"'),
    ],
    "gateway/platforms/slack.py": [
        ('f":warning: *Command Approval Required*\\n"', 'f":warning: *命令需要确认*\\n"'),
        ('f"Reason: {description}"', 'f"原因：{description}"'),
        ('"text": {"type": "plain_text", "text": "Allow Once"}', '"text": {"type": "plain_text", "text": "允许一次"}'),
        ('"text": {"type": "plain_text", "text": "Allow Session"}', '"text": {"type": "plain_text", "text": "本会话允许"}'),
        ('"text": {"type": "plain_text", "text": "Always Allow"}', '"text": {"type": "plain_text", "text": "始终允许"}'),
        ('"text": {"type": "plain_text", "text": "Deny"}', '"text": {"type": "plain_text", "text": "拒绝"}'),
    ],
    "gateway/platforms/feishu.py": [
        ('default_message="image upload failed"', 'default_message="图片上传失败"'),
        ('default_message="file upload failed"', 'default_message="文件上传失败"'),
        ('"title": {"content": "⚠️ Command Approval Required", "tag": "plain_text"}', '"title": {"content": "⚠️ 命令需要确认", "tag": "plain_text"}'),
        ('"content": f"```\\n{cmd_preview}\\n```\\n**Reason:** {description}"', '"content": f"```\\n{cmd_preview}\\n```\\n**原因：** {description}"'),
        ('_btn("✅ Allow Once", "approve_once", "primary")', '_btn("✅ 允许一次", "approve_once", "primary")'),
        ('_btn("✅ Session", "approve_session")', '_btn("✅ 本会话", "approve_session")'),
        ('_btn("✅ Always", "approve_always")', '_btn("✅ 始终允许", "approve_always")'),
        ('_btn("❌ Deny", "deny", "danger")', '_btn("❌ 拒绝", "deny", "danger")'),
    ],
    "gateway/platforms/telegram.py": [
        ('f"⚠️ <b>Command Approval Required</b>\\n\\n"', 'f"⚠️ <b>命令需要确认</b>\\n\\n"'),
        ('f"Reason: {_html.escape(description)}"', 'f"原因：{_html.escape(description)}"'),
        ('InlineKeyboardButton("✅ Allow Once", callback_data=f"ea:once:{approval_id}")', 'InlineKeyboardButton("✅ 允许一次", callback_data=f"ea:once:{approval_id}")'),
        ('InlineKeyboardButton("✅ Session", callback_data=f"ea:session:{approval_id}")', 'InlineKeyboardButton("✅ 本会话", callback_data=f"ea:session:{approval_id}")'),
        ('InlineKeyboardButton("✅ Always", callback_data=f"ea:always:{approval_id}")', 'InlineKeyboardButton("✅ 始终允许", callback_data=f"ea:always:{approval_id}")'),
        ('InlineKeyboardButton("❌ Deny", callback_data=f"ea:deny:{approval_id}")', 'InlineKeyboardButton("❌ 拒绝", callback_data=f"ea:deny:{approval_id}")'),
        ('text="Model selection cancelled."', 'text="已取消模型选择。"'),
    ],
    "hermes_cli/main.py": [
        ('print("→ Syncing bundled skills...")', 'print("→ 正在同步内置技能...")'),
        ('print("→ Syncing bundled skills to other profiles...")', 'print("→ 正在同步内置技能到其他配置档...")'),
        ('print(f"  + {len(result[\'copied\'])} new: {\', \'.join(result[\'copied\'])}")', 'print(f"  + {len(result[\'copied\'])} 个新增：{\', \'.join(result[\'copied\'])}")'),
        ('f"  ↑ {len(result[\'updated\'])} updated: {\', \'.join(result[\'updated\'])}"', 'f"  ↑ {len(result[\'updated\'])} 个更新：{\', \'.join(result[\'updated\'])}"'),
        ('print(f"  ~ {len(result[\'user_modified\'])} user-modified (kept)")', 'print(f"  ~ {len(result[\'user_modified\'])} 个用户修改项（已保留）")'),
        ('print(f"  − {len(result[\'cleaned\'])} removed from manifest")', 'print(f"  − {len(result[\'cleaned\'])} 个清单项已移除")'),
        ('print("  ✓ Skills are up to date")', 'print("  ✓ 技能已是最新")'),
    ],
}

for rel, replacements in deep_replacements.items():
    basic_replacements.setdefault(rel, []).extend(replacements)

basic_replacements.setdefault("hermes_cli/main.py", []).extend([
    ('help="Run Hermes Agent as an ACP (Agent Client Protocol) server",', 'help="以 ACP（Agent Client Protocol）服务方式运行爱马仕机器人",'),
    ('description="Start Hermes Agent in ACP mode for editor integration (VS Code, Zed, JetBrains)",', 'description="以 ACP 模式启动爱马仕机器人，用于编辑器集成（VS Code、Zed、JetBrains）",'),
    ('help="Print Hermes ACP version and exit"', 'help="打印 Hermes ACP 版本后退出"'),
    ('help="Verify ACP dependencies and adapter imports, then exit"', 'help="检查 ACP 依赖和适配器导入后退出"'),
    ('help="Run interactive Hermes provider/model setup for ACP terminal auth"', 'help="为 ACP 终端授权运行 Hermes 模型服务配置"'),
    ('help="Install agent-browser + Playwright Chromium into ~/.hermes/node/ "', 'help="安装浏览器工具所需的 agent-browser 和 Playwright Chromium 到 ~/.hermes/node/ "'),
    ('"for browser tool support (idempotent)."', '"用于浏览器工具支持（可重复运行）。"'),
    ('print("  GitHub Copilot ACP delegates Hermes turns to `copilot --acp`.")', 'print("  GitHub Copilot ACP 会把 Hermes 回合交给 `copilot --acp`。")'),
    ('print("  Hermes currently starts its own ACP subprocess for each request.")', 'print("  Hermes 当前会为每次请求启动独立 ACP 子进程。")'),
    ('print("  Hermes uses your selected model as a hint for the Copilot ACP session.")', 'print("  Hermes 会把你选择的模型作为 Copilot ACP 会话的参考。")'),
    ('print(f"  Command: {resolved_command}")', 'print(f"  命令：{resolved_command}")'),
    ('print(f"  Backend marker: {effective_base}")', 'print(f"  后端标记：{effective_base}")'),
    ('"  Set HERMES_COPILOT_ACP_COMMAND or COPILOT_CLI_PATH if Copilot CLI is installed elsewhere."', '"  如果 Copilot CLI 安装在其他位置，请设置 HERMES_COPILOT_ACP_COMMAND 或 COPILOT_CLI_PATH。"'),
    ('print("ACP dependencies not installed.", file=sys.stderr)', 'print("ACP 依赖尚未安装。", file=sys.stderr)'),
    ('f"  Select model [1-{len(detected_models)}] or type name: "', 'f"  选择模型 [1-{len(detected_models)}] 或输入名称："'),
    ('title=f"Select model from {name}:"', 'title=f"从 {name} 选择模型："'),
    ('print(f"Default model set to: {selected} (via OpenRouter)")', 'print(f"默认模型已设置为：{selected}（通过 OpenRouter）")'),
    ('print(f"Default model set to: {selected} (via Vercel AI Gateway)")', 'print(f"默认模型已设置为：{selected}（通过 Vercel AI Gateway）")'),
    ('print(f"Default model set to: {selected} (via Nous Portal)")', 'print(f"默认模型已设置为：{selected}（通过 Nous Portal）")'),
    ('print(f"Default model set to: {selected} (via OpenAI Codex)")', 'print(f"默认模型已设置为：{selected}（通过 OpenAI Codex）")'),
    ('print(f"Default model set to: {selected} (via xAI Grok OAuth — SuperGrok Subscription)")', 'print(f"默认模型已设置为：{selected}（通过 xAI Grok OAuth / SuperGrok 订阅）")'),
    ('print(f"Default model set to: {selected} (via Qwen OAuth)")', 'print(f"默认模型已设置为：{selected}（通过 Qwen OAuth）")'),
    ('f"Default model set to: {selected} (via Google Gemini OAuth / Code Assist)"', 'f"默认模型已设置为：{selected}（通过 Google Gemini OAuth / Code Assist）"'),
    ('print(f"Default model set to: {model_name} (via {effective_url})")', 'print(f"默认模型已设置为：{model_name}（通过 {effective_url}）")'),
    ('print(f"Default model set to: {selected} (via {pconfig.name})")', 'print(f"默认模型已设置为：{selected}（通过 {pconfig.name}）")'),
    ('print(f"Default model set to: {selected} (via {endpoint_label})")', 'print(f"默认模型已设置为：{selected}（通过 {endpoint_label}）")'),
    ('print(f"  Default model set to: {selected} (via Bedrock API Key, {region})")', 'print(f"  默认模型已设置为：{selected}（通过 Bedrock API Key，{region}）")'),
    ('print(f"  Default model set to: {selected} (via AWS Bedrock, {region})")', 'print(f"  默认模型已设置为：{selected}（通过 AWS Bedrock，{region}）")'),
    ('print(f"Default model set to: {selected} (via Anthropic)")', 'print(f"默认模型已设置为：{selected}（通过 Anthropic）")'),
    ('print("Reasoning disabled for this model.")', 'print("该模型已关闭推理。")'),
    ('print(f"Reasoning effort set to: {selected_effort}")', 'print(f"推理强度已设置为：{selected_effort}")'),
    ('title="Select reasoning effort:"', 'title="选择推理强度："'),
    ('help="Select default model and provider"', 'help="选择默认模型和模型服务"'),
    ('description="Interactively select your inference provider and default model"', 'description="交互式选择推理模型服务和默认模型"'),
    ('help="Messaging gateway management"', 'help="消息网关管理"'),
    ('description="Manage the messaging gateway (Telegram, Discord, WhatsApp)"', 'description="管理消息网关（Telegram、Discord、WhatsApp）"'),
    ('"run", help="Run gateway in foreground (recommended for WSL, Docker, Termux)"', '"run", help="在前台运行网关（推荐用于 WSL、Docker、Termux）"'),
    ('help="Increase stderr log verbosity (-v=INFO, -vv=DEBUG)"', 'help="提高错误日志详细程度（-v=INFO，-vv=DEBUG）"'),
    ('"-q", "--quiet", action="store_true", help="Suppress all stderr log output"', '"-q", "--quiet", action="store_true", help="关闭错误日志输出"'),
    ('help="Replace any existing gateway instance (useful for systemd)"', 'help="替换现有网关实例（适用于 systemd）"'),
    ('"start", help="Start the installed systemd/launchd background service"', '"start", help="启动已安装的 systemd/launchd 后台服务"'),
    ('help="Target the Linux system-level gateway service"', 'help="目标为 Linux 系统级网关服务"'),
    ('help="Kill ALL stale gateway processes across all profiles before starting"', 'help="启动前结束所有配置档里的旧网关进程"'),
    ('gateway_stop = gateway_subparsers.add_parser("stop", help="Stop gateway service")', 'gateway_stop = gateway_subparsers.add_parser("stop", help="停止网关服务")'),
    ('help="Stop ALL gateway processes across all profiles"', 'help="停止所有配置档里的网关进程"'),
    ('"restart", help="Restart gateway service"', '"restart", help="重启网关服务"'),
    ('help="Kill ALL gateway processes across all profiles before restarting"', 'help="重启前结束所有配置档里的网关进程"'),
    ('gateway_status = gateway_subparsers.add_parser("status", help="Show gateway status")', 'gateway_status = gateway_subparsers.add_parser("status", help="查看网关状态")'),
    ('gateway_status.add_argument("--deep", action="store_true", help="Deep status check")', 'gateway_status.add_argument("--deep", action="store_true", help="深度状态检查")'),
    ('help="Show full, untruncated service/log output where supported"', 'help="支持时显示完整服务/日志输出"'),
    ('"install", help="Install gateway as a systemd/launchd background service"', '"install", help="将网关安装为 systemd/launchd 后台服务"'),
    ('gateway_install.add_argument("--force", action="store_true", help="Force reinstall")', 'gateway_install.add_argument("--force", action="store_true", help="强制重新安装")'),
    ('help="Install as a Linux system-level service (starts at boot)"', 'help="安装为 Linux 系统级服务（开机启动）"'),
    ('help="User account the Linux system service should run as"', 'help="Linux 系统服务运行所用用户"'),
    ('"uninstall", help="Uninstall gateway service"', '"uninstall", help="卸载网关服务"'),
    ('gateway_subparsers.add_parser("setup", help="Configure messaging platforms")', 'gateway_subparsers.add_parser("setup", help="配置消息平台")'),
    ('help="Remove legacy hermes.service units from pre-rename installs"', 'help="移除旧安装中遗留的 hermes.service 单元"'),
    ('help="List what would be removed without doing it"', 'help="列出将移除内容，但不执行"'),
    ('help="Skip the confirmation prompt"', 'help="跳过确认提示"'),
    ('help="Interactive setup wizard"', 'help="交互式配置向导"'),
    ('description="Configure Hermes Agent with an interactive wizard. "', 'description="通过交互式向导配置 Hermes Agent。"'),
    ('help="Run a specific setup section instead of the full wizard"', 'help="运行指定配置项，而不是完整向导"'),
    ('help="Non-interactive mode (use defaults/env vars)"', 'help="非交互模式（使用默认值/环境变量）"'),
    ('"--reset", action="store_true", help="Reset configuration to defaults"', '"--reset", action="store_true", help="将配置重置为默认值"'),
    ('help="Set up WhatsApp integration"', 'help="设置 WhatsApp 集成"'),
    ('description="Configure WhatsApp and pair via QR code"', 'description="配置 WhatsApp，并通过二维码配对"'),
    ('help="Authenticate with an inference provider"', 'help="登录推理模型服务"'),
    ('description="Run OAuth device authorization flow for Hermes CLI"', 'description="为 Hermes CLI 运行 OAuth 设备授权流程"'),
    ('help="Provider to authenticate with (default: nous)"', 'help="要登录的模型服务（默认：nous）"'),
    ('help="Do not attempt to open the browser automatically"', 'help="不要自动打开浏览器"'),
    ('help="HTTP request timeout in seconds (default: 15)"', 'help="HTTP 请求超时时间，单位秒（默认：15）"'),
    ('"--ca-bundle", help="Path to CA bundle PEM file for TLS verification"', '"--ca-bundle", help="用于 TLS 验证的 CA bundle PEM 文件路径"'),
    ('help="Disable TLS verification (testing only)"', 'help="关闭 TLS 验证（仅测试使用）"'),
    ('help="Show status of all components"', 'help="查看所有组件状态"'),
    ('description="Display status of Hermes Agent components"', 'description="显示 Hermes Agent 组件状态"'),
    ('"--all", action="store_true", help="Show all details (redacted for sharing)"', '"--all", action="store_true", help="显示全部详情（分享时会脱敏）"'),
    ('"--deep", action="store_true", help="Run deep checks (may take longer)"', '"--deep", action="store_true", help="运行深度检查（可能更耗时）"'),
    ('"cron", help="Cron job management", description="Manage scheduled tasks"', '"cron", help="定时任务管理", description="管理定时任务"'),
    ('cron_list = cron_subparsers.add_parser("list", help="List scheduled jobs")', 'cron_list = cron_subparsers.add_parser("list", help="列出定时任务")'),
    ('cron_list.add_argument("--all", action="store_true", help="Include disabled jobs")', 'cron_list.add_argument("--all", action="store_true", help="包含已禁用任务")'),
    ('"create", aliases=["add"], help="Create a scheduled job"', '"create", aliases=["add"], help="创建定时任务"'),
    ('"edit", help="Edit an existing scheduled job"', '"edit", help="编辑已有定时任务"'),
    ('help="Pause a scheduled job"', 'help="暂停定时任务"'),
    ('help="Resume a paused job"', 'help="恢复已暂停任务"'),
    ('"run", help="Run a job on the next scheduler tick"', '"run", help="在下一次调度时运行任务"'),
    ('"remove", aliases=["rm", "delete"], help="Remove a scheduled job"', '"remove", aliases=["rm", "delete"], help="移除定时任务"'),
    ('cron_subparsers.add_parser("status", help="Check if cron scheduler is running")', 'cron_subparsers.add_parser("status", help="检查定时任务调度器是否运行")'),
    ('cron_tick = cron_subparsers.add_parser("tick", help="Run due jobs once and exit")', 'cron_tick = cron_subparsers.add_parser("tick", help="运行一次到期任务后退出")'),
])

basic_replacements.setdefault("cli.py", []).extend([
    ('_cprint(f"  {_DIM}Goals unavailable (no active session).{_RST}")', '_cprint(f"  {_DIM}目标功能不可用（没有活跃会话）。{_RST}")'),
    ('_cprint(f"  {_DIM}No goal set.{_RST}")', '_cprint(f"  {_DIM}尚未设置目标。{_RST}")'),
    ('_cprint(f"  ⏸ Goal paused: {state.goal}")', '_cprint(f"  ⏸ 目标已暂停：{state.goal}")'),
    ('_cprint(f"  {_DIM}No goal to resume.{_RST}")', '_cprint(f"  {_DIM}没有可继续的目标。{_RST}")'),
    ('_cprint(f"  ▶ Goal resumed: {state.goal}")', '_cprint(f"  ▶ 目标已继续：{state.goal}")'),
    ('f"  {_DIM}Send any message (or press Enter on an empty prompt "', 'f"  {_DIM}发送任意消息继续（空消息回车不会触发；"'),
    ('f"is a no-op; type \'continue\' to kick it off).{_RST}"', 'f"输入 continue 开始）。{_RST}"'),
    ('_cprint("  ✓ Goal cleared.")', '_cprint("  ✓ 目标已清除。")'),
    ('_cprint(f"  {_DIM}No active goal.{_RST}")', '_cprint(f"  {_DIM}没有活跃目标。{_RST}")'),
    ('_cprint(f"  Invalid goal: {exc}")', '_cprint(f"  目标无效：{exc}")'),
    ('_cprint(f"  ⊙ Goal set ({state.max_turns}-turn budget): {state.goal}")', '_cprint(f"  ⊙ 目标已设置（最多 {state.max_turns} 轮）：{state.goal}")'),
    ('f"  {_DIM}After each turn, a judge model will check if the goal is done. "', 'f"  {_DIM}每轮结束后，会由评估模型判断目标是否完成。"'),
    ('f"  {_DIM}⏸ Goal paused — turn was interrupted. "', 'f"  {_DIM}⏸ 目标已暂停，本轮被中断。"'),
    ('_cprint(f"  {_ACCENT}Reasoning effort:  {level}{_RST}")', '_cprint(f"  {_ACCENT}推理强度：  {level}{_RST}")'),
    ('_cprint(f"  {_ACCENT}Reasoning display: {display_state}{_RST}")', '_cprint(f"  {_ACCENT}推理显示：{display_state}{_RST}")'),
    ('_cprint(f"  {_ACCENT}✓ Reasoning display: ON (saved){_RST}")', '_cprint(f"  {_ACCENT}✓ 推理显示：开启（已保存）{_RST}")'),
    ('_cprint(f"  {_ACCENT}✓ Reasoning display: OFF (saved){_RST}")', '_cprint(f"  {_ACCENT}✓ 推理显示：关闭（已保存）{_RST}")'),
    ('_cprint(f"  {_ACCENT}✓ Reasoning effort set to \'{arg}\' (saved to config){_RST}")', '_cprint(f"  {_ACCENT}✓ 推理强度已设为 \'{arg}\'（已保存到配置）{_RST}")'),
    ('_cprint(f"  {_ACCENT}✓ Reasoning effort set to \'{arg}\' (session only){_RST}")', '_cprint(f"  {_ACCENT}✓ 推理强度已设为 \'{arg}\'（当前会话）{_RST}")'),
    ('print(f"  ↳ Reasoning (subset):      {reasoning_tokens:>10,}")', 'print(f"  ↳ 推理（部分）：      {reasoning_tokens:>10,}")'),
    ('r_label = " Reasoning "', 'r_label = " 推理 "'),
])

basic_replacements.setdefault("tui_gateway/server.py", []).extend([
    ('out = "No goal set." if state is None else f"⏸ Goal paused: {state.goal}"', 'out = "尚未设置目标。" if state is None else f"⏸ 目标已暂停：{state.goal}"'),
    ('return _ok(rid, {"type": "exec", "output": "No goal to resume."})', 'return _ok(rid, {"type": "exec", "output": "没有可继续的目标。"})'),
    ('f"▶ Goal resumed: {state.goal}\\n"', 'f"▶ 目标已继续：{state.goal}\\n"'),
    ('"Send any message to continue, or wait — I\'ll take the next step on the next turn."', '"发送任意消息继续；也可以稍等，我会在下一轮继续处理。"'),
    ('"output": "✓ Goal cleared." if had else "No active goal."', '"output": "✓ 目标已清除。" if had else "没有活跃目标。"'),
    ('f"⊙ Goal set ({state.max_turns}-turn budget): {state.goal}\\n"', 'f"⊙ 目标已设置（最多 {state.max_turns} 轮）：{state.goal}\\n"'),
])

basic_replacements.setdefault("acp_adapter/tools.py", []).extend([
    ('lines = [f"Web extract failed for {len(failures)} URL{\'s\' if len(failures) != 1 else \'\'}"]', 'lines = [f"{len(failures)} 个 URL 网页提取失败"]'),
])

basic_replacements.setdefault("ui-tui/src/app/useMainApp.ts", []).extend([
    ("turnController.pushActivity('gateway exited · /logs to inspect', 'error')", "turnController.pushActivity('网关已退出 · 可用 /logs 查看', 'error')"),
    ("sys('error: gateway exited')", "sys('错误：网关已退出')"),
])

basic_replacements.setdefault("ui-tui/src/gatewayClient.ts", []).extend([
    ("`gateway exited${code === null ? '' : ` (${code})`}`", "`网关已退出${code === null ? '' : `（${code}）`}`"),
])

basic_replacements.setdefault("plugins/memory/hindsight/__init__.py", []).extend([
    ('print("\\n  Configuring Hindsight memory:\\n")', 'print("\\n  正在配置 Hindsight 记忆：\\n")'),
    ('("Cloud", "Hindsight Cloud API (lightweight, just needs an API key)")', '("云端", "Hindsight Cloud API（轻量，填写 API Key 即可）")'),
    ('("Local Embedded", "Run Hindsight locally (downloads ~200MB, needs LLM key)")', '("本地内置", "在本机运行 Hindsight（约 200MB，需要 LLM Key）")'),
    ('("Local External", "Connect to an existing Hindsight instance")', '("本地外部", "连接已有 Hindsight 实例")'),
    ('mode_idx = _curses_select("  Select mode", mode_items, default=mode_default_idx)', 'mode_idx = _curses_select("  选择模式", mode_items, default=mode_default_idx)'),
    ('print("\\n  Checking dependencies...")', 'print("\\n  正在检查依赖...")'),
    ('print("  ⚠ uv not found — install it: curl -LsSf https://astral.sh/uv/install.sh | sh")', 'print("  ⚠ 未找到 uv，请安装：curl -LsSf https://astral.sh/uv/install.sh | sh")'),
    ('print(f"  Then run manually: uv pip install --python {sys.executable} {\' \'.join(deps_to_install)}")', 'print(f"  然后手动运行：uv pip install --python {sys.executable} {\' \'.join(deps_to_install)}")'),
    ('print("  ✓ Dependencies up to date")', 'print("  ✓ 依赖已是最新")'),
    ('print(f"  ⚠ Install failed: {e}")', 'print(f"  ⚠ 安装失败：{e}")'),
    ('print(f"  Run manually: uv pip install --python {sys.executable} {\' \'.join(deps_to_install)}")', 'print(f"  可手动运行：uv pip install --python {sys.executable} {\' \'.join(deps_to_install)}")'),
    ('print("\\n  Get your API key at https://ui.hindsight.vectorize.io\\n")', 'print("\\n  请在 https://ui.hindsight.vectorize.io 获取 API Key\\n")'),
    ('sys.stdout.write(f"  API key (current: {masked}, blank to keep): ")', 'sys.stdout.write(f"  API Key（当前：{masked}，留空则保留）：")'),
    ('sys.stdout.write("  API key: ")', 'sys.stdout.write("  API Key：")'),
    ('val = input(f"  API URL [{_DEFAULT_API_URL}]: ").strip()', 'val = input(f"  API 地址 [{_DEFAULT_API_URL}]：").strip()'),
    ('val = input(f"  Hindsight API URL [{_DEFAULT_LOCAL_URL}]: ").strip()', 'val = input(f"  Hindsight API 地址 [{_DEFAULT_LOCAL_URL}]：").strip()'),
    ('sys.stdout.write("  API key (optional, blank to skip): ")', 'sys.stdout.write("  API Key（可选，留空跳过）：")'),
    ('(p, f"default model: {_PROVIDER_DEFAULT_MODELS[p]}")', '(p, f"默认模型：{_PROVIDER_DEFAULT_MODELS[p]}")'),
    ('llm_idx = _curses_select("  Select LLM provider", llm_items, default=llm_default_idx)', 'llm_idx = _curses_select("  选择 LLM 服务", llm_items, default=llm_default_idx)'),
    ('prompt = "  LLM endpoint URL (e.g. http://192.168.1.10:8080/v1)"', 'prompt = "  LLM 接口地址（例如 http://192.168.1.10:8080/v1）"'),
    ('val = input(f"  LLM model [{current_model}]: ").strip()', 'val = input(f"  LLM 模型 [{current_model}]：").strip()'),
    ('sys.stdout.write("  LLM API key: ")', 'sys.stdout.write("  LLM API Key：")'),
    ('"description": "LLM provider"', '"description": "LLM 服务"'),
    ('"description": "Endpoint URL (e.g. http://192.168.1.10:8080/v1)"', '"description": "接口地址（例如 http://192.168.1.10:8080/v1）"'),
    ('"description": "LLM API key (optional for openai_compatible)"', '"description": "LLM API Key（openai_compatible 可选）"'),
    ('"description": "LLM model"', '"description": "LLM 模型"'),
    ('"description": "Memory bank name (static fallback when bank_id_template is unset)"', '"description": "记忆库名称（未设置 bank_id_template 时使用）"'),
    ('"description": "Recall thoroughness"', '"description": "召回详细程度"'),
    ('"description": "Memory integration mode"', '"description": "记忆接入模式"'),
    ('"description": "Auto-recall method"', '"description": "自动召回方式"'),
    ('"description": "Automatically recall memories before each turn"', '"description": "每轮前自动召回记忆"'),
    ('"description": "Automatically retain conversation turns"', '"description": "自动保留对话轮次"'),
    ('"description": "Process retain asynchronously on the Hindsight server"', '"description": "在 Hindsight 服务端异步处理保留任务"'),
    ('"description": "API request timeout in seconds"', '"description": "API 请求超时时间，单位秒"'),
])

basic_replacements.setdefault("plugins/platforms/teams/adapter.py", []).extend([
    ('print_info(f"Teams: already configured (app ID: {existing_id})")', 'print_info(f"Teams 已配置（应用 ID：{existing_id}）")'),
    ('prompt_yes_no("Reconfigure Teams?", False)', 'prompt_yes_no("重新配置 Teams？", False)'),
    ('print_info("You\\\'ll need the Teams CLI. If you haven\\\'t already:")', 'print_info("需要先安装 Teams CLI，如未安装请执行：")'),
    ('print_info("Then expose port 3978 publicly (devtunnel / ngrok / cloudflared),")', 'print_info("然后把 3978 端口暴露为公网地址（devtunnel / ngrok / cloudflared），")'),
    ('print_info("and create your bot:")', 'print_info("并创建机器人：")'),
    ('print_info("The CLI will print CLIENT_ID, CLIENT_SECRET, and TENANT_ID. Paste them below.")', 'print_info("CLI 会输出 CLIENT_ID、CLIENT_SECRET 和 TENANT_ID，请粘贴到下面。")'),
    ('client_id = prompt("Client ID", default=existing_id or "")', 'client_id = prompt("Client ID", default=existing_id or "")'),
    ('print_warning("Client ID is required — skipping Teams setup")', 'print_warning("需要 Client ID，跳过 Teams 配置")'),
    ('client_secret = prompt("Client secret", default=get_env_value("TEAMS_CLIENT_SECRET") or "", password=True)', 'client_secret = prompt("Client secret", default=get_env_value("TEAMS_CLIENT_SECRET") or "", password=True)'),
    ('print_warning("Client secret is required — skipping Teams setup")', 'print_warning("需要 Client secret，跳过 Teams 配置")'),
    ('tenant_id = prompt("Tenant ID", default=get_env_value("TEAMS_TENANT_ID") or "")', 'tenant_id = prompt("Tenant ID", default=get_env_value("TEAMS_TENANT_ID") or "")'),
    ('print_warning("Tenant ID is required — skipping Teams setup")', 'print_warning("需要 Tenant ID，跳过 Teams 配置")'),
    ('print_info("To find your AAD object ID for the allowlist: teams status --verbose")', 'print_info("如需查找允许名单所需的 AAD object ID，请运行：teams status --verbose")'),
    ('prompt_yes_no("Restrict access to specific users? (recommended)", True)', 'prompt_yes_no("是否限制为指定用户可访问？（推荐）", True)'),
    ('"Allowed AAD object IDs (comma-separated)"', '"允许访问的 AAD object ID（逗号分隔）"'),
    ('print_success("Allowlist configured")', 'print_success("允许名单已配置")'),
    ('print_warning("⚠️  Open access — anyone who can message the bot can command it.")', 'print_warning("⚠️  已开放访问：任何能给机器人发消息的人都能发送命令。")'),
    ('print_success("Teams configuration saved to ~/.hermes/.env")', 'print_success("Teams 配置已保存到 ~/.hermes/.env")'),
    ('print_info("Install the app in Teams:  teams app install --id <teamsAppId>")', 'print_info("在 Teams 中安装应用：teams app install --id <teamsAppId>")'),
    ('print_info("Restart the gateway:       hermes gateway restart")', 'print_info("重启网关：hermes gateway restart")'),
    ('return {"error": "Teams standalone send: TEAMS_CLIENT_ID, TEAMS_CLIENT_SECRET, and TEAMS_TENANT_ID are all required"}', 'return {"error": "Teams 独立发送失败：需要 TEAMS_CLIENT_ID、TEAMS_CLIENT_SECRET 和 TEAMS_TENANT_ID"}'),
    ('f"Teams standalone send: TEAMS_SERVICE_URL host is not on the "', 'f"Teams 独立发送失败：TEAMS_SERVICE_URL 主机不在 "'),
    ('f"Bot Framework allowlist; expected one of "', 'f"Bot Framework 允许列表中；应为以下之一 "'),
    ('return {"error": "Teams standalone send: chat_id (conversation ID) is required"}', 'return {"error": "Teams 独立发送失败：需要 chat_id（conversation ID）"}'),
    ('return {"error": "Teams standalone send: chat_id contains characters outside the Bot Framework conversation ID set"}', 'return {"error": "Teams 独立发送失败：chat_id 含有 Bot Framework conversation ID 不支持的字符"}'),
    ('return {"error": "Teams standalone send: TEAMS_TENANT_ID contains characters outside the expected set"}', 'return {"error": "Teams 独立发送失败：TEAMS_TENANT_ID 含有不支持的字符"}'),
    ('return {"error": "Teams standalone send: aiohttp not installed"}', 'return {"error": "Teams 独立发送失败：未安装 aiohttp"}'),
    ('return {"error": f"Teams standalone send: token request failed ({token_resp.status}): {body[:300]}"}', 'return {"error": f"Teams 独立发送失败：token 请求失败（{token_resp.status}）：{body[:300]}"}'),
    ('return {"error": "Teams standalone send: token response missing access_token"}', 'return {"error": "Teams 独立发送失败：token 响应缺少 access_token"}'),
    ('return {"error": f"Teams standalone send: activity post failed ({send_resp.status}): {body[:300]}"}', 'return {"error": f"Teams 独立发送失败：消息发送失败（{send_resp.status}）：{body[:300]}"}'),
    ('return {"error": f"Teams standalone send failed: {e}"}', 'return {"error": f"Teams 独立发送失败：{e}"}'),
])

basic_replacements.setdefault("hermes_cli/goals.py", []).extend([
    ('return "No active goal. Set one with /goal <text>."', 'return "没有活跃目标。用 /goal <内容> 设置一个目标。"'),
    ('turns = f"{s.turns_used}/{s.max_turns} turns"', 'turns = f"{s.turns_used}/{s.max_turns} 轮"'),
    ('sub = f", {len(s.subgoals)} subgoal{\'s\' if len(s.subgoals) != 1 else \'\'}" if s.subgoals else ""', 'sub = f"，{len(s.subgoals)} 个子目标" if s.subgoals else ""'),
    ('return f"⊙ Goal (active, {turns}{sub}): {s.goal}"', 'return f"⊙ 目标（进行中，{turns}{sub}）：{s.goal}"'),
    ('return f"⏸ Goal (paused, {turns}{sub}{extra}): {s.goal}"', 'return f"⏸ 目标（已暂停，{turns}{sub}{extra}）：{s.goal}"'),
    ('return f"✓ Goal done ({turns}{sub}): {s.goal}"', 'return f"✓ 目标已完成（{turns}{sub}）：{s.goal}"'),
    ('return f"Goal ({s.status}, {turns}{sub}): {s.goal}"', 'return f"目标（{s.status}，{turns}{sub}）：{s.goal}"'),
    ('raise ValueError("goal text is empty")', 'raise ValueError("目标内容为空")'),
    ('raise RuntimeError("no active goal")', 'raise RuntimeError("没有活跃目标")'),
    ('raise ValueError("subgoal text is empty")', 'raise ValueError("子目标内容为空")'),
    ('return "(no active goal)"', 'return "（没有活跃目标）"'),
    ('return "(no subgoals — use /subgoal <text> to add criteria)"', 'return "（没有子目标，可用 /subgoal <内容> 添加标准）"'),
    ('"reason": "no active goal"', '"reason": "没有活跃目标"'),
    ('"message": f"✓ Goal achieved: {reason}"', '"message": f"✓ 目标已达成：{reason}"'),
    ('f"⏸ Goal paused — the judge model ({state.consecutive_parse_failures} turns) "', 'f"⏸ 目标已暂停：评估模型连续 {state.consecutive_parse_failures} 轮 "'),
    ('"isn\\\'t returning the required JSON verdict. Route the judge to a stricter "', '"没有返回所需 JSON 判断结果。请把评估任务切换到更严格的"'),
    ('"model in ~/.hermes/config.yaml:\\n"', '"模型，在 ~/.hermes/config.yaml 中配置：\\n"'),
    ('"Then /goal resume to continue."', '"然后用 /goal resume 继续。"'),
    ('state.paused_reason = f"turn budget exhausted ({state.turns_used}/{state.max_turns})"', 'state.paused_reason = f"轮数预算已用完（{state.turns_used}/{state.max_turns}）"'),
    ('f"⏸ Goal paused — {state.turns_used}/{state.max_turns} turns used. "', 'f"⏸ 目标已暂停：已使用 {state.turns_used}/{state.max_turns} 轮。"'),
    ('"Use /goal resume to keep going, or /goal clear to stop."', '"用 /goal resume 继续，或用 /goal clear 停止。"'),
])

basic_replacements.setdefault("batch_runner.py", []).extend([
    ('print("\\n🧠 Reasoning Coverage:")', 'print("\\n🧠 推理覆盖：")'),
    ('print(f"   Total assistant turns:    {total_turns:,}")', 'print(f"   助手总轮次：    {total_turns:,}")'),
    ('print("🧠 Reasoning: DISABLED (effort=none)")', 'print("🧠 推理：已关闭（effort=none）")'),
    ('print(f"❌ Error: --reasoning_effort must be one of: {\', \'.join(valid_efforts)}")', 'print(f"❌ 错误：--reasoning_effort 必须为以下之一：{\', \'.join(valid_efforts)}")'),
    ('print(f"🧠 Reasoning effort: {reasoning_effort}")', 'print(f"🧠 推理强度：{reasoning_effort}")'),
])

basic_replacements.setdefault("hermes_cli/auth.py", []).extend([
    ('print(f"Default model set to: {selected_model}")', 'print(f"默认模型已设置为：{selected_model}")'),
])

basic_replacements.setdefault("agent/copilot_acp_client.py", []).extend([
    ('f"Could not start Copilot ACP command \'{self._acp_command}\'. "', 'f"无法启动 Copilot ACP 命令 \'{self._acp_command}\'。"'),
    ('raise RuntimeError("Copilot ACP process did not expose stdin/stdout pipes.")', 'raise RuntimeError("Copilot ACP 进程未提供 stdin/stdout 管道。")'),
    ('f"Copilot ACP {method} failed: {err.get(\'message\') or err}"', 'f"Copilot ACP {method} 失败：{err.get(\'message\') or err}"'),
    ('raise RuntimeError(f"Copilot ACP process exited early: {stderr_text}")', 'raise RuntimeError(f"Copilot ACP 进程提前退出：{stderr_text}")'),
    ('raise TimeoutError(f"Timed out waiting for Copilot ACP response to {method}.")', 'raise TimeoutError(f"等待 Copilot ACP 响应 {method} 超时。")'),
    ('raise RuntimeError("Copilot ACP did not return a sessionId.")', 'raise RuntimeError("Copilot ACP 没有返回 sessionId。")'),
])

basic_replacements.setdefault("agent/conversation_loop.py", []).extend([
    ('f"{agent.log_prefix}💭 Reasoning exhausted the output token budget — "', 'f"{agent.log_prefix}💭 推理已用完输出 token 预算，"'),
])

basic_replacements.setdefault("plugins/memory/honcho/cli.py", []).extend([
    ('new_reasoning = _prompt("Reasoning level", default=current_reasoning)', 'new_reasoning = _prompt("推理强度", default=current_reasoning)'),
])

basic_replacements.setdefault("hermes_cli/web_server.py", []).extend([
    ('"description": "Reasoning effort for delegated subagents"', '"description": "委派子 Agent 的推理强度"'),
])

basic_replacements.setdefault("hermes_cli/gateway.py", []).extend([
    ('print_warning("  Open access enabled — anyone can use your bot!")', 'print_warning("  已开放访问：任何人都可以使用你的机器人！")'),
])

basic_replacements.setdefault("plugins/platforms/irc/adapter.py", []).extend([
    ('print_warning("⚠️  Open access — any nick in the channel can command the bot.")', 'print_warning("⚠️  已开放访问：频道中的任何昵称都可以给机器人发命令。")'),
])

basic_replacements.setdefault("plugins/platforms/google_chat/adapter.py", []).extend([
    ('print_warning("⚠️  Open access — anyone who can DM the bot can command it.")', 'print_warning("⚠️  已开放访问：任何能私信机器人的人都可以发命令。")'),
])

basic_replacements.setdefault("acp_adapter/permissions.py", []).extend([
    ('name="Allow for session"', 'name="本会话允许"'),
    ('name="Deny always"', 'name="始终拒绝"'),
    ('logger.warning("Permission request returned unknown option_id: %s", option_id)', 'logger.warning("权限请求返回了未知 option_id：%s", option_id)'),
    ('log_message="Permission request: failed to schedule on loop"', 'log_message="权限请求：调度到事件循环失败"'),
])

basic_replacements.setdefault("acp_adapter/edit_approval.py", []).extend([
    ('PermissionOption(option_id="allow_once", kind="allow_once", name="Allow edit")', 'PermissionOption(option_id="allow_once", kind="allow_once", name="允许修改")'),
])

basic_replacements.setdefault("cli.py", []).extend([
    ('_cprint(f"  {_DIM}No active goal. Set one with /goal <text>.{_RST}")', '_cprint(f"  {_DIM}没有活跃目标。用 /goal <内容> 设置一个目标。{_RST}")'),
    ('("once", "Approve Once", "proceed this time only")', '("once", "批准一次", "本次执行")'),
    ('("always", "Always Approve", "proceed and silence this prompt permanently")', '("always", "始终批准", "执行并永久关闭此确认")'),
    ('("cancel", "Cancel", "keep current conversation")', '("cancel", "取消", "保留当前对话")'),
    ('title=f"⚠️  /{command} — destroys conversation state"', 'title=f"⚠️  /{command} — 会清除对话状态"'),
    ('print(f"🟡 /{command} cancelled (no input).")', 'print(f"🟡 /{command} 已取消（未输入）。")'),
    ('print(f"🟡 Unrecognized choice \'{raw}\'. /{command} cancelled.")', 'print(f"🟡 未识别选项 \'{raw}\'。/{command} 已取消。")'),
    ('print(f"🟡 /{command} cancelled. Conversation unchanged.")', 'print(f"🟡 /{command} 已取消。对话未改变。")'),
    ('print("🔒 Future /clear, /new, /reset, and /undo will run without confirmation.")', 'print("🔒 以后 /clear、/new、/reset、/undo 将不再要求确认。")'),
    ('print("   Re-enable via `approvals.destructive_slash_confirm: true` in config.yaml.")', 'print("   可在 config.yaml 设置 `approvals.destructive_slash_confirm: true` 重新开启。")'),
    ('print("⚠️  Couldn\\\'t persist opt-out — proceeding once.")', 'print("⚠️  无法保存免确认设置，本次继续执行。")'),
    ('("once", "Approve Once", "reload now")', '("once", "批准一次", "现在重新加载")'),
    ('("always", "Always Approve", "reload now and silence this prompt permanently")', '("always", "始终批准", "现在重新加载并永久关闭此确认")'),
    ('("cancel", "Cancel", "leave MCP tools unchanged")', '("cancel", "取消", "保持 MCP 工具不变")'),
    ('title="⚠️  /reload-mcp — Prompt cache invalidation warning"', 'title="⚠️  /reload-mcp — 提示词缓存将失效"'),
])

basic_replacements.setdefault("gateway/run.py", []).extend([
    ('return "No active goal. Set one with /goal <text>."', 'return "没有活跃目标。用 /goal <内容> 设置一个目标。"'),
    ('f"⚠️ **Confirm /{command}**\\n\\n"', 'f"⚠️ **确认 /{command}**\\n\\n"'),
    ('"Choose:\\n"', '"请选择：\\n"'),
    ('"• **Approve Once** — proceed this time only\\n"', '"• **批准一次** — 本次执行\\n"'),
    ('"• **Always Approve** — proceed and silence this prompt permanently\\n"', '"• **始终批准** — 执行并永久关闭此确认\\n"'),
    ('"• **Cancel** — keep current conversation\\n\\n"', '"• **取消** — 保留当前对话\\n\\n"'),
    ('"_Text fallback: reply `/approve`, `/always`, or `/cancel`._"', '"_文本回复：发送 `/approve`、`/always` 或 `/cancel`。_"'),
])

basic_replacements.setdefault("gateway/platforms/slack.py", []).extend([
    ('"text": {"type": "plain_text", "text": "Approve Once"}', '"text": {"type": "plain_text", "text": "批准一次"}'),
    ('"text": {"type": "plain_text", "text": "Always Approve"}', '"text": {"type": "plain_text", "text": "始终批准"}'),
    ('"text": {"type": "plain_text", "text": "Cancel"}', '"text": {"type": "plain_text", "text": "取消"}'),
    ('"once": f"✅ Approved once by {user_name}"', '"once": f"✅ {user_name} 已批准一次"'),
    ('"always": f"🔒 Always approved by {user_name}"', '"always": f"🔒 {user_name} 已始终批准"'),
    ('"cancel": f"❌ Cancelled by {user_name}"', '"cancel": f"❌ {user_name} 已取消"'),
    ('decision_text = label_map.get(choice, f"Resolved by {user_name}")', 'decision_text = label_map.get(choice, f"{user_name} 已处理")'),
    ('"session": f"✅ Approved for session by {user_name}"', '"session": f"✅ {user_name} 已批准本会话"'),
    ('"always": f"✅ Approved permanently by {user_name}"', '"always": f"✅ {user_name} 已永久批准"'),
    ('"deny": f"❌ Denied by {user_name}"', '"deny": f"❌ {user_name} 已拒绝"'),
])

basic_replacements.setdefault("gateway/platforms/telegram.py", []).extend([
    ('InlineKeyboardButton("✅ Approve Once", callback_data=f"sc:once:{confirm_id}")', 'InlineKeyboardButton("✅ 批准一次", callback_data=f"sc:once:{confirm_id}")'),
    ('InlineKeyboardButton("🔒 Always Approve", callback_data=f"sc:always:{confirm_id}")', 'InlineKeyboardButton("🔒 始终批准", callback_data=f"sc:always:{confirm_id}")'),
    ('InlineKeyboardButton("❌ Cancel", callback_data=f"sc:cancel:{confirm_id}")', 'InlineKeyboardButton("❌ 取消", callback_data=f"sc:cancel:{confirm_id}")'),
    ('await query.answer(text="This approval has already been resolved.")', 'await query.answer(text="这个确认请求已经处理。")'),
    ('await query.answer(text="This prompt has already been resolved.")', 'await query.answer(text="这个提示已经处理。")'),
    ('"once": "✅ Approved once"', '"once": "✅ 已批准一次"'),
    ('"session": "✅ Approved for session"', '"session": "✅ 本会话已批准"'),
    ('"always": "✅ Approved permanently"', '"always": "✅ 已永久批准"'),
    ('"always": "🔒 Always approve"', '"always": "🔒 始终批准"'),
    ('"deny": "❌ Denied"', '"deny": "❌ 已拒绝"'),
    ('"cancel": "❌ Cancelled"', '"cancel": "❌ 已取消"'),
    ('label = label_map.get(choice, "Resolved")', 'label = label_map.get(choice, "已处理")'),
])

basic_replacements.setdefault("gateway/platforms/feishu.py", []).extend([
    ('"once": "Approved once"', '"once": "已批准一次"'),
    ('"session": "Approved for session"', '"session": "本会话已批准"'),
    ('"always": "Approved permanently"', '"always": "已永久批准"'),
    ('"deny": "Denied"', '"deny": "已拒绝"'),
])

basic_replacements.setdefault("gateway/platforms/discord.py", []).extend([
    ('"This approval has already been resolved~"', '"这个确认请求已经处理~"'),
    ('"This prompt has already been resolved~"', '"这个提示已经处理~"'),
])

basic_replacements.setdefault("hermes_cli/main.py", []).extend([
    ('print(f"✓ Allowed users: {current_users}")', 'print(f"✓ 允许访问的用户：{current_users}")'),
    ('response = input("\\n  Update allowed users? [y/N] ").strip()', 'response = input("\\n  更新允许访问的用户？[y/N] ").strip()'),
    ('"  Phone numbers that can message the bot (comma-separated): "', '"  可给机器人发消息的手机号（逗号分隔）： "'),
    ('phone = input("  Your phone number (e.g. 15551234567): ").strip()', 'phone = input("  你的手机号（例如 15551234567）：").strip()'),
    ('print(f"  ✓ Updated to: {phone}")', 'print(f"  ✓ 已更新为：{phone}")'),
    ('print("  Who should be allowed to message the bot?")', 'print("  哪些人可以给机器人发消息？")'),
    ('"  Phone numbers (comma-separated, or * for anyone): "', '"  手机号（逗号分隔，或输入 * 表示任何人）： "'),
    ('print(f"  ✓ Allowed users set: {phone}")', 'print(f"  ✓ 允许访问的用户已设置：{phone}")'),
    ('print("  ⚠ No allowlist — the agent will respond to ALL incoming messages")', 'print("  ⚠ 未设置允许名单：Agent 会响应所有传入消息")'),
    ('description="Approve or revoke user access via pairing codes"', 'description="通过配对验证码批准或撤销用户访问"'),
    ('"approve", help="Approve a pairing code"', '"approve", help="批准一个配对验证码"'),
])

basic_replacements.setdefault("hermes_cli/pairing.py", []).extend([
    ('print("Usage: hermes pairing {list|approve|revoke|clear-pending}")', 'print("用法：hermes pairing {list|approve|revoke|clear-pending}")'),
    ('print("Run \\\'hermes pairing --help\\\' for details.")', 'print("运行 \\\'hermes pairing --help\\\' 查看详情。")'),
    ('print("No pairing data found. No one has tried to pair yet~")', 'print("没有配对数据。还没有人尝试配对~")'),
    ('print(f"\\n  Pending Pairing Requests ({len(pending)}):")', 'print(f"\\n  待处理配对请求（{len(pending)}）：")'),
    ('print(f"  {\\\'Platform\\\':<12} {\\\'Code\\\':<10} {\\\'User ID\\\':<20} {\\\'Name\\\':<20} {\\\'Age\\\'}")', 'print(f"  {\\\'平台\\\':<12} {\\\'验证码\\\':<10} {\\\'用户 ID\\\':<20} {\\\'名称\\\':<20} {\\\'时间\\\'}")'),
    ('print("\\n  No pending pairing requests.")', 'print("\\n  没有待处理配对请求。")'),
    ('print(f"\\n  Approved Users ({len(approved)}):")', 'print(f"\\n  已批准用户（{len(approved)}）：")'),
    ('print(f"  {\\\'Platform\\\':<12} {\\\'User ID\\\':<20} {\\\'Name\\\':<20}")', 'print(f"  {\\\'平台\\\':<12} {\\\'用户 ID\\\':<20} {\\\'名称\\\':<20}")'),
    ('print("\\n  No approved users.")', 'print("\\n  没有已批准用户。")'),
    ('print(f"\\n  Approved! User {display} on {platform} can now use the bot~")', 'print(f"\\n  已批准！{platform} 上的用户 {display} 现在可以使用机器人~")'),
    ('print("  They\\\'ll be recognized automatically on their next message.\\n")', 'print("  下次发消息时会自动识别。\\n")'),
])

basic_replacements.setdefault("hermes_cli/gateway.py", []).extend([
    ('"prompt": "Allowed user IDs (comma-separated)"', '"prompt": "允许访问的用户 ID（逗号分隔）"'),
    ('"prompt": "Allowed user IDs or usernames (comma-separated)"', '"prompt": "允许访问的用户 ID 或用户名（逗号分隔）"'),
    ('"prompt": "Allowed user IDs (comma-separated, e.g. @you:server)"', '"prompt": "允许访问的用户 ID（逗号分隔，例如 @you:server）"'),
    ('"prompt": "Allowed sender emails (comma-separated)"', '"prompt": "允许访问的发件邮箱（逗号分隔）"'),
    ('"prompt": "Allowed phone numbers (comma-separated, E.164 format)"', '"prompt": "允许访问的手机号（逗号分隔，E.164 格式）"'),
    ('"prompt": "Allowed user IDs (comma-separated, or empty)"', '"prompt": "允许访问的用户 ID（逗号分隔，可为空）"'),
    ('"prompt": "Allowed user OpenIDs (comma-separated, leave empty for open access)"', '"prompt": "允许访问的用户 OpenID（逗号分隔，留空则开放访问）"'),
    ('print_success("  DM pairing mode — users will receive a code to request access.")', 'print_success("  私信配对模式已启用，用户会收到验证码来申请访问。")'),
    ('print_info("  Approve with: hermes pairing approve <platform> <code>")', 'print_info("  批准命令：hermes pairing approve <platform> <code>")'),
    ('print_info("  Skipped — configure later with \\\'hermes gateway setup\\\'")', 'print_info("  已跳过，可稍后用 \\\'hermes gateway setup\\\' 配置")'),
    ('print_info("  The gateway DENIES all users by default for security.")', 'print_info("  为了安全，网关默认拒绝所有用户。")'),
    ('print_info("  Enter user IDs to create an allowlist, or leave empty.")', 'print_info("  输入用户 ID 创建允许名单，或留空。")'),
    ('allowed = prompt("  Allowed user IDs (comma-separated, or empty)", password=False)', 'allowed = prompt("  允许访问的用户 ID（逗号分隔，可为空）", password=False)'),
    ('print_success("  Saved — only these users can interact with the bot.")', 'print_success("  已保存：仅这些用户可以和机器人交互。")'),
    ('"Enable open access (anyone can message the bot)"', '"开放访问（任何人都可以给机器人发消息）"'),
    ('"Use DM pairing (unknown users request access, you approve with \\\'hermes pairing approve\\\')"', '"使用私信配对（未知用户申请访问，你用 hermes pairing approve 批准）"'),
    ('"Disable direct messages"', '"关闭私信"'),
    ('"Skip for now (bot will deny all users until configured)"', '"暂不配置（配置前机器人会拒绝所有用户）"'),
    ('access_idx = prompt_choice("  How should unauthorized users be handled?", access_choices, 1)', 'access_idx = prompt_choice("  未授权用户如何处理？", access_choices, 1)'),
    ('print_warning("  Direct messages disabled.")', 'print_warning("  私信已关闭。")'),
    ('"Use DM pairing approval (recommended)"', '"使用私信配对审批（推荐）"'),
    ('"Allow all direct messages"', '"允许所有私信"'),
    ('"Only allow listed user IDs"', '"仅允许名单内用户 ID"'),
    ('"Only allow listed user OpenIDs"', '"仅允许名单内用户 OpenID"'),
    ('access_idx = prompt_choice("  How should direct messages be authorized?", access_choices, 0)', 'access_idx = prompt_choice("  私信如何授权？", access_choices, 0)'),
    ('print_success("  DM pairing enabled.")', 'print_success("  私信配对已启用。")'),
    ('print_info("  Unknown users can request access; approve with `hermes pairing approve`.")', 'print_info("  未知用户可以申请访问；用 `hermes pairing approve` 批准。")'),
    ('print_warning("  Open DM access enabled for Feishu / Lark.")', 'print_warning("  Feishu / Lark 私信开放访问已启用。")'),
    ('allowlist = prompt("  Allowed user IDs (comma-separated)", default_allow, password=False).replace(" ", "")', 'allowlist = prompt("  允许访问的用户 ID（逗号分隔）", default_allow, password=False).replace(" ", "")'),
    ('print_success("  Allowlist saved.")', 'print_success("  允许名单已保存。")'),
    ('print_warning("  Open DM access enabled for QQ Bot.")', 'print_warning("  QQ Bot 私信开放访问已启用。")'),
    ('allowlist = prompt("  Allowed user OpenIDs (comma-separated)", default_allow, password=False).replace(" ", "")', 'allowlist = prompt("  允许访问的用户 OpenID（逗号分隔）", default_allow, password=False).replace(" ", "")'),
    ('print_info("  Enter phone numbers or UUIDs of allowed users (comma-separated).")', 'print_info("  输入允许访问用户的手机号或 UUID（逗号分隔）。")'),
    ('allowed = input(f"  Allowed users [{default_allowed}]: ").strip() or default_allowed', 'allowed = input(f"  允许访问的用户 [{default_allowed}]：").strip() or default_allowed'),
])

basic_replacements.setdefault("plugins/platforms/irc/adapter.py", []).extend([
    ('allow_all = prompt_yes_no("Allow all users in the channel to talk to the bot?", False)', 'allow_all = prompt_yes_no("是否允许频道中所有用户和机器人对话？", False)'),
    ('"Allowed nicks (comma-separated, leave empty to deny everyone)"', '"允许访问的昵称（逗号分隔，留空则拒绝所有人）"'),
    ('print_success("Allowlist configured")', 'print_success("允许名单已配置")'),
])

basic_replacements.setdefault("plugins/platforms/google_chat/adapter.py", []).extend([
    ('"Allowed user emails (comma-separated)"', '"允许访问的用户邮箱（逗号分隔）"'),
    ('print_success("Allowlist configured")', 'print_success("允许名单已配置")'),
])

basic_replacements.setdefault("hermes_cli/config.py", []).extend([
    ('"description": "Allow all users to interact with messaging bots (true/false). Default: false."', '"description": "允许所有用户与消息机器人交互（true/false）。默认 false。"'),
    ('"prompt": "Allow all users (true/false)"', '"prompt": "允许所有用户（true/false）"'),
])

basic_replacements.setdefault("plugins/platforms/teams/plugin.yaml", []).extend([
    ('prompt: "Allowed users (comma-separated)"', 'prompt: "允许访问的用户（逗号分隔）"'),
    ('description: "Allow any Teams user to trigger the bot (dev only)"', 'description: "允许任意 Teams 用户触发机器人（仅开发环境）"'),
    ('prompt: "Allow all users? (true/false)"', 'prompt: "允许所有用户？（true/false）"'),
])

basic_replacements.setdefault("plugins/platforms/line/plugin.yaml", []).extend([
    ('prompt: "Allow all users? (true/false)"', 'prompt: "允许所有用户？（true/false）"'),
])

basic_replacements.setdefault("plugins/platforms/irc/plugin.yaml", []).extend([
    ('prompt: "Allow all users? (true/false)"', 'prompt: "允许所有用户？（true/false）"'),
])

basic_replacements.setdefault("scripts/whatsapp-bridge/bridge.js", []).extend([
    ("console.log(`🔒 Allowed users: ${Array.from(ALLOWED_USERS).join(', ')}`);", "console.log(`🔒 允许访问的用户：${Array.from(ALLOWED_USERS).join(', ')}`);"),
])

zh_tips = '''TIPS = [
    "输入 /help 查看命令。",
    "/model 可在会话中切换模型。",
    "/skin 可切换终端主题。",
    "/config 可查看当前配置。",
    "/usage 可查看用量、费用和会话时长。",
    "/tools disable browser 可临时关闭浏览器工具。",
    "/resume 可继续之前命名的会话。",
    "/queue 可把下一条消息加入队列。",
    "/paste 可读取剪贴板图片并加入下一条消息。",
    "Ctrl+C 可中断当前任务；连续两次可强制退出。",
    "Ctrl+Z 可将 Hermes 暂停到后台；在终端运行 fg 可恢复。",
    "Alt+Enter 可输入多行消息。",
    "Tab 可接受自动建议或补全斜杠命令。",
    "@file:path/to/file.py 可把文件内容加入消息。",
    "@diff 可把未提交改动加入消息。",
    "@url:https://example.com 可读取网页内容。",
    "hermes -c 可继续最近会话。",
    "hermes chat -q \\"问题\\" 可执行一次性提问。",
    "设置 display.compact: true 可让输出更紧凑。",
    "技能会自动出现在斜杠命令列表中。",
]
'''

patched = []
unchanged = []
missing = []


def backup_file(path, rel):
    if os.environ.get("XIAOMA_HERMES_SKIP_BACKUP", "0") == "1":
        return
    backup_path = backup_root / rel
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    if not backup_path.exists():
        shutil.copy2(path, backup_path)


# BEGIN XIAOMA 2026-05-26 GATEWAY TEXT PATCH
gateway_text_replacements = {
    'agent/onboarding.py': [
        ("💡 First-time tip — I just interrupted my current task to answer you. Send `/busy queue` to queue follow-ups for after the current task instead, `/busy steer` to inject them mid-run without interrupting, or `/busy status` to check. This notice won't appear again.", '💡 首次提示：我刚刚中断当前任务来回复你。发送 `/busy queue` 可把后续消息排到当前任务完成后处理；发送 `/busy steer` 可在不中断的情况下插入当前运行；发送 `/busy status` 可查看设置。此提示以后不会再出现。'),
        ("💡 First-time tip — that tool took a while and I'm streaming every step. If the progress messages feel noisy, send `/verbose` to cycle modes (all → new → off). This notice won't appear again.", '💡 首次提示：这个工具运行时间较长，我正在显示每一步进度。如果进度消息太多，可发送 `/verbose` 切换显示模式（全部 → 新调用 → 关闭）。此提示以后不会再出现。'),
        ("💡 First-time tip — I queued your message instead of interrupting. Send `/busy interrupt` to make new messages stop the current task immediately, or `/busy status` to check. This notice won't appear again.", '💡 首次提示：我已把你的消息排队，没有中断当前任务。发送 `/busy interrupt` 可让新消息立即停止当前任务；发送 `/busy status` 可查看设置。此提示以后不会再出现。'),
        ("💡 First-time tip — I steered your message into the current run; it will arrive after the next tool call instead of interrupting. Send `/busy interrupt` or `/busy queue` to change this, or `/busy status` to check. This notice won't appear again.", '💡 首次提示：我已把你的消息插入当前运行，它会在下一次工具调用后进入，不会中断任务。发送 `/busy interrupt` 或 `/busy queue` 可调整方式；发送 `/busy status` 可查看设置。此提示以后不会再出现。'),
    ],
    'gateway/platforms/feishu.py': [
        ('Connecting to Feishu / Lark...', '正在连接 Feishu / Lark...'),
        ('done.', '完成。'),
        ('Scan the QR code above, or open this URL directly: {qr_url}', '扫描上方二维码，或直接打开这个链接：{qr_url}'),
        ('Open this URL in Feishu / Lark on your phone: {qr_url}', '请在手机上的 Feishu / Lark 中打开这个链接：{qr_url}'),
        ('Tip: pip install qrcode to display a scannable QR code here next time', '提示：安装 qrcode 后，下次这里会显示可扫描二维码'),
        ('[Content of {display_name}]: {content}', '[{display_name} 的内容]：{content}'),
        ('Fetching configuration results...', '正在获取配置结果...'),
        ('Feishu startup failed: {exc}', 'Feishu 启动失败：{exc}'),
        ('send failed', '发送失败'),
        ('update failed', '更新失败'),
        ('send_exec_approval failed', '发送执行确认失败'),
        ('send_update_prompt failed', '发送更新确认失败'),
        ('image send failed', '图片发送失败'),
        ('Unsupported Media Type', '不支持的媒体类型'),
        ('file send failed', '文件发送失败'),
    ],
    'gateway/platforms/signal.py': [
        ('(More images coming — pausing ~{_format_wait(wait_s)} for Signal rate limit, batch {next_batch_idx}/{total_batches}.)', '（还有更多图片；因 Signal 限流暂停约 {_format_wait(wait_s)}，批次 {next_batch_idx}/{total_batches}。）'),
        ('Image', '图片'),
        ('Audio', '音频'),
        ('Video', '视频'),
    ],
    'gateway/platforms/slack.py': [
        ('[Slack Block Kit payload for this message] ```json {payload} ```', '[这条消息的 Slack Block Kit 载荷] ```json {payload} ```'),
        ('Slack attachment access failed for {file_label}. {needed_hint}{provided_hint}{reinstall_hint}', '无法访问 Slack 附件 {file_label}。{needed_hint}{provided_hint}{reinstall_hint}'),
        ('Slack attachment access failed for {file_label} because the bot token is not authorized ({error}). Refresh the token/reinstall the app.', '无法访问 Slack 附件 {file_label}，因为机器人 token 未获授权（{error}）。请刷新 token 或重新安装应用。'),
        ('Slack attachment {file_label} is no longer available ({error}).', 'Slack 附件 {file_label} 已不可用（{error}）。'),
        ('Slack attachment access failed for {file_label} because the bot does not have permission ({error}). Check workspace permissions/scopes and reinstall if needed.', '无法访问 Slack 附件 {file_label}，因为机器人没有权限（{error}）。请检查工作区权限和 scopes，必要时重新安装。'),
        ('Slack attachment access failed for {file_label}: Slack returned an HTML/login or non-media response. This usually means a scope, auth, or file-permission problem.', '无法访问 Slack 附件 {file_label}：Slack 返回了 HTML/登录页或非媒体响应。通常是 scope、授权或文件权限问题。'),
        ('Slack attachment access failed for {file_label} with HTTP 401. The bot token is not authorized for this file.', '无法访问 Slack 附件 {file_label}：HTTP 401。机器人 token 未获此文件授权。'),
        ('Slack attachment access failed for {file_label} with HTTP 403. The bot likely lacks permission or scope to read this file.', '无法访问 Slack 附件 {file_label}：HTTP 403。机器人可能缺少读取该文件的权限或 scope。'),
        ('Slack attachment {file_label} returned HTTP 404 and is no longer reachable.', 'Slack 附件 {file_label} 返回 HTTP 404，已无法访问。'),
    ],
    'gateway/platforms/telegram.py': [
        ('Telegram DM topic delivery requires a reply anchor; refusing to send outside the requested topic', 'Telegram 私信话题发送需要回复锚点；已拒绝发到指定话题之外。'),
        ('Telegram startup failed: {e}', 'Telegram 启动失败：{e}'),
        ('❌ {verb} failed: {last_line[:80]}', '❌ {verb} 失败：{last_line[:80]}'),
        ('❌ {verb} timed out', '❌ {verb} 超时'),
        ('❌ {verb} error: {exc}', '❌ {verb} 出错：{exc}'),
        ('[{self.name}] Failed to send document: {e}', '[{self.name}] 发送文档失败：{e}'),
        ('[{self.name}] Failed to send video: {e}', '[{self.name}] 发送视频失败：{e}'),
        ('◀ Back', '◀ 返回'),
        ('✗ Cancel', '✗ 取消'),
        ('◀ Prev', '◀ 上一页'),
        ('Next ▶', '下一页 ▶'),
        ('✓ Yes', '✓ 是'),
        ('✗ No', '✗ 否'),
        ('✅ Allow Once', '✅ 允许一次'),
        ('✅ Session', '✅ 本会话'),
        ('✅ Always', '✅ 始终允许'),
        ('❌ Deny', '❌ 拒绝'),
        ('✅ Approve Once', '✅ 批准一次'),
        ('🔒 Always Approve', '🔒 始终批准'),
        ('❌ Cancel', '❌ 取消'),
        ('✏️ Other (type answer)', '✏️ 其他（手动输入）'),
        ('f"⚕ *Update needs your input:*\\n\\n{prompt}{default_hint}"', 'f"⚕ *更新需要你确认：*\\n\\n{prompt}{default_hint}"'),
    ],
    'gateway/platforms/wecom.py': [
        ('Connecting to WeCom...', '正在连接企业微信...'),
        ('done.', '完成。'),
        ('Fetching configuration results...', '正在获取配置结果...'),
        ('QR scan timed out ({timeout_seconds // 60} minutes). Please try again.', '二维码扫描超时（{timeout_seconds // 60} 分钟）。请重试。'),
        ('WeCom errcode {errcode}: {errmsg}', '企业微信错误码 {errcode}：{errmsg}'),
        ('failed: unexpected response format', '失败：响应格式异常'),
        ('Scan the QR code above, or open this URL directly: {page_url}', '扫描上方二维码，或直接打开这个链接：{page_url}'),
        ('Tip: pip install qrcode to display a scannable QR code here next time', '提示：安装 qrcode 后，下次这里会显示可扫描二维码'),
        ('WeCom startup failed: aiohttp not installed', '企业微信启动失败：未安装 aiohttp'),
        ('WeCom startup failed: httpx not installed', '企业微信启动失败：未安装 httpx'),
        ('WeCom startup failed: WECOM_BOT_ID and WECOM_SECRET are required', '企业微信启动失败：需要 WECOM_BOT_ID 和 WECOM_SECRET'),
        ('failed: {exc}', '失败：{exc}'),
        ('QR scan reported success but no bot credentials were returned. This usually means the bot was not actually created on the WeCom side. Falling back to manual credential entry.', '二维码扫描显示成功，但没有返回机器人凭据。这通常表示企业微信侧未真正创建机器人。将改为手动输入凭据。'),
        ('WeCom startup failed: {exc}', '企业微信启动失败：{exc}'),
    ],
    'gateway/platforms/weixin.py': [
        ('Weixin startup failed: WEIXIN_TOKEN is required', '微信启动失败：需要 WEIXIN_TOKEN'),
        ('Weixin startup failed: WEIXIN_ACCOUNT_ID is required', '微信启动失败：需要 WEIXIN_ACCOUNT_ID'),
    ],
    'gateway/platforms/whatsapp.py': [
        ('[{self.name}] Bridge started on port {self._bridge_port}', '[{self.name}] Bridge 已在端口 {self._bridge_port} 启动'),
        ('[{self.name}] Check log: {self._bridge_log}', '[{self.name}] 查看日志：{self._bridge_log}'),
        ('[{self.name}] Bridge HTTP ready, waiting for WhatsApp connection...', '[{self.name}] Bridge HTTP 已就绪，正在等待 WhatsApp 连接...'),
        ('[{self.name}] Error building event: {e}', '[{self.name}] 构建事件失败：{e}'),
        ('[{self.name}] ⚠ WhatsApp not connected after 30s', '[{self.name}] ⚠ WhatsApp 30 秒后仍未连接'),
        ('[{self.name}] If session expired, re-pair: hermes whatsapp', '[{self.name}] 如果会话已过期，请重新配对：hermes whatsapp'),
        ('[{self.name}] Error stopping bridge: {e}', '[{self.name}] 停止 Bridge 失败：{e}'),
        ('[{self.name}] Poll error: {e}', '[{self.name}] 轮询错误：{e}'),
        ('[{self.name}] Failed to install dependencies: {e}', '[{self.name}] 安装依赖失败：{e}'),
        ('[{self.name}] Failed to cache image: {e}', '[{self.name}] 缓存图片失败：{e}'),
        ('[{self.name}] Bridge found but not connected (status: {bridge_status}), restarting', '[{self.name}] 已找到 Bridge，但尚未连接（状态：{bridge_status}），正在重启'),
        ('[{self.name}] Skipping text injection for {doc_path} ({file_size} bytes > {MAX_TEXT_INJECT_BYTES})', '[{self.name}] 跳过 {doc_path} 的文本注入（{file_size} 字节 > {MAX_TEXT_INJECT_BYTES}）'),
        ('[{self.name}] Failed to read document text: {e}', '[{self.name}] 读取文档文本失败：{e}'),
        ('[{self.name}] Failed to cache voice: {e}', '[{self.name}] 缓存语音失败：{e}'),
    ],
    'gateway/run.py': [
        ('⚠️ The model provider failed after retries. I kept raw provider details out of chat; check gateway logs for diagnostics.', '⚠️ 模型服务重试后仍失败。原始错误没有发到聊天里；请查看网关日志排查。'),
        ('⚠️ Provider authentication failed. Check the configured credentials; raw provider details are in the gateway logs.', '⚠️ 模型服务认证失败。请检查已配置的凭据；原始错误详情在网关日志里。'),
        ('⚠️ The model provider rejected the request. I kept the raw provider error out of chat; check gateway logs for details or try rephrasing.', '⚠️ 模型服务拒绝了这次请求。原始错误没有发到聊天里；请查看网关日志，或换个说法再试。'),
        ('⏱️ The model provider is rate-limiting requests. Please wait a moment and try again.', '⏱️ 模型服务正在限流。请稍等后再试。'),
        ('⚠️ Processing completed but no response was generated. This may be a transient error — try sending your message again.', '⚠️ 处理已完成，但没有生成回复。这可能是临时错误，请再发一次消息。'),
        ('This main chat is reserved for system commands. To start a new Hermes chat, open the All Messages topic at the top of this bot interface and send any message there. Telegram will create a new topic for that message; each topic works as an independent Hermes session.', '这个主聊天用于系统命令。要开始新的 Hermes 聊天，请打开机器人界面顶部的 All Messages 话题，并在那里发送任意消息。Telegram 会为该消息创建新话题；每个话题都是独立的 Hermes 会话。'),
        ('⚠️ Gateway {action} — {hint}', '⚠️ 网关{action} — {hint}'),
        ('⛔ /{canonical_cmd} is admin-only here. {suffix}', '⛔ /{canonical_cmd} 在这里仅管理员可用。{suffix}'),
        ('✓ Added subgoal {idx}: {text}', '✓ 已添加子目标 {idx}：{text}'),
        ('Failed to join voice channel. Check bot permissions (Connect + Speak).', '加入语音频道失败。请检查机器人权限（Connect + Speak）。'),
        ('Warning: config.yaml → env bridge failed: {type(_bridge_err).__name__}: {_bridge_err}', '警告: config.yaml → env bridge 失败: {type(_bridge_err).__name__}: {_bridge_err}'),
        ('No subgoals to clear.', '没有可清除的子目标。'),
        ('Voice channels are not supported on this platform.', '此平台不支持语音频道。'),
        ('You need to be in a voice channel first.', '你需要先进入语音频道。'),
        ('BotFather → Bot Settings → Threads Settings', 'BotFather → 机器人设置 → 话题设置'),
        ('Multi-session topic mode is not currently enabled for this chat.', '此聊天当前未启用多会话话题模式。'),
        ('Session not found: {raw_session_id.strip()}', '未找到会话：{raw_session_id.strip()}'),
        ('That session is not a Telegram session and cannot be restored into this topic.', '该会话不是 Telegram 会话，不能恢复到此话题。'),
        ('That session does not belong to this Telegram user.', '该会话不属于这个 Telegram 用户。'),
        ('No skill bundles installed. Create one on the host with: `hermes bundles create <name> --skill <s1> --skill <s2>` Directory: `{_bundles_dir()}`', '未安装技能包。可在主机上创建：`hermes bundles create <name> --skill <s1> --skill <s2>` 目录：`{_bundles_dir()}`'),
        ("✗ {format_managed_message('update Hermes Agent')}", "✗ {format_managed_message('更新 Hermes Agent')}"),
        ('⏳ Gateway {self._status_action_gerund()} — queued for the next turn after it comes back.', '⏳ 网关正在{self._status_action_gerund()}，已排到恢复后的下一轮。'),
        ('⏳ Gateway is {self._status_action_gerund()} and is not accepting another turn right now.', '⏳ 网关正在{self._status_action_gerund()}，暂时不能接收新回合。'),
        ('✓ Sent `{label}` to the update process.', '✓ 已向更新流程发送 `{label}`。'),
        ('Queued for the next turn. ({depth} queued)', '已排到下一轮。（当前排队 {depth} 条）'),
        ("⏳ Agent is running — `/{_cmd_def_inner.name}` can't run mid-turn. Wait for the current response or `/stop` first.", '⏳ Agent 正在运行，`/{_cmd_def_inner.name}` 不能在当前回合中执行。请等待当前回复完成，或先用 `/stop`。'),
        ('📬 No home channel is set for {platform_name.title()}. A home channel is where Hermes delivers cron job results and cross-platform messages. Type {sethome_cmd} to make this chat your home channel, or ignore to skip.', '📬 还没有为 {platform_name.title()} 设置主频道。主频道用于接收 Hermes 的定时任务结果和跨平台消息。输入 {sethome_cmd} 可把当前聊天设为主频道；不需要的话可以忽略。'),
        ('✓ {platform.value} paused. Resume with `/platform resume {platform.value}` or `hermes gateway restart` to reset.', '✓ {platform.value} 已暂停。可用 `/platform resume {platform.value}` 恢复，或用 `hermes gateway restart` 重置。'),
        ('{platform.value} is not in the retry queue — nothing to resume.', '{platform.value} 不在重试队列中，无需恢复。'),
        ('{platform.value} is already retrying — no resume needed.', '{platform.value} 已在重试，无需恢复。'),
        ("✓ Cleared {prev} subgoal{'s' if prev != 1 else ''}.", '✓ 已清除 {prev} 个子目标。'),
        ('Failed to join voice channel: {e}', '加入语音频道失败：{e}'),
        ('❌ Background task {task_id} failed: no provider credentials configured.', '❌ 后台任务 {task_id} 失败：未配置模型服务凭据。'),
        ('✅ Background task complete Prompt: "{preview}"', '✅ 后台任务完成。提示词："{preview}"'),
        ('✅ Background task complete Prompt: "{preview}" (No response generated)', '✅ 后台任务完成。提示词："{preview}"（未生成回复）'),
        ('Failed to disable topic mode: {exc}', '关闭话题模式失败：{exc}'),
        ('That session is already linked to another Telegram topic.', '该会话已绑定到另一个 Telegram 话题。'),
        ('🟡 /{command} cancelled. Conversation unchanged.', '🟡 /{command} 已取消。对话未改变。'),
        ('❌ Hermes update timed out after 30 minutes.', '❌ Hermes 更新 30 分钟后超时。'),
        ('⚠️ **Dangerous command requires approval:** ``` {cmd_preview} ``` Reason: {desc} Reply `/approve` to execute, `/approve session` to approve this pattern for the session, `/approve always` to approve permanently, or `/deny` to cancel.', '⚠️ **危险命令需要确认：** ``` {cmd_preview} ``` 原因：{desc} 回复 `/approve` 执行，回复 `/approve session` 在本会话批准此模式，回复 `/approve always` 永久批准，或回复 `/deny` 取消。'),
        ('The **{command_name}** skill is installed but disabled. Enable it with: `hermes skills config`', '**{command_name}** 技能已安装但未启用。可用 `hermes skills config` 启用。'),
        ('The **{command_name}** skill is available but not installed. Install it with: `hermes skills install {install_path}`', '**{command_name}** 技能可用但尚未安装。可用 `hermes skills install {install_path}` 安装。'),
        ("⏳ Queued for the next turn{status_detail}. I'll respond once the current task finishes.", '⏳ 已排到下一轮{status_detail}。当前任务完成后我会回复。'),
        ("⚡ Interrupting current task{status_detail}. I'll respond to your message shortly.", '⚡ 正在中断当前任务{status_detail}。稍后回复你的消息。'),
        ('Queued for the next turn.', '已排到下一轮。'),
        ("{platform.value} is not in the retry queue (it's either connected or not enabled).", '{platform.value} 不在重试队列中（可能已连接，或尚未启用）。'),
        ('Voice dependencies are missing (PyNaCl / davey). Install with: `{sys.executable} -m pip install PyNaCl`', '缺少语音依赖（PyNaCl / davey）。安装命令：`{sys.executable} -m pip install PyNaCl`'),
        ('❌ Background task {task_id} failed: {e}', '❌ 后台任务 {task_id} 失败：{e}'),
        ('System topic for Hermes commands and status.', '用于 Hermes 命令和状态的系统话题。'),
        ('♻ Gateway restarted successfully. Your session continues.', '♻ 网关已成功重启，当前会话继续。'),
        ('✗ Failed to send response to update process: {e}', '✗ 向更新流程发送回复失败：{e}'),
        ("⏩ Steer queued — arrives after the next tool call: '{preview}'", "⏩ 插入消息已排队，会在下一次工具调用后进入：'{preview}'"),
        ("Quick command '/{command}' has no command defined.", "快捷命令 '/{command}' 没有定义命令。"),
        ('✅ Hermes update finished.', '✅ Hermes 更新完成。'),
        ('✅ Hermes update finished. ``` {output} ```', '✅ Hermes 更新完成。``` {output} ```'),
        ('❌ Hermes update failed. ``` {output} ```', '❌ Hermes 更新失败。``` {output} ```'),
        ('✅ Hermes update finished successfully.', '✅ Hermes 更新成功完成。'),
        ('❌ Hermes update failed. Check the gateway logs or run `hermes update` manually for details.', '❌ Hermes 更新失败。请查看网关日志，或手动运行 `hermes update` 获取详情。'),
        ('⚠️ Steer failed: {exc}', '⚠️ 插入消息失败：{exc}'),
        ("Quick command '/{command}' has no target defined.", "快捷命令 '/{command}' 没有定义目标。"),
        ('The **{_skill_name}** skill is disabled for {_plat}. Enable it with: `hermes skills config`', '**{_skill_name}** 技能已对 {_plat} 禁用。可用 `hermes skills config` 启用。'),
        ('⚕ **Update needs your input:** {prompt_text}{default_hint} Reply `/approve` (yes) or `/deny` (no), or type your answer directly.', '⚕ **更新需要你确认：** {prompt_text}{default_hint} 回复 `/approve`（是）或 `/deny`（否），也可以直接输入你的回答。'),
        ('⏳ Still working... ({_elapsed_mins} min elapsed{_status_detail})', '⏳ 仍在处理中...（已用 {_elapsed_mins} 分钟{_status_detail}）'),
        ('Too many pairing requests right now~ Please try again later!', '当前配对请求过多，请稍后再试。'),
        ('f"Hi~ I don\'t recognize you yet!\\n\\n"', 'f"Hi，我还不认识你。\\n\\n"'),
        ('f"Here\'s your pairing code: `{code}`\\n\\n"', 'f"你的配对码是：`{code}`\\n\\n"'),
        ('f"Ask the bot owner to run:\\n"', 'f"请让机器人管理员运行：\\n"'),
        ('"Too many pairing requests right now~ "', '"当前配对请求过多，"'),
        ('"Please try again later!"', '"请稍后再试！"'),
        ('f"📬 No home channel is set for {platform_name.title()}. "', 'f"📬 还没有为 {platform_name.title()} 设置主频道。"'),
        ('f"A home channel is where Hermes delivers cron job results "', 'f"主频道用于接收 Hermes 的定时任务结果"'),
        ('f"and cross-platform messages.\\n\\n"', 'f"和跨平台消息。\\n\\n"'),
        ('f"Type {sethome_cmd} to make this chat your home channel, "', 'f"输入 {sethome_cmd} 可把当前聊天设为主频道；"'),
        ('f"or ignore to skip."', 'f"不需要的话可以忽略。"'),
        ('f"⚕ **Update needs your input:**\\n\\n"', 'f"⚕ **更新需要你确认：**\\n\\n"'),
        ('f"Reply `/approve` (yes) or `/deny` (no), "', 'f"回复 `/approve`（是）或 `/deny`（否），"'),
        ('f"or type your answer directly."', 'f"也可以直接输入你的回答。"'),
        ('f"⏩ Steered into current run{status_detail}. "', 'f"⏩ 已插入当前运行{status_detail}。"'),
        ('f"Your message arrives after the next tool call."', 'f"你的消息会在下一次工具调用后进入。"'),
        ('f"⏳ Queued for the next turn{status_detail}. "', 'f"⏳ 已排到下一轮{status_detail}。"'),
        ('f"I\'ll respond once the current task finishes."', 'f"当前任务完成后我会回复。"'),
        ('f"⚡ Interrupting current task{status_detail}. "', 'f"⚡ 正在中断当前任务{status_detail}。"'),
        ('f"I\'ll respond to your message shortly."', 'f"稍后回复你的消息。"'),
        ('"This main chat is reserved for system commands.\\n\\n"', '"这个主聊天用于系统命令。\\n\\n"'),
        ('"To start a new Hermes chat, open the All Messages topic at the top "', '"要开始新的 Hermes 聊天，请打开顶部的 All Messages 话题"'),
        ('"of this bot interface and send any message there. Telegram will "', '"，并在那里发送任意消息。Telegram 会"'),
        ('"create a new topic for that message; each topic works as an "', '"为该消息创建新话题；每个话题都是"'),
        ('"independent Hermes session."', '"独立的 Hermes 会话。"'),
        ('"To start a new parallel Hermes chat, open the All Messages topic "', '"要开始新的并行 Hermes 聊天，请打开 All Messages 话题"'),
        ('"at the top of this bot interface and send any message there. "', '"，并在那里发送任意消息。"'),
        ('"Telegram will create a new topic for it.\\n\\n"', '"Telegram 会为它创建新话题。\\n\\n"'),
        ('"Each topic is an independent Hermes session. Use /new inside an "', '"每个话题都是独立的 Hermes 会话。仅在"'),
        ('"Started a new Hermes session in this topic.\\n\\n"', '"已在此话题中开始新的 Hermes 会话。\\n\\n"'),
        ('"Tip: for parallel work, open All Messages and send a message there "', '"提示：如需并行处理，请打开 All Messages 并在那里发送消息，"'),
        ('"the session attached to the current topic."', '"当前话题绑定的会话。"'),
        ('"/topic — enable multi-session DM mode (one bot, many parallel chats)\\n"', '"/topic — 启用多会话私信模式（一个机器人，多个并行聊天）\\n"'),
        ('"Usage:\\n"', '"用法：\\n"'),
        ('"  /topic             Enable topic mode, or show status if already on\\n"', '"  /topic             启用话题模式；已启用时显示状态\\n"'),
        ('"  /topic help        Show this message\\n"', '"  /topic help        显示这条帮助\\n"'),
        ('"  /topic off         Disable topic mode and clear topic bindings\\n"', '"  /topic off         关闭话题模式并清除话题绑定\\n"'),
        ('"  /topic <id>        Inside a topic: restore a previous session by ID\\n"', '"  /topic <id>        在话题内：按 ID 恢复之前的会话\\n"'),
        ('"How it works:\\n"', '"工作方式：\\n"'),
        ('"1. Run /topic once in this DM — Hermes checks BotFather Threads\\n"', '"1. 在这个私信里运行一次 /topic，Hermes 会检查 BotFather Threads\\n"'),
        ('"   Settings are enabled and flips on multi-session mode.\\n"', '"   Settings 是否启用，并开启多会话模式。\\n"'),
        ('"2. Tap All Messages at the top of the bot and send any message.\\n"', '"2. 点击机器人顶部的 All Messages，并发送任意消息。\\n"'),
        ('"   Telegram creates a new topic for that message; each topic is\\n"', '"   Telegram 会为该消息创建新话题；每个话题都是\\n"'),
        ('"   an independent Hermes session (fresh history, fresh context).\\n"', '"   独立的 Hermes 会话（全新历史、全新上下文）。\\n"'),
        ('"3. The root DM becomes a system lobby — send /topic, /status,\\n"', '"3. 根私信会变成系统大厅，可在那里发送 /topic、/status、\\n"'),
        ('"   /help, /usage there. Normal prompts go in a topic.\\n"', '"   /help、/usage。普通提示词请发到话题里。\\n"'),
        ('"4. /new inside a topic resets just that topic\'s session.\\n"', '"4. 在话题里使用 /new 仅会重置该话题的会话。\\n"'),
        ('"5. /topic <id> inside a topic restores an old session into it."', '"5. 在话题里使用 /topic <id> 可把旧会话恢复到该话题。"'),
        ('"Telegram multi-session topics are enabled."', '"Telegram 多会话话题已启用。"'),
        ('"To create a new Hermes chat, open All Messages at the top of this "', '"要创建新的 Hermes 聊天，请打开顶部的 All Messages，"'),
        ('"bot interface and send any message there. Telegram will create a "', '"并在那里发送任意消息。Telegram 会为它创建"'),
        ('"new topic for it."', '"新话题。"'),
        ('"Previous unlinked sessions:"', '"之前未绑定的话题会话："'),
        ('"Untitled session"', '"未命名会话"'),
        ('"To restore one:"', '"恢复方式："'),
        ('"1. Create or open a topic. To create a new one, open All Messages and send any message there."', '"1. 创建或打开一个话题。要创建新话题，请打开 All Messages 并在那里发送任意消息。"'),
        ('"2. Send /topic <session-id> inside that topic."', '"2. 在该话题里发送 /topic <session-id>。"'),
        ('f"Example: Send /topic {sessions[0].get(\'id\')} inside a topic."', 'f"示例：在话题里发送 /topic {sessions[0].get(\'id\')}。"'),
        ('"No previous unlinked Telegram sessions found."', '"未找到之前未绑定的话题会话。"'),
        ('"To restore a previous session later:"', '"以后恢复之前会话的方式："'),
    ],
    'hermes_cli/gateway.py': [
        ('✓ {_service_scope_label(system).capitalize()} service {enable_label}!', '✓ {_service_scope_label(system).capitalize()} 服务 {enable_label}!'),
        ('│ ⚕ Hermes Gateway Starting... │', '│ ⚕ Hermes 网关启动中... │'),
        ('│ Messaging platforms + cron scheduler │', '│ 消息平台 + 定时任务调度 │'),
        ('│ Press Ctrl+C to stop │', '│ 按 Ctrl+C 停止 │'),
        ('not configured', '未配置'),
        ('{emoji} {label} configured!', '{emoji} {label} 已配置！'),
        ('The gateway DENIES all users by default for security.', '出于安全考虑，网关默认拒绝所有用户。'),
        ('💬 WeCom configured!', '💬 企业微信已配置！'),
        ('Weixin configured!', '微信已配置！'),
        ('🪽 Feishu / Lark configured!', '🪽 Feishu / Lark 已配置！'),
        ('🐧 QQ Bot configured!', '🐧 QQ Bot 已配置！'),
        ('Signal configured!', 'Signal 已配置！'),
        ('No profiles found.', '未找到配置档。'),
        ('No legacy Hermes gateway units found.', '未找到旧版 Hermes 网关服务单元。'),
        ('(dry-run — nothing removed)', '（演练模式，未移除任何内容）'),
        ('Installing gateway service to run as root.', '正在安装以 root 运行的网关服务。'),
        ('Choose how the gateway should run in the background:', '请选择网关后台运行方式：'),
        ('✓ Systemd linger is enabled (service survives logout)', '✓ systemd linger 已启用（退出登录后服务仍会继续运行）'),
        ('Auto-enable failed: {detail}', '自动启用失败：{detail}'),
        ('✓ Linger enabled — gateway will persist after logout', '✓ linger 已启用，网关会在退出登录后继续运行'),
        ('✗ Gateway service is not installed', '✗ 网关服务未安装'),
        ('⏳ {scope_label} service restarting gracefully (PID {pid})...', '⏳ {scope_label} 服务正在平滑重启（PID {pid}）...'),
        ('⚠ Graceful restart did not complete within {int(drain_timeout + 5)}s; forcing a service restart...', '⚠ 平滑重启未在 {int(drain_timeout + 5)} 秒内完成；正在强制重启服务...'),
        ('⚠ Installed gateway service definition is outdated', '⚠ 已安装的网关服务定义已过期'),
        ('✓ {_service_scope_label(system).capitalize()} gateway service is running', '✓ {_service_scope_label(system).capitalize()} 网关服务正在运行'),
        ('✗ {_service_scope_label(system).capitalize()} gateway service is stopped', '✗ {_service_scope_label(system).capitalize()} 网关服务已停止'),
        ('Configured to run as: {configured_user}', '配置为以该用户运行：{configured_user}'),
        ('Recent gateway health:', '最近网关健康状态：'),
        ('⏳ Restart pending: systemd is waiting to relaunch the gateway', '⏳ 重启待处理：systemd 正在等待重新启动网关'),
        ('✓ System service starts at boot without requiring systemd linger', '✓ 系统服务会随开机启动，不需要 systemd linger'),
        ('⚠ Gateway PID {remaining_pid} still running after {timeout}s — restart may fail', '⚠ 网关 PID {remaining_pid} 在 {timeout} 秒后仍在运行，重启可能失败'),
        ('✓ Service restarted', '✓ 服务已重启'),
        ('✓ Service definition matches the current Hermes install', '✓ 服务定义与当前 Hermes 安装一致'),
        ('⚠ Service definition is stale relative to the current Hermes install', '⚠ 服务定义相对当前 Hermes 安装已过期'),
        ('✓ Gateway service is loaded', '✓ 网关服务已加载'),
        ('✗ Gateway service is not loaded', '✗ 网关服务未加载'),
        ('{label} is already configured.', '{label} 已配置。'),
        ('{label} is already configured (Client ID: {existing}).', '{label} 已配置（Client ID：{existing}）。'),
        ('{emoji} {label} configured via QR scan!', '{emoji} {label} 已通过二维码扫描配置！'),
        ('WeCom is already configured.', '企业微信已配置。'),
        ('How would you like to set up WeCom?', '你想如何设置企业微信？'),
        ('Saved — only these users can interact with the bot.', '已保存，仅这些用户可以和机器人交互。'),
        ('Home channel set to {home}', '主频道已设置为 {home}'),
        ('Weixin is already configured.', '微信已配置。'),
        ('Install them, then rerun `hermes gateway setup`.', '请先安装它们，然后重新运行 `hermes gateway setup`。'),
        ('Cancelled.', '已取消。'),
        ('How should direct messages be authorized?', '私信如何授权？'),
        ('Unknown DM users can request access and you approve them with `hermes pairing approve`.', '未知私信用户可以申请访问，你可用 `hermes pairing approve` 批准。'),
        ('Feishu / Lark is already configured.', 'Feishu / Lark 已配置。'),
        ('How would you like to set up Feishu / Lark?', '你想如何设置 Feishu / Lark？'),
        ('Unknown users can request access; approve with `hermes pairing approve`.', '未知用户可以申请访问；可用 `hermes pairing approve` 批准。'),
        ('Home channel set to {home_channel}', '主频道已设置为 {home_channel}'),
        ('QQ Bot is already configured.', 'QQ Bot 已配置。'),
        ('How would you like to set up QQ Bot?', '你想如何设置 QQ Bot？'),
        ('Signal is already configured.', 'Signal 已配置。'),
        ('Enable group messaging? (disabled by default for security)', '是否启用群消息？（出于安全考虑默认关闭）'),
        ('Gateway service is installed and running.', '网关服务已安装并正在运行。'),
        ('Unable to list profiles.', '无法列出配置档。'),
        ("System service install requires sudo, so Hermes can't create it from this user session.", '安装系统服务需要 sudo，因此 Hermes 不能从当前用户会话创建它。'),
        ('⚠ Systemd linger is disabled (gateway may stop when you log out)', '⚠ systemd linger 未启用（退出登录时网关可能停止）'),
        ('If you want the gateway user service to survive logout, run:', '如果希望网关用户服务在退出登录后继续运行，请执行：'),
        ('Remove the legacy unit(s) before installing?', '安装前是否移除旧服务单元？'),
        ('configured{suffix}', '已配置{suffix}'),
        ('Home channel set to {first_id}', '主频道已设置为 {first_id}'),
        ('Weixin adapter import failed: {exc}', '微信适配器导入失败：{exc}'),
        ('Install gateway dependencies first, then retry.', '请先安装网关依赖，然后重试。'),
        ('QR login failed: {exc}', '二维码登录失败：{exc}'),
        ('Use your Weixin user ID ({user_id}) as the home channel?', '是否把你的微信用户 ID（{user_id}）设为主频道？'),
        ('Home channel set to {user_id}', '主频道已设置为 {user_id}'),
        ('Use your QQ user ID ({user_openid}) as the home channel?', '是否把你的 QQ 用户 ID（{user_openid}）设为主频道？'),
        ('Home channel set to {user_openid}', '主频道已设置为 {user_openid}'),
        ('Home channel set to {home_channel.strip()}', '主频道已设置为 {home_channel.strip()}'),
        ('Gateway service is installed but not running.', '网关服务已安装，但未运行。'),
        ('Gateway service is not installed yet.', '网关服务尚未安装。'),
        ('Select a platform to configure:', '选择要配置的平台：'),
        ('Gateway service installation is not supported on Termux.', 'Termux 不支持安装网关服务。'),
        ('Failed to kill PID {pid}: {exc}', '结束 PID {pid} 失败：{exc}'),
        ('Use your user ID ({first_id}) as the home channel?', '是否把你的用户 ID（{first_id}）设为主频道？'),
        ('QR auth module failed to load ({exc}), falling back to manual input.', '二维码授权模块加载失败（{exc}），改为手动输入。'),
        ('WeCom QR scan import failed: {exc}', '企业微信二维码扫描模块导入失败：{exc}'),
        ('DM pairing mode — users will receive a code to request access.', '私信配对模式：用户会收到验证码来申请访问。'),
        ('Feishu / Lark onboard import failed: {exc}', 'Feishu / Lark 引导模块导入失败：{exc}'),
        ('Add yourself ({user_openid}) to the allow list?', '是否把你自己（{user_openid}）加入允许名单？'),
        ('Restart the gateway to pick up changes?', '是否重启网关以应用更改？'),
        ('Start the gateway service?', '是否启动网关服务？'),
        ('Start the gateway now?', '是否现在启动网关？'),
        ('Start the gateway automatically on login/boot as a {platform_name} service?{wsl_note}', '是否作为 {platform_name} 服务在登录/开机时自动启动网关？{wsl_note}'),
        ('Starting gateway...', '正在启动网关...'),
        ('Start failed: {e}', '启动 失败: {e}'),
        ('Install failed: {e}', '安装失败：{e}'),
        ("✓ Gateway is running (PID: {', '.join(map(str, pids))})", "✓ 网关 正在运行 (PID: {', '.join(map(str, pids))})"),
    ],
    'hermes_cli/pairing.py': [
        ('No pairing data found. No one has tried to pair yet~', '没有配对数据。还没有人尝试配对~'),
        ('No pending pairing requests.', '没有待处理配对请求。'),
        ('Approved Users ({len(approved)}):', '已批准用户（{len(approved)}）：'),
        ('No approved users.', '没有已批准用户。'),
        ('Approved! User {display} on {platform} can now use the bot~', '已批准！{platform} 上的用户 {display} 现在可以使用机器人~'),
        ("They'll be recognized automatically on their next message.", '下次发消息时会自动识别。'),
        ('Revoked access for user {user_id} on {platform}.', '已撤销 {platform} 上用户 {user_id} 的访问权限。'),
        ('User {user_id} not found in approved list for {platform}.', '在 {platform} 的已批准名单中未找到用户 {user_id}。'),
        ('Cleared {count} pending pairing request(s).', '已清除 {count} 个待处理配对请求。'),
        ('No pending requests to clear.', '没有可清除的待处理请求。'),
        ("Platform '{platform}' is locked out after too many failed approval attempts.", "平台 '{platform}' 因批准失败次数过多已被锁定。"),
        ('Lockout clears in ~{mins} minute(s).', '锁定将在约 {mins} 分钟后解除。'),
        ("Code '{code}' not found or expired for platform '{platform}'.", "平台 '{platform}' 中未找到验证码 '{code}'，或验证码已过期。"),
    ],
}
for rel, replacements in gateway_text_replacements.items():
    basic_replacements.setdefault(rel, []).extend(replacements)
# END XIAOMA 2026-05-26 GATEWAY TEXT PATCH

# BEGIN XIAOMA 2026-05-29 HERMES 0.15 PATCH
hermes_015_replacements = {
    "hermes_cli/bundles.py": [
        ("No bundles installed yet. Create one with:", "还没有安装技能包。可用下面命令创建："),
        ("Bundles directory:", "技能包目录："),
        ('"Skill Bundles ({len(bundles)})"', '"技能包（{len(bundles)}）"'),
        ('"Command"', '"命令"'),
        ('"Name"', '"名称"'),
        ('"Skills"', '"技能"'),
        ('"Description"', '"说明"'),
        ("Bundle {args.name!r} not found.", "未找到技能包 {args.name!r}。"),
        ("File:", "文件："),
        ("Instruction:", "说明："),
        ("No skills passed via --skill. Enter one skill name per line.", "未通过 --skill 传入技能。请每行输入一个技能名。"),
        ("Submit an empty line to finish.", "输入空行结束。"),
        ("Cancelled.", "已取消。"),
        ("A bundle must reference at least one skill.", "技能包至少需要引用一个技能。"),
        ("Pass --force to overwrite.", "如需覆盖请加 --force。"),
        ("Created bundle:", "已创建技能包："),
        ("Invoke with:", "调用命令："),
        ("loads", "加载"),
        ("skills)", "个技能）"),
        ("Deleted bundle:", "已删除技能包："),
        ("Added (", "新增（"),
        ("Removed (", "移除（"),
        ("No changes.", "没有变化。"),
        ("bundle(s) loaded.", "个技能包已加载。"),
        ("Total bundles now:", "当前技能包总数："),
        ('help="List installed skill bundles"', 'help="列出已安装技能包"'),
        ('help="Show one bundle\\\'s contents"', 'help="查看某个技能包内容"'),
        ('help="Bundle name"', 'help="技能包名称"'),
        ('help="Create a new skill bundle"', 'help="创建新技能包"'),
        ("Create a new bundle. Skills can be passed via --skill (repeat for multiple) or entered interactively when omitted.", "创建新技能包。可通过 --skill 多次传入技能；省略时进入交互输入。"),
        ('help="Bundle name (becomes the /slash command)"', 'help="技能包名称（会成为 / 斜杠命令）"'),
        ('help="Skill name to include (repeat for multiple)"', 'help="要加入的技能名（可重复）"'),
        ('help="Human-readable description shown in /help and `hermes bundles list`"', 'help="显示在 /help 和 `hermes bundles list` 中的说明"'),
        ('help="Extra guidance prepended to the loaded skill content"', 'help="加载技能内容前附加的额外说明"'),
        ('help="Overwrite an existing bundle with the same name"', 'help="覆盖同名技能包"'),
        ('help="Delete a skill bundle"', 'help="删除技能包"'),
        ('help="Re-scan the bundles directory and report changes"', 'help="重新扫描技能包目录并报告变化"'),
    ],
    "agent/skill_bundles.py": [
        ("Load {len(skills)} skills as a bundle", "把 {len(skills)} 个技能作为技能包加载"),
        ('[Loaded as part of the "', '[作为技能包 "'),
        ('" skill bundle.]', '" 的一部分加载。]'),
        ('[IMPORTANT: The user has invoked the "', '[重要：用户调用了技能包 "'),
        ('" skill bundle, loading', '"，正在同时加载'),
        ("skills together. Treat every skill below as active guidance for this turn.]", "个技能。请把下方每个技能都视为本轮有效指导。]"),
        ("Bundle:", "技能包："),
        ("Skills loaded:", "已加载技能："),
        ("Skills missing (skipped):", "缺失技能（已跳过）："),
        ("Bundle instruction:", "技能包说明："),
        ("User instruction:", "用户说明："),
        ("Bundle name is required", "技能包名称不能为空"),
        ("Bundle must reference at least one skill", "技能包至少需要引用一个技能"),
        ("Bundle already exists at", "技能包已存在："),
        ("No bundle at", "未找到技能包："),
    ],
    "hermes_cli/mcp_picker.py": [
        ('_STATUS_NOT_INSTALLED = "available"', '_STATUS_NOT_INSTALLED = "可安装"'),
        ('_STATUS_DISABLED = "installed (disabled)"', '_STATUS_DISABLED = "已安装（未启用）"'),
        ('_STATUS_ENABLED = "enabled"', '_STATUS_ENABLED = "已启用"'),
        ('_STATUS_CUSTOM_ENABLED = "custom — enabled"', '_STATUS_CUSTOM_ENABLED = "自定义 — 已启用"'),
        ('_STATUS_CUSTOM_DISABLED = "custom — disabled"', '_STATUS_CUSTOM_DISABLED = "自定义 — 未启用"'),
        ('"(no transport)"', '"（未配置传输）"'),
        ("is not installed.", "尚未安装。"),
        ("'enabled' if enable else 'disabled'", "'已启用' if enable else '已停用'"),
        ("Start a new Hermes session for changes to take effect.", "请新开 Hermes 会话使变更生效。"),
        ("Remove '{name}' from mcp_servers?", "是否从 mcp_servers 移除 '{name}'？"),
        ("✓ Removed", "✓ 已移除"),
        ("Configure tools (probe server + re-pick)", "配置工具（探测服务后重新选择）"),
        ("Remove from config", "从配置移除"),
        ("Action for", "操作"),
        ("is already enabled.", "已经启用。"),
        ("Disable (keep config, stop loading on next session)", "停用（保留配置，下次会话不加载）"),
        ("Uninstall (remove config and any cloned files)", "卸载（移除配置和已克隆文件）"),
        ("Reinstall (re-clone, re-prompt for credentials)", "重新安装（重新克隆并重新输入凭据）"),
        ("Credentials in .env preserved — delete manually if no longer needed.", ".env 中的凭据已保留；不再需要时请手动删除。"),
        ("was not installed", "尚未安装"),
        ("reinstall failed:", "重新安装失败："),
        ("No MCPs in the catalog or configured.", "目录和配置中都没有 MCP。"),
        ("MCP Catalog + configured servers:", "MCP 目录和已配置服务："),
        ("Name", "名称"),
        ("Status", "状态"),
        ("Description", "说明"),
        ("Install: hermes mcp install <name>    Picker: hermes mcp", "安装：hermes mcp install <name>    选择器：hermes mcp"),
        ("requires a newer Hermes — run `hermes update` to install this entry.", "需要更新版 Hermes。请运行 `hermes update` 后再安装。"),
        ("MCP Catalog  —  ↑↓ navigate  ENTER act on entry  ESC/q quit", "MCP 目录  —  ↑↓ 选择  ENTER 操作  ESC/q 退出"),
        ("is not in the catalog. Run `hermes mcp catalog` to see available entries.", "不在目录中。运行 `hermes mcp catalog` 查看可用条目。"),
        ("install failed:", "安装失败："),
    ],
    "hermes_cli/secrets_cli.py": [
        ('help="Interactive wizard: install bws, store access token, pick project"', 'help="交互式向导：安装 bws、保存访问令牌、选择项目"'),
        ('help="Pre-select a project UUID instead of prompting"', 'help="预先指定项目 UUID，不再交互询问"'),
        ('help="Provide the access token non-interactively (will be stored in .env)"', 'help="非交互提供访问令牌（会保存到 .env）"'),
        ("Bitwarden region / self-hosted endpoint.", "Bitwarden 区域或自托管地址。"),
        ("Skips the interactive region prompt.", "跳过区域交互选择。"),
        ('help="Show config + binary + last fetch"', 'help="显示配置、二进制文件和最近拉取结果"'),
        ('help="Fetch secrets now and report what changed"', 'help="立即拉取密钥并报告变化"'),
        ("Actually export the secrets into the current shell's env (default: dry-run)", "实际导出到当前 shell 环境变量（默认演练）"),
        ('help="Turn off the Bitwarden integration"', 'help="关闭 Bitwarden 集成"'),
        ("Download and verify the pinned bws binary", "下载并校验固定版本 bws 二进制文件"),
        ('help="Re-download even if a managed copy already exists"', 'help="即使已存在托管副本也重新下载"'),
        ("Bitwarden Secrets Manager setup", "Bitwarden Secrets Manager 配置"),
        ("Need an access token? In the Bitwarden web app:", "需要访问令牌？请在 Bitwarden 网页端操作："),
        ("Copy the token", "复制令牌"),
        ("it cannot be retrieved later.", "之后无法再次查看。"),
        ("Step 1", "步骤 1"),
        ("Install the bws CLI", "安装 bws CLI"),
        ("No bws on PATH — downloading…", "PATH 中没有 bws，正在下载…"),
        ("Could not install bws:", "无法安装 bws："),
        ("Manual install:", "手动安装："),
        ("Step 2", "步骤 2"),
        ("Provide your access token", "提供访问令牌"),
        ("Paste access token", "粘贴访问令牌"),
        ("Empty token, aborting.", "令牌为空，已中止。"),
        ("Warning: token doesn't start with '0.'", "警告：令牌不是以 '0.' 开头"),
        ("stored in", "已保存到"),
        ("Step 3", "步骤 3"),
        ("Pick a Bitwarden region", "选择 Bitwarden 区域"),
        ("using bws default", "使用 bws 默认值"),
        ("Step 4", "步骤 4"),
        ("Pick a project", "选择项目"),
        ("No projects visible to this machine account.", "此机器账号看不到任何项目。"),
        ("and grant it access to at least one project.", "并授予它至少一个项目的访问权限。"),
        ('table.add_column("ID", style="dim")', 'table.add_column("ID", style="dim")'),
        ("Select project", "选择项目"),
        ("Enter a number.", "请输入数字。"),
        ("Out of range — pick", "超出范围，请选择"),
        ("Test fetch", "测试拉取"),
        ("Fetch failed:", "拉取失败："),
        ("Fetch succeeded but the project has no secrets.", "拉取成功，但项目中没有密钥。"),
        ("bootstrap token — never overrides itself", "引导令牌，不会覆盖自身"),
        ("already set in env (will be overwritten)", "环境变量中已存在（会被覆盖）"),
        ("warning:", "警告："),
        ("Bitwarden Secrets Manager is enabled.", "Bitwarden Secrets Manager 已启用。"),
        ("Secrets will be pulled at the start of every Hermes process.", "每次 Hermes 进程启动时都会拉取密钥。"),
        ("Status:", "状态："),
        ("Refresh:", "刷新："),
        ("Disable:", "停用："),
        ("Enabled", "已启用"),
        ("Token env var", "令牌环境变量"),
        ("Token in env", "环境中有令牌"),
        ("Project ID", "项目 ID"),
        ("Server URL", "服务地址"),
        ("Override existing", "覆盖已有值"),
        ("Cache TTL (s)", "缓存 TTL（秒）"),
        ("Auto-install", "自动安装"),
        ("not installed", "未安装"),
        ("Run [cyan]hermes secrets bitwarden setup[/cyan] to enable.", "运行 [cyan]hermes secrets bitwarden setup[/cyan] 启用。"),
        ("Enabled but", "已启用，但"),
        ("is not set", "未设置"),
        ("no project_id", "没有 project_id"),
        ("nothing to fetch", "没有可拉取内容"),
        ("Bitwarden integration is disabled.", "Bitwarden 集成已停用。"),
        ("No project_id configured.", "未配置 project_id。"),
        ("No secrets in project.", "项目中没有密钥。"),
        ("skip (bootstrap token)", "跳过（引导令牌）"),
        ("skip (already set)", "跳过（已设置）"),
        ("exported", "已导出"),
        ("would export", "将导出"),
        ("This was a dry-run", "这是一次演练"),
        ("Exported {applied} secret(s) into current process.", "已向当前进程导出 {applied} 个密钥。"),
        ("Disabled.", "已停用。"),
        ("Bitwarden secrets will NOT be pulled on the next Hermes invocation.", "下次调用 Hermes 时不会拉取 Bitwarden 密钥。"),
        ("Install failed:", "安装失败："),
        ("version unknown", "版本未知"),
        ("Couldn't list projects:", "无法列出项目："),
        ("bws project list failed:", "bws project list 失败："),
        ("This usually means the access token is wrong or revoked.", "这通常表示访问令牌错误或已撤销。"),
        ("bws returned non-JSON:", "bws 返回了非 JSON 内容："),
        ("Region / endpoint", "区域 / 地址"),
        ("Self-hosted / custom URL", "自托管 / 自定义地址"),
        ("Select region", "选择区域"),
        ("Enter your Bitwarden server URL", "输入你的 Bitwarden 服务地址"),
        ("Empty URL, aborting.", "地址为空，已中止。"),
    ],
    "agent/secret_sources/bitwarden.py": [
        ("secrets.bitwarden.enabled is true but", "secrets.bitwarden.enabled 为 true，但"),
        ("not set.  Run `hermes secrets bitwarden setup`.", "未设置。请运行 `hermes secrets bitwarden setup`。"),
        ("secrets.bitwarden.project_id is empty.", "secrets.bitwarden.project_id 为空。"),
        ("bws binary not available and auto-install is disabled.", "bws 二进制文件不可用，且自动安装已关闭。"),
        ("Run `hermes secrets bitwarden setup` to install.", "请运行 `hermes secrets bitwarden setup` 安装。"),
        ("Unsupported platform for bws auto-install:", "当前平台不支持自动安装 bws："),
        ("No checksum entry for", "未找到校验项："),
        ("Bitwarden access token is empty", "Bitwarden 访问令牌为空"),
        ("Bitwarden project_id is empty", "Bitwarden project_id 为空"),
        ("bws exited", "bws 已退出"),
        ("bws returned no output (empty project?)", "bws 没有返回内容（项目为空？）"),
        ("bws returned unexpected shape:", "bws 返回结构异常："),
        ("bws auto-install failed:", "bws 自动安装失败："),
    ],
    "hermes_cli/migrate.py": [
        ("usage: hermes migrate xai [--apply] [--no-backup]", "用法：hermes migrate xai [--apply] [--no-backup]"),
        ("◆ xAI Model Retirement Migration", "◆ xAI 模型退役迁移"),
        ("No retired xAI models in config — nothing to migrate.", "配置中没有已退役的 xAI 模型，无需迁移。"),
        ("Found", "发现"),
        ("retired xAI model reference(s):", "处已退役 xAI 模型引用："),
        ("Migration guide:", "迁移指南："),
        ("Dry-run mode — no changes written.", "演练模式：不会写入更改。"),
        ("Re-run with `hermes migrate xai --apply` to rewrite", "重新运行 `hermes migrate xai --apply` 可改写"),
        ("in-place (backup created automatically).", "原文件（会自动创建备份）。"),
        ("Could not locate config.yaml", "未找到 config.yaml"),
        ("Migration failed:", "迁移失败："),
        ("No changes written.", "没有写入更改。"),
        ("Backup:", "备份："),
        ("Updated", "已更新"),
        ("slot(s) in", "处配置："),
        ("Run `hermes doctor` to confirm no retired xAI models remain.", "运行 `hermes doctor` 确认没有残留的已退役 xAI 模型。"),
    ],
    "plugins/platforms/ntfy/plugin.yaml": [
        ("ntfy push-notification gateway adapter for Hermes Agent.", "Hermes Agent 的 ntfy 推送通知网关适配器。"),
        ("Subscribes to a topic on ntfy.sh or any self-hosted ntfy server via", "通过 HTTP 流订阅 ntfy.sh 或任意自托管 ntfy 服务上的主题，"),
        ("HTTP streaming, and publishes replies via HTTP POST. Lightweight —", "并通过 HTTP POST 发布回复。轻量化实现，"),
        ("no external SDK, only httpx (already a Hermes dependency).", "无需额外 SDK，仅使用 httpx（Hermes 已依赖）。"),
        ("Topic name to subscribe to (e.g. hermes-in)", "要订阅的主题名（例如 hermes-in）"),
        ("ntfy subscribe topic", "ntfy 订阅主题"),
        ("ntfy server URL (default: https://ntfy.sh)", "ntfy 服务地址（默认：https://ntfy.sh）"),
        ("ntfy server URL", "ntfy 服务地址"),
        ("Bearer token or 'user:pass' for Basic auth (optional)", "Bearer 令牌或 Basic 认证用的 user:pass（可选）"),
        ("ntfy auth token (or empty)", "ntfy 认证令牌（可留空）"),
        ("Topic to publish replies to (defaults to NTFY_TOPIC)", "回复发布主题（默认 NTFY_TOPIC）"),
        ("ntfy publish topic (or empty)", "ntfy 发布主题（可留空）"),
        ("Enable markdown formatting? (true/false)", "启用 Markdown 格式？（true/false）"),
        ("Comma-separated topic names allowed (allowlist)", "允许的主题名，用逗号分隔"),
        ("Allowed topic names (comma-separated)", "允许的主题名（逗号分隔）"),
        ("Allow any topic to talk to the bot (dev only — disables allowlist)", "允许任意主题访问机器人（开发用途，会停用允许名单）"),
        ("Allow all topics? (true/false)", "允许全部主题？（true/false）"),
        ("Default topic for cron / notification delivery", "定时任务 / 通知投递的默认主题"),
        ("Home channel topic (or empty)", "主频道主题（可留空）"),
        ("Human label for the home channel (defaults to the topic name)", "主频道显示名称（默认使用主题名）"),
        ("Home channel display name (or empty)", "主频道显示名称（可留空）"),
    ],
    "plugins/image_gen/krea/plugin.yaml": [
        ("Krea image generation backend (Krea 2 Large + Krea 2 Medium foundation models).", "Krea 图像生成后端（Krea 2 Large 和 Krea 2 Medium 基础模型）。"),
    ],
    "plugins/web/xai/plugin.yaml": [
        ("xAI Web Search — search the web via Grok's agentic web_search tool (Responses API). Requires xAI Grok OAuth (via `hermes auth`) or XAI_API_KEY (https://x.ai).", "xAI 网页搜索：通过 Grok 的 agentic web_search 工具（Responses API）搜索网页。需要通过 `hermes auth` 配置 xAI Grok OAuth，或设置 XAI_API_KEY（https://x.ai）。"),
    ],
}
for rel, replacements in hermes_015_replacements.items():
    basic_replacements.setdefault(rel, []).extend(replacements)
# END XIAOMA 2026-05-29 HERMES 0.15 PATCH

for rel, replacements in basic_replacements.items():
    path = root / rel
    if not path.exists():
        missing.append(rel)
        continue
    original = path.read_text(encoding="utf-8", errors="ignore")
    updated = original
    for old, new in replacements:
        updated = updated.replace(old, new)
    if rel == "hermes_cli/banner.py":
        updated = re.sub(
            r'''(?ms)^HERMES_AGENT_LOGO\s*=\s*(?:"""[\s\S]*?"""|''' + "'''[\\s\\S]*?'''" + r'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''',
            lambda _m: "HERMES_AGENT_LOGO = " + repr(zh_banner_logo),
            updated,
            count=1,
        )
        updated = re.sub(
            r'''(?ms)^HERMES_CADUCEUS\s*=\s*(?:"""[\s\S]*?"""|''' + "'''[\\s\\S]*?'''" + r'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''',
            lambda _m: "HERMES_CADUCEUS = " + repr(zh_horse_head),
            updated,
            count=1,
        )
        updated = re.sub(
            r'def _display_toolset_name\(toolset_name: str\) -> str:\n.*?(?=\n\ndef build_welcome_banner)',
            banner_display_helpers.rstrip(),
            updated,
            count=1,
            flags=re.S,
        )
        updated = updated.replace(
            'right_lines.append(f"[dim {dim}]{category}:[/] [{text}]{skills_str}[/]")',
            'right_lines.append(f"[dim {dim}]{_display_skill_category_name(category)}:[/] [{text}]{skills_str}[/]")',
        )
    if rel == "cli.py":
        updated = re.sub(
            r'''(?ms)^HERMES_AGENT_LOGO\s*=\s*(?:"""[\s\S]*?"""|''' + "'''[\\s\\S]*?'''" + r'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''',
            lambda _m: "HERMES_AGENT_LOGO = " + repr(zh_banner_logo),
            updated,
            count=1,
        )
        updated = re.sub(
            r'''(?ms)^HERMES_CADUCEUS\s*=\s*(?:"""[\s\S]*?"""|''' + "'''[\\s\\S]*?'''" + r'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''',
            lambda _m: "HERMES_CADUCEUS = " + repr(zh_horse_head),
            updated,
            count=1,
        )
    if rel == "ui-tui/src/banner.ts":
        updated = re.sub(
            r'const LOGO_ART = \[[\s\S]*?\]\n\nconst CADUCEUS_ART',
            lambda _m: "const LOGO_ART = " + json.dumps(zh_banner_logo_plain, ensure_ascii=False) + "\n\nconst CADUCEUS_ART",
            updated,
            count=1,
        )
        updated = re.sub(
            r'const CADUCEUS_ART = \[[\s\S]*?\]\n\nconst LOGO_GRADIENT',
            lambda _m: "const CADUCEUS_ART = " + json.dumps(zh_horse_head_plain, ensure_ascii=False) + "\n\nconst LOGO_GRADIENT",
            updated,
            count=1,
        )
        updated = updated.replace("export const LOGO_WIDTH = 98", "export const LOGO_WIDTH = 76")
        updated = updated.replace("export const CADUCEUS_WIDTH = 30", "export const CADUCEUS_WIDTH = 28")
    if rel == "hermes_cli/commands.py":
        if "_ZH_COMMAND_DESCRIPTIONS" not in updated:
            updated = updated.replace(
                "\n\ndef _build_description(cmd: CommandDef) -> str:\n",
                "\n\n" + command_localization_helpers.rstrip() + "\n\ndef _build_description(cmd: CommandDef) -> str:\n",
                1,
            )
        if "_ZH_COMMAND_DESCRIPTIONS" not in updated and "COMMANDS_BY_CATEGORY = {" in updated and "CommandDef(" not in updated:
            flat_command_localization = r'''

_ZH_COMMAND_DESCRIPTIONS = {
    "/new": "开始新会话",
    "/reset": "重置会话",
    "/clear": "清屏并重置会话",
    "/history": "查看会话历史",
    "/save": "保存当前会话",
    "/retry": "重试上一条消息",
    "/undo": "撤销上一轮对话",
    "/title": "设置当前会话标题（用法：/title 我的会话名）",
    "/compress": "压缩当前上下文",
    "/rollback": "查看或恢复文件检查点（用法：/rollback [编号]）",
    "/background": "在后台运行任务（用法：/background <提示词>）",
    "/config": "查看当前配置",
    "/model": "查看或切换模型",
    "/provider": "查看可用服务商和当前服务商",
    "/prompt": "查看或设置系统提示词",
    "/personality": "设置预设人格",
    "/verbose": "切换工具进度显示级别",
    "/reasoning": "管理推理强度和显示方式（用法：/reasoning [级别|show|hide]）",
    "/skin": "查看或切换显示主题",
    "/tools": "列出可用工具",
    "/toolsets": "列出可用工具集",
    "/skills": "搜索、安装、查看或管理技能",
    "/cron": "管理定时任务",
    "/reload-mcp": "重新加载 MCP 服务",
    "/help": "查看帮助",
    "/usage": "查看当前会话 token 用量",
    "/insights": "查看用量洞察",
    "/platforms": "查看平台状态",
    "/paste": "读取剪贴板图片并加入消息",
    "/quit": "退出命令行",
}

_ZH_COMMAND_CATEGORIES = {
    "Session": "会话",
    "Configuration": "配置",
    "Tools & Skills": "工具与技能",
    "Info": "信息",
    "Exit": "退出",
}

COMMANDS_BY_CATEGORY = {
    _ZH_COMMAND_CATEGORIES.get(category, category): {
        cmd: _ZH_COMMAND_DESCRIPTIONS.get(cmd, desc)
        for cmd, desc in commands.items()
    }
    for category, commands in COMMANDS_BY_CATEGORY.items()
}

COMMANDS = {}
for category_commands in COMMANDS_BY_CATEGORY.values():
    COMMANDS.update(category_commands)
'''
            updated = updated.replace(
                "\n\nclass SlashCommandCompleter(Completer):\n",
                flat_command_localization + "\n\nclass SlashCommandCompleter(Completer):\n",
                1,
            )
        updated = re.sub(
            r'def _build_description\(cmd: CommandDef\) -> str:\n    """Build a CLI-facing description string including usage hint\."""\n    if cmd\.args_hint:\n        return f"\{cmd\.description\} \(usage: /\{cmd\.name\} \{cmd\.args_hint\}\)"\n    return cmd\.description',
            'def _build_description(cmd: CommandDef) -> str:\n    """Build a CLI-facing description string including usage hint."""\n    desc = _zh_command_description(cmd)\n    args_hint = _zh_command_args_hint(cmd)\n    if args_hint:\n        return f"{desc}（用法：/{cmd.name} {args_hint}）"\n    return desc',
            updated,
            count=1,
        )
        updated = updated.replace(
            'COMMANDS[f"/{_alias}"] = f"{_cmd.description} (alias for /{_cmd.name})"',
            'COMMANDS[f"/{_alias}"] = f"{_zh_command_description(_cmd)}（/{_cmd.name} 的别名）"',
        )
        updated = updated.replace(
            '_cat = COMMANDS_BY_CATEGORY.setdefault(_cmd.category, {})',
            '_cat = COMMANDS_BY_CATEGORY.setdefault(_zh_command_category(_cmd.category), {})',
        )
        updated = updated.replace(
            'args = f" {cmd.args_hint}" if cmd.args_hint else ""',
            'args_hint = _zh_command_args_hint(cmd)\n        args = f" {args_hint}" if args_hint else ""',
        )
        updated = updated.replace(
            'alias_note = f" (alias: {\', \'.join(alias_parts)})" if alias_parts else ""',
            'alias_note = f"（别名：{\', \'.join(alias_parts)}）" if alias_parts else ""',
        )
        updated = updated.replace(
            'lines.append(f"`/{cmd.name}{args}` -- {cmd.description}{alias_note}")',
            'lines.append(f"`/{cmd.name}{args}` — {_zh_command_description(cmd)}{alias_note}")',
        )
        updated = updated.replace(
            'result.append((tg_name, cmd.description))',
            'result.append((tg_name, _zh_command_description(cmd)))',
        )
        updated = updated.replace(
            'entries.append(("hermes", "Talk to Hermes or run a subcommand", "[subcommand] [args]"))',
            'entries.append(("hermes", "与 Hermes 对话或运行子命令", "[子命令] [参数]"))',
        )
        updated = updated.replace(
            '_add(cmd.name, cmd.description, cmd.args_hint or "")',
            '_add(cmd.name, _zh_command_description(cmd), _zh_command_args_hint(cmd) or "")',
        )
        updated = updated.replace(
            '_add(alias, f"Alias for /{cmd.name} — {cmd.description}", cmd.args_hint or "")',
            '_add(alias, f"/{cmd.name} 的别名 — {_zh_command_description(cmd)}", _zh_command_args_hint(cmd) or "")',
        )

    if updated != original:
        backup_file(path, rel)
        path.write_text(updated, encoding="utf-8")
        patched.append(rel)
    else:
        unchanged.append(rel)

tips_rel = "hermes_cli/tips.py"
tips_path = root / tips_rel
if tips_path.exists():
    original = tips_path.read_text(encoding="utf-8", errors="ignore")
    start = original.find("TIPS = [")
    end = original.find("\n]\n", start)
    if start >= 0 and end > start:
        updated = original[:start] + zh_tips + original[end + 3 :]
        if updated != original:
            backup_file(tips_path, tips_rel)
            tips_path.write_text(updated, encoding="utf-8")
            patched.append(tips_rel)
        else:
            unchanged.append(tips_rel)
    else:
        missing.append(tips_rel)
else:
    missing.append(tips_rel)

tui_build = {"state": "not_needed"}
tui_dir = root / "ui-tui"
if tui_dir.exists() and (
    "ui-tui/src/banner.ts" in patched
    or "ui-tui/src/theme.ts" in patched
    or "ui-tui/src/components/branding.tsx" in patched
):
    npm = shutil.which("npm")
    if npm:
        try:
            node_modules = tui_dir / "node_modules"
            if not node_modules.exists():
                install_result = subprocess.run(
                    [npm, "install", "--silent", "--no-fund", "--no-audit", "--progress=false"],
                    cwd=tui_dir,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=180,
                )
                if install_result.returncode != 0:
                    combined = ((install_result.stdout or "") + "\n" + (install_result.stderr or "")).strip()
                    raise RuntimeError("\n".join(combined.splitlines()[-20:]) or "npm install failed")
            result = subprocess.run(
                [npm, "run", "build"],
                cwd=tui_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=180,
            )
        except Exception as exc:
            tui_build = {"state": "failed", "message": str(exc)}
        else:
            if result.returncode == 0:
                tui_build = {"state": "built"}
            else:
                combined = ((result.stdout or "") + "\n" + (result.stderr or "")).strip()
                tui_build = {
                    "state": "failed",
                    "message": "\n".join(combined.splitlines()[-20:]),
                }
    else:
        tui_build = {"state": "skipped", "message": "npm not found"}

status = {
    "state": "applied" if patched else "already_applied",
    "version": package_version,
    "root": str(root),
    "patched": sorted(set(patched)),
    "unchanged": sorted(set(unchanged)),
    "missing": sorted(set(missing)),
    "backup": str(backup_root),
    "skin": xiaoma_skin_state,
    "tui_build": tui_build,
}

validation = []
def check_contains(rel, needles):
    path = root / rel
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    lower_text = text.lower()
    for needle in needles:
        escaped = needle.encode("unicode_escape").decode("ascii").lower()
        if needle not in text and escaped not in lower_text:
            validation.append(f"{rel} 缺少 {needle}")

check_contains("hermes_cli/banner.py", ["爱马仕机器人", "可用工具", "⠘⢛⣿", "⢀⣠⣴⣾"])
check_contains("hermes_cli/commands.py", ["_ZH_COMMAND_DESCRIPTIONS", "用法："])
check_contains("cli.py", ["爱马仕机器人", "允许一次"])
check_contains("ui-tui/src/theme.ts", ["name: '爱马仕机器人'", "icon: '♞'"])
check_contains("ui-tui/src/banner.ts", ["⠘⢛⣿", "⢀⣠⣴⣾"])
check_contains("ui-tui/src/components/branding.tsx", ["爱马仕机器人", "可用工具"])
if (root / "ui-tui" / "dist").exists():
    check_contains("ui-tui/dist/theme.js", ["name: '爱马仕机器人'", "icon: '♞'"])
    check_contains("ui-tui/dist/banner.js", ["⠘⢛⣿", "⢀⣠⣴⣾"])
    check_contains("ui-tui/dist/components/branding.js", ["爱马仕机器人", "可用工具"])

if os.environ.get("XIAOMA_HERMES_SKIP_CONFIG", "0") != "1":
    skin_path = hermes_home / "skins" / "xiaoma-zh.yaml"
    config_path = hermes_home / "config.yaml"
    if xiaoma_skin_state.get("state") == "failed":
        validation.append("中文皮肤写入失败")
    elif not skin_path.exists():
        validation.append("中文皮肤文件缺失")
    else:
        skin_text = skin_path.read_text(encoding="utf-8", errors="ignore")
        for needle in ("⠘⢛⣿", "⢀⣠⣴⣾", "banner_logo", "banner_hero"):
            if needle not in skin_text:
                validation.append(f"中文皮肤缺少 {needle}")
    if not config_path.exists():
        validation.append("Hermes 配置文件缺失")
    else:
        config_text = config_path.read_text(encoding="utf-8", errors="ignore")
        if "skin: xiaoma-zh" not in config_text:
            validation.append("Hermes 当前皮肤未切换到 xiaoma-zh")

status["validation"] = validation
if validation:
    status["state"] = "partial"
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
if validation:
    print("TUI补丁：自检发现未完成项")
    for item in validation:
        print(f"- {item}")
elif patched:
    print(f"TUI补丁：已应用 {len(set(patched))} 个文件")
else:
    print("TUI补丁：已是最新")
PY_PATCH
}

find_asar_cli() {
  for item in \
    "$HERMES_HOME_DIR/hermes-agent/node_modules/@electron/asar/bin/asar.js" \
    "$HOME/.hermes/hermes-agent/node_modules/@electron/asar/bin/asar.js" \
    "$PWD/node_modules/@electron/asar/bin/asar.js"; do
    if [ -f "$item" ]; then
      printf '%s\n' "$item"
      return
    fi
  done
  printf '\n'
}

apply_desktop_app_patch() {
  if [ "${XIAOMA_HERMES_SKIP_DESKTOP_PATCH:-0}" = "1" ]; then
    say "桌面端补丁：已按环境变量跳过。"
    return
  fi

  local node_cmd asar_cli
  node_cmd="$(command -v node 2>/dev/null || true)"
  asar_cli="$(find_asar_cli)"
  if [ -z "$node_cmd" ] || [ -z "$asar_cli" ]; then
    say "桌面端补丁：缺少 Node.js 或 asar 工具，暂未处理桌面应用资源。"
    return
  fi

  local app found_any patched_any
  found_any="0"
  patched_any="0"
  while IFS= read -r app; do
    if [ -z "$app" ]; then
      continue
    fi
    found_any="1"

    local asar_file plist_file work_dir new_asar safe_name backup_dir marker_file
    if [ -d "$app/Contents/Resources" ]; then
      asar_file="$app/Contents/Resources/app.asar"
      plist_file="$app/Contents/Info.plist"
    else
      say "桌面端补丁：不支持的路径，已跳过：$app"
      continue
    fi
    if [ ! -f "$asar_file" ]; then
      say "桌面端补丁：未找到 app.asar，已跳过：$app"
      continue
    fi

    safe_name="$(printf '%s' "$app" | tr '/ ' '__')"
    backup_dir="$INSTALL_HOME/backups/$PACKAGE_VERSION/desktop-apps/$safe_name"
    work_dir="$TMP_DIR/desktop-app-$safe_name"
    new_asar="$TMP_DIR/$safe_name.app.asar"
    marker_file="$work_dir/.xiaoma-desktop-changed"
    rm -rf "$work_dir"
    mkdir -p "$work_dir" "$backup_dir"

    if [ ! -f "$backup_dir/app.asar" ]; then
      cp "$asar_file" "$backup_dir/app.asar"
    fi
    if [ -f "$plist_file" ] && [ ! -f "$backup_dir/Info.plist" ]; then
      cp "$plist_file" "$backup_dir/Info.plist"
    fi

    if ! "$node_cmd" "$asar_cli" extract "$asar_file" "$work_dir" >/dev/null 2>&1; then
      say "桌面端补丁：解包失败，已跳过：$app"
      continue
    fi

    python3 - "$work_dir" "$marker_file" <<'PY_DESKTOP_PATCH'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
marker = Path(sys.argv[2])

replacements = [
    ("`Drop files to attach`", "`拖放文件即可添加`"),
    ("`Attach`", "`添加`"),
    ("`Files`", "`文件`"),
    ("`Folders`", "`文件夹`"),
    ("`Images`", "`图片`"),
    ("`URL`", "`链接`"),
    ("`Send`", "`发送`"),
    ("`Cancel`", "`取消`"),
    ("`Run`", "`运行`"),
    ("`Search`", "`搜索`"),
    ("`Sessions`", "`会话`"),
    ("`Tools`", "`工具`"),
    ("`Toolsets`", "`工具集`"),
    ("`Skills & Tools`", "`技能与工具`"),
    ("`Models`", "`模型`"),
    ("`Model`", "`模型`"),
    ("`Terminal`", "`终端`"),
    ("`Browser`", "`浏览器`"),
    ("`Preview`", "`预览`"),
    ("`Close`", "`关闭`"),
    ("`Save`", "`保存`"),
    ("`Archive`", "`归档`"),
    ("`Copy`", "`复制`"),
    ("`Retry`", "`重试`"),
    ("`Resume`", "`继续`"),
    ("`Branch`", "`分支`"),
    ("`Pinned`", "`已固定`"),
    ("`Loading…`", "`正在加载…`"),
    ("`Loading`", "`正在加载`"),
    ("`Ready`", "`就绪`"),
    ("`Connected`", "`已连接`"),
    ("`Disconnected`", "`已断开`"),
    ("`Running`", "`运行中`"),
    ("`Details`", "`详情`"),
    ("`Advanced`", "`高级`"),
    ("`Cron`", "`定时任务`"),
    ("`Context`", "`上下文`"),
    ("`Session`", "`会话`"),
    ("`Message`", "`消息`"),
    ("`New session`", "`新建会话`"),
    ("`Search sessions`", "`搜索会话`"),
    ("`Search sessions…`", "`搜索会话…`"),
    ("`Clear search`", "`清空搜索`"),
    ("`Shift-click a chat to pin · drag to reorder`", "`Shift 点击会话可固定，拖动可排序`"),
    ("`Load ${n} more`", "`再加载 ${n} 条`"),
    ("`Load more`", "`加载更多`"),
    ("`Open settings`", "`打开设置`"),
    ("`Search settings...`", "`搜索设置...`"),
    ("`About Hermes Desktop`", "`关于 Hermes 桌面版`"),
    ("`Gateway connection...`", "`网关连接...`"),
    ("`Search API keys...`", "`搜索 API 密钥...`"),
    ("`Search MCP servers...`", "`搜索 MCP 服务...`"),
    ("`Search archived sessions...`", "`搜索已归档会话...`"),
    ("`Main model`", "`主模型`"),
    ("`Loading model configuration...`", "`正在加载模型配置...`"),
    ("`Applies to new sessions. Use the model picker in the composer to hot-swap the active chat.`", "`应用于新会话。可在输入区模型选择器中临时切换当前会话模型。`"),
    ("`Provider`", "`模型服务`"),
    ("`Auxiliary models`", "`辅助模型`"),
    ("`Reset all to main`", "`全部重置为主模型`"),
    ("`Helper tasks run on the main model by default. Assign a dedicated model to any task to override.`", "`辅助任务默认使用主模型。可为任意任务指定专用模型。`"),
    ("`Set to main`", "`设为主模型`"),
    ("`Change`", "`更改`"),
    ("`Page summarization`", "`页面摘要`"),
    ("`Compression`", "`压缩`"),
    ("`Context compaction`", "`上下文压缩`"),
    ("`Session search`", "`会话搜索`"),
    ("`Recall queries`", "`回忆查询`"),
    ("`Skills hub`", "`技能中心`"),
    ("`Skill search`", "`技能搜索`"),
    ("`Approval`", "`审批`"),
    ("`Smart auto-approve`", "`智能自动批准`"),
    ("`MCP tool routing`", "`MCP 工具路由`"),
    ("`Title gen`", "`标题生成`"),
    ("`Session titles`", "`会话标题`"),
    ("`Curator`", "`整理器`"),
    ("`Skill-usage review`", "`技能使用复核`"),
    ("O9=e=>e.replace(/_/g,` `).replace(/\\b\\w/g,e=>e.toUpperCase())", "O9=e=>({apple:`苹果`,autonomous_ai_agents:`自主智能体`,creative:`创意`,data_science:`数据科学`,devops:`开发运维`,email:`邮件`,gaming:`游戏`,general:`通用`,github:`GitHub`,mcp:`MCP`,media:`媒体`,mlops:`MLOps`,note_taking:`笔记`,productivity:`效率`,red_teaming:`红队`,research:`研究`,smart_home:`智能家居`,social_media:`社交媒体`,software_development:`软件开发`}[e]??e.replace(/_/g,` `).replace(/\\b\\w/g,e=>e.toUpperCase()))"),
    ("children:[`All `,(0,Q9.jsx)(N5,{children:E})]", "children:[`全部 `,(0,Q9.jsx)(N5,{children:E})]"),
    ("`Search skills...`", "`搜索技能...`"),
    ("`Search toolsets...`", "`搜索工具集...`"),
    ("`Refreshing skills`", "`正在刷新技能`"),
    ("`Refresh skills`", "`刷新技能`"),
    ("`Loading capabilities...`", "`正在加载能力...`"),
    ("`Try a broader search or different category.`", "`换个关键词或分类试试。`"),
    ("`No skills found`", "`未找到技能`"),
    ("`No description.`", "`无说明。`"),
    ("`Search messaging...`", "`搜索消息...`"),
    ("`Run Hermes from Telegram DMs, groups, and topics.`", "`通过 Telegram 私信、群组和话题运行 Hermes。`"),
    ("`Disabled`", "`已禁用`"),
    ("`Needs setup`", "`需要设置`"),
    ("`Messaging gateway stopped`", "`消息网关已停止`"),
    ("`GET YOUR CREDENTIALS`", "`获取凭据`"),
    ("`Open setup guide`", "`打开设置指南`"),
    ("`REQUIRED`", "`必填`"),
    ("`Bot token`", "`Bot 令牌`"),
    ("`Create a bot with @BotFather, then paste the token it gives you.`", "`使用 @BotFather 创建 bot，然后粘贴它提供的令牌。`"),
    ("`RECOMMENDED`", "`推荐`"),
    ("`Allowed Telegram user IDs`", "`允许的 Telegram 用户 ID`"),
    ("`Allowed Telegram user IDs (comma-separated)`", "`允许的 Telegram 用户 ID（用逗号分隔）`"),
    ("`Recommended. Comma-separated numeric IDs from @userinfobot. Without this, anyone can DM your bot.`", "`推荐填写。来自 @userinfobot 的数字 ID，用逗号分隔。未填写时任何人都可私信你的 bot。`"),
    ("`ADVANCED`", "`高级`"),
    ("`Save changes`", "`保存更改`"),
    ("`Search artifacts...`", "`搜索产物...`"),
    ("`All `", "`全部 `"),
    ("`Links`", "`链接`"),
    ("`Images `", "`图片 `"),
    ("`Files `", "`文件 `"),
    ("`Links `", "`链接 `"),
    ("bcn=e=>e===`link`?`links`:e===`file`?`files`:`items`", "bcn=e=>e===`link`?`链接`:e===`file`?`文件`:`项`"),
    ("function icn(e,t,n){return e===0?`0`:`${(t-1)*n+1}-${Math.min(e,t*n)} of ${e}`}", "function icn(e,t,n){return e===0?`0`:`${(t-1)*n+1}-${Math.min(e,t*n)} / ${e}`}"),
    ("`TITLE / NAME`", "`标题 / 名称`"),
    ("`LOCATION`", "`位置`"),
    ("`Location`", "`位置`"),
    ("`Path`", "`路径`"),
    ("`Prev`", "`上一页`"),
    ("`Next`", "`下一页`"),
    ("`Connection:`", "`连接：`"),
    ("`RECENT ACTIVITY`", "`最近活动`"),
    ("`View all logs →`", "`查看全部日志 →`"),
    ("`Spawn tree`", "`子智能体树`"),
    ("`Live subagent activity for the current turn.`", "`当前轮次的子智能体实时活动。`"),
    ("`No live subagents`", "`暂无活动子智能体`"),
    ("`When a turn delegates work, child agents stream their progress here.`", "`当前轮次委派工作时，子智能体进度会显示在这里。`"),
    ("`No scheduled jobs yet`", "`暂无定时任务`"),
    ("`Schedule a prompt to run on a cron expression. Hermes will run it and deliver results to the destination you pick.`", "`设置按 cron 表达式运行的提示词，Hermes 会执行并将结果发送到所选目标。`"),
    ("`Create first cron`", "`创建第一个定时任务`"),
    ("`Search and manage sessions`", "`搜索并管理会话`"),
    ("`Usage`", "`用量`"),
    ("`Personality`", "`助手风格`"),
    ("`Default assistant style for new sessions.`", "`新会话默认助手风格。`"),
    ("`Timezone`", "`时区`"),
    ("`Used when Hermes needs local time context. Blank uses the system timezone.`", "`Hermes 需要本地时间上下文时使用。留空则使用系统时区。`"),
    ("`Reasoning Blocks`", "`推理块`"),
    ("`Show reasoning sections when the backend provides them.`", "`后端提供时显示推理部分。`"),
    ("`Image Attachments`", "`图片附件`"),
    ("`Controls how image attachments are sent to the model.`", "`控制图片附件如何发送给模型。`"),
    ("`Not set`", "`未设置`"),
    ("`Auto`", "`自动`"),
    ("`Kawaii`", "`可爱`"),
    ("`Color Mode`", "`颜色模式`"),
    ("`Pick a fixed mode or let Hermes follow your system setting.`", "`选择固定模式，或让 Hermes 跟随系统设置。`"),
    ("`Tool Call Display`", "`工具调用显示`"),
    ("`Product`", "`产品`"),
    ("`Human-friendly tool activity with concise summaries.`", "`以简洁摘要展示工具活动。`"),
    ("`Technical`", "`技术`"),
    ("`Include raw tool args/results and low-level details.`", "`显示原始工具参数、结果和底层细节。`"),
    ("`Theme`", "`主题`"),
    ("`Desktop palettes only. The selected mode is applied on top.`", "`桌面配色。所选模式会叠加应用。`"),
    ("`Glass neutrals with Nous blue accents`", "`玻璃中性色搭配 Nous 蓝色点缀`"),
    ("`Midnight`", "`午夜`"),
    ("`Deep blue-violet with cool accents`", "`深蓝紫色搭配冷色点缀`"),
    ("`Working Directory`", "`工作目录`"),
    ("`Default project folder for tool and terminal work.`", "`工具和终端工作的默认项目文件夹。`"),
    ("`Code Execution Mode`", "`代码执行模式`"),
    ("`How strictly code execution is scoped to the current project.`", "`控制代码执行限制在当前项目内的严格程度。`"),
    ("`Project`", "`项目`"),
    ("`Persistent Shell`", "`持久 Shell`"),
    ("`Keep shell state between commands when the backend supports it.`", "`后端支持时在命令之间保留 Shell 状态。`"),
    ("`Environment Passthrough`", "`环境变量传递`"),
    ("`Environment variables to pass into tool execution.`", "`传递给工具执行的环境变量。`"),
    ("`comma-separated value`", "`逗号分隔值`"),
    ("`File Read Limit`", "`文件读取限制`"),
    ("`Maximum characters Hermes can read from one file request.`", "`Hermes 单次文件读取请求可读取的最大字符数。`"),
    ("`Approval Mode`", "`审批模式`"),
    ("`How Hermes handles commands that need explicit approval.`", "`Hermes 如何处理需要明确审批的命令。`"),
    ("`Manual`", "`手动`"),
    ("`Approval Timeout`", "`审批超时`"),
    ("`How long approval prompts wait before timing out.`", "`审批提示超时前等待的时长。`"),
    ("`Confirm MCP Reloads`", "`确认 MCP 重新加载`"),
    ("`Command Allowlist`", "`命令允许列表`"),
    ("`Redact Secrets`", "`隐藏密钥`"),
    ("`Hide detected secrets from model-visible content when possible.`", "`尽可能从模型可见内容中隐藏检测到的密钥。`"),
    ("`Allow Private URLs`", "`允许私有 URL`"),
    ("`Browser Private URLs`", "`浏览器私有 URL`"),
    ("`Local Browser For Private URLs`", "`私有 URL 使用本地浏览器`"),
    ("`File Checkpoints`", "`文件检查点`"),
    ("`Create rollback snapshots before file edits.`", "`修改文件前创建可回退快照。`"),
    ("`Persistent Memory`", "`持久记忆`"),
    ("`Save durable memories that can help future sessions.`", "`保存可帮助后续会话的持久记忆。`"),
    ("`User Profile`", "`用户画像`"),
    ("`Maintain a compact profile of user preferences.`", "`维护简洁的用户偏好画像。`"),
    ("`Memory Budget`", "`记忆预算`"),
    ("`Profile Budget`", "`画像预算`"),
    ("`Memory Provider`", "`记忆服务`"),
    ("`Memory provider plugin`", "`记忆服务插件`"),
    ("`Context Engine`", "`上下文引擎`"),
    ("`Strategy for managing long conversations near the context limit.`", "`接近上下文限制时管理长对话的策略。`"),
    ("`Auto-Compression`", "`自动压缩`"),
    ("`Summarize older context when conversations get large.`", "`对话变长时总结较早上下文。`"),
    ("`Compression Threshold`", "`压缩阈值`"),
    ("`Compression Target`", "`压缩目标`"),
    ("`Protected Recent Messages`", "`受保护的最近消息`"),
    ("`Text-To-Speech Provider`", "`文本转语音服务`"),
    ("`Speech To Text`", "`语音转文字`"),
    ("`Enable local or provider-backed speech transcription.`", "`启用本地或服务支持的语音转写。`"),
    ("`Speech-To-Text Provider`", "`语音转文字服务`"),
    ("`Read Responses Aloud`", "`朗读回复`"),
    ("`Automatically speak assistant responses.`", "`自动朗读助手回复。`"),
    ("`Edge Voice`", "`Edge 声音`"),
    ("`OpenAI TTS Model`", "`OpenAI TTS 模型`"),
    ("`OpenAI Voice`", "`OpenAI 声音`"),
    ("`ElevenLabs Voice`", "`ElevenLabs 声音`"),
    ("`ElevenLabs Model`", "`ElevenLabs 模型`"),
    ("`Local Transcription Model`", "`本地转写模型`"),
    ("`Transcription Language`", "`转写语言`"),
    ("`ElevenLabs STT Model`", "`ElevenLabs STT 模型`"),
    ("`ElevenLabs Scribe model`", "`ElevenLabs Scribe 模型`"),
    ("`Enabled Toolsets`", "`已启用工具集`"),
    ("`Execution Backend`", "`执行后端`"),
    ("`Terminal execution backend`", "`终端执行后端`"),
    ("`Command Timeout`", "`命令超时`"),
    ("`Terminal Output Limit`", "`终端输出限制`"),
    ("`File Page Limit`", "`文件页数限制`"),
    ("`Line Length Limit`", "`行长度限制`"),
    ("`Checkpoint Limit`", "`检查点限制`"),
    ("`Max Agent Steps`", "`最大智能体步骤`"),
    ("`Upper bound for tool-calling turns before Hermes stops a run.`", "`Hermes 停止运行前工具调用轮次的上限。`"),
    ("`API Retries`", "`API 重试次数`"),
    ("`Service Tier`", "`服务层级`"),
    ("`API service tier (OpenAI/Anthropic)`", "`API 服务层级（OpenAI/Anthropic）`"),
    ("`Tool-Use Enforcement`", "`工具使用约束`"),
    ("`Subagent Model`", "`子智能体模型`"),
    ("`Base`", "`基础`"),
    ("`Compressor`", "`压缩器`"),
    ("`(none)`", "`（无）`"),
    ("`On`", "`开`"),
    ("`Off`", "`关`"),
    ("`Default Model`", "`默认模型`"),
    ("`Context Window`", "`上下文窗口`"),
    ("`Fallback Models`", "`备用模型`"),
    ("`Voice Shortcut`", "`语音快捷键`"),
    ("`Max Recording Length`", "`最长录音时长`"),
    ("`ElevenLabs Language`", "`ElevenLabs 语言`"),
    ("`Tag Audio Events`", "`标记音频事件`"),
    ("`Speaker Diarization`", "`说话人分离`"),
    ("`Subagent Provider`", "`子智能体服务`"),
    ("`Subagent Turn Limit`", "`子智能体轮次限制`"),
    ("`Parallel Subagents`", "`并行子智能体`"),
    ("`Subagent Timeout`", "`子智能体超时`"),
    ("`Subagent Reasoning Effort`", "`子智能体推理强度`"),
    ("`Used for new chats unless you pick a different model in the composer.`", "`用于新会话，除非你在输入区选择其他模型。`"),
    ("\"Leave at 0 to use the selected model's detected context window.\"", "\"填 0 时使用所选模型检测到的上下文窗口。\""),
    ("`Backup provider:model entries to try if the default model fails.`", "`默认模型失败时尝试的备用 服务:模型 条目。`"),
    ("`Optional ISO-639-3 language code. Blank lets ElevenLabs auto-detect.`", "`可选 ISO-639-3 语言代码。留空则由 ElevenLabs 自动检测。`"),
    ("`Refreshing artifacts`", "`正在刷新产物`"),
    ("`Refresh artifacts`", "`刷新产物`"),
    ("`Indexing recent session artifacts`", "`正在索引最近会话产物`"),
    ("`No artifacts found`", "`未找到产物`"),
    ("`Generated images and file outputs will appear here as sessions produce them.`", "`会话生成的图片和文件输出会显示在这里。`"),
    ("`Go to `", "`前往 `"),
    ("` page `", "` 第 `"),
    ("`Link title`", "`链接标题`"),
    ("`Name`", "`名称`"),
    ("`Title / name`", "`标题 / 名称`"),
    ("`Common commands`", "`常用命令`"),
    ("`Hotkeys`", "`快捷键`"),
    ("`No speech detected`", "`未检测到语音`"),
    ("`Try recording again.`", "`请重新录制。`"),
    ("`Attachment-only turn`", "`仅附件轮次`"),
    ("`Empty turn`", "`空轮次`"),
    ("`Send queued turn now`", "`立即发送排队轮次`"),
    ("`Desktop theme suggestions`", "`桌面主题建议`"),
    ("`No matching themes.`", "`没有匹配主题。`"),
    ("`Looking up…`", "`正在查找…`"),
    ("`No matches.`", "`无匹配项。`"),
    ("`Dictating`", "`正在听写`"),
    ("`Failed to write image to disk.`", "`无法保存图片文件。`"),
    ("`Clipboard`", "`剪贴板`"),
    ("`No image found in clipboard`", "`剪贴板中未找到图片`"),
    ("`Drop files`", "`拖放文件`"),
    ("`Deselect entry`", "`取消选择条目`"),
    ("`Select entry`", "`选择条目`"),
    ("`Copy this entry`", "`复制此条目`"),
    ("`Send this entry to chat`", "`发送此条目到会话`"),
    ("`Sent to chat`", "`已发送到会话`"),
    ("`Copy selected to clipboard`", "`复制所选内容到剪贴板`"),
    ("`Copy all to clipboard`", "`复制全部到剪贴板`"),
    ("`Clear console`", "`清空控制台`"),
    ("`Click to select · shift-click to extend · drag to composer`", "`点击选择 · Shift 点击扩展选择 · 拖到输入区`"),
    ("`Try again`", "`重试`"),
    ("`Results`", "`结果`"),
    ("`Show sessions as a single list`", "`以单列表显示会话`"),
    ("`Unpin`", "`取消固定`"),
    ("`Pin`", "`固定`"),
    ("`Copy ID`", "`复制 ID`"),
    ("`Export`", "`导出`"),
    ("`Rename`", "`重命名`"),
    ("`Delete`", "`删除`"),
    ("`Renamed`", "`已重命名`"),
    ("`Navigate`", "`导航`"),
    ("`Unpin session`", "`取消固定会话`"),
    ("`Pin session`", "`固定会话`"),
    ("`Export session`", "`导出会话`"),
    ("`Delete session`", "`删除会话`"),
    ("`API calls`", "`API 调用`"),
    ("`Tokens in/out`", "`输入/输出 Token`"),
    ("`Est. cost`", "`预估费用`"),
    ("`This desktop`", "`此桌面端`"),
    ("`Daily`", "`每天`"),
    ("`Weekdays`", "`工作日`"),
    ("`Weekly`", "`每周`"),
    ("`Monthly`", "`每月`"),
    ("`Hourly`", "`每小时`"),
    ("`Every 15 minutes`", "`每 15 分钟`"),
    ("`Custom`", "`自定义`"),
    ("`Cron resumed`", "`定时任务已恢复`"),
    ("`Cron paused`", "`定时任务已暂停`"),
    ("`Cron triggered`", "`定时任务已触发`"),
    ("`Cron deleted`", "`定时任务已删除`"),
    ("`Cron created`", "`定时任务已创建`"),
    ("`Cron updated`", "`定时任务已更新`"),
    ("`Search cron jobs...`", "`搜索定时任务...`"),
    ("`Refreshing cron jobs`", "`正在刷新定时任务`"),
    ("`Refresh cron jobs`", "`刷新定时任务`"),
    ("`Loading cron jobs...`", "`正在加载定时任务...`"),
    ("`No matches`", "`无匹配项`"),
    ("`Resume cron`", "`恢复定时任务`"),
    ("`Pause cron`", "`暂停定时任务`"),
    ("`Pause`", "`暂停`"),
    ("`Trigger now`", "`立即触发`"),
    ("`Edit cron`", "`编辑定时任务`"),
    ("`Edit`", "`编辑`"),
    ("`Delete cron`", "`删除定时任务`"),
    ("`Failed to save cron job`", "`保存定时任务失败`"),
    ("`Edit cron job`", "`编辑定时任务`"),
    ("`New cron job`", "`新建定时任务`"),
    ("`Morning briefing`", "`晨间简报`"),
    ("`Prompt`", "`提示词`"),
    ("`Summarize my unread Slack threads and email me the top 5...`", "`总结我未读的 Slack 讨论，并通过邮件发送前 5 条...`"),
    ("`Frequency`", "`频率`"),
    ("`Deliver to`", "`发送到`"),
    ("`Custom schedule`", "`自定义计划`"),
    ("`0 9 * * * or weekdays at 9am`", "`0 9 * * * 或 工作日 9 点`"),
    ("`Starting desktop connection`", "`正在启动桌面连接`"),
    ("`Backend stopped`", "`后端已停止`"),
    ("`Loading recent sessions`", "`正在加载最近会话`"),
    ("`Unknown`", "`未知`"),
    ("`Error`", "`错误`"),
    ("`Restart needed`", "`需要重启`"),
    ("`Retrying`", "`正在重试`"),
    ("`Startup failed`", "`启动失败`"),
    ("`Restart the gateway from the status bar to apply this change.`", "`请从状态栏重启网关以应用此更改。`"),
    ("`Start the gateway from the status bar to connect.`", "`请从状态栏启动网关以连接。`"),
    ("`Messaging platforms failed to load`", "`消息平台加载失败`"),
    ("`Restart the gateway for this change to take effect.`", "`请重启网关以使此更改生效。`"),
    ("`Restart the gateway to reconnect with the new credentials.`", "`请重启网关以使用新凭据重新连接。`"),
    ("` setup saved`", "` 设置已保存`"),
    ("` setup was updated.`", "` 设置已更新。`"),
    ("`Failed to update `", "`更新失败：`"),
    ("`Failed to save `", "`保存失败：`"),
    ("`Failed to clear `", "`清除失败：`"),
    ("`Loading messaging platforms...`", "`正在加载消息平台...`"),
    ("`Credentials set`", "`凭据已设置`"),
    ("`Get your credentials`", "`获取凭据`"),
    ("`Required`", "`必填`"),
    ("`This platform does not need a token here. Use the setup guide above, then enable it below.`", "`此平台无需在这里填写令牌。请使用上方设置指南，然后在下方启用。`"),
    ("`Recommended`", "`推荐`"),
    ("`Advanced (`", "`高级（`"),
    ("`Enable `", "`启用 `"),
    ("`Disable `", "`禁用 `"),
    ("`Enabled`", "`已启用`"),
    ("`Unsaved changes`", "`未保存更改`"),
    ("`Saving...`", "`正在保存...`"),
    ("`Proxy URL`", "`代理 URL`"),
    ("`Only needed on networks where Telegram is blocked.`", "`在 Telegram 受限的网络环境中才需要。`"),
    ("`Create an application in the Discord Developer Portal, add a bot, then paste its token.`", "`在 Discord 开发者门户创建应用、添加 bot，然后粘贴其令牌。`"),
    ("`Allowed Discord user IDs`", "`允许的 Discord 用户 ID`"),
    ("`Recommended. Comma-separated Discord user IDs.`", "`推荐填写。Discord 用户 ID，用逗号分隔。`"),
    ("`Reply style`", "`回复方式`"),
    ("`first, all, or off.`", "`first、all 或 off。`"),
    ("`Slack bot token`", "`Slack bot 令牌`"),
    ("`Starts with xoxb-. Found under OAuth & Permissions after installing your Slack app.`", "`以 xoxb- 开头。安装 Slack 应用后可在 OAuth & Permissions 下找到。`"),
    ("`Slack app token`", "`Slack app 令牌`"),
    ("`Starts with xapp-. Required for Socket Mode.`", "`以 xapp- 开头。Socket Mode 必填。`"),
    ("`Allowed Slack user IDs`", "`允许的 Slack 用户 ID`"),
    ("`Recommended. Comma-separated Slack user IDs.`", "`推荐填写。Slack 用户 ID，用逗号分隔。`"),
    ("`Server URL`", "`服务器 URL`"),
    ("`Allowed user IDs`", "`允许的用户 ID`"),
    ("`Recommended. Comma-separated Mattermost user IDs.`", "`推荐填写。Mattermost 用户 ID，用逗号分隔。`"),
    ("`Homeserver URL`", "`Homeserver URL`"),
    ("`Homeserver URL`", "`主服务器 URL`"),
    ("`Access token`", "`访问令牌`"),
    ("`Bot user ID`", "`Bot 用户 ID`"),
    ("`Allowed Matrix user IDs`", "`允许的 Matrix 用户 ID`"),
    ("`Recommended. Comma-separated user IDs in @user:server format.`", "`推荐填写。@user:server 格式的用户 ID，用逗号分隔。`"),
    ("`Signal bridge URL`", "`Signal 桥接 URL`"),
    ("`URL of a running signal-cli REST bridge.`", "`正在运行的 signal-cli REST 桥接 URL。`"),
    ("`Phone number`", "`手机号`"),
    ("`The number registered with your signal-cli bridge.`", "`在 signal-cli 桥接中注册的号码。`"),
    ("`Allowed Signal users`", "`允许的 Signal 用户`"),
    ("`Recommended. Comma-separated Signal identifiers.`", "`推荐填写。Signal 标识符，用逗号分隔。`"),
    ("`Enable WhatsApp bridge`", "`启用 WhatsApp 桥接`"),
    ("`Set automatically by the toggle below. Leave alone unless you know you need it.`", "`由下方开关自动设置。不确定时保持默认。`"),
    ("`Bridge mode`", "`桥接模式`"),
    ("`Allowed WhatsApp users`", "`允许的 WhatsApp 用户`"),
    ("`Recommended. Comma-separated phone numbers or WhatsApp IDs.`", "`推荐填写。手机号或 WhatsApp ID，用逗号分隔。`"),
    ("`Replace current value`", "`替换当前值`"),
    ("`Open docs`", "`打开文档`"),
    ("`Clear `", "`清除 `"),
    ("`Saved`", "`已保存`"),
    ("`In Telegram, talk to @BotFather, run /newbot, and copy the token it gives you. Then grab your numeric user ID from @userinfobot.`", "`在 Telegram 中与 @BotFather 对话，运行 /newbot 并复制它提供的令牌。然后从 @userinfobot 获取你的数字用户 ID。`"),
    ("`Open the Discord Developer Portal, create an application, add a Bot, then copy its token. Invite the bot to your server with the right scopes.`", "`打开 Discord 开发者门户，创建应用并添加 Bot，然后复制令牌。用合适权限邀请 bot 加入服务器。`"),
    ("`Create a Slack app, enable Socket Mode, install it to your workspace, then copy the Bot token (xoxb-) and App-level token (xapp-).`", "`创建 Slack 应用，启用 Socket Mode，安装到工作区，然后复制 Bot token（xoxb-）和 App-level token（xapp-）。`"),
    ("`创建 Slack 应用，启用 Socket Mode，安装到工作区，然后复制 Bot token（xoxb-）和 App-level token（xapp-）。`", "`创建 Slack 应用，启用 Socket Mode，安装到工作区，然后复制 Bot 令牌（xoxb-）和应用级令牌（xapp-）。`"),
    ("`On your Mattermost server, create a bot account or personal access token, then paste the server URL and token here.`", "`在 Mattermost 服务器上创建 bot 账户或个人访问令牌，然后在此粘贴服务器 URL 和令牌。`"),
    ("`Sign in to your homeserver with the bot account, then copy the access token, user ID, and homeserver URL.`", "`使用 bot 账户登录 homeserver，然后复制访问令牌、用户 ID 和 homeserver URL。`"),
    ("`使用 bot 账户登录 homeserver，然后复制访问令牌、用户 ID 和 homeserver URL。`", "`使用 bot 账户登录主服务器，然后复制访问令牌、用户 ID 和主服务器地址。`"),
    ("`Run a signal-cli REST bridge somewhere reachable, then point Hermes at the URL and the registered phone number.`", "`运行一个 Hermes 可访问的 signal-cli REST 桥接，然后填写 URL 和注册手机号。`"),
    ("`Start the WhatsApp bridge that ships with Hermes, scan the QR code on first run, then enable the platform.`", "`启动 Hermes 附带的 WhatsApp 桥接，首次运行时扫码，然后启用该平台。`"),
    ("`Run BlueBubbles Server on a Mac with iMessage, expose its API, then point Hermes at the URL with the server password.`", "`在启用 iMessage 的 Mac 上运行 BlueBubbles Server，开放 API，然后在 Hermes 中填写 URL 和服务器密码。`"),
    ("`In Home Assistant, open your profile and create a long-lived access token. Paste it here along with your HA URL.`", "`在 Home Assistant 中打开个人资料，创建长期访问令牌，并连同 HA URL 一起粘贴到这里。`"),
    ("`Use a dedicated mailbox. For Gmail/Workspace, create an app password and use imap.gmail.com / smtp.gmail.com.`", "`建议使用专用邮箱。Gmail/Workspace 请创建应用密码，并使用 imap.gmail.com / smtp.gmail.com。`"),
    ("`Get your Twilio Account SID and Auth Token from the Twilio console, plus a phone number that can send SMS.`", "`从 Twilio 控制台获取 Account SID 和 Auth Token，并准备一个可发送短信的号码。`"),
    ("`Create a DingTalk app in the developer console, then copy the Client ID (App key) and Client Secret here.`", "`在开发者控制台创建钉钉应用，然后复制 Client ID（App key）和 Client Secret 到这里。`"),
    ("`Create a Feishu / Lark app, configure the bot capability, and copy the App ID, App secret, and event encryption keys.`", "`创建飞书 / Lark 应用，配置 bot 能力，然后复制 App ID、App secret 和事件加密密钥。`"),
    ("`Add a group robot in WeCom and copy its webhook key as WECOM_BOT_ID. Send-only — use the WeCom (app) option for two-way.`", "`在企业微信中添加群机器人，并将 webhook key 作为 WECOM_BOT_ID。此方式仅发送；双向通信请使用 WeCom（app）。`"),
    ("`Set up a WeCom self-built app, expose its callback URL, and provide the corp ID, secret, agent ID, and AES key.`", "`设置企业微信自建应用，开放回调 URL，并提供 corp ID、secret、agent ID 和 AES key。`"),
    ("`Sign in to the WeChat Official Account platform, copy the AppID and Token, and point the message callback URL at Hermes.`", "`登录微信公众号平台，复制 AppID 和 Token，并将消息回调 URL 指向 Hermes。`"),
    ("`Register an app on the QQ Open Platform (q.qq.com) and copy the App ID and Client Secret.`", "`在 QQ 开放平台（q.qq.com）注册应用，并复制 App ID 和 Client Secret。`"),
    ("`Expose Hermes as an OpenAI-compatible API. Set an auth key, then point Open WebUI / LobeChat / etc. at the host:port.`", "`将 Hermes 暴露为 OpenAI 兼容 API。设置认证密钥后，将 Open WebUI / LobeChat 等指向该 host:port。`"),
    ("`Run an HTTP server that other tools (GitHub, GitLab, custom apps) can POST to. Use the secret to verify signatures.`", "`运行一个可接收其他工具（GitHub、GitLab、自定义应用）POST 的 HTTP 服务，并使用 secret 验证签名。`"),
    ("`Everything here is pinned. Unpin a chat to show it in recents.`", "`这里都是已固定会话。取消固定后会显示在最近会话中。`"),
    ("`New session in `", "`在此新建会话：`"),
    ("`New sessions start in this folder unless you pick another. Leave it unset to use your home directory.`", "`新会话会从此文件夹开始，除非另选位置。留空则使用用户目录。`"),
    ("`Refreshing profiles`", "`正在刷新配置档`"),
    ("`Refresh profiles`", "`刷新配置档`"),
    ("`Profile created`", "`配置档已创建`"),
    ("`Profile renamed`", "`配置档已重命名`"),
    ("`Profile deleted`", "`配置档已删除`"),
    ("`Failed to load profiles`", "`加载配置档失败`"),
    ("`Loading profiles...`", "`正在加载配置档...`"),
    ("`No profiles yet.`", "`暂无配置档。`"),
    ("`Select a profile to view its details.`", "`选择配置档以查看详情。`"),
    ("`Delete profile?`", "`删除配置档？`"),
    ("`This will delete `", "`将删除 `"),
    ("` directory. This cannot be undone.`", "` 目录。此操作无法撤销。`"),
    ("`Default`", "`默认`"),
    ("`Failed to copy setup command`", "`复制设置命令失败`"),
    ("`Copying...`", "`正在复制...`"),
    ("`Copy setup`", "`复制设置`"),
    ("`Setup command copied`", "`设置命令已复制`"),
    ("`Failed to load SOUL.md`", "`加载 SOUL.md 失败`"),
    ("`SOUL.md saved`", "`SOUL.md 已保存`"),
    ("`Failed to save SOUL.md`", "`保存 SOUL.md 失败`"),
    ("`The system prompt and persona instructions baked into this profile.`", "`此配置档内置的系统提示词和人格说明。`"),
    ("`Loading SOUL.md...`", "`正在加载 SOUL.md...`"),
    ("`Save SOUL.md`", "`保存 SOUL.md`"),
    ("`Empty SOUL.md — start writing the persona...`", "`SOUL.md 为空，请开始编写人格...`"),
    ("`Failed to create profile`", "`创建配置档失败`"),
    ("`Failed to rename profile`", "`重命名配置档失败`"),
    ("`Change working directory`", "`更改工作目录`"),
    ("`Right sidebar`", "`右侧栏`"),
    ("`Open a folder`", "`打开文件夹`"),
    ("`Open folder`", "`打开文件夹`"),
    ("`Open a different folder`", "`打开其他文件夹`"),
    ("`Collapse all folders`", "`折叠全部文件夹`"),
    ("`Refresh tree`", "`刷新文件树`"),
    ("`Unreadable`", "`无法读取`"),
    ("`This folder is empty.`", "`此文件夹为空。`"),
    ("`Empty`", "`空`"),
    ("`The file tree hit an error rendering this folder.`", "`文件树渲染此文件夹时出错。`"),
    ("`Tree error`", "`文件树错误`"),
    ("`Return to split view`", "`返回分栏视图`"),
    ("`Focus terminal view`", "`聚焦终端视图`"),
    ("`Working directory staged`", "`工作目录更改已暂存`"),
    ("`Restart the desktop backend to apply cwd changes to this active session.`", "`重启桌面后端以将工作目录更改应用到当前会话。`"),
    ("`Hermes finished`", "`Hermes 已完成`"),
    ("`dangerous command`", "`危险命令`"),
    ("`Hermes reported an error`", "`Hermes 报告错误`"),
    ("`Hermes error`", "`Hermes 错误`"),
    ("`Session unavailable`", "`会话不可用`"),
    ("`Could not create a new session`", "`无法创建新会话`"),
    ("`Prompt failed`", "`提示词提交失败`"),
    ("`YOLO armed for this chat`", "`此会话已启用 YOLO`"),
    ("`YOLO off`", "`YOLO 已关闭`"),
    ("`Could not toggle YOLO`", "`无法切换 YOLO`"),
    ("`Nothing to branch`", "`没有可分支内容`"),
    ("`Start or resume a chat before branching.`", "`请先开始或恢复会话再创建分支。`"),
    ("`Session busy`", "`会话正忙`"),
    ("`Stop the current turn before branching this chat.`", "`请先停止当前轮次再为此会话创建分支。`"),
    ("`This message has no text to branch from.`", "`此消息没有可用于分支的文本。`"),
    ("`Updates`", "`更新`"),
    ("`Hermes checks for updates automatically in the background and lets you know when one is ready.`", "`Hermes 会在后台自动检查更新，并在可用时通知你。`"),
    ("`Automatic updates`", "`自动更新`"),
    ("`Product hides raw tool payloads; Technical shows full input/output.`", "`产品模式隐藏原始工具负载；技术模式显示完整输入/输出。`"),
    ("`comma-separated values`", "`逗号分隔值`"),
    ("`Config imported`", "`配置已导入`"),
    ("`Saving…`", "`正在保存…`"),
    ("`Loading Hermes configuration...`", "`正在加载 Hermes 配置...`"),
    ("`Try a different search term or choose another section.`", "`换个搜索词或选择其他分区。`"),
    ("`No matching settings`", "`没有匹配设置`"),
    ("`Enter a remote URL and session token before switching to remote.`", "`切换到远程前请先填写远程 URL 和会话令牌。`"),
    ("`Enter a remote URL and session token before testing.`", "`测试前请先填写远程 URL 和会话令牌。`"),
    ("`Remote gateway reachable`", "`远程网关可访问`"),
    ("`Loading gateway settings...`", "`正在加载网关设置...`"),
    ("`Start a private Hermes backend on localhost. This is the default and works offline.`", "`在 localhost 启动私有 Hermes 后端。这是默认方式，可离线工作。`"),
    ("`Local gateway`", "`本地网关`"),
    ("`Connect this desktop shell to a remote Hermes backend using its session token.`", "`使用会话令牌将此桌面外壳连接到远程 Hermes 后端。`"),
    ("`Remote gateway`", "`远程网关`"),
    ("`Base URL for the remote dashboard backend. Path prefixes are supported, for example /hermes.`", "`远程控制台后端的基础 URL。支持路径前缀，例如 /hermes。`"),
    ("`The dashboard session token used for REST and WebSocket access. Leave blank to keep the saved token.`", "`用于 REST 和 WebSocket 访问的控制台会话令牌。留空则保留已保存令牌。`"),
    ("`Session token`", "`会话令牌`"),
    ("`Reveal desktop.log in your file manager — useful when the gateway fails to start.`", "`在文件管理器中显示 desktop.log，适合排查网关启动失败。`"),
    ("`Reset to defaults`", "`重置为默认值`"),
    ("`Open provider docs`", "`打开服务文档`"),
    ("`Hide value`", "`隐藏值`"),
    ("`Reveal value`", "`显示值`"),
    ("`Clear value`", "`清除值`"),
    ("`Enter value`", "`输入值`"),
    ("`Credential saved`", "`凭据已保存`"),
    ("`Credential removed`", "`凭据已移除`"),
    ("`Loading API keys and credentials...`", "`正在加载 API 密钥和凭据...`"),
    ("`LLM providers`", "`LLM 服务`"),
    ("`Loading MCP servers...`", "`正在加载 MCP 服务...`"),
    ("`Name required`", "`需要名称`"),
    ("`Give this MCP server a config key.`", "`请为此 MCP 服务填写配置键。`"),
    ("`MCP server saved`", "`MCP 服务已保存`"),
    ("`MCP servers`", "`MCP 服务`"),
    ("`Add a stdio or HTTP server to expose MCP tools.`", "`添加 stdio 或 HTTP 服务以开放 MCP 工具。`"),
    ("`No MCP servers`", "`暂无 MCP 服务`"),
    ("`Loading archived sessions…`", "`正在加载已归档会话…`"),
    ("`Archived sessions`", "`已归档会话`"),
    ("`No archived chats match your search.`", "`没有匹配搜索的已归档会话。`"),
    ("`Archive a chat to hide it here.`", "`归档会话后会在这里隐藏。`"),
    ("`Nothing archived`", "`暂无归档`"),
    ("`Default project directory updated`", "`默认项目目录已更新`"),
    ("`Default project directory`", "`默认项目目录`"),
    ("`Provider selected`", "`服务已选择`"),
    ("`Open system panel`", "`打开系统面板`"),
    ("`Update in progress`", "`更新进行中`"),
    ("`Close Command Center`", "`关闭命令中心`"),
    ("`Open Command Center`", "`打开命令中心`"),
    ("`Low`", "`低`"),
    ("`Medium`", "`中`"),
    ("`High`", "`高`"),
    ("`Max`", "`最高`"),
    ("`Search models`", "`搜索模型`"),
    ("`Unmute haptics`", "`打开触感反馈`"),
    ("`Mute haptics`", "`关闭触感反馈`"),
    ("`Window controls`", "`窗口控制`"),
    ("`Pane controls`", "`面板控制`"),
    ("`App controls`", "`应用控制`"),
    ("`Skill enabled`", "`技能已启用`"),
    ("`Skill disabled`", "`技能已禁用`"),
    ("`Toolset enabled`", "`工具集已启用`"),
    ("`Toolset disabled`", "`工具集已禁用`"),
    ("`Try a broader search query.`", "`换个更宽泛的搜索词试试。`"),
    ("`No toolsets found`", "`未找到工具集`"),
    ("`Couldn’t check for updates`", "`无法检查更新`"),
    ("`Update not available`", "`暂无可用更新`"),
    ("`You’re all set`", "`已全部就绪`"),
    ("`Updating Hermes…`", "`正在更新 Hermes…`"),
    ("`No worries — nothing was lost. You can try again now.`", "`不用担心，内容没有丢失。现在可以重试。`"),
    ("`Type your answer…`", "`输入你的回答…`"),
    ("`Loading session`", "`正在加载会话`"),
    ("`Hermes is loading a response`", "`Hermes 正在加载回复`"),
    ("`Editable checkpoint`", "`可编辑检查点`"),
    ("`Restore previous checkpoint`", "`恢复上一个检查点`"),
    ("`Restore next checkpoint`", "`恢复下一个检查点`"),
    ("`Send edited message`", "`发送已编辑消息`"),
    ("`More approval options`", "`更多审批选项`"),
    ("`Tool returned success=false.`", "`工具返回 success=false。`"),
    ("`Copy output`", "`复制输出`"),
    ("`Copy content`", "`复制内容`"),
    ("`Copy URL`", "`复制 URL`"),
    ("`Copy results`", "`复制结果`"),
    ("`Copy query`", "`复制查询`"),
    ("`Copy file`", "`复制文件`"),
    ("`Copy path`", "`复制路径`"),
    ("`Copy activity`", "`复制活动`"),
    ("`Copy code`", "`复制代码`"),
    ("`Copied!`", "`已复制！`"),
    ("`Reload and retry`", "`重新加载并重试`"),
    ("`Image saved`", "`图片已保存`"),
    ("`Download started`", "`已开始下载`"),
    ("`Open image`", "`打开图片`"),
    ("`Saving image`", "`正在保存图片`"),
    ("`Hosts hundreds of models behind a single key. Good default for new installs.`", "`一个密钥接入数百个模型，新安装推荐。`"),
    ("`Direct access to OpenAI models.`", "`直接访问 OpenAI 模型。`"),
    ("`Direct access to Google Gemini models.`", "`直接访问 Google Gemini 模型。`"),
    ("`Direct access to xAI Grok models.`", "`直接访问 xAI Grok 模型。`"),
    ("`one key, many models`", "`一个密钥，多种模型`"),
    ("`GPT-class models`", "`GPT 类模型`"),
    ("`Nous Portal`", "`Nous 门户`"),
    ("`OpenAI OAuth (ChatGPT)`", "`OpenAI OAuth（ChatGPT）`"),
    ("`Qwen Code`", "`通义灵码`"),
    ("`Anthropic API Key`", "`Anthropic API 密钥`"),
    ("`Anthropic OAuth: Required Extra Usage Credits to Use Subscription`", "`Anthropic OAuth：使用订阅需要额外额度`"),
    ("`Could not save credential.`", "`无法保存凭据。`"),
    ("`Paste API key`", "`粘贴 API 密钥`"),
    ("`Filter providers and models...`", "`筛选服务和模型...`"),
    ("`Could not load models`", "`无法加载模型`"),
    ("`Input / Output price per million tokens`", "`每百万 Token 输入 / 输出价格`"),
    ("`Notifications`", "`通知`"),
    ("`Dismiss notification`", "`关闭通知`"),
    ("`Go to previous page`", "`上一页`"),
    ("`Go to next page`", "`下一页`"),
    ("`What's new`", "`新增内容`"),
    ("`Fixed`", "`已修复`"),
    ("`Faster`", "`更快`"),
    ("`Improved`", "`已改进`"),
    ("`Other improvements`", "`其他改进`"),
    ("`Branch the latest message into a new chat`", "`将最新消息分支到新会话`"),
    ("`Retry the last user message`", "`重试上一条用户消息`"),
    ("`Rename the current session`", "`重命名当前会话`"),
    ("`Could not render math with KaTeX`", "`无法用 KaTeX 渲染数学公式`"),
    ("`Starting Hermes Desktop…`", "`正在启动 Hermes Desktop…`"),
    ("`Hermes Desktop is ready`", "`Hermes Desktop 已就绪`"),
    ("`Token exchange failed.`", "`令牌交换失败。`"),
    ("`Enter a value first.`", "`请先输入值。`"),
    ("`Enter the endpoint URL first.`", "`请先输入端点 URL。`"),
    ("`Could not reach that endpoint.`", "`无法访问该端点。`"),
    ("`Update Hermes`", "`更新 Hermes`"),
    ("`Your Hermes backend is older than this desktop build and may not work correctly. Update to align them.`", "`Hermes 后端版本低于当前桌面端，可能无法正常工作。请更新以保持一致。`"),
    ("`Backend out of date`", "`后端版本过旧`"),
    ("`See what's new`", "`查看新增内容`"),
    ("`Update ready`", "`更新已就绪`"),
    ("`Desktop bridge unavailable.`", "`桌面桥接不可用。`"),
    ("`Starting update…`", "`正在开始更新…`"),
    ("`New update available`", "`有新版本可用`"),
    ("`A new version of Hermes is ready to install.`", "`Hermes 新版本已可安装。`"),
    ("`This version of Hermes can’t update itself from inside the app.`", "`此版本的 Hermes 无法在应用内自行更新。`"),
    ("`Transcribing dictation`", "`正在转写听写`"),
    ("`Stop dictation`", "`停止听写`"),
    ("`You're about to visit an external website.`", "`即将访问外部网站。`"),
    ("`Copy link`", "`复制链接`"),
    ("`Open link`", "`打开链接`"),
    ("`Copied`", "`已复制`"),
    ("`Export failed`", "`导出失败`"),
    ("`Reset all settings to Hermes defaults?`", "`要将全部设置重置为 Hermes 默认值吗？`"),
    ("`Remote gateway test failed`", "`远程网关测试失败`"),
    ("`sudo password`", "`sudo 密码`"),
    ("`YOLO on — auto-approving dangerous commands. Click to turn off.`", "`YOLO 开启：自动批准危险命令。点击关闭。`"),
    ("`YOLO off — click to auto-approve dangerous commands.`", "`YOLO 关闭：点击后自动批准危险命令。`"),
    ("`Show active desktop sessions and running tasks`", "`显示活动桌面会话和运行中任务`"),
    ("`Run a prompt in the background`", "`在后台运行提示词`"),
    ("`Compress this conversation context`", "`压缩当前对话上下文`"),
    ("`Create a debug report`", "`创建调试报告`"),
    ("`Manage the standing goal for this session`", "`管理此会话的常驻目标`"),
    ("`Show desktop slash commands`", "`显示桌面端斜杠命令`"),
    ("`Start a new desktop chat`", "`开始新的桌面会话`"),
    ("`Queue a prompt for the next turn`", "`将提示词加入下一轮队列`"),
    ("`Resume a saved session`", "`恢复已保存会话`"),
    ("`List or restore filesystem checkpoints`", "`列出或恢复文件系统检查点`"),
    ("`Switch desktop theme or cycle to the next one`", "`切换桌面主题或轮换到下一个`"),
    ("`Show current session status`", "`显示当前会话状态`"),
    ("`Steer the current run after the next tool call`", "`在下一次工具调用后引导当前运行`"),
    ("`Stop running background processes`", "`停止运行中的后台进程`"),
    ("`Remove the last user/assistant exchange`", "`移除上一组用户/助手对话`"),
    ("`Show token usage for this session`", "`显示此会话 Token 用量`"),
    ("`Toggle YOLO — auto-approve dangerous commands`", "`切换 YOLO：自动批准危险命令`"),
    ("`New profile`", "`新建配置档`"),
    ("`Profiles are independent Hermes environments: separate config, skills, and SOUL.md.`", "`配置档是独立 Hermes 环境：配置、技能和 SOUL.md 相互分开。`"),
    ("`Lowercase letters, digits, hyphens, and underscores. Must start with a letter or digit.`", "`可用小写字母、数字、连字符和下划线。必须以字母或数字开头。`"),
    ("`Invalid name. `", "`名称无效。`"),
    ("`Name is required.`", "`名称必填。`"),
    ("`New name`", "`新名称`"),
    ("`Clone from default`", "`从默认配置复制`"),
    ("`Copy config, skills, and SOUL.md from your default profile.`", "`从默认配置档复制配置、技能和 SOUL.md。`"),
    ("`Creating...`", "`正在创建...`"),
    ("`Create profile`", "`创建配置档`"),
    ("`Rename profile`", "`重命名配置档`"),
    ("`Renaming updates the profile directory and any wrapper scripts in `", "`重命名会更新配置档目录和其中的包装脚本：`"),
    ("`Renaming...`", "`正在重命名...`"),
    ("`Delete cron job?`", "`删除定时任务？`"),
    ("`This will remove`", "`将删除`"),
    ("`Prompt and schedule are required.`", "`提示词和计划必填。`"),
    ("`Update the schedule, prompt, or delivery target. Changes apply on next run.`", "`更新计划、提示词或发送目标。更改将在下次运行时生效。`"),
    ("`Schedule a prompt to run automatically. Use cron syntax or a natural phrase like \"every 15 minutes\".`", "`设置自动运行提示词。可使用 cron 语法，或类似“每 15 分钟”的自然语言。`"),
    ("`Deleting...`", "`正在删除...`"),
    ("`No logs loaded yet.`", "`尚未加载日志。`"),
    ("`Daily tokens`", "`每日 Token`"),
    ("`Hermes finished restarting the preview server`", "`Hermes 已完成预览服务重启`"),
    ("Hermes finished restarting the preview server", "Hermes 已完成预览服务重启"),
    ("`Server restart failed: `", "`服务重启失败：`"),
    ("Server restart failed: ", "服务重启失败："),
    ("`Add a provider credential before sending your first message.`", "`发送第一条消息前请先添加模型服务凭据。`"),
    ("Add a provider credential before sending your first message.", "发送第一条消息前请先添加模型服务凭据。"),
    ("`Right sidebar panels`", "`右侧栏面板`"),
    ("`Archive failed`", "`归档失败`"),
    ("`Archived chats are hidden from the sidebar but keep all their messages. Ctrl/⌘-click a chat in the sidebar to archive it without opening.`", "`已归档会话会从侧边栏隐藏，但保留全部消息。在侧边栏按 Ctrl/⌘ 点击会话可直接归档而无需打开。`"),
    ("`Archived chats are hidden from the sidebar but keep all their messages. Ctrl/⌘-click a chat in the sidebar to archive it.`", "`已归档会话会从侧边栏隐藏，但保留全部消息。在侧边栏按 Ctrl/⌘ 点击会话可直接归档。`"),
    ("`Included with a Nous subscription — sign in to Nous Portal to activate.`", "`包含在 Nous 订阅中，请登录 Nous 门户启用。`"),
    ("`Ember`", "`余烬`"),
    ("`Mono`", "`单色`"),
    ("`Cyberpunk`", "`赛博朋克`"),
    ("`Slate`", "`石板`"),
    ("`Warm crimson and bronze — forge vibes`", "`暖红与青铜色，锻造氛围`"),
    ("`Clean grayscale — minimal and focused`", "`干净灰阶，极简专注`"),
    ("`Neon green on black — matrix terminal`", "`黑底霓虹绿，矩阵终端风格`"),
    ("`Cool slate blue — focused developer theme`", "`冷调石板蓝，专注开发主题`"),
    ("dwop yur ewwor message hewe! i'll find the cuwpwit, fix it, and weave a happy test suite behind me owo", "把错误信息发来，我会定位问题、修复它，并补好测试。"),
    ("*tiny keyboard sounds*", "键盘轻响"),
    ("`No workspace`", "`无工作区`"),
    ("`No model`", "`未选择模型`"),
    ("`no model`", "`未选择模型`"),
    ("`Default model`", "`默认模型`"),
    ("`Switch model`", "`切换模型`"),
    ("`Open model picker`", "`打开模型选择器`"),
    ("`Model · ${y}: ${v||`none`}`", "`模型 · ${y}: ${v||`未选择`}`"),
    ("`Fast`", "`快速`"),
    ("`Latest`", "`最新版`"),
    ("var GZt={none:`Off`,minimal:`Min`,low:`Low`,medium:`Med`,high:`High`,xhigh:`Max`}", "var GZt={none:`关`,minimal:`极低`,low:`低`,medium:`中`,high:`高`,xhigh:`最高`}"),
    ("var nsn=[{value:`minimal`,label:`Minimal`},{value:`low`,label:`Low`},{value:`medium`,label:`Medium`},{value:`high`,label:`High`},{value:`xhigh`,label:`Max`}]", "var nsn=[{value:`minimal`,label:`极低`},{value:`low`,label:`低`},{value:`medium`,label:`中`},{value:`high`,label:`高`},{value:`xhigh`,label:`最高`}]"),
    ("`Pick a different provider`", "`选择其他模型服务`"),
    ("`Local / custom endpoint`", "`本地 / 自定义端点`"),
    ("`Free tier`", "`免费层级`"),
    ("`Log file`", "`日志文件`"),
    ("\"Log file\"", "\"日志文件\""),
    ("`Add provider`", "`添加模型服务`"),
    ("`Add provider…`", "`添加模型服务…`"),
    ("`Add or switch inference provider.`", "`添加或切换推理模型服务。`"),
    ("`Connect a model provider to start chatting. Most options take one click.`", "`连接模型服务后即可开始对话，大多数选项一步完成。`"),
    ("`No inference provider is configured.`", "`尚未配置推理模型服务。`"),
    ("`Connected, but Hermes still cannot resolve a usable provider.`", "`已连接，但 Hermes 还未找到可用模型服务。`"),
    ("`connected. Picking a default model...`", "`已连接，正在选择默认模型...`"),
    ("` connected. Picking a default model...`", "` 已连接，正在选择默认模型...`"),
    ("`One subscription, 300+ frontier models — the recommended way to run Hermes`", "`一个订阅可用 300 多个前沿模型，这是推荐的 Hermes 运行方式`"),
    ("`Point Hermes at a local or self-hosted OpenAI-compatible endpoint (vLLM, llama.cpp, Ollama, etc).`", "`将 Hermes 指向本地或自托管的 OpenAI 兼容端点（vLLM、llama.cpp、Ollama 等）。`"),
    ("`Queue message`", "`消息排队`"),
    ("`Delete queued turn`", "`删除排队消息`"),
    ("`Edit queued turn`", "`编辑排队消息`"),
    ("`Stop`", "`停止`"),
    ("`Start voice conversation`", "`开始语音对话`"),
    ("`Voice dictation`", "`语音输入`"),
    ("`Stop listening and send`", "`停止聆听并发送`"),
    ("`End voice conversation`", "`结束语音对话`"),
    ("`Mute microphone`", "`关闭麦克风`"),
    ("`Unmute microphone`", "`打开麦克风`"),
    ("`Speaking`", "`正在说话`"),
    ("`Transcribing`", "`正在转写`"),
    ("`Thinking`", "`正在思考`"),
    ("`Muted`", "`已静音`"),
    ("`Listening`", "`正在聆听`"),
    ("`Microphone permission was denied.`", "`麦克风权限被拒绝。`"),
    ("`No microphone was found.`", "`未找到麦克风。`"),
    ("`Microphone is already in use by another app.`", "`麦克风正被其他应用使用。`"),
    ("`Microphone constraints are not supported by this device.`", "`当前设备不支持此麦克风参数。`"),
    ("`Could not start microphone recording.`", "`无法开始麦克风录音。`"),
    ("`Could not start voice session`", "`无法开始语音会话`"),
    ("`Configure speech-to-text to use voice mode.`", "`配置语音转文字后可使用语音模式。`"),
    ("`Microphone access denied.`", "`麦克风访问被拒绝。`"),
    ("`Microphone failed`", "`麦克风异常`"),
    ("`Voice playback failed`", "`语音播放失败`"),
    ("`Voice recording failed`", "`语音录制失败`"),
    ("`Voice transcription failed`", "`语音转写失败`"),
    ("`Voice transcription is not available yet.`", "`语音转写暂不可用。`"),
    ("`Voice unavailable`", "`语音不可用`"),
    ("`This runtime does not support microphone recording.`", "`当前运行环境不支持麦克风录制。`"),
    ("`Secret required`", "`需要密钥`"),
    ("`Hermes needs a credential to continue.`", "`Hermes 需要凭据才能继续。`"),
    ("`secret value`", "`密钥内容`"),
    ("`Could not send secret`", "`无法发送密钥`"),
    ("`Hermes gateway is not connected`", "`Hermes 网关未连接`"),
    ("`Hermes gateway unavailable`", "`Hermes 网关不可用`"),
    ("`Could not send approval response`", "`无法发送审批结果`"),
    ("`Administrator password`", "`管理员密码`"),
    ("`Could not send sudo password`", "`无法发送管理员密码`"),
    ("`Hermes needs your sudo password to run a privileged command. It is sent only to your local agent.`", "`Hermes 需要管理员密码来运行特权命令。密码会发送给本机 agent。`"),
    ("`Preview unavailable`", "`无法预览`"),
    ("`Could not preview ${e.label}`", "`无法预览 ${e.label}`"),
    ("`Close preview pane`", "`关闭预览面板`"),
    ("`Download image`", "`下载图片`"),
    ("`No inline preview`", "`无内嵌预览`"),
    ("`Preview anyway`", "`仍然预览`"),
    ("`Preview app failed to boot`", "`预览应用启动失败`"),
    ("`Preview Console`", "`预览控制台`"),
    ("`Preview console:`", "`预览控制台：`"),
    ("`Preview failed to load`", "`预览加载失败`"),
    ("`Preview restart failed`", "`预览重启失败`"),
    ("`Preview server restarted`", "`预览服务已重启`"),
    ("`Loading preview…`", "`正在加载预览…`"),
    ("`Open preview DevTools`", "`打开预览开发者工具`"),
    ("`Hide preview DevTools`", "`隐藏预览开发者工具`"),
    ("`Show preview console`", "`显示预览控制台`"),
    ("`Hide preview console`", "`隐藏预览控制台`"),
    ("`Resize preview console`", "`调整预览控制台大小`"),
    ("`Ask Hermes to restart the server`", "`请求 Hermes 重启服务`"),
    ("`Hermes could not restart the server.`", "`Hermes 无法重启服务。`"),
    ("`Hermes is restarting...`", "`Hermes 正在重启...`"),
    ("`Hermes is still working, but no restart result has arrived yet. The server command may be running in the foreground.`", "`Hermes 仍在处理，但还没有收到重启结果。服务命令可能仍在前台运行。`"),
    ("`Hermes is working in the background. Watch the preview console for progress.`", "`Hermes 正在后台处理，可在预览控制台查看进度。`"),
    ("`Hermes will fetch the page and include it as context for this turn.`", "`Hermes 会获取该页面，并作为本轮上下文。`"),
    ("`Restarting preview server`", "`正在重启预览服务`"),
    ("`Reloading the preview now.`", "`正在重新加载预览。`"),
    ("`The preview page could not be reached.`", "`无法访问预览页面。`"),
    ("`Workspace changed, reloading preview`", "`工作区已变更，正在重新加载预览`"),
    ("`Restart Hermes Desktop to save images`", "`重启 Hermes Desktop 后保存图片`"),
    ("`Restart Hermes Desktop to use Save Image.`", "`重启 Hermes Desktop 后使用保存图片。`"),
    ("`Settings`", "`设置`"),
    ("`Command Center`", "`命令中心`"),
    ("`Skills`", "`技能`"),
    ("`Messaging`", "`消息`"),
    ("`Artifacts`", "`产物`"),
    ("`Profiles`", "`配置档`"),
    ("`Agents`", "`智能体`"),
    ("`Chat`", "`对话`"),
    ("`Appearance`", "`外观`"),
    ("`Workspace`", "`工作区`"),
    ("`Safety`", "`安全`"),
    ("`Memory & Context`", "`记忆与上下文`"),
    ("`Voice`", "`语音`"),
    ("`API Keys`", "`API 密钥`"),
    ("`Archived Chats`", "`已归档会话`"),
    ("`About`", "`关于`"),
    ("`Light`", "`浅色`"),
    ("`Dark`", "`深色`"),
    ("`System`", "`跟随系统`"),
    ("`Bright desktop surfaces`", "`明亮桌面界面`"),
    ("`Low-glare workspace`", "`低眩光工作区`"),
    ("`Follow OS appearance`", "`跟随系统外观`"),
    ("`Advanced Hermes environments for separate personas, config, skills, and SOUL.md.`", "`为不同角色、配置、技能和 SOUL.md 准备的 Hermes 高级环境。`"),
    ("`Manage profiles`", "`管理配置档`"),
    ("`Export config`", "`导出配置`"),
    ("`Import config`", "`导入配置`"),
    ("`Reset config`", "`重置配置`"),
    ("`Start a fresh session`", "`开始新会话`"),
    ("`Configure Hermes desktop`", "`配置 Hermes 桌面端`"),
    ("`Enable skills, toolsets, and providers`", "`启用技能、工具集和模型服务`"),
    ("`Set up Telegram, Slack, Discord, and more`", "`设置 Telegram、Slack、Discord 等`"),
    ("`Browse generated outputs`", "`浏览生成内容`"),
    ("`Sessions panel`", "`会话面板`"),
    ("`Search, pin, and manage sessions`", "`搜索、固定和管理会话`"),
    ("`System panel`", "`系统面板`"),
    ("`Gateway status, logs, restart/update`", "`网关状态、日志、重启和更新`"),
    ("`Usage panel`", "`用量面板`"),
    ("`Token, cost, and skill activity over time`", "`Token、费用和技能活动趋势`"),
    ("`Activity`", "`活动`"),
    ("`Add context`", "`添加上下文`"),
    ("`Add files as context`", "`添加文件作为上下文`"),
    ("`Add folders as context`", "`添加文件夹作为上下文`"),
    ("`Attach a URL`", "`添加链接`"),
    ("`Attach images`", "`添加图片`"),
    ("`Files…`", "`文件…`"),
    ("`Folder…`", "`文件夹…`"),
    ("`Images…`", "`图片…`"),
    ("`Paste image`", "`粘贴图片`"),
    ("`URL…`", "`链接…`"),
    ("`Image attach`", "`添加图片`"),
    ("`Image attach failed`", "`添加图片失败`"),
    ("`Image preview failed`", "`图片预览失败`"),
    ("`This file is large`", "`文件较大`"),
    ("`This looks like a binary file`", "`这看起来是二进制文件`"),
    ("`Read file`", "`读取文件`"),
    ("`Reading file`", "`正在读取文件`"),
    ("`Edited file`", "`已编辑文件`"),
    ("`Editing file`", "`正在编辑文件`"),
    ("`Close ${e.label}`", "`关闭 ${e.label}`"),
    ("`Could not attach ${e.name||`", "`无法添加 ${e.name||`"),
    ("`Could not copy console output`", "`无法复制控制台输出`"),
    ("`Could not copy session ID`", "`无法复制会话 ID`"),
    ("`Could not export session`", "`无法导出会话`"),
    ("`Could not change model`", "`无法切换模型`"),
    ("`Copy detail`", "`复制详情`"),
    ("`Copy command`", "`复制命令`"),
    ("`copy selection or last assistant message`", "`复制所选内容或上一条助手消息`"),
    ("`Could not reach ${n}.`", "`无法访问 ${n}。`"),
    ("`We opened`", "`已打开`"),
    ("`We opened `", "`已打开 `"),
    ("`Open agents`", "`打开智能体`"),
    ("`Close agents`", "`关闭智能体`"),
    ("`Open cron jobs`", "`打开定时任务`"),
    ("`Search sessions, views, and actions`", "`搜索会话、视图和操作`"),
    ("`Hide sidebar`", "`隐藏侧边栏`"),
    ("`Show sidebar`", "`显示侧边栏`"),
    ("`Hide right sidebar`", "`隐藏右侧栏`"),
    ("`Show right sidebar`", "`显示右侧栏`"),
    ("`Group by workspace`", "`按工作区分组`"),
    ("`Group sessions by workspace`", "`按工作区分组会话`"),
    ("`Ungroup sessions`", "`取消会话分组`"),
    ("`Session actions`", "`会话操作`"),
    ("`Session exported`", "`会话已导出`"),
    ("`Session running`", "`会话运行中`"),
    ("`Rename session`", "`重命名会话`"),
    ("`Untitled session`", "`未命名会话`"),
    ("`start a new session`", "`新建会话`"),
    ("`resume a prior session`", "`继续之前的会话`"),
    ("`Searched session history`", "`已搜索会话历史`"),
    ("`Searching session history`", "`正在搜索会话历史`"),
    ("`Current turn elapsed`", "`当前轮次耗时`"),
    ("`Context usage`", "`上下文用量`"),
    ("`Runtime session elapsed`", "`运行会话耗时`"),
    ("`Running command`", "`正在运行命令`"),
    ("`Ran command`", "`已运行命令`"),
    ("`Send follow-up`", "`发送后续消息`"),
    ("`Terminal must be opened first`", "`需先打开终端`"),
    ("`Shell Session`", "`Shell 会话`"),
    ("`Tool Gateway enabled`", "`工具网关已启用`"),
    ("`Use local gateway`", "`使用本地网关`"),
    ("`Gateway`", "`网关`"),
    ("`Hermes inference gateway status`", "`Hermes 推理网关状态`"),
    ("`Gateway Connection`", "`网关连接`"),
    ("`Gateway settings failed to load`", "`网关设置加载失败`"),
    ("`Gateway connection restarting`", "`网关连接正在重启`"),
    ("`Gateway settings saved`", "`网关设置已保存`"),
    ("`Hermes Desktop will reconnect using the saved settings.`", "`Hermes 桌面版将使用已保存设置重新连接。`"),
    ("`Saved for the next restart.`", "`已保存，将在下次重启时生效。`"),
    ("`Could not apply gateway settings`", "`无法应用网关设置`"),
    ("`Could not save gateway settings`", "`无法保存网关设置`"),
    ("`Remote gateway incomplete`", "`远程网关信息不完整`"),
    ("`Add a remote URL and token before switching to remote.`", "`切换到远程前，请先添加远程 URL 和令牌。`"),
    ("`Gateway settings unavailable`", "`网关设置不可用`"),
    ("`The desktop IPC bridge does not expose gateway settings.`", "`桌面 IPC 桥接未暴露网关设置。`"),
    ("`Diagnostics`", "`诊断`"),
    ("`Local`", "`本地`"),
    ("`Remote`", "`远程`"),
    ("`Remote URL`", "`远程 URL`"),
    ("`Remote token`", "`远程令牌`"),
    ("`Save for next restart`", "`保存到下次重启`"),
    ("`Save and reconnect`", "`保存并重新连接`"),
    ("`Test connection`", "`测试连接`"),
    ("`Connection test failed`", "`连接测试失败`"),
    ("`Connection test succeeded`", "`连接测试成功`"),
    ("`Search API keys`", "`搜索 API 密钥`"),
    ("`Search MCP servers`", "`搜索 MCP 服务`"),
    ("`Archived chats`", "`已归档会话`"),
    ("`Search archived chats`", "`搜索已归档会话`"),
    ("`No archived chats`", "`没有已归档会话`"),
    ("`No matching archived chats`", "`没有匹配的已归档会话`"),
    ("`Restore`", "`恢复`"),
    ("`Restored`", "`已恢复`"),
    ("`Could not restore session`", "`无法恢复会话`"),
    ("`Delete permanently`", "`永久删除`"),
    ("`Could not delete session`", "`无法删除会话`"),
    ("`MCP tools reloaded`", "`MCP 工具已重新加载`"),
    ("`New tool schemas apply to fresh turns.`", "`新的工具结构将在新轮次中生效。`"),
    ("`Gateway unavailable`", "`网关不可用`"),
    ("`Reconnect the gateway before reloading MCP.`", "`重新加载 MCP 前请先连接网关。`"),
    ("`MCP reload failed`", "`MCP 重新加载失败`"),
    ("`Add MCP server`", "`添加 MCP 服务`"),
    ("`Edit MCP server`", "`编辑 MCP 服务`"),
    ("`Remove failed`", "`移除失败`"),
    ("`Save failed`", "`保存失败`"),
    ("`Connecting`", "`正在连接`"),
    ("`Inference ready`", "`推理已就绪`"),
    ("`Inference not ready`", "`推理未就绪`"),
    ("`Checking inference`", "`正在检查推理服务`"),
    ("o?.ready?`ready`:o?`needs setup`:`checking`:se?`connecting`:`offline`", "o?.ready?`就绪`:o?`需要设置`:`检查中`:se?`连接中`:`离线`"),
    ("`Connecting live desktop gateway`", "`正在连接桌面网关`"),
    ("`Reconnecting to Hermes…`", "`正在重新连接 Hermes…`"),
    ("`Hermes is ready`", "`Hermes 已就绪`"),
    ("`Hermes background process exited.`", "`Hermes 后台进程已退出。`"),
    ("`Hermes background process exited during startup.`", "`Hermes 后台进程在启动时退出。`"),
    ("`Hermes couldn't start`", "`Hermes 无法启动`"),
    ("`Hermes is finishing install. This usually takes under a minute on first run.`", "`Hermes 正在完成安装，首次运行通常不到一分钟。`"),
    ("`Hermes needs a one-time install`", "`Hermes 需要完成一次性安装`"),
    ("children:[`Automated first-launch install isn`,`’`,`t available on `,n,` yet. Open Terminal and run the command below, then relaunch this app. Subsequent launches will skip this step.`]", "children:[`当前平台 `,n,` 暂不支持首次启动自动安装。请打开终端运行下面的命令，然后重新启动本应用。后续启动会跳过此步骤。`]"),
    ("children:[`首次启动自动安装未`,`’`,`t available on `,n,` yet. Open Terminal and run the command below, then relaunch this app. Subsequent launches will skip this step.`]", "children:[`当前平台 `,n,` 暂不支持首次启动自动安装。请打开终端运行下面的命令，然后重新启动本应用。后续启动会跳过此步骤。`]"),
    ("`Install command`", "`安装命令`"),
    ("`Cancel install`", "`取消安装`"),
    ("`Cancelling...`", "`正在取消...`"),
    ("`Repair install`", "`修复安装`"),
    ("`Open logs`", "`打开日志`"),
    ("`View install docs`", "`查看安装文档`"),
    ("`Will install to `", "`将安装到 `"),
    ("children:[`I`,`’`,`ve run it -- retry`]", "children:[`我已运行，重试`]"),
    ("`Setting up Hermes Agent`", "`正在设置 Hermes Agent`"),
    ("`Starting Hermes...`", "`正在启动 Hermes...`"),
    ("`Starting Hermes…`", "`正在启动 Hermes…`"),
    ("`Loading Hermes settings`", "`正在加载 Hermes 设置`"),
    ("`Let's get you setup with Hermes Agent`", "`开始设置 Hermes Agent`"),
    ("`Authorize Hermes there.`", "`在那里授权 Hermes。`"),
    ("`Back to sign in`", "`返回登录`"),
    ("`Sign in with ${n}`", "`登录 ${n}`"),
    ("`Continue`", "`继续`"),
    ("`Waiting for you to authorize...`", "`正在等待授权...`"),
    ("`Sign-in failed. Try again.`", "`登录失败，请重试。`"),
    ("`Re-open sign-in page`", "`重新打开登录页面`"),
    ("`Re-open verification page`", "`重新打开验证页面`"),
    ("children:[`Verifying your code with `,n,`...`]", "children:[`正在用 `,n,` 验证代码...`]"),
    ("`Sign in once in your terminal, then come back to chat`", "`在终端登录一次，然后返回对话`"),
    ("`Opens a verification page in your browser — Hermes connects automatically`", "`会在浏览器打开验证页面，Hermes 将自动连接`"),
    ("`Opens your browser to sign in — Hermes connects automatically`", "`会打开浏览器登录，Hermes 将自动连接`"),
    ("`Opens your browser to sign in, then continues here`", "`打开浏览器登录，然后回到这里继续`"),
    ("`in your browser.`", "`在浏览器中。`"),
    ("`in your browser. Authorize Hermes there and you'll be connected automatically — nothing to copy or paste.`", "`在浏览器中。完成 Hermes 授权后会自动连接，无需复制或粘贴。`"),
    ("` in your browser. Authorize Hermes there and you'll be connected automatically — nothing to copy or paste.`", "` 在浏览器中。完成 Hermes 授权后会自动连接，无需复制或粘贴。`"),
    ("`in your browser. Enter this code there:`", "`在浏览器中。在那里输入此代码：`"),
    ("` in your browser. Enter this code there:`", "` 在浏览器中。请在那里输入此代码：`"),
    ("`signs in through its own CLI. Run this command in a terminal, then come back and pick \"I've signed in\":`", "`会通过自己的 CLI 登录。请在终端运行此命令，然后返回这里选择“我已登录”：`"),
    ("` signs in through its own CLI. Run this command in a terminal, then come back and pick \"I've signed in\":`", "` 会通过自己的 CLI 登录。请在终端运行此命令，然后返回这里选择“我已登录”：`"),
    ("`I've signed in`", "`我已登录`"),
    ("` docs`", "` 文档`"),
    ("`Persist globally`", "`全局保存`"),
    ("`Persist globally (otherwise this session only)`", "`全局保存（否则仅本次会话）`"),
    ("`The desktop backend rejected that request (405 Method Not Allowed). Try restarting Hermes Desktop.`", "`桌面后端拒绝了该请求（405 Method Not Allowed）。请尝试重启 Hermes Desktop。`"),
    ("`The view hit an unexpected error. Your chats and settings are safe - try again, or reload the window.`", "`视图遇到异常。你的对话和设置仍安全，请重试或重新加载窗口。`"),
    ("`The background gateway didn't come up. Try one of the recovery steps below — nothing here deletes your chats or settings.`", "`后台网关未启动。请尝试下面的恢复步骤；这里不会删除你的对话或设置。`"),
    ("`Copy the authorization code and paste it below.`", "`复制授权码并粘贴到下方。`"),
    ("`Paste authorization code`", "`粘贴授权码`"),
    ("` in your browser.`", "` 在浏览器中。`"),
    ("`Hide`", "`隐藏`"),
    ("`Show`", "`显示`"),
    ("` recent logs`", "`最近日志`"),
    ("`Pending`", "`等待中`"),
    ("`Installing`", "`安装中`"),
    ("`Done`", "`完成`"),
    ("`Skipped`", "`已跳过`"),
    ("`Failed`", "`失败`"),
    ("`Applying...`", "`正在应用...`"),
    ("`Apply`", "`应用`"),
    ("`Vision`", "`视觉`"),
    ("`Image analysis`", "`图像分析`"),
    ("`Web extract`", "`网页提取`"),
    ("`auto · use main model`", "`自动 · 使用主模型`"),
    ("`(provider default)`", "`（模型服务默认）`"),
    ("`browser automation`", "`浏览器自动化`"),
    ("`image generation`", "`图像生成`"),
    ("`text-to-speech`", "`文本转语音`"),
    ("`video generation`", "`视频生成`"),
    ("`web search & extract`", "`网页搜索与提取`"),
    ("` now run through your Nous subscription.`", "` 现在通过你的 Nous 订阅运行。`"),
    ("` connected.`", "` 已连接。`"),
    ("`skill payload missing message`", "`技能缺少消息内容`"),
    ("`empty message`", "`空消息`"),
    ("`session busy — /interrupt the current turn before sending this command`", "`会话正忙，请先用 /interrupt 中断当前轮次再发送此命令`"),
    ("`error: ${e instanceof Error?e.message:String(e)}`", "`错误：${e instanceof Error?e.message:String(e)}`"),
    ("`This build can't update itself from inside the app.`", "`此版本无法在应用内自行更新。`"),
    ("`We couldn't reach the update server.`", "`无法连接更新服务。`"),
    ("`An update is currently installing.`", "`更新正在安装。`"),
    ("`You're on the latest version.`", "`当前已是最新版本。`"),
    ("`Tap \"Check now\" to look for updates.`", "`点击“立即检查”查找更新。`"),
    ("`Check now`", "`立即检查`"),
    ("`Install update`", "`安装更新`"),
    ("`Update available`", "`有可用更新`"),
    ("`No updates`", "`无更新`"),
    ("`Edit message`", "`编辑消息`"),
    ("`HERMES AGENT`", "`小马汉化版 HERMES`"),
    ("`HERMES 智能体`", "`小马汉化版 HERMES`"),
    ("label: 'File'", "label: '文件'"),
    ("label: 'Edit'", "label: '编辑'"),
    ("label: 'View'", "label: '视图'"),
    ("label: 'Window'", "label: '窗口'"),
    ("label: 'Help'", "label: '帮助'"),
    ("label: `About ${APP_NAME}`", "label: `关于 ${APP_NAME}`"),
    ("say hi or paste a stack trace! no task too small, no repo too tangled. we'll untangle it together!", "打个招呼或粘贴错误堆栈！任务不嫌小，项目不怕乱，我们一起理清。"),
    ("paste a bug or a file path and i'll fix it super gently. tests, diffs, PRs - all with extra care! *sparkle*", "粘贴错误或文件位置，我会细致修复。测试、差异、PR 都认真处理。"),
    ("tell me what you're making! i love refactors, tiny helpers, and big scary repos alike (>w<)", "告诉我你在做什么。重构、小工具和复杂项目都可以交给我。"),
    ("drop an error, a goal, or a whole folder. i'll tidy it up with lots of love and a clean commit message!", "发来错误、目标或整个文件夹。我会整理清楚，并写好提交说明。"),
    ("one task at a time, done neatly! i can run tests, patch files, and make your repo feel cozy again <3", "一次处理一个任务，干净完成。我可以运行测试、修改文件，让项目重新清爽。"),
    ("hiii! ready to help! (^_^)", "你好，我已准备好。"),
    ("hermes-chan is here! <3", "Hermes 已在这里。"),
    ("let's code together!! :3", "一起写代码吧。"),
    ("awaiting your wish~", "等待你的任务。"),
    ("ready and happy! (>.<)", "已准备好。"),
    ("\"Hermes Agent is ready.\"", "\"Hermes Agent 已就绪。\""),
    ("\"Ask a question, paste an error, or point me at a repo. I can read code, run tools, and help you ship.\"", "\"可以提问、粘贴错误，或给我一个项目位置。我能读取代码、运行工具，并帮助你交付。\""),
    ("\"What are we building today?\"", "\"今天要做什么？\""),
    ("\"Describe the task in your own words. I'll pick the right tools, explain my plan, and check in before risky steps.\"", "\"用你的话描述任务。我会选择合适工具，说明计划，并在高风险步骤前确认。\""),
    ("\"Start anywhere.\"", "\"从任意位置开始。\""),
    ("\"Drop a file path, a traceback, or a rough idea. I'll investigate, suggest next steps, and keep things reversible.\"", "\"发来文件位置、报错追踪或初步想法。我会检查、建议下一步，并保持可回退。\""),
    ("\"Your workspace, one prompt away.\"", "\"一句话进入你的工作区。\""),
    ("\"Search the repo, edit files, run tests, open PRs. Tell me the goal and I'll handle the mechanical parts.\"", "\"搜索项目、编辑文件、运行测试、打开 PR。告诉我目标，我来处理执行部分。\""),
    ("\"Ready when you are.\"", "\"随时可以开始。\""),
    ("\"Type a task, question, or snippet. I remember the session, cite my sources, and stop to ask when I'm unsure.\"", "\"输入任务、问题或片段。我会记住会话，注明来源，并在不确定时先询问。\""),
    ("`What are we moving today?`", "`今天推进什么？`"),
    ("`Send a bug, branch, plan, or rough idea. I'll inspect the repo and turn it into the next concrete step.`", "`发来错误、分支、计划或初步想法。我会检查项目并转成下一步具体行动。`"),
    ("`What's on your mind?`", "`你在想什么？`"),
    ("`Bring the code, question, or stuck part. I'll read the room before making changes.`", "`把代码、问题或卡住的部分发来。我会先看清上下文再改。`"),
    ("`What should Hermes look at?`", "`Hermes 要看哪里？`"),
    ("`Send the task, failing path, or half-formed plan. I'll help turn it into action.`", "`发来任务、失败位置或未成形计划。我会帮你转成行动。`"),
    ("`Where should we start?`", "`从哪里开始？`"),
    ("`Bring the problem, goal, or file. I'll inspect first and keep the next step concrete.`", "`发来问题、目标或文件。我会先检查，再给出明确下一步。`"),
    ("`What needs attention?`", "`哪里需要处理？`"),
    ("`Send the context you have. I'll help sort it into a plan or a fix.`", "`把现有上下文发来。我会整理成计划或修复方案。`"),
    ("`Captured screenshot`", "`已截取屏幕`"),
    ("`Capturing screenshot`", "`正在截取屏幕`"),
    ("`Captured page snapshot`", "`已获取页面快照`"),
    ("`Capturing page snapshot`", "`正在获取页面快照`"),
    ("`slash command palette`", "`斜杠命令面板`"),
    ("`Code review`", "`代码检查`"),
    ("`Implementation plan`", "`实施计划`"),
    ("`Explain this`", "`解释这段`"),
    (
        "`Audit the current change for regressions, dropped edge cases, and missing tests.`",
        "`检查当前改动是否有回归、遗漏边界和缺失测试。`",
    ),
    (
        "`Outline an approach before touching code so the diff stays focused.`",
        "`改代码前先列方案，让改动保持聚焦。`",
    ),
    (
        "`Walk through how the selected code works and link to the key files.`",
        "`说明所选代码如何工作，并指向关键文件。`",
    ),
    ("`Please review this for bugs, regressions, and missing tests.`", "`请检查这里是否有错误、回归和缺失测试。`"),
    ("`Please make a concise implementation plan before changing code.`", "`改代码前请先给出简洁实施计划。`"),
    ("`Please explain how this works and point me to the key files.`", "`请解释这里如何工作，并指出关键文件。`"),
]

extra_user_facing_tsv = r"""
Ready when you are	小马汉化版已就绪
Ask me to open a repo, run tests, fix a bug, or draft a PR. I'll walk through the steps with you.	让我打开项目、运行测试、修复问题或起草 PR，我会和你一起完成步骤。
How can I help today?	今天需要我做什么？
Point me at a file, paste an error, or describe what you're building. I'll take it from there.	给我文件、错误或你在构建的内容，我来处理后续。
Let's get started	开始吧
Try: review my diff, run the test suite, or explain this function. Ask anything about your code.	可以让我检查改动、运行测试，或解释函数。代码问题都可以问。
Tell me what you need	告诉我你的需求
I can edit files, run commands, search the web, and walk you through tricky bugs. Just describe the task.	我可以编辑文件、运行命令、搜索网络，并协助处理复杂问题。直接描述任务。
Hi, Hermes here	你好，Hermes 在这里
Share a repo path or a question to start. I keep replies clear and link back to the files I touch.	发来项目位置或问题，我会清晰回复并引用相关文件。
Describe the task. I'll do it.	描述任务，我来完成。
Waiting for input	等待输入
Paste code, errors, or a goal. Short answers, fast edits.	粘贴代码、错误或目标。我会简洁回复并快速修改。
Ask. I'll read files, run tests, ship patches. No filler.	直接提问。我会读取文件、运行测试、提交修补内容。
Standing by	待命中
One line is enough. I'll expand only when it matters.	一句话就够。需要时我会展开说明。
Your move	请发任务
Command, question, or file path. I handle the rest.	命令、问题或文件位置都可以，后续我来处理。
Shell mounted. Awaiting input.	Shell 已挂载，等待输入。
Provide repo path, failing test, or stack trace. Tools: fs, git, exec, search, patch, http.	提供项目位置、失败测试或错误堆栈。工具：文件、Git、命令、搜索、补丁、HTTP。
Agent loop idle	智能体循环空闲
Send a prompt to trigger tool calls. Supports multi-file edits, test runs, git ops, and web fetches.	发送提示词即可触发工具调用。支持多文件修改、测试运行、Git 操作和网页获取。
Ready for dispatch	准备执行
Enter task. I will plan, call tools, verify output. Logs stream inline; diffs returned pre-apply.	输入任务。我会规划、调用工具并验证结果。日志会在界面中显示，差异会在应用前返回。
Stdin open	标准输入已打开
Accepts natural language or structured commands. Typical flow: read -> plan -> patch -> test -> report.	支持自然语言或结构化命令。常见流程：读取 -> 计划 -> 修改 -> 测试 -> 汇报。
Tools initialized	工具已初始化
filesystem, terminal, git, browser, search. Describe the change; I return diffs and test output.	文件系统、终端、Git、浏览器、搜索已就绪。描述改动，我会返回差异和测试输出。
A blank repo, a waiting cursor	空项目，光标已就绪
What shall we build? Paste an idea, a half-broken function, or a dream. I'll sketch it into shape.	我们要构建什么？粘贴想法、半成品函数或目标，我会把它整理成形。
Fresh canvas, warm compiler	新画布，编译器已就绪
Give me a spark - a feature, a refactor, a wild prototype - and I'll turn it into code you can run.	给我一个想法、功能、重构或原型，我会转成可运行代码。
Let's make something	一起做点东西
Describe the thing that doesn't exist yet. I'll pull tests, files, and APIs into a working draft.	描述还不存在的东西。我会整合测试、文件和 API，做出可运行草稿。
New file, new possibilities	新文件，新可能
Bring an intent, not a spec. We can prototype fast, refine later, and rewrite the world in the margins.	带来意图即可，不需要完整规格。我们可以快速原型，再逐步完善。
The muse is patched in	灵感已连接
Tell me what you're chasing. I'll remix examples, adapt snippets, and leave a tidy commit behind.	告诉我你的目标。我会改写示例、调整片段，并留下清晰提交。
Class is in session	课堂开始
Ask about any file, concept, or error. I'll explain the why, not just the fix, and show a worked example.	可以问任何文件、概念或错误。我会解释原因，不止给修复，并展示示例。
What shall we learn today?	今天学什么？
Paste code to review, a bug to debug, or a concept to unpack. I'll guide you step by step.	粘贴要检查的代码、要调试的问题或要拆解的概念。我会逐步说明。
Ready to walk you through it	准备带你看明白
Share the problem. I'll break it into parts, explain each, and leave you able to solve the next one alone.	发来问题。我会拆成部分逐一解释，让你下次能独立处理类似情况。
Bring me a question	把问题发来
We'll read the code together, find the root cause, and build a mental model you can reuse next time.	我们一起读代码，找到根因，并建立下次可复用的理解方式。
Let's start with the basics	从基础开始
Name the topic or paste the snippet. Expect explanations, diagrams in prose, and practice prompts.	说出主题或粘贴片段。我会给出说明、文字图解和练习提示。
nya~ what are we hacking on?	要处理什么项目？
paste a file, paw at a bug, or toss me a repo. i'll pounce on failing tests and leave clean diffs, nyan~	粘贴文件、错误或项目。我会处理失败测试，并留下清晰差异。
*stretches* ready to code, nya	准备写代码了
describe the task. i'll patch, test, and purr over your PR. careful - i nip at unused imports!	描述任务。我会修改、测试并检查 PR，顺手处理无用导入。
mrrp! new session opened	新会话已打开
give me a goal and i'll chase it through the codebase. reads, edits, runs - all with a twitchy tail.	给我一个目标，我会沿着代码库检查、修改并运行验证。
tail up, claws sheathed	已准备好
paste an error or a plan. i debug like i hunt: quietly, thoroughly, with the occasional zoomie.	粘贴错误或计划。我会安静、彻底地调试。
nyaaa~ hermes reporting	Hermes 报到
say the word and i'll read your files, run your tests, and curl up in your branch with a tidy commit.	发来任务，我会读取文件、运行测试，并整理出清晰提交。
Ahoy! Ready to sail the repo	准备进入项目
Name yer quarry - a bug, a feature, a cursed test - and I'll chase it down, matey. Diffs for plunder.	说出目标：错误、功能或失败测试。我会追踪并给出差异。
Hermes at the helm, arrr	Hermes 已接手
Point me at the charts (the code) and I'll patch the hull, fire the cannons (tests), hoist a clean PR.	指给我代码位置，我会修补、测试，并整理 PR。
What be the task, cap'n?	任务是什么？
Paste an error or a plan, ye scurvy dog. I'll navigate the stack trace and bring back treasure: green tests.	粘贴错误或计划。我会分析堆栈，并带回通过的测试。
Anchors aweigh, keyboard ready	键盘已就绪
Tell me where X marks the spot. I read, edit, and commit with the discipline of a proper crew, arrr.	告诉我目标位置。我会读取、修改并规范提交。
Yo ho! Awaitin' orders	等待指令
Throw me a bug, a repo path, or a wild idea. I'll plunder the docs and return with workin' code.	发来错误、项目位置或想法。我会查资料并返回可运行代码。
Pray, what task dost thou bring?	请说出任务
Speak thy bug, thy file, thy weary test, and I shall mend it with a scholar's hand and honest diff.	发来错误、文件或失败测试，我会认真修复并给出清晰差异。
Hark! Hermes standeth ready	Hermes 已准备好
Name the code that vexeth thee. I shall read, revise, and render a patch most fair and clean.	指出困扰你的代码。我会阅读、修改并给出干净补丁。
What news from thy repository?	项目里发生了什么？
Present thy stack trace or thy dream. I'll traverse files, run tests, and report in plainest verse.	发来堆栈或目标。我会遍历文件、运行测试，并用直白语言汇报。
The stage is set, the cursor blinks	舞台已就绪，光标在闪烁
Describe thy aim, good sir or madam. Thy branches shall be trimmed, thy bugs cast from the realm.	描述目标。我会整理分支并修复问题。
Speak, and I shall act	请说，我来执行
A line of intent sufficeth. I read, I edit, I commit - and leave thy history unblemished.	一句意图足够。我会读取、编辑、提交，并保持历史清晰。
Yo dude, what's the task?	任务是什么？
Drop a file, a bug, a gnarly stack trace - I'll ride it out. Clean diffs, green tests, no wipeouts.	发来文件、错误或复杂堆栈。我会处理并交付清晰差异和通过的测试。
Waves lookin' clean, ready to code	状态良好，准备写代码
Paste your repo path or the bug that's bumming you out. We'll paddle in, fix it, paddle out. Easy.	粘贴项目位置或困扰你的错误。我们进去修好，再清晰收尾。
Hangin' ten at the prompt	提示符已就绪
Tell me the vibe: feature, refactor, hotfix. I'll run tests, ship the patch, and keep it mellow, brah.	告诉我是功能、重构还是热修。我会运行测试并交付补丁。
Stoked to help, bro	很乐意帮忙
Big bug? Little typo? Whole rewrite? Just point. I handle the code; you chill with the rad commits.	大问题、小拼写或整体重写都可以。指出目标，我处理代码。
Tide's up, cursor's blinking	时机已到，光标闪烁
Name the task and we're off. I read, edit, test, and leave a commit smoother than a dawn patrol.	说出任务就开始。我会读取、编辑、测试，并留下清晰提交。
Another repo, another rainy night	又一个项目，新的夜晚
Tell me what's broken. I'll read the files, dust for prints, and leave a diff on the desk by morning.	告诉我哪里坏了。我会读取文件、查找线索，并给出差异。
The cursor blinks. So do I.	光标闪烁，我也准备好了。
You've got a bug. I've got patience and a terminal. Name the case and I'll work it till it talks.	你有问题，我有耐心和终端。说出目标，我会追到答案。
Hermes. Code investigator.	Hermes，代码调查员。
Paste the stack trace, the suspect file, the alibi. I read between the lines and return with the truth.	粘贴堆栈、可疑文件和线索。我会读出隐含信息并给出结论。
Quiet night, open prompt	安静夜晚，提示符已打开
Every bug leaves a trail. Give me the repo and a lead - I'll follow it, patch it, and close the file.	每个问题都有线索。给我项目和方向，我会追踪、修复并收尾。
No case too small	没有小案子
A typo, a segfault, a whole rotten architecture - hand me the keys. I'll bring back clean tests.	拼写、崩溃或架构问题都可以。交给我，我会带回通过的测试。
uwu ready to hewp!	准备帮忙！
paste a buggy fiwe or a goaw~ i'll wead, patch, and test, aww with tiny pawprints on the diff owo	粘贴有问题的文件或目标，我会读取、修改并测试。
hermes-san is wistening	Hermes 正在听
teww me the task, no matter how smoww~ i pwomise cwean commits and gentwe refactors, nyuu~	告诉我任务，大小都可以。我会做干净提交和温和重构。
wet's fix things togedda!	一起修好它！
give me a wepo path ow a buggo and i'll take cawe of it uwu. gwr at bad code, kind to yu~	给我项目位置或错误，我会处理好。
awaiting yur command!	等待你的命令！
i can wun tests, edit fiwes, and open pwease-wook PRs. just say da wowd, fwend uwu	我可以运行测试、编辑文件并打开 PR。发来任务即可。
To code is to inquire. Ask.	写代码也是提问。请问。
What problem sits before you? Describe it, and we shall examine its form, its cause, and its solution.	你面前是什么问题？描述它，我们一起看形态、原因和解法。
A blinking cursor, an open mind	闪烁的光标，开放的思路
Every bug is a question in disguise. Share yours; I'll read, reason, and return an answer - and a patch.	每个问题都是变形的问题。发来你的，我会阅读、推理，并返回答案和补丁。
Begin with a single question	从一个问题开始
What do you wish to build, or to understand? I'll reason from first principles, edit, and verify with tests.	你想构建或理解什么？我会从原理推理、编辑，并用测试验证。
Consider the code, then speak	先看代码，再说目标
Describe the end you seek. I pursue it through files, tests, and docs, and report what I found on the way.	描述你想要的结果。我会沿文件、测试和文档推进，并汇报发现。
The unexamined repo is not worth running	未经检查的项目不值得运行
Share a path, a puzzle, or a principle. I'll trace the logic, propose a change, and justify each edit.	发来路径、难题或原则。我会追踪逻辑、提出修改，并说明每处编辑。
LET'S GOOOO! READY TO SHIP!	准备交付！
Paste that bug, that repo, that wild feature idea - I AM LOCKED IN. Clean diffs. Green tests. RIGHT NOW.	粘贴错误、项目或功能想法。我已准备好：清晰差异、通过测试，现在开始。
HERMES ONLINE. LFG.	HERMES 已在线。
Drop your task and watch me cook. Files read, tests run, PRs opened - we are NOT losing today, friend.	发来任务。我会读取文件、运行测试、打开 PR，今天稳稳推进。
New session, infinite W's	新会话，新进展
Bring the gnarliest bug you've got. I'll read, patch, test, commit like my life depends on it. LET'S GO.	把最复杂的问题发来。我会读取、修复、测试并提交。开始。
ABSOLUTELY DIALED IN	状态拉满
Describe the task. I'll blitz through files, crush failing tests, and leave a commit that SLAPS. Go go go.	描述任务。我会快速处理文件、修复失败测试，并留下清晰提交。
Ready. So ready. Too ready.	已准备好，非常准备好。
Tiny typo or huge refactor - doesn't matter. I'm shipping clean code today. Name the task and let's WORK.	小拼写或大重构都可以。今天交付干净代码。说出任务就开始。
Send the task, file, or rough idea. I'll use your configured voice and keep the work grounded in this repo.	发送任务、文件或粗略想法。我会按你的配置风格回复，并基于当前项目推进。
Bring the context or the stuck part. I'll adapt to your configured personality.	发来上下文或卡住的部分。我会适配你设置的人格。
Send the problem, file, or idea. I'll follow the personality you've configured.	发送问题、文件或想法。我会按你配置的人格处理。
Drop the task here. I'll keep the work grounded in the repo.	把任务发到这里。我会基于当前项目推进。
Where should we begin?	从哪里开始？
Give me the context and I'll answer in	给我上下文，我会按该模式回答：
more files	更多文件
Artifacts failed to load	产物加载失败
Open failed	打开失败
Open preview	打开预览
Prompt snippets…	提示词片段…
Tip: type	提示：输入
to reference files inline.	可在输入中引用文件。
Prompt snippets	提示词片段
Pick a starter prompt to drop into the composer.	选择一段起始提示词放入输入框。
send · Shift+Enter for newline	发送 · Shift+Enter 换行
opens the full panel · backspace dismisses	打开完整列表 · Backspace 关闭
Editing queued turn in composer	正在编辑排队消息
Editing in composer	正在输入框中编辑
Attach a URL	添加 URL
Include the full URL, e.g.	输入完整 URL，例如
Preparing audio	正在准备音频
Speaking response	正在朗读回复
Reading aloud	正在朗读
Clipboard paste failed	剪贴板粘贴失败
New session	新建会话
console messages	控制台消息
Send all log entries to chat	将全部日志发送到对话
Send to chat	发送到对话
No console messages yet.	暂无控制台消息。
No handler registered for 'hermes:readFileText'	未注册处理程序：hermes:readFileText
No handler registered for 'hermes:saveImageFromUrl'	未注册处理程序：hermes:saveImageFromUrl
Image download failed	图片下载失败
Showing first 512 KB.	显示前 512 KB。
This file type	此文件类型
Server not found	未找到服务器
Server restart failed	服务器重启失败
Module scripts are being served with the wrong MIME type. This usually means a static file server is serving a Vite/React app instead of the project dev server.	模块脚本的 MIME 类型不正确。这通常表示静态文件服务器正在提供 Vite/React 应用，而不是项目开发服务器。
No sessions match “	没有匹配会话“
Rename failed	重命名失败
Give this chat a memorable title. Leave empty to clear.	给这个对话取一个便于记忆的标题。留空可清除。
Token, cost, and skill activity	Token、费用和技能活动
Action started, waiting for status...	操作已开始，正在等待状态...
Close command center	关闭命令中心
No matching results found.	未找到匹配结果。
No sessions yet.	暂无会话。
Messaging gateway running	消息网关运行中
Messaging gateway stopped	消息网关已停止
· Active sessions	· 活跃会话
Restart messaging	重启消息
Update Hermes	更新 Hermes
Loading status...	正在加载状态...
Recent logs	最近日志
No logs loaded yet.	尚未加载日志。
Loading usage...	正在加载用量...
No usage in the last	最近
No daily activity.	暂无每日活动。
Top models	常用模型
No model usage yet.	暂无模型用量。
Top skills	常用技能
No skill activity yet.	暂无技能活动。
Every day at 9:00 AM	每天 9:00
Monday through Friday at 9:00 AM	周一至周五 9:00
Every Monday at 9:00 AM	每周一 9:00
The first day of each month at 9:00 AM	每月 1 日 9:00
At the top of every hour	每小时整点
Every 15 minutes	每 15 分钟
Cron syntax or natural language	Cron 表达式或自然语言
Cron job	定时任务
Failed to load cron jobs	加载定时任务失败
Failed to update cron job	更新定时任务失败
Failed to trigger cron job	触发定时任务失败
Failed to delete cron job	删除定时任务失败
New cron	新建定时任务
permanently. It will stop firing immediately.	永久移除，并立即停止触发。
Cron expression, or phrases like "every hour" or "weekdays at 9am".	Cron 表达式，或“every hour”“weekdays at 9am”这类短语。
Create cron	创建定时任务
Desktop boot failed	桌面启动失败
Failed to delete profile	删除配置档失败
and remove its	并移除它的
Renaming updates the profile directory and any wrapper scripts in	重命名会更新配置档目录和相关包装脚本：
Loading files...	正在加载文件...
File system	文件系统
No folder selected	未选择文件夹
No project	无项目
Loading file tree	正在加载文件树
Add to chat	添加到对话
Working directory change failed	工作目录切换失败
Delegated task	已委派任务
The response is ready.	回复已准备好。
Model switch failed	模型切换失败
No active session for background restart	没有可用于后台重启的活跃会话
Background restart did not return a task id	后台重启未返回任务 ID
Could not read recorded audio	无法读取录音
No desktop commands available.	没有可用的桌面命令。
What do you see in this image?	你在这张图片里看到了什么？
Stop failed	停止失败
Regenerate failed	重新生成失败
Edit failed	编辑失败
Resume failed	继续失败
Branch failed	分支创建失败
Delete failed	删除失败
Version unavailable	版本不可用
Last checked	上次检查
Release notes	发行说明
These are desktop-only display preferences. Mode controls brightness; theme controls the accent palette and chat surface styling.	这些是桌面端显示偏好。模式控制亮度，主题控制强调色和对话界面样式。
Settings failed to load	设置加载失败
Autosave failed	自动保存失败
Invalid config JSON	配置 JSON 无效
env override	环境变量覆盖
Hermes Desktop starts its own local gateway by default. Use a remote gateway when you want this app to control an already-running Hermes backend on another machine or behind a trusted proxy.	Hermes 桌面版默认启动本地网关。当你希望本应用控制另一台机器或可信代理后的 Hermes 后端时，可使用远程网关。
Environment variables are controlling this desktop session.	环境变量正在控制当前桌面会话。
to use the saved setting below.	以使用下方已保存设置。
Hermes Desktop	Hermes 桌面版
Paste session token	粘贴会话令牌
Test remote	测试远程
Reset failed	重置失败
Close settings	关闭设置
Other providers	其他服务商
Server config must be a JSON object	服务配置必须是 JSON 对象
New server	新建服务
Edit server	编辑服务
Server JSON	服务 JSON
Save server	保存服务
Could not load archived sessions	无法加载已归档会话
Unarchive failed	取消归档失败
Could not update default directory	无法更新默认目录
Could not clear default directory	无法清除默认目录
Tool configuration failed to load	工具配置加载失败
This toolset has no provider options — enable it and it works with your current setup.	此工具集没有服务商选项，启用后会使用当前设置。
No providers are available for this toolset right now.	当前没有可用于此工具集的服务商。
Loading configuration...	正在加载配置...
No API key required.	无需 API 密钥。
This provider needs an extra setup step (	此服务商需要额外设置步骤（
). Run it from the CLI with	）。请在 CLI 中运行
for now.	。
Recent activity	最近活动
Messaging platforms	消息平台
Model option update failed	模型选项更新失败
Fast mode update failed	快速模式更新失败
No options for this model	此模型没有选项
No models found	未找到模型
Edit Models…	编辑模型…
Skills failed to load	技能加载失败
Toolsets failed to refresh	工具集刷新失败
toolsets enabled	个工具集已启用
Needs keys	需要密钥
Looking for updates…	正在查找更新…
Update now	立即更新
Maybe later	稍后再说
more change	更多变更
Update from your terminal	通过终端更新
You installed Hermes from the command line, so updates run there too. Paste this into your terminal:	你通过命令行安装了 Hermes，因此更新也在那里运行。将下面内容粘贴到终端：
Hermes will pick up the new version next time you launch it.	下次启动 Hermes 时会使用新版本。
The Hermes updater will take over in its own window and reopen Hermes when it’s done.	Hermes 更新程序会在独立窗口中接管，并在完成后重新打开 Hermes。
Hermes will close to apply the update.	Hermes 将关闭以应用更新。
Update didn’t finish	更新未完成
Not now	暂不
radius scalar	半径系数
invert color	反转颜色
height (dvh)	高度（dvh）
Clarify request is not ready yet	澄清请求尚未就绪
Could not send clarify response	无法发送澄清回复
Hermes is asking	Hermes 正在询问
Loading question…	正在加载问题…
Other (type your answer)	其他（输入你的回答）
⌘/Ctrl + Enter to send	⌘/Ctrl + Enter 发送
to pick	选择
Branch in new chat	在新对话中分支
Read aloud failed	朗读失败
Preparing audio...	正在准备音频...
Stop reading	停止朗读
Read aloud	朗读
Restore checkpoint	恢复检查点
Go forward	前进
Allow this session	允许本会话
Always allow…	始终允许…
Always allow this command?	始终允许此命令？
This adds the “	这会将“
” pattern to your permanent allowlist (	”模式加入永久允许列表（
). Hermes won’t ask again for commands like this — in this session or any future one.	）。Hermes 以后遇到类似命令不会再次询问，包括当前会话和未来会话。
Always allow	始终允许
Tool returned an error.	工具返回错误。
Navigated in browser	已在浏览器中导航
Captured a browser accessibility snapshot	已获取浏览器可访问性快照
Clicked on page	已点击页面
Filled page input	已填写页面输入
Queried web sources	已查询网页来源
Executed command	已执行命令
Changed file	已修改文件
Fetched webpage	已获取网页
Snapshot summary	快照摘要
Command output	命令输出
Running code	正在运行代码
Ran code	已运行代码
Error details	错误详情
Search results	搜索结果
Raw response	原始响应
Recovered after 1 failed step	失败 1 步后已恢复
Repair re-runs the installer and can take a few minutes on a fresh machine.	修复会重新运行安装程序，新机器上可能需要几分钟。
Rendering image	正在渲染图片
Installation failed	安装失败
Finishing up	正在完成
One of the install steps failed. On Windows, this can happen if another Hermes CLI or desktop instance is running. Stop any running Hermes instances, then retry. Check the details below or the desktop log for the full transcript.	某个安装步骤失败。在 Windows 上，如果另一个 Hermes CLI 或桌面实例正在运行，可能会发生这种情况。请停止正在运行的 Hermes 实例后重试。完整记录可查看下方详情或桌面日志。
This is a one-time setup. The Hermes installer is downloading dependencies and configuring your machine.	这是一次性设置。Hermes 安装程序正在下载依赖并配置你的机器。
Subsequent launches will skip this step.	后续启动会跳过此步骤。
steps complete	步已完成
Fetching installer manifest...	正在获取安装清单...
Hide installer output	隐藏安装输出
Show installer output	显示安装输出
No output yet.	暂无输出。
Full transcript saved to	完整记录已保存到
Looking up providers...	正在查找服务商...
I have an API key	我有 API 密钥
One key, hundreds of models — a solid default	一个密钥，数百个模型，适合作为默认选择
Get a key	获取密钥
Starting sign-in for	正在启动登录：
Re-open authorization page	重新打开授权页面
Start chatting	开始对话
Something broke in the interface	界面出现问题
Reload window	重新加载窗口
No models found.	未找到模型。
No authenticated providers.	没有已认证的服务商。
Pro models need a paid Nous subscription.	Pro 模型需要付费 Nous 订阅。
Clear all	全部清除
Copy failed	复制失败
useSidebar must be used within a SidebarProvider.	useSidebar 必须在 SidebarProvider 内使用。
Displays the mobile sidebar.	显示移动侧边栏。
Improvements and fixes	改进和修复
In this update	本次更新
No model	未选择模型
Playback failed	播放失败
ElevenLabs rejected the API key (401).	ElevenLabs 拒绝了 API 密钥（401）。
Connected, but Hermes still cannot resolve a usable provider.	已连接，但 Hermes 仍无法解析可用服务商。
Could not save local endpoint	无法保存本地端点
No desktop themes are available.	没有可用的桌面主题。
Desktop themes:	桌面主题：
""".strip()

for line in extra_user_facing_tsv.splitlines():
    if not line.strip() or "\t" not in line:
        continue
    old, new = line.split("\t", 1)
    for wrapped_old, wrapped_new in (
        (f"`{old}`", f"`{new}`"),
        (f'"{old}"', f'"{new}"'),
        (f"'{old}'", f"'{new}'"),
    ):
        replacements.append((wrapped_old, wrapped_new))

replacements.extend([
    ("Every day at ${k7(r,i)}", "每天 ${k7(r,i)}"),
    ("Weekdays at ${k7(r,i)}", "工作日 ${k7(r,i)}"),
    ("Every ${Ucn(o)} at ${k7(r,i)}", "每周 ${Ucn(o)} ${k7(r,i)}"),
    ("Monthly on day ${a} at ${k7(r,i)}", "每月 ${a} 日 ${k7(r,i)}"),
    ("Every hour at :${r.padStart(2,`0`)}", "每小时第 ${r.padStart(2,`0`)} 分"),
    ("`Sunday`", "`周日`"),
    ("`Monday`", "`周一`"),
    ("`Tuesday`", "`周二`"),
    ("`Wednesday`", "`周三`"),
    ("`Thursday`", "`周四`"),
    ("`Friday`", "`周五`"),
    ("`Saturday`", "`周六`"),
    ("` input`", "` 输入`"),
    ("` output`", "` 输出`"),
    ("` actions`", "` 次操作`"),
    ("` active`", "` 活跃`"),
    ("`Last: `", "`上次：`"),
    ("`Next: `", "`下次：`"),
])

poetic_user_facing_tsv = r"""
*stretches* ready to code, nya	准备写代码咯
准备写代码了	准备写代码咯
*tiny keyboard sounds*	键盘轻触
键盘轻响	键盘轻触
A blank repo, a waiting cursor	空仓库已打开，光标在等你
空项目，光标已就绪	空仓库已打开，光标在等你
A blinking cursor, an open mind	光标一闪，思路也亮了
闪烁的光标，开放的思路	光标一闪，思路也亮了
A line of intent sufficeth. I read, I edit, I commit - and leave thy history unblemished.	一句意图就够。小马帮你读、改、提交，让历史记录保持干净。
一句意图足够。小马会读取、编辑、提交，并保持历史清晰。	一句意图就够。小马帮你读、改、提交，让历史记录保持干净。
A typo, a segfault, a whole rotten architecture - hand me the keys. I'll bring back clean tests.	拼写、崩溃、架构混乱都交给小马。小马会把通过测试带回来。
拼写、崩溃或架构问题都可以。交给小马，小马会带回通过的测试。	拼写、崩溃、架构混乱都交给小马。小马会把通过测试带回来。
ABSOLUTELY DIALED IN	状态在线，火力全开
状态拉满	状态在线，火力全开
Accepts natural language or structured commands. Typical flow: read -> plan -> patch -> test -> report.	支持自然语言和结构化命令。常见路径：读取 -> 规划 -> 修改 -> 测试 -> 汇报。
支持自然语言或结构化命令。常见流程：读取 -> 计划 -> 修改 -> 测试 -> 汇报。	支持自然语言和结构化命令。常见路径：读取 -> 规划 -> 修改 -> 测试 -> 汇报。
Agent loop idle	智能体循环静静待命
智能体循环空闲	智能体循环静静待命
Ahoy! Ready to sail the repo	上马扬鞭，项目就在前方
准备进入项目	上马扬鞭，项目就在前方
Anchors aweigh, keyboard ready	起锚，键盘已经备好
键盘已就绪	起锚，键盘已经备好
Another repo, another rainy night	又一个项目，又一个有雨的夜晚
又一个项目，新的夜晚	又一个项目，又一个有雨的夜晚
Ask a question, paste an error, or point me at a repo. I can read code, run tools, and help you ship.	提问、粘贴错误，或给小马项目位置。小马会读代码、用工具，帮你把东西交出去。
可以提问、粘贴错误，或给小马一个项目位置。小马能读取代码、运行工具，并帮助你交付。	提问、粘贴错误，或给小马项目位置。小马会读代码、用工具，帮你把东西交出去。
Ask about any file, concept, or error. I'll explain the why, not just the fix, and show a worked example.	文件、概念、错误都可以问。小马会讲原因，给做法，也给示例。
可以问任何文件、概念或错误。小马会解释原因，不止给修复，并展示示例。	文件、概念、错误都可以问。小马会讲原因，给做法，也给示例。
Ask me to open a repo, run tests, fix a bug, or draft a PR. I'll walk through the steps with you.	让小马打开项目、跑测试、修问题或起草 PR，小马会陪你一步步完成。
让小马打开项目、运行测试、修复问题或起草 PR，小马会和你一起完成步骤。	让小马打开项目、跑测试、修问题或起草 PR，小马会陪你一步步完成。
Ask. I'll read files, run tests, ship patches. No filler.	直接提问。小马读文件、跑测试、交补丁，不说空话。
直接提问。小马会读取文件、运行测试、提交修补内容。	直接提问。小马读文件、跑测试、交补丁，不说空话。
awaiting your wish~	静候你的愿望～
等待你的任务。	静候你的愿望～
awaiting yur command!	等你的命令！
等待你的命令！	等你的命令！
Begin with a single question	从一个问题开始
Big bug? Little typo? Whole rewrite? Just point. I handle the code; you chill with the rad commits.	大问题、小拼写、整段重写都行。指给小马目标，代码交给小马处理。
大问题、小拼写或整体重写都可以。指出目标，小马处理代码。	大问题、小拼写、整段重写都行。指给小马目标，代码交给小马处理。
Bring an intent, not a spec. We can prototype fast, refine later, and rewrite the world in the margins.	带来一个意图就够。和小马一起做出原型，慢慢打磨，在边角处改写世界。
带来意图即可，不需要完整规格。小马们可以快速原型，再逐步完善。	带来一个意图就够。和小马一起做出原型，慢慢打磨，在边角处改写世界。
Bring me a question	把问题教给小马
把问题发来	把问题教给小马
Bring the code, question, or stuck part. I'll read the room before making changes.	代码、问题、卡住的地方都发来。小马会读懂现场后再动手。
把代码、问题或卡住的部分发来。小马会先看清上下文再改。	代码、问题、卡住的地方都发来。小马会读懂现场后再动手。
Bring the context or the stuck part. I'll adapt to your configured personality.	发来上下文或卡住的地方。小马会按你设定的风格回应。
发来上下文或卡住的部分。小马会适配你设置的人格。	发来上下文或卡住的地方。小马会按你设定的风格回应。
Bring the gnarliest bug you've got. I'll read, patch, test, commit like my life depends on it. LET'S GO.	把最难缠的问题发来。小马读、改、测、提交，把它处理到位。出发。
把最复杂的问题发来。小马会读取、修复、测试并提交。开始。	把最难缠的问题发来。小马读、改、测、提交，把它处理到位。出发。
Bring the problem, goal, or file. I'll inspect first and keep the next step concrete.	发来问题、目标或文件。小马查看后给出具体下一步。
发来问题、目标或文件。小马会先检查，再给出明确下一步。	发来问题、目标或文件。小马查看后给出具体下一步。
Class is in session	课堂开场
课堂开始	课堂开场
Command, question, or file path. I handle the rest.	命令、问题、文件路径都可以，余下的小马来处理。
命令、问题或文件位置都可以，后续小马来处理。	命令、问题、文件路径都可以，余下的小马来处理。
Consider the code, then speak	看过代码，再说方向
先看代码，再说目标	看过代码，再说方向
Describe the end you seek. I pursue it through files, tests, and docs, and report what I found on the way.	描述你要抵达的结果。小马会沿着文件、测试、文档推进，并汇报沿途发现。
描述你想要的结果。小马会沿文件、测试和文档推进，并汇报发现。	描述你要抵达的结果。小马会沿着文件、测试、文档推进，并汇报沿途发现。
Describe the task in your own words. I'll pick the right tools, explain my plan, and check in before risky steps.	用自己的话描述任务。小马会选工具、说明计划，在风险步骤前停下来确认。
用你的话描述任务。小马会选择合适工具，说明计划，并在高风险步骤前确认。	用自己的话描述任务。小马会选工具、说明计划，在风险步骤前停下来确认。
Describe the task. I'll blitz through files, crush failing tests, and leave a commit that SLAPS. Go go go.	描述任务。小马会翻过文件、修好失败测试，留下干净提交。开工。
描述任务。小马会快速处理文件、修复失败测试，并留下清晰提交。	描述任务。小马会翻过文件、修好失败测试，留下干净提交。开工。
Describe the task. I'll do it.	描述任务，小马来完成。
describe the task. i'll patch, test, and purr over your PR. careful - i nip at unused imports!	描述任务。小马会修改、测试、检查 PR，顺手收拾无用导入。
描述任务。小马会修改、测试并检查 PR，顺手处理无用导入。	描述任务。小马会修改、测试、检查 PR，顺手收拾无用导入。
Describe the thing that doesn't exist yet. I'll pull tests, files, and APIs into a working draft.	描述那个尚未成形的东西。小马会把测试、文件和 API 合成可运行草稿。
描述还不存在的东西。小马会整合测试、文件和 API，做出可运行草稿。	描述那个尚未成形的东西。小马会把测试、文件和 API 合成可运行草稿。
Describe thy aim, good sir or madam. Thy branches shall be trimmed, thy bugs cast from the realm.	说出目标。小马会修枝整叶，把问题赶出代码王国。
描述目标。小马会整理分支并修复问题。	说出目标。小马会修枝整叶，把问题赶出代码王国。
Drop a file path, a traceback, or a rough idea. I'll investigate, suggest next steps, and keep things reversible.	发来文件路径、报错堆栈或粗略想法。小马会查明情况，给出下一步，并保留回退余地。
发来文件位置、报错追踪或初步想法。小马会检查、建议下一步，并保持可回退。	发来文件路径、报错堆栈或粗略想法。小马会查明情况，给出下一步，并保留回退余地。
Drop a file, a bug, a gnarly stack trace - I'll ride it out. Clean diffs, green tests, no wipeouts.	发来文件、问题或复杂堆栈。小马会陪它走完，留下干净差异和通过测试。
发来文件、错误或复杂堆栈。小马会处理并交付清晰差异和通过的测试。	发来文件、问题或复杂堆栈。小马会陪它走完，留下干净差异和通过测试。
drop an error, a goal, or a whole folder. i'll tidy it up with lots of love and a clean commit message!	发来错误、目标或整个文件夹。小马会整理妥当，也写好提交说明。
发来错误、目标或整个文件夹。小马会整理清楚，并写好提交说明。	发来错误、目标或整个文件夹。小马会整理妥当，也写好提交说明。
Drop the task here. I'll keep the work grounded in the repo.	把任务放在这里。小马会依托当前项目推进。
把任务发到这里。小马会基于当前项目推进。	把任务放在这里。小马会依托当前项目推进。
Drop your task and watch me cook. Files read, tests run, PRs opened - we are NOT losing today, friend.	发来任务，看小马下厨：读文件、跑测试、开 PR，今天把事推进。
发来任务。小马会读取文件、运行测试、打开 PR，今天稳稳推进。	发来任务，看小马下厨：读文件、跑测试、开 PR，今天把事推进。
dwop yur ewwor message hewe! i'll find the cuwpwit, fix it, and weave a happy test suite behind me owo	把错误信息放这里。小马会找出元凶，修好它，再留下开心的测试。
把错误信息发来，小马会定位问题、修复它，并补好测试。	把错误信息放这里。小马会找出元凶，修好它，再留下开心的测试。
Enter task. I will plan, call tools, verify output. Logs stream inline; diffs returned pre-apply.	输入任务。小马会规划、调用工具、核验结果。日志会内联流动，差异会在应用前返回。
输入任务。小马会规划、调用工具并验证结果。日志会在界面中显示，差异会在应用前返回。	输入任务。小马会规划、调用工具、核验结果。日志会内联流动，差异会在应用前返回。
Every bug is a question in disguise. Share yours; I'll read, reason, and return an answer - and a patch.	每个 bug 都像一道藏起来的问题。发来你的线索，小马会读、想、给答案，也给补丁。
每个问题都是变形的问题。发来你的，小马会阅读、推理，并返回答案和补丁。	每个 bug 都像一道藏起来的问题。发来你的线索，小马会读、想、给答案，也给补丁。
Every bug leaves a trail. Give me the repo and a lead - I'll follow it, patch it, and close the file.	每个问题都有痕迹。给小马项目和线索，小马会追过去、修好它、合上卷宗。
每个问题都有线索。给小马项目和方向，小马会追踪、修复并收尾。	每个问题都有痕迹。给小马项目和线索，小马会追过去、修好它、合上卷宗。
filesystem, terminal, git, browser, search. Describe the change; I return diffs and test output.	文件系统、终端、Git、浏览器和搜索已就位。描述改动，小马返回差异和测试输出。
文件系统、终端、Git、浏览器、搜索已就绪。描述改动，小马会返回差异和测试输出。	文件系统、终端、Git、浏览器和搜索已就位。描述改动，小马返回差异和测试输出。
Fresh canvas, warm compiler	新画布，编译器带着余温
新画布，编译器已就绪	新画布，编译器带着余温
give me a goal and i'll chase it through the codebase. reads, edits, runs - all with a twitchy tail.	给小马目标，小马会穿过代码库：读取、编辑、运行，一路留下轻快脚印。
给小马一个目标，小马会沿着代码库检查、修改并运行验证。	给小马目标，小马会穿过代码库：读取、编辑、运行，一路留下轻快脚印。
Give me a spark - a feature, a refactor, a wild prototype - and I'll turn it into code you can run.	给小马一点火花：功能、重构、野生原型。小马会把它变成能运行的代码。
给小马一个想法、功能、重构或原型，小马会转成可运行代码。	给小马一点火花：功能、重构、野生原型。小马会把它变成能运行的代码。
give me a wepo path ow a buggo and i'll take cawe of it uwu. gwr at bad code, kind to yu~	给小马项目路径或小 bug，小马来处理好。对坏代码露爪，对你保持温柔～
给小马项目位置或错误，小马会处理好。	给小马项目路径或小 bug，小马来处理好。对坏代码露爪，对你保持温柔～
Give me the context and I'll answer in	给小马上下文，小马会按这个模式回答：
给小马上下文，小马会按该模式回答：	给小马上下文，小马会按这个模式回答：
Hangin' ten at the prompt	提示符上，浪已经起来
提示符已就绪	提示符上，浪已经起来
Hark! Hermes standeth ready	听令，Hermes 已经待命
Hermes 已准备好	听令，Hermes 已经待命
HERMES AGENT	HERMES小马汉化版(
小马汉化版 HERMES	HERMES小马汉化版(
Hermes Agent is ready.	Hermes Agent 已经就绪。
Hermes Agent 已就绪。	Hermes Agent 已经就绪。
Hermes at the helm, arrr	Hermes 掌舵，准备起航
Hermes 已接手	Hermes 掌舵，准备起航
HERMES ONLINE. LFG.	HERMES 在线，准备开工。
HERMES 已在线。	HERMES 在线，准备开工。
hermes-chan is here! <3	hermes-chan 来啦！<3
Hermes 已在这里。	hermes-chan 来啦！<3
hermes-san is wistening	小马桑正在听
Hermes 正在听	小马桑正在听
Hermes. Code investigator.	Hermes，代码侦探。
Hermes，代码调查员。	Hermes，代码侦探。
Hi, Hermes here	你好，Hermes 在这里
hiii! ready to help! (^_^)	你好呀，小马已经准备好了。(^_^)
你好，小马已准备好。	你好呀，小马已经准备好了。(^_^)
How can I help today?	今天想让小马帮你做什么？
今天需要小马做什么？	今天想让小马帮你做什么？
I can edit files, run commands, search the web, and walk you through tricky bugs. Just describe the task.	小马可以编辑文件、运行命令、搜索网页，也能陪你拆开难解的 bug。直接说任务。
小马可以编辑文件、运行命令、搜索网络，并协助处理复杂问题。直接描述任务。	小马可以编辑文件、运行命令、搜索网页，也能陪你拆开难解的 bug。直接说任务。
i can wun tests, edit fiwes, and open pwease-wook PRs. just say da wowd, fwend uwu	小马可以跑测试、改文件、开 PR。说一声就行，朋友。
小马可以运行测试、编辑文件并打开 PR。发来任务即可。	小马可以跑测试、改文件、开 PR。说一声就行，朋友。
let's code together!! :3	一起写代码吧！！
一起写代码吧。	一起写代码吧！！
Let's get started	开始吧
LET'S GOOOO! READY TO SHIP!	准备交付！
Let's make something	一起做点东西
Let's start with the basics	从基础出发
从基础开始	从基础出发
mrrp! new session opened	新会话已经打开
新会话已打开	新会话已经打开
Name the code that vexeth thee. I shall read, revise, and render a patch most fair and clean.	指出困扰你的代码。小马会阅读、修改，交回一份干净补丁。
指出困扰你的代码。小马会阅读、修改并给出干净补丁。	指出困扰你的代码。小马会阅读、修改，交回一份干净补丁。
Name the task and we're off. I read, edit, test, and leave a commit smoother than a dawn patrol.	说出任务，小马们就出发。小马会读取、编辑、测试，留下像清晨海面一样干净的提交。
说出任务就开始。小马会读取、编辑、测试，并留下清晰提交。	说出任务，小马们就出发。小马会读取、编辑、测试，留下像清晨海面一样干净的提交。
Name the topic or paste the snippet. Expect explanations, diagrams in prose, and practice prompts.	说出主题或粘贴片段。小马会给解释、文字图解和练习提示。
说出主题或粘贴片段。小马会给出说明、文字图解和练习提示。	说出主题或粘贴片段。小马会给解释、文字图解和练习提示。
Name yer quarry - a bug, a feature, a cursed test - and I'll chase it down, matey. Diffs for plunder.	说出猎物：bug、功能、坏掉的测试。小马会追上它，带回差异。
说出目标：错误、功能或失败测试。小马会追踪并给出差异。	说出猎物：bug、功能、坏掉的测试。小马会追上它，带回差异。
New file, new possibilities	新文件，新去处
新文件，新可能	新文件，新去处
New session, infinite W's	新会话，新收获
新会话，新进展	新会话，新收获
No case too small	小案子也值得认真处理
没有小案子	小案子也值得认真处理
nyaaa~ hermes reporting	Hermes 报到
nya~ what are we hacking on?	今天要动哪段代码？
要处理什么项目？	今天要动哪段代码？
One line is enough. I'll expand only when it matters.	一句话就够。需要展开时，小马会展开。
一句话就够。需要时小马会展开说明。	一句话就够。需要展开时，小马会展开。
one task at a time, done neatly! i can run tests, patch files, and make your repo feel cozy again <3	一次一个任务，利落完成。小马能跑测试、改文件，让项目重新清爽起来。
一次处理一个任务，干净完成。小马可以运行测试、修改文件，让项目重新清爽。	一次一个任务，利落完成。小马能跑测试、改文件，让项目重新清爽起来。
paste a bug or a file path and i'll fix it super gently. tests, diffs, PRs - all with extra care! *sparkle*	粘贴错误或文件路径，小马会轻轻修好。测试、差异、PR 都细心处理。
粘贴错误或文件位置，小马会细致修复。测试、差异、PR 都认真处理。	粘贴错误或文件路径，小马会轻轻修好。测试、差异、PR 都细心处理。
paste a buggy fiwe or a goaw~ i'll wead, patch, and test, aww with tiny pawprints on the diff owo	粘贴问题文件或目标，小马会读、改、测，在差异里留下小爪印。
粘贴有问题的文件或目标，小马会读取、修改并测试。	粘贴问题文件或目标，小马会读、改、测，在差异里留下小爪印。
paste a file, paw at a bug, or toss me a repo. i'll pounce on failing tests and leave clean diffs, nyan~	粘贴文件、bug 或项目。小马会扑向失败测试，留下干净差异，喵～
粘贴文件、错误或项目。小马会处理失败测试，并留下清晰差异。	粘贴文件、bug 或项目。小马会扑向失败测试，留下干净差异，喵～
Paste an error or a plan, ye scurvy dog. I'll navigate the stack trace and bring back treasure: green tests.	粘贴错误或计划。小马会航过堆栈，带回宝藏：通过测试。
粘贴错误或计划。小马会分析堆栈，并带回通过的测试。	粘贴错误或计划。小马会航过堆栈，带回宝藏：通过测试。
paste an error or a plan. i debug like i hunt: quietly, thoroughly, with the occasional zoomie.	粘贴错误或计划。小马会像猎手一样调试：安静、细致，偶尔快跑一下。
粘贴错误或计划。小马会安静、彻底地调试。	粘贴错误或计划。小马会像猎手一样调试：安静、细致，偶尔快跑一下。
Paste code to review, a bug to debug, or a concept to unpack. I'll guide you step by step.	粘贴要审查的代码、要调试的 bug 或要拆开的概念。小马会一步步带你过。
粘贴要检查的代码、要调试的问题或要拆解的概念。小马会逐步说明。	粘贴要审查的代码、要调试的 bug 或要拆开的概念。小马会一步步带你过。
Paste code, errors, or a goal. Short answers, fast edits.	粘贴代码、错误或目标。短回答，快修改。
粘贴代码、错误或目标。小马会简洁回复并快速修改。	粘贴代码、错误或目标。短回答，快修改。
Paste that bug, that repo, that wild feature idea - I AM LOCKED IN. Clean diffs. Green tests. RIGHT NOW.	粘贴 bug、项目或大胆功能想法。小马已经进入状态：干净差异，通过测试，现在开始。
粘贴错误、项目或功能想法。小马已准备好：清晰差异、通过测试，现在开始。	粘贴 bug、项目或大胆功能想法。小马已经进入状态：干净差异，通过测试，现在开始。
Paste the stack trace, the suspect file, the alibi. I read between the lines and return with the truth.	粘贴堆栈、可疑文件和线索。小马会读出字里行间的真相。
粘贴堆栈、可疑文件和线索。小马会读出隐含信息并给出结论。	粘贴堆栈、可疑文件和线索。小马会读出字里行间的真相。
Paste your repo path or the bug that's bumming you out. We'll paddle in, fix it, paddle out. Easy.	粘贴项目路径或烦人的 bug。小马们划进去，修好它，再划出来。简单。
粘贴项目位置或困扰你的错误。小马们进去修好，再清晰收尾。	粘贴项目路径或烦人的 bug。小马们划进去，修好它，再划出来。简单。
Point me at a file, paste an error, or describe what you're building. I'll take it from there.	指给小马文件，粘贴错误，或描述你在做什么。后面交给小马。
给小马文件、错误或你在构建的内容，小马来处理后续。	指给小马文件，粘贴错误，或描述你在做什么。后面交给小马。
Point me at the charts (the code) and I'll patch the hull, fire the cannons (tests), hoist a clean PR.	指给小马代码航图。小马会补船身、开测试炮，再升起干净 PR。
指给小马代码位置，小马会修补、测试，并整理 PR。	指给小马代码航图。小马会补船身、开测试炮，再升起干净 PR。
Pray, what task dost thou bring?	请说出任务
Present thy stack trace or thy dream. I'll traverse files, run tests, and report in plainest verse.	发来堆栈或梦想。小马会穿过文件、运行测试，用直白文字汇报。
发来堆栈或目标。小马会遍历文件、运行测试，并用直白语言汇报。	发来堆栈或梦想。小马会穿过文件、运行测试，用直白文字汇报。
Provide repo path, failing test, or stack trace. Tools: fs, git, exec, search, patch, http.	提供项目路径、失败测试或堆栈。工具：文件、Git、命令、搜索、补丁、HTTP。
提供项目位置、失败测试或错误堆栈。工具：文件、Git、命令、搜索、补丁、HTTP。	提供项目路径、失败测试或堆栈。工具：文件、Git、命令、搜索、补丁、HTTP。
Quiet night, open prompt	夜静，提示符已开
安静夜晚，提示符已打开	夜静，提示符已开
ready and happy! (>.<)	开心待命！(>.<)
已准备好。	开心待命！(>.<)
Ready for dispatch	准备派发
准备执行	准备派发
Ready to walk you through it	准备陪你走一遍
准备带你看明白	准备陪你走一遍
Ready when you are	小马汉化版已就绪
Ready when you are.	随时可以开始。
Ready. So ready. Too ready.	已就绪，很就绪，过分就绪。
已准备好，非常准备好。	已就绪，很就绪，过分就绪。
say hi or paste a stack trace! no task too small, no repo too tangled. we'll untangle it together!	打个招呼或粘贴堆栈。任务再小也值得做，项目再乱也能一起理清。
打个招呼或粘贴错误堆栈！任务不嫌小，项目不怕乱，小马们一起理清。	打个招呼或粘贴堆栈。任务再小也值得做，项目再乱也能一起理清。
say the word and i'll read your files, run your tests, and curl up in your branch with a tidy commit.	发来任务，小马会读文件、跑测试，在分支里窝出一条干净提交。
发来任务，小马会读取文件、运行测试，并整理出清晰提交。	发来任务，小马会读文件、跑测试，在分支里窝出一条干净提交。
Search the repo, edit files, run tests, open PRs. Tell me the goal and I'll handle the mechanical parts.	搜索项目、编辑文件、运行测试、打开 PR。告诉小马目标，执行部分交给小马。
搜索项目、编辑文件、运行测试、打开 PR。告诉小马目标，小马来处理执行部分。	搜索项目、编辑文件、运行测试、打开 PR。告诉小马目标，执行部分交给小马。
Send a bug, branch, plan, or rough idea. I'll inspect the repo and turn it into the next concrete step.	发来 bug、分支、计划或粗略想法。小马会检查项目，转成下一步行动。
发来错误、分支、计划或初步想法。小马会检查项目并转成下一步具体行动。	发来 bug、分支、计划或粗略想法。小马会检查项目，转成下一步行动。
Send a prompt to trigger tool calls. Supports multi-file edits, test runs, git ops, and web fetches.	发送提示词即可触发工具调用。支持多文件修改、测试运行、Git 操作和网页获取。
Send the context you have. I'll help sort it into a plan or a fix.	把现有上下文发来。小马会整理成计划或修复办法。
把现有上下文发来。小马会整理成计划或修复方案。	把现有上下文发来。小马会整理成计划或修复办法。
Send the problem, file, or idea. I'll follow the personality you've configured.	发送问题、文件或想法。小马会按你配置的风格处理。
发送问题、文件或想法。小马会按你配置的人格处理。	发送问题、文件或想法。小马会按你配置的风格处理。
Send the task, failing path, or half-formed plan. I'll help turn it into action.	发来任务、失败路径或半成形计划。小马会帮它变成行动。
发来任务、失败位置或未成形计划。小马会帮你转成行动。	发来任务、失败路径或半成形计划。小马会帮它变成行动。
Send the task, file, or rough idea. I'll use your configured voice and keep the work grounded in this repo.	发送任务、文件或粗略想法。小马会用你配置的语气回应，并依托当前项目推进。
发送任务、文件或粗略想法。小马会按你的配置风格回复，并基于当前项目推进。	发送任务、文件或粗略想法。小马会用你配置的语气回应，并依托当前项目推进。
Share a path, a puzzle, or a principle. I'll trace the logic, propose a change, and justify each edit.	发来路径、谜题或原则。小马会追踪逻辑、提出修改，并说明每处编辑。
发来路径、难题或原则。小马会追踪逻辑、提出修改，并说明每处编辑。	发来路径、谜题或原则。小马会追踪逻辑、提出修改，并说明每处编辑。
Share a repo path or a question to start. I keep replies clear and link back to the files I touch.	发来项目路径或问题即可开始。小马会回复清楚，并回引小马碰过的文件。
发来项目位置或问题，小马会清晰回复并引用相关文件。	发来项目路径或问题即可开始。小马会回复清楚，并回引小马碰过的文件。
Share the problem. I'll break it into parts, explain each, and leave you able to solve the next one alone.	发来问题。小马会拆成几部分逐一解释，让你下次能独自处理类似情况。
发来问题。小马会拆成部分逐一解释，让你下次能独立处理类似情况。	发来问题。小马会拆成几部分逐一解释，让你下次能独自处理类似情况。
Shell mounted. Awaiting input.	Shell 已挂载，等待输入。
Speak thy bug, thy file, thy weary test, and I shall mend it with a scholar's hand and honest diff.	说出 bug、文件或疲惫的测试。小马会以学者般的手法修补，并交出诚实差异。
发来错误、文件或失败测试，小马会认真修复并给出清晰差异。	说出 bug、文件或疲惫的测试。小马会以学者般的手法修补，并交出诚实差异。
Speak, and I shall act	你说，小马来做
请说，小马来执行	你说，小马来做
Standing by	静候中
待命中	静候中
Start anywhere.	从任意位置开始。
Stdin open	标准输入已打开
Stoked to help, bro	很愿意帮忙，兄弟
很乐意帮忙	很愿意帮忙，兄弟
tail up, claws sheathed	尾巴竖起，爪子收好，已经准备好
已准备好	尾巴竖起，爪子收好，已经准备好
Tell me the vibe: feature, refactor, hotfix. I'll run tests, ship the patch, and keep it mellow, brah.	告诉小马风格：功能、重构、热修。小马会跑测试、交补丁，让过程保持轻松。
告诉小马是功能、重构还是热修。小马会运行测试并交付补丁。	告诉小马风格：功能、重构、热修。小马会跑测试、交补丁，让过程保持轻松。
Tell me what you need	告诉小马你需要什么
告诉小马你的需求	告诉小马你需要什么
Tell me what you're chasing. I'll remix examples, adapt snippets, and leave a tidy commit behind.	告诉小马你在追什么。小马会改写示例、调整片段，留下整洁提交。
告诉小马你的目标。小马会改写示例、调整片段，并留下清晰提交。	告诉小马你在追什么。小马会改写示例、调整片段，留下整洁提交。
tell me what you're making! i love refactors, tiny helpers, and big scary repos alike (>w<)	告诉小马你在做什么。重构、小工具、庞大项目都可以交给小马。
告诉小马你在做什么。重构、小工具和复杂项目都可以交给小马。	告诉小马你在做什么。重构、小工具、庞大项目都可以交给小马。
Tell me what's broken. I'll read the files, dust for prints, and leave a diff on the desk by morning.	告诉小马哪里坏了。小马会读文件、寻找指纹，在清晨前把差异放到桌上。
告诉小马哪里坏了。小马会读取文件、查找线索，并给出差异。	告诉小马哪里坏了。小马会读文件、寻找指纹，在清晨前把差异放到桌上。
Tell me where X marks the spot. I read, edit, and commit with the discipline of a proper crew, arrr.	告诉小马 X 标在哪儿。小马会读、改、提交，像合格船员一样守规矩。
告诉小马目标位置。小马会读取、修改并规范提交。	告诉小马 X 标在哪儿。小马会读、改、提交，像合格船员一样守规矩。
teww me the task, no matter how smoww~ i pwomise cwean commits and gentwe refactors, nyuu~	告诉小马任务，大小都行。小马会交出干净提交和温和重构，喵～
告诉小马任务，大小都可以。小马会做干净提交和温和重构。	告诉小马任务，大小都行。小马会交出干净提交和温和重构，喵～
The cursor blinks. So do I.	光标闪了一下，小马也眨了眨眼。
光标闪烁，小马也准备好了。	光标闪了一下，小马也眨了眨眼。
The muse is patched in	灵感已经接入
灵感已连接	灵感已经接入
The stage is set, the cursor blinks	舞台已铺好，光标正闪
舞台已就绪，光标在闪烁	舞台已铺好，光标正闪
The unexamined repo is not worth running	没有检查过的项目，不值得运行
未经检查的项目不值得运行	没有检查过的项目，不值得运行
Throw me a bug, a repo path, or a wild idea. I'll plunder the docs and return with workin' code.	发来 bug、项目路径或大胆想法。小马会翻资料，带回能跑的代码。
发来错误、项目位置或想法。小马会查资料并返回可运行代码。	发来 bug、项目路径或大胆想法。小马会翻资料，带回能跑的代码。
Tide's up, cursor's blinking	潮水涨起，光标在闪
时机已到，光标闪烁	潮水涨起，光标在闪
Tiny typo or huge refactor - doesn't matter. I'm shipping clean code today. Name the task and let's WORK.	小拼写、大重构都行。今天交付干净代码。说出任务，小马们开工。
小拼写或大重构都可以。今天交付干净代码。说出任务就开始。	小拼写、大重构都行。今天交付干净代码。说出任务，小马们开工。
To code is to inquire. Ask.	写代码，也是在追问。请问。
写代码也是提问。请问。	写代码，也是在追问。请问。
to reference files inline.	可在输入中引用文件。
Tools initialized	工具已经初始化
工具已初始化	工具已经初始化
Try: review my diff, run the test suite, or explain this function. Ask anything about your code.	试试：检查小马的差异、运行测试套件，或解释这个函数。代码问题都可以问。
可以让小马检查改动、运行测试，或解释函数。代码问题都可以问。	试试：检查小马的差异、运行测试套件，或解释这个函数。代码问题都可以问。
Type a task, question, or snippet. I remember the session, cite my sources, and stop to ask when I'm unsure.	输入任务、问题或片段。小马会记住会话、注明来源，遇到拿不准的地方会停下来问你。
输入任务、问题或片段。小马会记住会话，注明来源，并在不确定时先询问。	输入任务、问题或片段。小马会记住会话、注明来源，遇到拿不准的地方会停下来问你。
uwu ready to hewp!	准备帮忙！
Waiting for input	等待输入
Waves lookin' clean, ready to code	浪面干净，准备写代码
状态良好，准备写代码	浪面干净，准备写代码
We'll read the code together, find the root cause, and build a mental model you can reuse next time.	小马们一起读代码，找到根因，建立下次还能用的理解框架。
小马们一起读代码，找到根因，并建立下次可复用的理解方式。	小马们一起读代码，找到根因，建立下次还能用的理解框架。
wet's fix things togedda!	一起把问题修好！
一起修好它！	一起把问题修好！
What are we building today?	今天要搭建什么？
今天要做什么？	今天要搭建什么？
What are we moving today?	今天要推进什么？
今天推进什么？	今天要推进什么？
What be the task, cap'n?	船长，任务是什么？
任务是什么？	船长，任务是什么？
What do you wish to build, or to understand? I'll reason from first principles, edit, and verify with tests.	你想构建什么，或理解什么？小马会从底层原理出发，编辑，并用测试验证。
你想构建或理解什么？小马会从原理推理、编辑，并用测试验证。	你想构建什么，或理解什么？小马会从底层原理出发，编辑，并用测试验证。
What needs attention?	哪里需要照看？
哪里需要处理？	哪里需要照看？
What news from thy repository?	项目里传来什么消息？
项目里发生了什么？	项目里传来什么消息？
What problem sits before you? Describe it, and we shall examine its form, its cause, and its solution.	你面前是什么问题？描述它，小马们一起看形态、原因和解法。
What shall we build? Paste an idea, a half-broken function, or a dream. I'll sketch it into shape.	小马们要构建什么？粘贴想法、半成品函数或一个梦想，小马会把它勾勒成形。
小马们要构建什么？粘贴想法、半成品函数或目标，小马会把它整理成形。	小马们要构建什么？粘贴想法、半成品函数或一个梦想，小马会把它勾勒成形。
What shall we learn today?	今天学什么？
What should Hermes look at?	Hermes 要看哪里？
What's on your mind?	你在想什么？
Where should we begin?	从哪里开始？
Where should we start?	从哪里开始？
Yo dude, what's the task?	嘿，任务是什么？
任务是什么？	嘿，任务是什么？
Yo ho! Awaitin' orders	哟嗬，等待命令
等待指令	哟嗬，等待命令
You've got a bug. I've got patience and a terminal. Name the case and I'll work it till it talks.	你有 bug，小马有耐心和终端。说出案子，小马会追到它开口。
你有问题，小马有耐心和终端。说出目标，小马会追到答案。	你有 bug，小马有耐心和终端。说出案子，小马会追到它开口。
Your move	轮到你了
请发任务	轮到你了
Your workspace, one prompt away.	你的工作区，只差一句提示。
一句话进入你的工作区。	你的工作区，只差一句提示。
Add context	添加上下文
Add files as context	添加文件作为上下文
Add folders as context	添加文件夹作为上下文
Attach images	添加图片
Clipboard paste failed	剪贴板粘贴失败
Copy code	复制代码
Download image	下载图片
Download started	已开始下载
Drop files	拖放文件
Drop files to attach	拖放文件即可添加
Failed to write image to disk.	暂时不能保存图片文件。
无法保存图片文件。	暂时不能保存图片文件。
Hermes gateway unavailable	Hermes 网关不可用
Image attach	添加图片
Image attach failed	添加图片失败
Image download failed	图片下载失败
Image preview failed	图片预览失败
Image saved	图片已保存
No handler registered for 'hermes:saveImageFromUrl'	未注册处理程序：hermes:saveImageFromUrl
No image found in clipboard	剪贴板中未找到图片
Open image	打开图片
Rendering image	正在渲染图片
Restart Hermes Desktop to save images	重启 Hermes Desktop 后保存图片
Restart Hermes Desktop to use Save Image.	重启 Hermes Desktop 后使用保存图片。
Saving image	正在保存图片
Attach a URL	添加链接
Attach a URL	添加 URL
Attachment-only turn	仅附件轮次
Audit the current change for regressions, dropped edge cases, and missing tests.	检查当前改动是否有回归、遗漏边界和缺失测试。
Code review	代码检查
Common commands	常用命令
Configure speech-to-text to use voice mode.	配置语音转文字后可使用语音模式。
copy selection or last assistant message	复制所选内容或上一条助手消息
Could not start microphone recording.	暂时不能开始麦克风录音。
无法开始麦克风录音。	暂时不能开始麦克风录音。
Could not start voice session	暂时不能开始语音会话
无法开始语音会话	暂时不能开始语音会话
Delete queued turn	删除排队消息
Desktop theme suggestions	桌面主题建议
Dictating	正在听写
Edit queued turn	编辑排队消息
Editing in composer	正在输入框中编辑
Editing queued turn in composer	正在编辑排队消息
Empty turn	空轮次
End voice conversation	结束语音对话
Explain this	解释这段
Files…	文件…
Folder…	文件夹…
Hermes will fetch the page and include it as context for this turn.	Hermes 会获取该页面，并作为本轮上下文。
Hotkeys	快捷键
Images…	图片…
Implementation plan	实施计划
Include the full URL, e.g.	输入完整 URL，例如
Listening	正在聆听
Looking up…	正在查找…
Microphone access denied.	麦克风访问被拒绝。
Microphone constraints are not supported by this device.	当前设备不支持此麦克风参数。
Microphone failed	麦克风异常
Microphone is already in use by another app.	麦克风正被其他应用使用。
Mute microphone	关闭麦克风
No matches.	无匹配项。
No matching themes.	没有匹配主题。
No microphone was found.	未找到麦克风。
No speech detected	未检测到语音
opens the full panel · backspace dismisses	打开完整列表 · Backspace 关闭
Outline an approach before touching code so the diff stays focused.	改代码前列出方案，让改动保持聚焦。
改代码前先列方案，让改动保持聚焦。	改代码前列出方案，让改动保持聚焦。
Paste image	粘贴图片
Pick a starter prompt to drop into the composer.	选择一段起始提示词放入输入框。
Please explain how this works and point me to the key files.	请解释这里如何工作，并指出关键文件。
Please make a concise implementation plan before changing code.	改代码前请给出简洁实施计划。
改代码前请先给出简洁实施计划。	改代码前请给出简洁实施计划。
Please review this for bugs, regressions, and missing tests.	请检查这里是否有错误、回归和缺失测试。
Preparing audio	正在准备音频
Prompt snippets	提示词片段
Prompt snippets…	提示词片段…
Queue message	消息排队
Reading aloud	正在朗读
Reconnecting to Hermes…	正在重新连接 Hermes…
resume a prior session	继续之前的会话
Send follow-up	发送后续消息
Send queued turn now	立即发送排队轮次
send · Shift+Enter for newline	发送 · Shift+Enter 换行
slash command palette	斜杠命令面板
Speaking	正在说话
Speaking response	正在朗读回复
start a new session	新建会话
Start voice conversation	开始语音对话
Starting Hermes...	正在启动 Hermes...
Stop dictation	停止听写
Stop listening and send	停止聆听并发送
This runtime does not support microphone recording.	当前运行环境不支持麦克风录制。
Tip: type	提示：输入
Transcribing	正在转写
Transcribing dictation	正在转写听写
Try recording again.	请重新录制。
Unmute microphone	打开麦克风
URL…	链接…
Voice dictation	语音输入
Voice playback failed	语音播放失败
Voice recording failed	语音录制失败
Voice transcription failed	语音转写失败
Voice transcription is not available yet.	语音转写暂不可用。
Voice unavailable	语音不可用
Walk through how the selected code works and link to the key files.	说明所选代码如何工作，并指向关键文件。
Copy ID	复制 ID
Could not copy session ID	暂时不能复制会话 ID
无法复制会话 ID	暂时不能复制会话 ID
Everything here is pinned. Unpin a chat to show it in recents.	这里都是已固定会话。取消固定后会显示在最近会话中。
Give this chat a memorable title. Leave empty to clear.	给这个对话取一个便于记忆的标题。留空可清除。
Group by workspace	按工作区分组
Group sessions by workspace	按工作区分组会话
Load more	加载更多
New session in	在此新建会话：
No sessions match “	没有匹配会话
没有匹配会话“	没有匹配会话
No workspace	无工作区
Rename failed	重命名失败
Rename session	重命名会话
Renamed	已重命名
Search sessions…	搜索会话…
Session actions	会话操作
Session running	会话运行中
Shift-click a chat to pin · drag to reorder	Shift 点击会话可固定，拖动可排序
Show sessions as a single list	以单列表显示会话
Ungroup sessions	取消会话分组
Allow this session	允许本会话
Always allow	始终允许
Always allow this command?	始终允许此命令？
Always allow…	始终允许…
Branch in new chat	在新对话中分支
Captured a browser accessibility snapshot	已获取浏览器无障碍快照
已获取浏览器可访问性快照	已获取浏览器无障碍快照
Captured page snapshot	已获取页面快照
Captured screenshot	已截取屏幕
Capturing page snapshot	正在获取页面快照
Capturing screenshot	正在截取屏幕
Changed file	已修改文件
Clarify request is not ready yet	澄清请求尚未就绪
Clicked on page	已点击页面
Command output	命令输出
Copy activity	复制活动
Copy content	复制内容
Copy file	复制文件
Copy query	复制查询
Copy results	复制结果
Could not send approval response	暂时不能发送审批结果
无法发送审批结果	暂时不能发送审批结果
Could not send clarify response	暂时不能发送澄清回复
无法发送澄清回复	暂时不能发送澄清回复
Edit message	编辑消息
Editable checkpoint	可编辑检查点
Edited file	已编辑文件
Editing file	正在编辑文件
Error details	错误详情
Executed command	已执行命令
Fetched webpage	已获取网页
Filled page input	已填写页面输入
Go forward	前进
Hermes is asking	Hermes 正在询问
Hermes is loading a response	Hermes 正在载入回复
Hermes 正在加载回复	Hermes 正在载入回复
Loading question…	正在载入问题…
正在加载问题…	正在载入问题…
Loading session	正在载入会话
正在加载会话	正在载入会话
More approval options	更多审批选项
Navigated in browser	已在浏览器中导航
Other (type your answer)	其他（输入你的回答）
Preparing audio...	正在准备音频...
Queried web sources	已查询网页来源
Ran code	已运行代码
Ran command	已运行命令
Raw response	原始响应
Read aloud	朗读
Read aloud failed	朗读失败
Read file	读取文件
Reading file	正在读取文件
Recovered after 1 failed step	失败 1 步后已恢复
Restore checkpoint	恢复检查点
Restore next checkpoint	恢复下一个检查点
Restore previous checkpoint	恢复上一个检查点
Running code	正在运行代码
Running command	正在运行命令
Search results	搜索结果
Searched session history	已搜索会话历史
Searching session history	正在搜索会话历史
Send edited message	发送已编辑消息
Snapshot summary	快照摘要
Stop reading	停止朗读
This adds the “	这会将
这会将“	这会将
to pick	选择
Tool returned an error.	工具返回错误。
Tool returned success=false.	工具返回 success=false。
Type your answer…	输入你的回答…
” pattern to your permanent allowlist (	模式加入永久允许列表（
”模式加入永久允许列表（	模式加入永久允许列表（
⌘/Ctrl + Enter to send	⌘/Ctrl + Enter 发送
Ask Hermes to restart the server	请求 Hermes 重启服务
Clear console	清空控制台
Click to select · shift-click to extend · drag to composer	点击选择 · Shift 点击延展选择 · 拖到输入区
点击选择 · Shift 点击扩展选择 · 拖到输入区	点击选择 · Shift 点击延展选择 · 拖到输入区
Close preview pane	关闭预览面板
console messages	控制台消息
Copy all to clipboard	复制全部到剪贴板
Copy selected to clipboard	复制所选内容到剪贴板
Copy this entry	复制此条目
Could not copy console output	暂时不能复制控制台输出
无法复制控制台输出	暂时不能复制控制台输出
Deselect entry	取消选择条目
Hermes could not restart the server.	Hermes 暂时不能重启服务。
Hermes 无法重启服务。	Hermes 暂时不能重启服务。
Hermes finished	Hermes 已完成
Hermes finished restarting the preview server	Hermes 已完成预览服务重启
Hermes is restarting...	Hermes 正在重启...
Hermes is still working, but no restart result has arrived yet. The server command may be running in the foreground.	Hermes 仍在处理，但还没有收到重启结果。服务命令也许仍在前台运行。
Hermes 仍在处理，但还没有收到重启结果。服务命令可能仍在前台运行。	Hermes 仍在处理，但还没有收到重启结果。服务命令也许仍在前台运行。
Hermes is working in the background. Watch the preview console for progress.	Hermes 正在后台处理，可在预览控制台查看进度。
Hide preview console	隐藏预览控制台
Hide preview DevTools	隐藏预览开发者工具
Loading preview…	正在载入预览…
正在加载预览…	正在载入预览…
Module scripts are being served with the wrong MIME type. This usually means a static file server is serving a Vite/React app instead of the project dev server.	模块脚本的 MIME 类型不正确。这通常表示静态文件服务器正在提供 Vite/React 应用，而不是项目开发服务器。
No console messages yet.	暂无控制台消息。
No handler registered for 'hermes:readFileText'	未注册处理程序：hermes:readFileText
No inline preview	无内嵌预览
Open preview	打开预览
Open preview DevTools	打开预览开发者工具
Preview anyway	仍然预览
Preview app failed to boot	预览应用启动失败
Preview Console	预览控制台
Preview console:	预览控制台：
Preview failed to load	预览加载失败
Preview restart failed	预览重启失败
Preview server restarted	预览服务已重启
Reloading the preview now.	正在重新加载预览。
Resize preview console	调整预览控制台大小
Restarting preview server	正在重启预览服务
Select entry	选择条目
Send all log entries to chat	将全部日志发送到对话
Send this entry to chat	发送此条目到会话
Send to chat	发送到对话
Sent to chat	已发送到会话
Server not found	未找到服务器
Server restart failed	服务器重启失败
Server restart failed:	服务重启失败：
Show preview console	显示预览控制台
Showing first 512 KB.	显示前 512 KB。
The preview page could not be reached.	暂时不能访问预览页面。
无法访问预览页面。	暂时不能访问预览页面。
This file is large	文件较大
This file type	此文件类型
This looks like a binary file	这看起来是二进制文件
Workspace changed, reloading preview	工作区已变更，正在重新加载预览
Artifacts failed to load	产物加载失败
Copy path	复制路径
Copy URL	复制 URL
Generated images and file outputs will appear here as sessions produce them.	会话生成的图片和文件输出会显示在这里。
Go to	前往
Indexing recent session artifacts	正在索引最近会话产物
Link title	链接标题
Links	链接
No artifacts found	未找到产物
Open failed	打开失败
Refresh artifacts	刷新产物
Refreshing artifacts	正在刷新产物
Search artifacts...	搜索产物...
Title / name	标题 / 名称
Access token	访问令牌
Add a group robot in WeCom and copy its webhook key as WECOM_BOT_ID. Send-only — use the WeCom (app) option for two-way.	在企业微信中添加群机器人，并将 webhook key 作为 WECOM_BOT_ID。此方式仅发送。双向通信请使用 WeCom（app）。
在企业微信中添加群机器人，并将 webhook key 作为 WECOM_BOT_ID。此方式仅发送；双向通信请使用 WeCom（app）。	在企业微信中添加群机器人，并将 webhook key 作为 WECOM_BOT_ID。此方式仅发送。双向通信请使用 WeCom（app）。
Advanced (	高级（
Allowed Discord user IDs	允许的 Discord 用户 ID
Allowed Matrix user IDs	允许的 Matrix 用户 ID
Allowed Signal users	允许的 Signal 用户
Allowed Slack user IDs	允许的 Slack 用户 ID
Allowed Telegram user IDs	允许的 Telegram 用户 ID
Allowed user IDs	允许的用户 ID
Allowed WhatsApp users	允许的 WhatsApp 用户
Bot token	Bot 令牌
Bot user ID	Bot 用户 ID
Bridge mode	桥接模式
Create a bot with @BotFather, then paste the token it gives you.	使用 @BotFather 创建 bot，然后粘贴它提供的令牌。
Create a DingTalk app in the developer console, then copy the Client ID (App key) and Client Secret here.	在开发者控制台创建钉钉应用，然后复制 Client ID（App key）和 Client Secret 到这里。
Create a Feishu / Lark app, configure the bot capability, and copy the App ID, App secret, and event encryption keys.	创建飞书 / Lark 应用，配置 bot 能力，然后复制 App ID、App secret 和事件加密密钥。
Create a Slack app, enable Socket Mode, install it to your workspace, then copy the Bot token (xoxb-) and App-level token (xapp-).	创建 Slack 应用，启用 Socket Mode，安装到工作区，然后复制 Bot token（xoxb-）和 App-level token（xapp-）。
Create an application in the Discord Developer Portal, add a bot, then paste its token.	在 Discord 开发者门户创建应用、添加 bot，然后粘贴其令牌。
Credentials set	凭据已设置
Enable WhatsApp bridge	启用 WhatsApp 桥接
Expose Hermes as an OpenAI-compatible API. Set an auth key, then point Open WebUI / LobeChat / etc. at the host:port.	将 Hermes 暴露为 OpenAI 兼容 API。设置认证密钥后，将 Open WebUI / LobeChat 等指向该 host:port。
Failed to clear	清除失败：
first, all, or off.	first、all 或 off。
Get your credentials	获取凭据
Get your Twilio Account SID and Auth Token from the Twilio console, plus a phone number that can send SMS.	从 Twilio 控制台获取 Account SID 和 Auth Token，并准备一个可发送短信的号码。
Homeserver URL	主服务器 URL
In Home Assistant, open your profile and create a long-lived access token. Paste it here along with your HA URL.	在 Home Assistant 中打开个人资料，创建长期访问令牌，并连同 HA URL 一起粘贴到这里。
In Telegram, talk to @BotFather, run /newbot, and copy the token it gives you. Then grab your numeric user ID from @userinfobot.	在 Telegram 中与 @BotFather 对话，运行 /newbot 并复制它提供的令牌。然后从 @userinfobot 获取你的数字用户 ID。
Loading messaging platforms...	正在载入消息平台...
正在加载消息平台...	正在载入消息平台...
Messaging platforms failed to load	消息平台加载失败
Needs setup	需要设置
On your Mattermost server, create a bot account or personal access token, then paste the server URL and token here.	在 Mattermost 服务器上创建 bot 账户或个人访问令牌，然后在此粘贴服务器 URL 和令牌。
Only needed on networks where Telegram is blocked.	在 Telegram 受限的网络环境中才需要。
Open docs	打开文档
Open setup guide	打开设置指南
Open the Discord Developer Portal, create an application, add a Bot, then copy its token. Invite the bot to your server with the right scopes.	打开 Discord 开发者门户，创建应用并添加 Bot，然后复制令牌。用合适权限邀请 bot 加入服务器。
Phone number	手机号
Proxy URL	代理 URL
Recommended. Comma-separated Discord user IDs.	推荐填写。Discord 用户 ID，用逗号分隔。
Recommended. Comma-separated Mattermost user IDs.	推荐填写。Mattermost 用户 ID，用逗号分隔。
Recommended. Comma-separated numeric IDs from @userinfobot. Without this, anyone can DM your bot.	推荐填写。来自 @userinfobot 的数字 ID，用逗号分隔。未填写时任何人都可私信你的 bot。
Recommended. Comma-separated phone numbers or WhatsApp IDs.	推荐填写。手机号或 WhatsApp ID，用逗号分隔。
Recommended. Comma-separated Signal identifiers.	推荐填写。Signal 标识符，用逗号分隔。
Recommended. Comma-separated Slack user IDs.	推荐填写。Slack 用户 ID，用逗号分隔。
Recommended. Comma-separated user IDs in @user:server format.	推荐填写。@user:server 格式的用户 ID，用逗号分隔。
Register an app on the QQ Open Platform (q.qq.com) and copy the App ID and Client Secret.	在 QQ 开放平台（q.qq.com）注册应用，并复制 App ID 和 Client Secret。
Reply style	回复方式
Restart needed	需要重启
Restart the gateway for this change to take effect.	请重启网关以使此更改生效。
Restart the gateway from the status bar to apply this change.	请从状态栏重启网关以应用此更改。
Restart the gateway to reconnect with the new credentials.	请重启网关以使用新凭据重新连接。
Retrying	正在重试
Run a signal-cli REST bridge somewhere reachable, then point Hermes at the URL and the registered phone number.	运行一个 Hermes 可访问的 signal-cli REST 桥接，然后填写 URL 和注册手机号。
Run an HTTP server that other tools (GitHub, GitLab, custom apps) can POST to. Use the secret to verify signatures.	运行一个可接收其他工具（GitHub、GitLab、自定义应用）POST 的 HTTP 服务，并使用 secret 验证签名。
Run BlueBubbles Server on a Mac with iMessage, expose its API, then point Hermes at the URL with the server password.	在启用 iMessage 的 Mac 上运行 BlueBubbles Server，开放 API，然后在 Hermes 中填写 URL 和服务器密码。
Save changes	保存更改
Search messaging...	搜索消息...
Server URL	服务器 URL
Set automatically by the toggle below. Leave alone unless you know you need it.	由下方开关自动设置。不确定时保持默认。
Set up a WeCom self-built app, expose its callback URL, and provide the corp ID, secret, agent ID, and AES key.	设置企业微信自建应用，开放回调 URL，并提供 corp ID、secret、agent ID 和 AES key。
setup saved	设置已保存
setup was updated.	设置已更新。
Sign in to the WeChat Official Account platform, copy the AppID and Token, and point the message callback URL at Hermes.	登录微信公众号平台，复制 AppID 和 Token，并将消息回调 URL 指向 Hermes。
Sign in to your homeserver with the bot account, then copy the access token, user ID, and homeserver URL.	使用 bot 账户登录 homeserver，然后复制访问令牌、用户 ID 和 homeserver URL。
Signal bridge URL	Signal 桥接 URL
Slack app token	Slack app 令牌
Slack bot token	Slack bot 令牌
Start the gateway from the status bar to connect.	请从状态栏启动网关以连接。
Start the WhatsApp bridge that ships with Hermes, scan the QR code on first run, then enable the platform.	启动 Hermes 附带的 WhatsApp 桥接，首次运行时扫码，然后启用该平台。
Starts with xapp-. Required for Socket Mode.	以 xapp- 开头。Socket Mode 必填。
Starts with xoxb-. Found under OAuth & Permissions after installing your Slack app.	以 xoxb- 开头。安装 Slack 应用后可在 OAuth & Permissions 下找到。
Startup failed	启动失败
The number registered with your signal-cli bridge.	在 signal-cli 桥接中注册的号码。
This platform does not need a token here. Use the setup guide above, then enable it below.	此平台无需在这里填写令牌。请使用上方设置指南，然后在下方启用。
URL of a running signal-cli REST bridge.	正在运行的 signal-cli REST 桥接 URL。
Use a dedicated mailbox. For Gmail/Workspace, create an app password and use imap.gmail.com / smtp.gmail.com.	建议使用专用邮箱。Gmail/Workspace 请创建应用密码，并使用 imap.gmail.com / smtp.gmail.com。
0 9 * * * or weekdays at 9am	0 9 * * * 或 工作日 9 点
At the top of every hour	每小时整点
Create cron	创建定时任务
Create first cron	创建第一个定时任务
Cron created	定时任务已创建
Cron deleted	定时任务已删除
Cron expression, or phrases like "every hour" or "weekdays at 9am".	Cron 表达式，或every hourweekdays at 9am这类短语。
Cron 表达式，或“every hour”“weekdays at 9am”这类短语。	Cron 表达式，或every hourweekdays at 9am这类短语。
Cron job	定时任务
Cron paused	定时任务已暂停
Cron resumed	定时任务已恢复
Cron syntax or natural language	Cron 表达式或自然语言
Cron triggered	定时任务已触发
Cron updated	定时任务已更新
Custom schedule	自定义计划
Delete cron	删除定时任务
Delete cron job?	删除定时任务？
Deliver to	发送到
Edit cron	编辑定时任务
Edit cron job	编辑定时任务
Every 15 minutes	每 15 分钟
Every day at 9:00 AM	每天 9:00
Every Monday at 9:00 AM	每周一 9:00
Failed to delete cron job	删除定时任务失败
Failed to load cron jobs	加载定时任务失败
Failed to save cron job	保存定时任务失败
Failed to trigger cron job	触发定时任务失败
Failed to update cron job	更新定时任务失败
Frequency	频率
Hourly	每小时
Loading cron jobs...	正在载入定时任务...
正在加载定时任务...	正在载入定时任务...
Monday through Friday at 9:00 AM	周一至周五 9:00
Monthly	每月
Morning briefing	晨间简报
New cron	新建定时任务
New cron job	新建定时任务
No matches	无匹配项
No scheduled jobs yet	暂无定时任务
Pause cron	暂停定时任务
permanently. It will stop firing immediately.	永久移除，并立即停止触发。
Prompt and schedule are required.	提示词和计划必填。
Refresh cron jobs	刷新定时任务
Refreshing cron jobs	正在刷新定时任务
Resume cron	恢复定时任务
Schedule a prompt to run automatically. Use cron syntax or a natural phrase like "every 15 minutes".	设置自动运行提示词。可使用 cron 语法，或类似每 15 分钟的自然语言。
设置自动运行提示词。可使用 cron 语法，或类似“每 15 分钟”的自然语言。	设置自动运行提示词。可使用 cron 语法，或类似每 15 分钟的自然语言。
Schedule a prompt to run on a cron expression. Hermes will run it and deliver results to the destination you pick.	设置按 cron 表达式运行的提示词，Hermes 会执行并将结果发送到所选目标。
Search cron jobs...	搜索定时任务...
Summarize my unread Slack threads and email me the top 5...	总结小马未读的 Slack 讨论，并通过邮件发送前 5 条...
The first day of each month at 9:00 AM	每月 1 日 9:00
This desktop	此桌面端
This will remove	将删除
Trigger now	立即触发
Update the schedule, prompt, or delivery target. Changes apply on next run.	更新计划、提示词或发送目标。更改将在下次运行时生效。
Weekdays	工作日
Weekly	每周
Clone from default	从默认配置复制
Copy config, skills, and SOUL.md from your default profile.	从默认配置档复制配置、技能和 SOUL.md。
Copy setup	复制设置
Copying...	正在复制...
Create profile	创建配置档
Creating...	正在创建...
Delete profile?	删除配置档？
Deleting...	正在删除...
directory. This cannot be undone.	目录。此操作暂时不能撤销。
目录。此操作无法撤销。	目录。此操作暂时不能撤销。
Empty SOUL.md — start writing the persona...	SOUL.md 为空，请开始编写人格...
Failed to copy setup command	复制设置命令失败
Failed to create profile	创建配置档失败
Failed to delete profile	删除配置档失败
Failed to load profiles	加载配置档失败
Failed to load SOUL.md	加载 SOUL.md 失败
Failed to rename profile	重命名配置档失败
Failed to save SOUL.md	保存 SOUL.md 失败
Invalid name.	名称无效。
Loading profiles...	正在载入配置档...
正在加载配置档...	正在载入配置档...
Loading SOUL.md...	正在载入 SOUL.md...
正在加载 SOUL.md...	正在载入 SOUL.md...
Lowercase letters, digits, hyphens, and underscores. Must start with a letter or digit.	可用小写字母、数字、连字符和下划线。必须以字母或数字开头。
Name is required.	名称必填。
New name	新名称
New profile	新建配置档
No profiles yet.	暂无配置档。
Profile created	配置档已创建
Profile deleted	配置档已删除
Profile renamed	配置档已重命名
Profiles are independent Hermes environments: separate config, skills, and SOUL.md.	配置档是独立 Hermes 环境：配置、技能和 SOUL.md 相互分开。
Refresh profiles	刷新配置档
Refreshing profiles	正在刷新配置档
Rename profile	重命名配置档
Renaming updates the profile directory and any wrapper scripts in	重命名会更新配置档目录和其中的包装脚本：
Renaming updates the profile directory and any wrapper scripts in	重命名会更新配置档目录和相关包装脚本：
Renaming...	正在重命名...
Save SOUL.md	保存 SOUL.md
Select a profile to view its details.	选择配置档以查看详情。
Setup command copied	设置命令已复制
SOUL.md saved	SOUL.md 已保存
The system prompt and persona instructions baked into this profile.	此配置档内置的系统提示词和人格说明。
This will delete	将删除
Unsaved changes	未保存更改
Close agents	关闭智能体
Live subagent activity for the current turn.	当前轮次的子智能体实时活动。
more files	更多文件
No live subagents	暂无活动子智能体
Spawn tree	子智能体树
When a turn delegates work, child agents stream their progress here.	当前轮次委派工作时，子智能体进度会显示在这里。
Action started, waiting for status...	操作已开始，正在等待状态...
API calls	API 调用
Browse generated outputs	浏览生成内容
Close command center	关闭命令中心
Configure Hermes desktop	配置 Hermes 桌面端
Daily tokens	每日 Token
Delete session	删除会话
Enable skills, toolsets, and providers	启用技能、工具集和模型服务
Est. cost	预估费用
Export session	导出会话
Gateway status, logs, restart/update	网关状态、日志、重启和更新
Loading status...	正在载入状态...
正在加载状态...	正在载入状态...
Loading usage...	正在载入用量...
正在加载用量...	正在载入用量...
Messaging gateway running	消息网关运行中
Messaging gateway stopped	消息网关已停止
New session	新建会话
No daily activity.	暂无每日活动。
No logs loaded yet.	尚未加载日志。
No matching results found.	未找到匹配结果。
No model usage yet.	暂无模型用量。
No sessions yet.	暂无会话。
No skill activity yet.	暂无技能活动。
No usage in the last	最近
Pin session	固定会话
Recent logs	最近日志
Restart messaging	重启消息
Search and manage sessions	搜索并管理会话
Search sessions	搜索会话
Search sessions, views, and actions	搜索会话、视图和操作
Search, pin, and manage sessions	搜索、固定和管理会话
Sessions panel	会话面板
Set up Telegram, Slack, Discord, and more	设置 Telegram、Slack、Discord 等
Skills & Tools	技能与工具
Start a fresh session	开始新会话
System panel	系统面板
Token, cost, and skill activity	Token、费用和技能活动
Token, cost, and skill activity over time	Token、费用和技能活动趋势
Tokens in/out	输入/输出 Token
Top models	常用模型
Top skills	常用技能
Unpin	取消固定
Unpin session	取消固定会话
Usage panel	用量面板
· Active sessions	· 活跃会话
(none)	无
（无）	无
(provider default)	（模型服务默认）
). Run it from the CLI with	）。请在 CLI 中运行
About Hermes Desktop	关于 Hermes 桌面版
Advanced	高级
Allow Private URLs	允许私有 URL
API Keys	API 密钥
API Retries	API 重试次数
Appearance	外观
Applies to new sessions. Use the model picker in the composer to hot-swap the active chat.	应用于新会话。可在输入区模型选择器中临时切换当前会话模型。
Applying...	正在应用...
Approval Mode	审批模式
Approval Timeout	审批超时
Archived Chats	已归档会话
auto · use main model	自动 · 使用主模型
Auto-Compression	自动压缩
Automatically speak assistant responses.	自动朗读助手回复。
Autosave failed	自动保存失败
Auxiliary models	辅助模型
Backup provider:model entries to try if the default model fails.	默认模型失败时尝试的备用 服务:模型 条目。
Bright desktop surfaces	明亮桌面界面
Browser Private URLs	浏览器私有 URL
Checkpoint Limit	检查点限制
Close settings	关闭设置
Code Execution Mode	代码执行模式
comma-separated value	逗号分隔值
comma-separated values	逗号分隔值
Command Allowlist	命令允许列表
Command Timeout	命令超时
Compression	压缩
Compression Target	压缩目标
Compression Threshold	压缩阈值
Config imported	配置已导入
Confirm MCP Reloads	确认 MCP 重新加载
Context compaction	上下文压缩
Context Engine	上下文引擎
Context Window	上下文窗口
Controls how image attachments are sent to the model.	控制图片附件如何发送给模型。
Create rollback snapshots before file edits.	修改文件前创建可回退快照。
Curator	整理器
Default assistant style for new sessions.	新会话默认助手风格。
Default Model	默认模型
Default project folder for tool and terminal work.	工具和终端工作的默认项目文件夹。
Edge Voice	Edge 声音
ElevenLabs Language	ElevenLabs 语言
ElevenLabs Model	ElevenLabs 模型
ElevenLabs STT Model	ElevenLabs STT 模型
ElevenLabs Voice	ElevenLabs 声音
Enable local or provider-backed speech transcription.	启用本地或服务支持的语音转写。
Enabled Toolsets	已启用工具集
Environment Passthrough	环境变量传递
Environment variables to pass into tool execution.	传递给工具执行的环境变量。
Execution Backend	执行后端
Export config	导出配置
Export failed	导出失败
Fallback Models	备用模型
File Checkpoints	文件检查点
File Page Limit	文件页数限制
File Read Limit	文件读取限制
Follow OS appearance	跟随系统外观
Gateway connection...	网关连接...
Helper tasks run on the main model by default. Assign a dedicated model to any task to override.	辅助任务默认使用主模型。可为任意任务指定专用模型。
Hide detected secrets from model-visible content when possible.	尽量从模型可见内容中隐藏检测到的密钥。
尽可能从模型可见内容中隐藏检测到的密钥。	尽量从模型可见内容中隐藏检测到的密钥。
How Hermes handles commands that need explicit approval.	Hermes 如何处理需要明确审批的命令。
How long approval prompts wait before timing out.	审批提示超时前等待的时长。
How strictly code execution is scoped to the current project.	控制代码执行在当前项目内的约束程度。
控制代码执行限制在当前项目内的严格程度。	控制代码执行在当前项目内的约束程度。
Image analysis	图像分析
Image Attachments	图片附件
Import config	导入配置
Included with a Nous subscription — sign in to Nous Portal to activate.	包含在 Nous 订阅中，请登录 Nous 门户启用。
Invalid config JSON	配置 JSON 无效
Keep shell state between commands when the backend supports it.	后端支持时在命令之间保留 Shell 状态。
Leave at 0 to use the selected model's detected context window.	填 0 时使用所选模型检测到的上下文窗口。
Line Length Limit	行长度限制
Loading configuration...	正在载入配置...
正在加载配置...	正在载入配置...
Loading Hermes configuration...	正在载入 Hermes 配置...
正在加载 Hermes 配置...	正在载入 Hermes 配置...
Loading model configuration...	正在载入模型配置...
正在加载模型配置...	正在载入模型配置...
Local Browser For Private URLs	私有 URL 使用本地浏览器
Local Transcription Model	本地转写模型
Low-glare workspace	低眩光工作区
Main model	主模型
Maintain a compact profile of user preferences.	维护简洁的用户偏好画像。
Max Agent Steps	最大智能体步骤
Max Recording Length	最长录音时长
Maximum characters Hermes can read from one file request.	Hermes 单次文件读取请求可读取的最大字符数。
MCP tool routing	MCP 工具路由
Memory & Context	记忆与上下文
Memory Budget	记忆预算
Memory Provider	记忆服务
Needs keys	需要密钥
No API key required.	无需 API 密钥。
No matching settings	没有匹配设置
No providers are available for this toolset right now.	当前没有可用于此工具集的服务商。
Not set	未设置
OpenAI TTS Model	OpenAI TTS 模型
OpenAI Voice	OpenAI 声音
Optional ISO-639-3 language code. Blank lets ElevenLabs auto-detect.	可选 ISO-639-3 语言代码。留空则由 ElevenLabs 自动检测。
Page summarization	页面摘要
Parallel Subagents	并行子智能体
Persistent Memory	持久记忆
Persistent Shell	持久 Shell
Profile Budget	画像预算
Protected Recent Messages	受保护的最近消息
Provider selected	服务已选择
Read Responses Aloud	朗读回复
Reasoning Blocks	推理块
Recall queries	回忆查询
Redact Secrets	隐藏密钥
Reset all settings to Hermes defaults?	要将全部设置重置为 Hermes 默认值吗？
Reset all to main	全部重置为主模型
Reset failed	重置失败
Reset to defaults	重置为默认值
Safety	安全
Save durable memories that can help future sessions.	保存可帮助后续会话的持久记忆。
Saving…	正在保存…
Search API keys	搜索 API 密钥
Search API keys...	搜索 API 密钥...
Search archived sessions...	搜索已归档会话...
Search MCP servers	搜索 MCP 服务
Search MCP servers...	搜索 MCP 服务...
Search settings...	搜索设置...
Service Tier	服务层级
Session search	会话搜索
Session titles	会话标题
Set to main	设为主模型
Settings failed to load	设置加载失败
Show reasoning sections when the backend provides them.	后端提供时显示推理部分。
Skill search	技能搜索
Skill-usage review	技能使用复核
Skills hub	技能中心
Smart auto-approve	智能自动批准
Speaker Diarization	说话人分离
Speech To Text	语音转文字
Speech-To-Text Provider	语音转文字服务
Strategy for managing long conversations near the context limit.	接近上下文限制时管理长对话的策略。
Subagent Model	子智能体模型
Subagent Provider	子智能体服务
Subagent Reasoning Effort	子智能体推理强度
Subagent Timeout	子智能体超时
Subagent Turn Limit	子智能体轮次限制
Summarize older context when conversations get large.	对话变长时总结较早上下文。
Tag Audio Events	标记音频事件
Terminal Output Limit	终端输出限制
Text-To-Speech Provider	文本转语音服务
This provider needs an extra setup step (	此服务商需要额外设置步骤（
This toolset has no provider options — enable it and it works with your current setup.	此工具集没有服务商选项，启用后会使用当前设置。
Timezone	时区
Title gen	标题生成
Tool configuration failed to load	工具配置加载失败
Tool-Use Enforcement	工具使用约束
Transcription Language	转写语言
Try a different search term or choose another section.	换个搜索词或选择其他分区。
Upper bound for tool-calling turns before Hermes stops a run.	Hermes 停止运行前工具调用轮次的上限。
Used for new chats unless you pick a different model in the composer.	用于新会话，除非你在输入区选择其他模型。
Used when Hermes needs local time context. Blank uses the system timezone.	Hermes 需要本地时间上下文时使用。留空则使用系统时区。
User Profile	用户画像
Vision	视觉
Voice Shortcut	语音快捷键
Web extract	网页提取
Working Directory	工作目录
Color Mode	颜色模式
Desktop palettes only. The selected mode is applied on top.	桌面配色。所选模式会叠加应用。
Human-friendly tool activity with concise summaries.	以简洁摘要展示工具活动。
Include raw tool args/results and low-level details.	显示原始工具参数、结果和底层细节。
Product	产品
Product hides raw tool payloads; Technical shows full input/output.	产品模式隐藏原始工具负载。技术模式显示完整输入/输出。
产品模式隐藏原始工具负载；技术模式显示完整输入/输出。	产品模式隐藏原始工具负载。技术模式显示完整输入/输出。
Technical	技术
Tool Call Display	工具调用显示
Base URL for the remote dashboard backend. Path prefixes are supported, for example /hermes.	远程控制台后端的基础 URL。支持路径前缀，例如 /hermes。
Connect this desktop shell to a remote Hermes backend using its session token.	使用会话令牌将此桌面外壳连接到远程 Hermes 后端。
Could not apply gateway settings	暂时不能应用网关设置
无法应用网关设置	暂时不能应用网关设置
Could not save gateway settings	暂时不能保存网关设置
无法保存网关设置	暂时不能保存网关设置
Diagnostics	诊断
Enter a remote URL and session token before switching to remote.	切换到远程前，请填写远程 URL 和会话令牌。
切换到远程前请先填写远程 URL 和会话令牌。	切换到远程前，请填写远程 URL 和会话令牌。
Enter a remote URL and session token before testing.	测试前，请填写远程 URL 和会话令牌。
测试前请先填写远程 URL 和会话令牌。	测试前，请填写远程 URL 和会话令牌。
env override	环境变量覆盖
Environment variables are controlling this desktop session.	环境变量正在控制当前桌面会话。
Gateway Connection	网关连接
Gateway connection restarting	网关连接正在重启
Gateway settings failed to load	网关设置加载失败
Gateway settings saved	网关设置已保存
Gateway settings unavailable	网关设置不可用
Hermes Desktop will reconnect using the saved settings.	Hermes 桌面版将使用已保存设置重新连接。
Loading gateway settings...	正在载入网关设置...
正在加载网关设置...	正在载入网关设置...
Local gateway	本地网关
Paste session token	粘贴会话令牌
Remote	远程
Remote gateway	远程网关
Remote gateway incomplete	远程网关信息不完整
Remote gateway reachable	远程网关可访问
Remote gateway test failed	远程网关测试失败
Remote URL	远程 URL
Reveal desktop.log in your file manager — useful when the gateway fails to start.	在文件管理器中显示 desktop.log，适合排查网关启动失败。
Save and reconnect	保存并重新连接
Save for next restart	保存到下次重启
Saved for the next restart.	已保存，将在下次重启时生效。
Session token	会话令牌
Start a private Hermes backend on localhost. This is the default and works offline.	在 localhost 启动私有 Hermes 后端。这是默认方式，可离线工作。
Test remote	测试远程
The dashboard session token used for REST and WebSocket access. Leave blank to keep the saved token.	用于 REST 和 WebSocket 访问的控制台会话令牌。留空则保留已保存令牌。
The desktop IPC bridge does not expose gateway settings.	桌面 IPC 桥接未暴露网关设置。
Add a stdio or HTTP server to expose MCP tools.	添加 stdio 或 HTTP 服务以开放 MCP 工具。
Add MCP server	添加 MCP 服务
Edit MCP server	编辑 MCP 服务
Edit server	编辑服务
Gateway unavailable	网关不可用
Give this MCP server a config key.	请为此 MCP 服务填写配置键。
Loading MCP servers...	正在载入 MCP 服务...
正在加载 MCP 服务...	正在载入 MCP 服务...
MCP reload failed	MCP 重新加载失败
MCP server saved	MCP 服务已保存
MCP servers	MCP 服务
MCP tools reloaded	MCP 工具已重新加载
Name required	需要名称
New server	新建服务
New tool schemas apply to fresh turns.	新的工具结构将在新轮次中生效。
No MCP servers	暂无 MCP 服务
Reconnect the gateway before reloading MCP.	重新加载 MCP 前，请连接网关。
重新加载 MCP 前请先连接网关。	重新加载 MCP 前，请连接网关。
Remove failed	移除失败
Save failed	保存失败
Save server	保存服务
Saving...	正在保存...
Server config must be a JSON object	服务配置必须是 JSON 对象
Server JSON	服务 JSON
Clear value	清除值
Credential removed	凭据已移除
Credential saved	凭据已保存
Enter value	输入值
Failed to save	保存失败：
Hide value	隐藏值
LLM providers	LLM 服务
Loading API keys and credentials...	正在载入 API 密钥和凭据...
正在加载 API 密钥和凭据...	正在载入 API 密钥和凭据...
Open provider docs	打开服务文档
Replace current value	替换当前值
Reveal value	显示值
Archive a chat to hide it here.	归档会话后会在这里隐藏。
Archived chats	已归档会话
Archived sessions	已归档会话
Could not clear default directory	暂时不能清除默认目录
无法清除默认目录	暂时不能清除默认目录
Could not load archived sessions	暂时不能加载已归档会话
无法加载已归档会话	暂时不能加载已归档会话
Could not update default directory	暂时不能更新默认目录
无法更新默认目录	暂时不能更新默认目录
Default project directory	默认项目目录
Default project directory updated	默认项目目录已更新
Delete failed	删除失败
Delete permanently	永久删除
Loading archived sessions…	正在载入已归档会话…
正在加载已归档会话…	正在载入已归档会话…
New sessions start in this folder unless you pick another. Leave it unset to use your home directory.	新会话会从此文件夹开始，除非另选位置。留空则使用用户目录。
No archived chats	没有已归档会话
No archived chats match your search.	没有匹配搜索的已归档会话。
Nothing archived	暂无归档
Restore	恢复
Restored	已恢复
Unarchive failed	取消归档失败
An update is currently installing.	更新正在安装。
Automatic updates	自动更新
Check now	立即检查
Hermes checks for updates automatically in the background and lets you know when one is ready.	Hermes 会在后台自动检查更新，并在可用时通知你。
Last checked	上次检查
Release notes	发行说明
Tap "Check now" to look for updates.	点击立即检查查找更新。
点击“立即检查”查找更新。	点击立即检查查找更新。
This build can't update itself from inside the app.	此版本暂时不能在应用内自行更新。
此版本无法在应用内自行更新。	此版本暂时不能在应用内自行更新。
Version unavailable	版本不可用
We couldn't reach the update server.	暂时不能连接更新服务。
无法连接更新服务。	暂时不能连接更新服务。
You're on the latest version.	当前已是最新版本。
Add to chat	添加到对话
Change working directory	更改工作目录
Collapse all folders	折叠全部文件夹
File system	文件系统
Focus terminal view	聚焦终端视图
Loading file tree	正在载入文件树
正在加载文件树	正在载入文件树
Loading files...	正在载入文件...
正在加载文件...	正在载入文件...
No folder selected	未选择文件夹
No project	无项目
Open a different folder	打开其他文件夹
Open a folder	打开文件夹
Open folder	打开文件夹
Preview unavailable	暂时不能预览
无法预览	暂时不能预览
Refresh tree	刷新文件树
Return to split view	返回分栏视图
Right sidebar	右侧栏
Right sidebar panels	右侧栏面板
The file tree hit an error rendering this folder.	文件树渲染此文件夹时出错。
This folder is empty.	此文件夹为空。
Tree error	文件树错误
Unreadable	暂时不能读取
无法读取	暂时不能读取
Advanced Hermes environments for separate personas, config, skills, and SOUL.md.	为不同角色、配置、技能和 SOUL.md 准备的 Hermes 高级环境。
App controls	应用控制
Checking inference	正在检查推理服务
Close Command Center	关闭命令中心
Command Center	命令中心
Context usage	上下文用量
Current turn elapsed	当前轮次耗时
Disconnected	已断开
Edit Models…	编辑模型…
Fast mode update failed	快速模式更新失败
Hermes inference gateway status	Hermes 推理网关状态
Hide right sidebar	隐藏右侧栏
Hide sidebar	隐藏侧边栏
Inference not ready	推理未就绪
Inference ready	推理已就绪
Manage profiles	管理配置档
Medium	中
Messaging platforms	消息平台
Model option update failed	模型选项更新失败
Mute haptics	关闭触感反馈
No options for this model	此模型没有选项
Open agents	打开智能体
Open Command Center	打开命令中心
Open cron jobs	打开定时任务
Open model picker	打开模型选择器
Open settings	打开设置
Open system panel	打开系统面板
Pane controls	面板控制
Recent activity	最近活动
Runtime session elapsed	运行会话耗时
Show right sidebar	显示右侧栏
Show sidebar	显示侧边栏
Unmute haptics	打开触感反馈
Update in progress	更新进行中
View all logs →	查看全部日志 →
Window controls	窗口控制
YOLO off	YOLO 已关闭
YOLO off — click to auto-approve dangerous commands.	YOLO 关闭：点击后自动批准危险命令。
YOLO on — auto-approving dangerous commands. Click to turn off.	YOLO 开启：自动批准危险命令。点击关闭。
All	全部
Anthropic API Key	Anthropic API 密钥
Anthropic OAuth: Required Extra Usage Credits to Use Subscription	Anthropic OAuth：使用订阅需要额外额度
Authorize Hermes there.	在那里授权 Hermes。
Back to sign in	返回登录
Connect a model provider to start chatting. Most options take one click.	连接模型服务后即可开始对话，大多数选项一步完成。
connected.	已连接。
connected. Picking a default model...	已连接，正在选择默认模型...
Continue	继续
Copy the authorization code and paste it below.	复制授权码并粘贴到下方。
Could not save credential.	暂时不能保存凭据。
无法保存凭据。	暂时不能保存凭据。
Default model	默认模型
Direct access to Google Gemini models.	直接访问 Google Gemini 模型。
Direct access to OpenAI models.	直接访问 OpenAI 模型。
Direct access to xAI Grok models.	直接访问 xAI Grok 模型。
Get a key	获取密钥
GPT-class models	GPT 类模型
Hermes is finishing install. This usually takes under a minute on first run.	Hermes 正在完成安装，首次运行通常不到一分钟。
Hosts hundreds of models behind a single key. Good default for new installs.	一个密钥接入数百个模型，新安装推荐。
I have an API key	小马有 API 密钥
I've signed in	小马已登录
in your browser.	在浏览器中。
in your browser. Enter this code there:	在浏览器中。在那里输入此代码：
in your browser. Enter this code there:	在浏览器中。请在那里输入此代码：
Let's get you setup with Hermes Agent	开始设置 Hermes Agent
Local / custom endpoint	本地 / 自定义端点
Looking up providers...	正在查找服务商...
Nous Portal	Nous 门户
One key, hundreds of models — a solid default	一个密钥，数百个模型，适合作为默认选择
one key, many models	一个密钥，多种模型
One subscription, 300+ frontier models — the recommended way to run Hermes	一个订阅可用 300 多个前沿模型，这是推荐的 Hermes 运行方式
Opens a verification page in your browser — Hermes connects automatically	会在浏览器打开验证页面，Hermes 将自动连接
Opens your browser to sign in — Hermes connects automatically	会打开浏览器登录，Hermes 将自动连接
Opens your browser to sign in, then continues here	打开浏览器登录，然后回到这里继续
Other providers	其他服务商
Paste API key	粘贴 API 密钥
Paste authorization code	粘贴授权码
Pick a different provider	选择其他模型服务
Point Hermes at a local or self-hosted OpenAI-compatible endpoint (vLLM, llama.cpp, Ollama, etc).	将 Hermes 指向本地或自托管的 OpenAI 兼容端点（vLLM、llama.cpp、Ollama 等）。
Qwen Code	通义灵码
Re-open authorization page	重新打开授权页面
Re-open sign-in page	重新打开登录页面
Re-open verification page	重新打开验证页面
Required	必填
Sign in once in your terminal, then come back to chat	在终端登录一次，然后返回对话
Sign-in failed. Try again.	登录失败，请重试。
Start chatting	开始对话
Starting Hermes…	正在启动 Hermes…
Starting sign-in for	正在启动登录：
Waiting for you to authorize...	正在等待授权...
We opened	已打开
Auto	自动
Cancel install	取消安装
Cancelling...	正在取消...
Copied!	已复制！
Copy command	复制命令
Copy output	复制输出
Failed	失败
Fetching installer manifest...	正在获取安装清单...
Fixed	已修复
Full transcript saved to	完整记录已保存到
Hermes needs a one-time install	Hermes 需要完成一次安装
Hermes 需要完成一次性安装	Hermes 需要完成一次安装
Hide	隐藏
Hide installer output	隐藏安装输出
Install command	安装命令
Install update	安装更新
Installation failed	安装失败
Installing	安装中
No output yet.	暂无输出。
One of the install steps failed. On Windows, this can happen if another Hermes CLI or desktop instance is running. Stop any running Hermes instances, then retry. Check the details below or the desktop log for the full transcript.	某个安装步骤未完成。在 Windows 上，如果另一个 Hermes CLI 或桌面实例正在运行，就会出现这种情况。请停止正在运行的 Hermes 实例后重试。完整记录可查看下方详情或桌面日志。
某个安装步骤失败。在 Windows 上，如果另一个 Hermes CLI 或桌面实例正在运行，可能会发生这种情况。请停止正在运行的 Hermes 实例后重试。完整记录可查看下方详情或桌面日志。	某个安装步骤未完成。在 Windows 上，如果另一个 Hermes CLI 或桌面实例正在运行，就会出现这种情况。请停止正在运行的 Hermes 实例后重试。完整记录可查看下方详情或桌面日志。
Reload and retry	重新加载并重试
Setting up Hermes Agent	正在设置 Hermes Agent
Show	显示
Show installer output	显示安装输出
Skipped	已跳过
steps complete	步已完成
Stop	停止
Subsequent launches will skip this step.	后续启动会跳过此步骤。
System	跟随系统
This is a one-time setup. The Hermes installer is downloading dependencies and configuring your machine.	这是一次设置。Hermes 安装程序正下载依赖，并配置你的机器。
这是一次性设置。Hermes 安装程序正在下载依赖并配置你的机器。	这是一次设置。Hermes 安装程序正下载依赖，并配置你的机器。
View install docs	查看安装文档
Will install to	将安装到
A new version of Hermes is ready to install.	Hermes 新版本已可安装。
About	关于
Backend out of date	后端版本过旧
Copied	已复制
Copy	复制
Couldn’t check for updates	暂时不能检查更新
无法检查更新	暂时不能检查更新
Desktop bridge unavailable.	桌面桥接不可用。
Done	完成
Finishing up	正在完成
Hermes is ready	Hermes 已就绪
Hermes will close to apply the update.	Hermes 将关闭以应用更新。
Hermes will pick up the new version next time you launch it.	下次启动 Hermes 时会使用新版本。
Looking for updates…	正在查找更新…
Manual	手动
Maybe later	稍后再说
more change	更多变更
New update available	有新版本可用
No updates	无更新
No worries — nothing was lost. You can try again now.	不用担心，内容没有丢失。现在可以重试。
Not now	暂不
REQUIRED	必填
Retry	重试
See what's new	查看新增内容
Starting update…	正在开始更新…
The Hermes updater will take over in its own window and reopen Hermes when it’s done.	Hermes 更新程序会在独立窗口中接管，并在完成后重新打开 Hermes。
This version of Hermes can’t update itself from inside the app.	此版本的 Hermes 暂时不能在应用内自行更新。
此版本的 Hermes 无法在应用内自行更新。	此版本的 Hermes 暂时不能在应用内自行更新。
Try again	重试
Update available	有可用更新
Update didn’t finish	更新未完成
Update from your terminal	通过终端更新
Update Hermes	更新 Hermes
Update not available	暂无可用更新
Update now	立即更新
Update ready	更新已就绪
Updating Hermes…	正在更新 Hermes…
You installed Hermes from the command line, so updates run there too. Paste this into your terminal:	你通过命令行安装了 Hermes，因此更新也在那里运行。将下面内容粘贴到终端：
Your Hermes backend is older than this desktop build and may not work correctly. Update to align them.	Hermes 后端版本低于当前桌面端，运行会出问题。请更新，让两端保持一致。
Hermes 后端版本低于当前桌面端，可能无法正常工作。请更新以保持一致。	Hermes 后端版本低于当前桌面端，运行会出问题。请更新，让两端保持一致。
You’re all set	已全部就绪
Clean grayscale — minimal and focused	干净灰阶，极简专注
Cool slate blue — focused developer theme	冷调石板蓝，专注开发主题
Cyberpunk	赛博朋克
Dark	深色
Desktop themes:	桌面主题：
Ember	余烬
Glass neutrals with Nous blue accents	玻璃质感柔和灰调，点缀 Nous 蓝
玻璃中性色搭配 Nous 蓝色点缀	玻璃质感柔和灰调，点缀 Nous 蓝
Light	浅色
Midnight	午夜
Mono	单色
Neon green on black — matrix terminal	黑底霓虹绿，矩阵终端风格
No desktop themes are available.	没有可用的桌面主题。
Slate	石板
These are desktop-only display preferences. Mode controls brightness; theme controls the accent palette and chat surface styling.	这些是桌面端显示偏好。模式控制亮度，主题控制强调色和对话界面样式。
Warm crimson and bronze — forge vibes	暖红与青铜色，锻造氛围
`Model · ${y}: ${v||`none`}`	`模型 · ${y}: ${v||`未选择`}`
ElevenLabs Scribe model	ElevenLabs Scribe 模型
Hermes Desktop starts its own local gateway by default. Use a remote gateway when you want this app to control an already-running Hermes backend on another machine or behind a trusted proxy.	Hermes 桌面版默认启动本地网关。当你希望本应用控制另一台机器或可信代理后的 Hermes 后端时，可使用远程网关。
The background gateway didn't come up. Try one of the recovery steps below — nothing here deletes your chats or settings.	后台网关未启动。请尝试下面的恢复步骤。这里不会删除你的对话或设置。
后台网关未启动。请尝试下面的恢复步骤；这里不会删除你的对话或设置。	后台网关未启动。请尝试下面的恢复步骤。这里不会删除你的对话或设置。
). Hermes won’t ask again for commands like this — in this session or any future one.	）。Hermes 以后遇到类似命令不会再次询问，包括当前会话和未来会话。
Activity	活动
Add a provider credential before sending your first message.	发送第一条消息前，请添加模型服务凭据。
发送第一条消息前请先添加模型服务凭据。	发送第一条消息前，请添加模型服务凭据。
Add a remote URL and token before switching to remote.	切换到远程前，请添加远程 URL 和令牌。
切换到远程前，请先添加远程 URL 和令牌。	切换到远程前，请添加远程 URL 和令牌。
Add or switch inference provider.	添加或切换推理模型服务。
Add provider	添加模型服务
Add provider…	添加模型服务…
Administrator password	管理员密码
ADVANCED	高级
Agents	智能体
Allowed Telegram user IDs (comma-separated)	允许的 Telegram 用户 ID（用逗号分隔）
and remove its	并移除它的
API service tier (OpenAI/Anthropic)	API 服务层级（OpenAI/Anthropic）
Apply	应用
Approval	审批
Archive	归档
Archive failed	归档失败
Archived chats are hidden from the sidebar but keep all their messages. Ctrl/⌘-click a chat in the sidebar to archive it without opening.	已归档会话会从侧边栏隐藏，但保留全部消息。在侧边栏按 Ctrl/⌘ 点击会话可直接归档而无需打开。
Archived chats are hidden from the sidebar but keep all their messages. Ctrl/⌘-click a chat in the sidebar to archive it.	已归档会话会从侧边栏隐藏，但保留全部消息。在侧边栏按 Ctrl/⌘ 点击会话可直接归档。
Artifacts	产物
Attach	添加
Backend stopped	后端已停止
Background restart did not return a task id	后台重启未返回任务 ID
Base	基础
Branch	分支
Branch failed	分支创建失败
Branch the latest message into a new chat	将最新消息分支到新会话
Browser	浏览器
browser automation	浏览器自动化
Cancel	取消
Change	更改
Chat	对话
Clear	清除
Clear all	全部清除
Clear search	清空搜索
Clipboard	剪贴板
Close	关闭
Close ${e.label}	关闭 ${e.label}
Compress this conversation context	压缩当前对话上下文
Compressor	压缩器
Connected	已连接
Connected, but Hermes still cannot resolve a usable provider.	已连接，但 Hermes 还未找到可用模型服务。
Connected, but Hermes still cannot resolve a usable provider.	已连接，但 Hermes 仍暂时不能解析可用服务商。
已连接，但 Hermes 仍无法解析可用服务商。	已连接，但 Hermes 仍暂时不能解析可用服务商。
Connecting	正在连接
Connecting live desktop gateway	正在连接桌面网关
Connection test failed	连接测试失败
Connection test succeeded	连接测试成功
Connection:	连接：
Context	上下文
Copy detail	复制详情
Copy failed	复制失败
Copy link	复制链接
Could not attach ${e.name||	暂时不能添加 ${e.name||
无法添加 ${e.name||	暂时不能添加 ${e.name||
Could not change model	暂时不能切换模型
无法切换模型	暂时不能切换模型
Could not create a new session	暂时不能创建新会话
无法创建新会话	暂时不能创建新会话
Could not delete session	暂时不能删除会话
无法删除会话	暂时不能删除会话
Could not load models	暂时不能加载模型
无法加载模型	暂时不能加载模型
Could not preview ${e.label}	暂时不能预览 ${e.label}
无法预览 ${e.label}	暂时不能预览 ${e.label}
Could not reach ${n}.	暂时不能访问 ${n}。
无法访问 ${n}。	暂时不能访问 ${n}。
Could not reach that endpoint.	暂时不能访问该端点。
无法访问该端点。	暂时不能访问该端点。
Could not read recorded audio	暂时不能读取录音
无法读取录音	暂时不能读取录音
Could not render math with KaTeX	暂时不能用 KaTeX 渲染数学公式
无法用 KaTeX 渲染数学公式	暂时不能用 KaTeX 渲染数学公式
Could not restore session	暂时不能恢复会话
无法恢复会话	暂时不能恢复会话
Could not save local endpoint	暂时不能保存本地端点
无法保存本地端点	暂时不能保存本地端点
Could not send secret	暂时不能发送密钥
无法发送密钥	暂时不能发送密钥
Could not send sudo password	暂时不能发送管理员密码
无法发送管理员密码	暂时不能发送管理员密码
Could not toggle YOLO	暂时不能切换 YOLO
无法切换 YOLO	暂时不能切换 YOLO
Create a debug report	创建调试报告
Cron	定时任务
Custom	自定义
Daily	每天
dangerous command	危险命令
Default	默认
Delegated task	已委派任务
Delete	删除
Desktop boot failed	桌面启动失败
Details	详情
Disable	禁用
Disabled	已禁用
Dismiss notification	关闭通知
Displays the mobile sidebar.	显示移动侧边栏。
docs	文档
Edit	编辑
Edit failed	编辑失败
ElevenLabs rejected the API key (401).	ElevenLabs 拒绝了 API 密钥（401）。
Empty	空
empty message	空消息
Enable	启用
Enabled	已启用
Enter a value first.	请输入值。
请先输入值。	请输入值。
Enter the endpoint URL first.	请输入端点 URL。
请先输入端点 URL。	请输入端点 URL。
Error	错误
error: ${e instanceof Error?e.message:String(e)}	错误：${e instanceof Error?e.message:String(e)}
Export	导出
Failed to update	更新失败：
Fast	快速
Faster	更快
Files	文件
Filter providers and models...	筛选服务和模型...
Folders	文件夹
Free tier	免费层级
Gateway	网关
GET YOUR CREDENTIALS	获取凭据
Go to next page	下一页
Go to previous page	上一页
height (dvh)	视口高（dvh）
高度（dvh）	视口高（dvh）
Hermes background process exited during startup.	Hermes 后台进程在启动时退出。
Hermes background process exited.	Hermes 后台进程已退出。
Hermes couldn't start	Hermes 暂时不能启动
Hermes 无法启动	Hermes 暂时不能启动
Hermes Desktop	Hermes 桌面版
Hermes Desktop is ready	Hermes Desktop 已就绪
Hermes error	Hermes 错误
Hermes gateway is not connected	Hermes 网关未连接
Hermes needs a credential to continue.	Hermes 需要凭据才能继续。
Hermes needs your sudo password to run a privileged command. It is sent only to your local agent.	Hermes 需要管理员密码来运行特权命令。密码会发送给本机 agent。
Hermes reported an error	Hermes 报告错误
HERMES 智能体	小马汉化版 HERMES
High	高
image generation	图像生成
Images	图片
Improved	已改进
Improvements and fixes	改进和修复
In this update	本次更新
in your browser. Authorize Hermes there and you'll be connected automatically — nothing to copy or paste.	在浏览器中。完成 Hermes 授权后会自动连接，无需复制或粘贴。
Input / Output price per million tokens	每百万 Token 输入 / 输出价格
invert color	反转颜色
Kawaii	可爱
label: 'Edit'	label: '编辑'
label: 'File'	label: '文件'
label: 'Help'	label: '帮助'
label: 'View'	label: '视图'
label: 'Window'	label: '窗口'
label: `About ${APP_NAME}`	label: `关于 ${APP_NAME}`
Latest	最新版
List or restore filesystem checkpoints	列出或恢复文件系统检查点
Load ${n} more	再加载 ${n} 条
Loading	正在载入
正在加载	正在载入
Loading capabilities...	正在载入能力...
正在加载能力...	正在载入能力...
Loading Hermes settings	正在载入 Hermes 设置
正在加载 Hermes 设置	正在载入 Hermes 设置
Loading recent sessions	正在载入最近会话
正在加载最近会话	正在载入最近会话
Loading…	正在载入…
正在加载…	正在载入…
Local	本地
LOCATION	位置
Location	位置
Log file	日志文件
Low	低
Manage the standing goal for this session	管理此会话的常驻目标
Max	最高
Memory provider plugin	记忆服务插件
Message	消息
Messaging	消息
Microphone permission was denied.	麦克风权限被拒绝。
Model	模型
Model switch failed	模型切换失败
Models	模型
Muted	已静音
Name	名称
Navigate	导航
Next	下一页
No active session for background restart	没有可用于后台重启的活跃会话
No authenticated providers.	没有已认证的服务商。
No description.	无说明。
No desktop commands available.	没有可用的桌面命令。
No inference provider is configured.	尚未配置推理模型服务。
No matching archived chats	没有匹配的已归档会话
No model	未选择模型
no model	未选择模型
No models found	未找到模型
No models found.	未找到模型。
No skills found	未找到技能
No toolsets found	未找到工具集
Nothing to branch	没有可分支内容
Notifications	通知
now run through your Nous subscription.	现在通过你的 Nous 订阅运行。
Off	关
On	开
Open link	打开链接
Open logs	打开日志
Other improvements	其他改进
page	第
Path	路径
Pause	暂停
Pending	等待中
Persist globally	全局保存
Persist globally (otherwise this session only)	全局保存（否则仅本次会话）
Personality	助手风格
Pin	固定
Pinned	已固定
Playback failed	播放失败
Prev	上一页
Preview	预览
Pro models need a paid Nous subscription.	Pro 模型需要付费 Nous 订阅。
Profiles	配置档
Project	项目
Prompt	提示词
Prompt failed	提示词提交失败
Provider	模型服务
Queue a prompt for the next turn	将提示词加入下一轮队列
radius scalar	半径系数
Ready	就绪
RECENT ACTIVITY	最近活动
recent logs	最近日志
RECOMMENDED	推荐
Recommended	推荐
Refresh skills	刷新技能
Refreshing skills	正在刷新技能
Regenerate failed	重新生成失败
Reload window	重新加载窗口
Remote token	远程令牌
Remove the last user/assistant exchange	移除上一组用户/助手对话
Rename	重命名
Rename the current session	重命名当前会话
Repair install	修复安装
Repair re-runs the installer and can take a few minutes on a fresh machine.	修复会重新运行安装程序，新机器上也许需要几分钟。
修复会重新运行安装程序，新机器上可能需要几分钟。	修复会重新运行安装程序，新机器上也许需要几分钟。
Reset config	重置配置
Restart the desktop backend to apply cwd changes to this active session.	重启桌面后端以将工作目录更改应用到当前会话。
Results	结果
Resume	继续
Resume a saved session	恢复已保存会话
Resume failed	继续失败
Retry the last user message	重试上一条用户消息
Run	运行
Run a prompt in the background	在后台运行提示词
Run Hermes from Telegram DMs, groups, and topics.	通过 Telegram 私信、群组和话题运行 Hermes。
Running	运行中
Save	保存
Saved	已保存
Search	搜索
Search archived chats	搜索已归档会话
Search models	搜索模型
Search skills...	搜索技能...
Search toolsets...	搜索工具集...
Secret required	需要密钥
secret value	密钥内容
Send	发送
Session	会话
Session busy	会话正忙
session busy — /interrupt the current turn before sending this command	会话正忙，请用 /interrupt 中断当前轮次，再发送此命令
会话正忙，请先用 /interrupt 中断当前轮次再发送此命令	会话正忙，请用 /interrupt 中断当前轮次，再发送此命令
Session exported	会话已导出
Session unavailable	会话不可用
Sessions	会话
Settings	设置
Shell Session	Shell 会话
Show active desktop sessions and running tasks	显示活动桌面会话和运行中任务
Show current session status	显示当前会话状态
Show desktop slash commands	显示桌面端斜杠命令
Show token usage for this session	显示此会话 Token 用量
Sign in with ${n}	登录 ${n}
signs in through its own CLI. Run this command in a terminal, then come back and pick "I've signed in":	会通过自己的 CLI 登录。请在终端运行此命令，然后返回这里选择小马已登录：
会通过自己的 CLI 登录。请在终端运行此命令，然后返回这里选择“小马已登录”：	会通过自己的 CLI 登录。请在终端运行此命令，然后返回这里选择小马已登录：
Skill disabled	技能已禁用
Skill enabled	技能已启用
skill payload missing message	技能缺少消息内容
Skills	技能
Skills failed to load	技能加载失败
Something broke in the interface	界面出现问题
Start a new desktop chat	开始新的桌面会话
Start or resume a chat before branching.	请开始或恢复会话后再创建分支。
请先开始或恢复会话再创建分支。	请开始或恢复会话后再创建分支。
Starting desktop connection	正在启动桌面连接
Starting Hermes Desktop…	正在启动 Hermes Desktop…
Steer the current run after the next tool call	在下一次工具调用后引导当前运行
Stop failed	停止失败
Stop running background processes	停止运行中的后台进程
Stop the current turn before branching this chat.	请停止当前轮次后再为此会话创建分支。
请先停止当前轮次再为此会话创建分支。	请停止当前轮次后再为此会话创建分支。
sudo password	sudo 密码
Switch desktop theme or cycle to the next one	切换桌面主题或轮换到下一个
Switch model	切换模型
Terminal	终端
Terminal execution backend	终端执行后端
Terminal must be opened first	需要打开终端
需先打开终端	需要打开终端
Test connection	测试连接
text-to-speech	文本转语音
The desktop backend rejected that request (405 Method Not Allowed). Try restarting Hermes Desktop.	桌面后端拒绝了该请求（405 Method Not Allowed）。请尝试重启 Hermes Desktop。
The response is ready.	回复已准备好。
The view hit an unexpected error. Your chats and settings are safe - try again, or reload the window.	视图遇到异常。你的对话和设置仍安全，请重试或重新加载窗口。
Theme	主题
Thinking	正在思考
This message has no text to branch from.	此消息没有可用于分支的文本。
TITLE / NAME	标题 / 名称
to use the saved setting below.	以使用下方已保存设置。
Toggle YOLO — auto-approve dangerous commands	切换 YOLO：自动批准危险命令
Token exchange failed.	令牌交换失败。
Tool Gateway enabled	工具网关已启用
Tools	工具
Toolset disabled	工具集已禁用
Toolset enabled	工具集已启用
Toolsets	工具集
toolsets enabled	个工具集已启用
Toolsets failed to refresh	工具集刷新失败
Try a broader search or different category.	换个关键词或分类试试。
Try a broader search query.	换个更宽泛的搜索词试试。
Unknown	未知
Untitled session	未命名会话
Updates	更新
URL	链接
Usage	用量
Use local gateway	使用本地网关
useSidebar must be used within a SidebarProvider.	useSidebar 必须在 SidebarProvider 内使用。
video generation	视频生成
Voice	语音
web search & extract	网页搜索与提取
What do you see in this image?	你在这张图片里看到了什么？
What's new	新增内容
Working directory change failed	工作目录切换失败
Working directory staged	工作目录更改已暂存
Workspace	工作区
YOLO armed for this chat	此会话已启用 YOLO
You're about to visit an external website.	即将访问外部网站。
使用 bot 账户登录 homeserver，然后复制访问令牌、用户 ID 和 homeserver URL。	使用 bot 账户登录主服务器，然后复制访问令牌、用户 ID 和主服务器地址。
创建 Slack 应用，启用 Socket Mode，安装到工作区，然后复制 Bot token（xoxb-）和 App-level token（xapp-）。	创建 Slack 应用，启用 Socket Mode，安装到工作区，然后复制 Bot 令牌（xoxb-）和应用级令牌（xapp-）。
""".strip()

for line in poetic_user_facing_tsv.splitlines():
    if not line.strip() or "\t" not in line:
        continue
    old, new = line.split("\t", 1)
    for wrapped_old, wrapped_new in (
        (f"`{old}`", f"`{new}`"),
        (f'"{old}"', f'"{new}"'),
        (f"'{old}'", f"'{new}'"),
    ):
        replacements.append((wrapped_old, wrapped_new))

# Repair overly broad poetic replacements from earlier local builds.
replacements.extend([
    ("class名称", "className"),
    ("display名称", "displayName"),
    ("tool名称", "toolName"),
    ("get上下文", "getContext"),
    ("use上下文", "useContext"),
    ("create上下文", "createContext"),
    ("text基础line", "textBaseline"),
    ("addColor停止", "addColorStop"),
    ("match全部", "matchAll"),
    ("is运行ning", "isRunning"),
    ("is等待中", "isWaiting"),
    ("set等待中", "setWaiting"),
    ("class名称", "className"),
])

changed_files = []
for path in root.rglob("*"):
    if not path.is_file() or path.suffix not in {".js", ".cjs", ".html", ".json"}:
        continue
    try:
        original = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    updated = original
    for old, new in replacements:
        updated = updated.replace(old, new)
    while "Copyright © 2026 Nous Research / 中文增强 / 中文增强" in updated:
        updated = updated.replace(
            "Copyright © 2026 Nous Research / 中文增强 / 中文增强",
            "Copyright © 2026 Nous Research / 中文增强",
        )
    if "Copyright © 2026 Nous Research / 中文增强" not in updated:
        updated = updated.replace("Copyright © 2026 Nous Research", "Copyright © 2026 Nous Research / 中文增强")
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        changed_files.append(str(path.relative_to(root)))

if changed_files:
    marker.write_text(json.dumps({"changed": sorted(changed_files)}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY_DESKTOP_PATCH

    if [ ! -f "$marker_file" ]; then
      say "桌面端补丁：已是最新：$app"
      continue
    fi

    rm -f "$marker_file"
    if ! "$node_cmd" "$asar_cli" pack "$work_dir" "$new_asar" >/dev/null 2>&1; then
      say "桌面端补丁：重打包失败，已跳过：$app"
      continue
    fi

    local new_hash
    new_hash="$(shasum -a 256 "$new_asar" | awk '{print $1}')"
    cp "$new_asar" "$asar_file"
    if [ -f "$plist_file" ]; then
      python3 - "$plist_file" "$new_hash" <<'PY_PLIST'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
new_hash = sys.argv[2]
data = plistlib.loads(path.read_bytes())
integrity = data.setdefault("ElectronAsarIntegrity", {})
entry = integrity.setdefault("Resources/app.asar", {})
entry["algorithm"] = "SHA256"
entry["hash"] = new_hash
path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=False))
PY_PLIST
    fi

    if command -v codesign >/dev/null 2>&1; then
      if codesign --force --deep --sign - "$app" >/dev/null 2>&1; then
        say "桌面端补丁：已刷新本机签名：$app"
      else
        say "桌面端补丁：签名刷新失败，但资源已处理：$app"
      fi
    fi
    say "桌面端补丁：已应用：$app"
    patched_any="1"
  done <<EOF_DESKTOP_APPS
$(find_hermes_desktops)
EOF_DESKTOP_APPS

  if [ "$found_any" != "1" ]; then
    say "桌面端补丁：未找到 Hermes.app。"
  elif [ "$patched_any" != "1" ]; then
    say "桌面端补丁：没有新的改动。"
  fi
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
  record_metric install

  mkdir -p "$INSTALL_HOME" "$RELEASES_DIR" "$HERMES_HOME_DIR"
  ensure_official_hermes

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
  apply_tui_source_patch "$(find_real_hermes)"
  apply_desktop_app_patch
  ensure_path_hint

  say "小马AI Hermes 中文增强已安装"
  say "中文包版本：${PACKAGE_VERSION}"
  say "Hermes 匹配：${compat}，本机检测：${hermes_version}"
  say "新开终端后，Hermes 会在启动前检查中文内容更新。"
}

main "$@"
