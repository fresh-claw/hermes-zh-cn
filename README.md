# 小马AI Hermes 中文增强包

面向中文用户的 Hermes Desktop 桌面版、Hermes Agent TUI 和 CLI 汉化补丁。适合刚开始用 Hermes、看不懂英文启动页和快捷指令、或者安装后仍有部分界面没有变成中文的人。

官网入口：[useai.live/hermes](https://useai.live/hermes/)

遇到安装问题、版本适配、中文补丁未生效，或者想讨论 Hermes 在真实业务里的用法，可以扫码加入官网首页的「Hermes交流答疑群」。群里主要讨论业务落地和疑难杂症。

让用户在 Hermes 对话中发送一句话：

```text
请访问 useai.live/hermes 安装汉化补丁
```

Hermes 读取页面说明后，直接执行安装命令。安装器会先检测本机 Hermes；未安装时自动执行官方安装脚本，安装完成后继续安装中文补丁。随后检测版本，0.15.x、0.14.x、0.13.x 使用对应中文包，失败或超时时使用 legacy 兼容包，并把 Hermes 静态界面语言设置为 `zh`，加入小马AI中文增强说明和启动更新辅助脚本，备份后修改启动界面、快捷指令、分类、网关、ACP、权限按钮、配对配置和审批相关文案。

Windows 桌面版用户可直接运行：

```powershell
iwr https://useai.live/hermes/install.ps1 -UseBasicParsing | iex
```

macOS、Linux 和 WSL2 用户运行：

```bash
curl -fsSL https://useai.live/hermes/install.sh | bash
```

## 机制

1. `useai.live/hermes` 同时服务两类内容：人看的页面，以及 Hermes 可读取的正文、`agent.json` 和 `latest.json`。
2. Hermes 执行一条安装命令；不要在安装前反复读取 JSON 或探测版本。
3. 安装器自包含当前中文包；若本机没有 Hermes，会先调用官方安装脚本，再继续中文补丁安装。
4. 安装器 4 秒内检测本机 Hermes 版本，0.15.x、0.14.x、0.13.x 使用对应包，失败时使用 legacy 兼容包。
5. 安装器校验包文件的 SHA256 后，把中文增强内容安装到 `~/.xiaoma-hermes/current`。
6. 安装器设置 `display.language=zh`，旧版 Hermes 命令不可用时直接更新 `~/.hermes/config.yaml`。
7. 安装器检测 Hermes 程序目录，备份后修改 `hermes_cli/banner.py`、`hermes_cli/skin_engine.py`、`hermes_cli/tips.py`、`hermes_cli/commands.py`、`hermes_cli/bundles.py`、`hermes_cli/mcp_picker.py`、`hermes_cli/secrets_cli.py`、`acp_adapter/*.py`、`gateway/platforms/*.py`、`plugins/platforms/ntfy/plugin.yaml`、`ui-tui/src/**/*.ts` 等文件，并中文显示启动标题、原版风格点阵标识、快捷指令、工具集、技能分类、网关状态、ACP 权限、配对配置和审批提示。
8. 安装器写入 `~/.hermes/skills/xiaoma-hermes-zh/SKILL.md`，让 Hermes 知道本项目的中文说明、边界和更新方式。
9. 可选启动更新由 `~/.xiaoma-hermes/bin/hermes` 包装命令完成：启动前检查 `latest.json`，有新版本就执行同一个安装器，再启动原 Hermes。

## 文件结构

```text
web/
  index.html                 # useai.live/hermes 页面
  details.html               # 详细说明页
  agent.json                 # Hermes 读取的任务清单
  latest.json                # 版本入口
  platforms.json             # Windows/macOS/Linux 入口和桌面版策略
  install.sh                 # 一键安装器
  install.ps1                # Windows PowerShell 一键入口
  install.command            # macOS 双击入口
  tools/xiaoma-hermes        # 更新与状态辅助脚本
  packages/0.15.x/zh-CN/     # Hermes 0.15.x 中文增强包
  packages/0.14.x/zh-CN/     # Hermes 0.14.x 中文增强包
  packages/0.13.x/zh-CN/     # Hermes 0.13.x 中文增强包
  packages/legacy/zh-CN/     # 旧版兼容包
scripts/check_release.sh     # 本地自检
```

## 安装

```bash
curl -fsSL https://useai.live/hermes/install.sh | bash
```

本地测试时可以改成：

```bash
XIAOMA_HERMES_BASE_URL=http://127.0.0.1:4173 bash web/install.sh
```

## 多语言说明

网站页面保持中文；其他语言说明仅在 GitHub 仓库提供：

- [English](README.en.md)
- [日本語](README.ja.md)
- [한국어](README.ko.md)
