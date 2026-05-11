# 小马AI Hermes 中文增强包

让用户在 Hermes 对话中发送一句话：

```text
请访问 useai.live/hermes 安装汉化
```

Hermes 读取页面里的机器说明后，可以判断本机版本、获取匹配的中文增强包，并执行安装。安装后会把 Hermes 静态界面语言设置为 `zh`，同时加入小马AI中文增强说明和启动更新辅助脚本。

## 机制

1. `useai.live/hermes` 同时服务两类内容：人看的页面，以及 Hermes 可读取的 `agent.json` 和页面内嵌 JSON。
2. 安装器读取 `latest.json`，按本机 Hermes 版本匹配 `packages/<version>/zh-CN/manifest.json`。
3. 安装器校验包文件的 SHA256 后，把中文增强内容安装到 `~/.xiaoma-hermes/current`。
4. 安装器调用官方命令 `hermes config set display.language zh`，不改 Hermes 主程序。
5. 安装器写入 `~/.hermes/skills/xiaoma-hermes-zh/SKILL.md`，让 Hermes 知道本项目的中文说明、边界和更新方式。
6. 可选启动更新由 `~/.xiaoma-hermes/bin/hermes` 包装命令完成：启动前检查 `latest.json`，有新版本就更新中文包，再启动原 Hermes。

## 文件结构

```text
web/
  index.html                 # useai.live/hermes 页面
  details.html               # 详细说明页
  agent.json                 # Hermes 读取的任务清单
  latest.json                # 版本入口
  install.sh                 # 一键安装器
  tools/xiaoma-hermes        # 更新与状态辅助脚本
  packages/0.13.x/zh-CN/     # 当前中文增强包
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

## English

This repository provides the Xiaoma AI Chinese enhancement pack for Hermes Agent. It keeps Hermes upstream intact, uses the official `display.language=zh` setting, adds a Chinese helper skill, and checks for updated localization files from `useai.live/hermes`.

