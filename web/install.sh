#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${XIAOMA_HERMES_BASE_URL:-https://useai.live/hermes}"
BASE_URL="${BASE_URL%/}"
PACKAGE_VERSION="2026.05.18.3"
OFFICIAL_HERMES_INSTALL_URL="${XIAOMA_HERMES_OFFICIAL_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"
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

ensure_official_hermes() {
  if [ -n "${XIAOMA_HERMES_SOURCE_ROOT:-}" ]; then
    return
  fi
  if [ -n "$(find_real_hermes)" ]; then
    return
  fi
  if [ "${XIAOMA_HERMES_SKIP_OFFICIAL_INSTALL:-0}" = "1" ]; then
    return
  fi

  need_cmd curl
  say "未检测到 Hermes，正在先安装官方 Hermes Agent。"
  curl -fsSL "$OFFICIAL_HERMES_INSTALL_URL" | bash

  if [ -z "$(find_real_hermes)" ]; then
    printf '官方 Hermes 安装后仍未检测到 hermes 命令，请打开新终端后重试。\\n' >&2
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
printf '未找到原版 Hermes，请重新执行：curl -fsSL https://useai.live/hermes/install.sh | bash\\n' >&2
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
		        ('{t.brand.icon} NOUS HERMES', '{t.brand.icon} 爱马仕机器人'),
		        ('{t.brand.icon} Nous Research · Messenger of the Digital Gods', '{t.brand.icon} 爱马仕机器人 · 中文增强版'),
		        ('<Text color={t.color.muted}> · Nous Research</Text>', '<Text color={t.color.muted}> · Nous Research</Text>'),
		        ('Available {title}', "{title === 'Tools' ? '可用工具' : title === 'Skills' ? '可用技能' : `可用 ${title}`}"),
		        ("label={title === 'Tools' ? 'discovering tools' : 'scanning skills'}", "label={title === 'Tools' ? '正在发现工具' : '正在扫描技能'}"),
		        ("'more toolsets…'", "'个工具集…'"),
		        ("'more…'", "'项…'"),
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
		        ("'commit' : 'commits'", "'次提交' : '次提交'"),
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
		        ("sys(`startup image attach failed: ${rpcErrorMessage(e)}`)", "sys(`启动图片附加失败：${rpcErrorMessage(e)}`)"),
		        ("patchUiState({ status: 'resuming…' })", "patchUiState({ status: '正在继续…' })"),
		        ("patchUiState({ status: 'forging session…' })", "patchUiState({ status: '正在创建会话…' })"),
		        ("patchUiState({ status: 'resuming most recent…' })", "patchUiState({ status: '正在继续最近会话…' })"),
		        ("state.status === 'starting agent…' ? 'ready' : state.status", "state.status === '正在启动 Agent…' ? '就绪' : state.status"),
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
		    "acp_adapter/server.py": [
		        ('return f"Hermes Agent v{HERMES_VERSION}"', 'return f"爱马仕机器人 v{HERMES_VERSION}"'),
		        ('Tip: run /compact to compress manually before the threshold.', '提示：达到阈值前，可运行 /compact 手动压缩上下文。'),
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
    backup_path = backup_root / rel
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    if not backup_path.exists():
        shutil.copy2(path, backup_path)


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
  ensure_path_hint

  say "小马AI Hermes 中文增强已安装"
  say "中文包版本：${PACKAGE_VERSION}"
  say "Hermes 匹配：${compat}，本机检测：${hermes_version}"
  say "新开终端后，Hermes 会在启动前检查中文内容更新。"
}

main "$@"
