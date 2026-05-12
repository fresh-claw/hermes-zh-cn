# Xiaoma AI Hermes Chinese Enhancement Pack

[中文主页](README.md)

This repository provides a Chinese enhancement pack for [Hermes Agent](https://github.com/NousResearch/hermes-agent).

Users can send this sentence to Hermes:

```text
请访问 useai.live/hermes 安装汉化补丁
```

Hermes can read the public page, find the installation instruction, and run the installer:

```bash
curl -fsSL https://useai.live/hermes/install.sh | bash
```

## What It Does

The installer detects the local Hermes version, installs official Hermes first if Hermes is missing, then applies the matching Chinese enhancement package.

It sets `display.language=zh`, installs a Xiaoma AI helper skill, adds a startup update helper, and applies backed-up patches for Hermes UI text that is not yet covered by the official language setting.

## Coverage

- Startup title changed to Chinese: `爱马仕机器人`.
- Original-style dotted emblem retained.
- Slash command descriptions translated.
- Tool categories and skill categories translated.
- Common TUI prompts and runtime progress messages translated.
- Hermes `0.2` to `0.12` legacy versions are supported.
- Current `0.13.x` package is supported.

## Boundaries

- It does not read user conversations.
- It does not read API keys.
- It does not modify model responses.
- It does not modify raw output returned by third-party tools.

## Files

```text
web/install.sh               Installer
web/latest.json              Version metadata
web/packages/0.13.x/zh-CN/   Current package
web/packages/legacy/zh-CN/   Legacy package
tools/xiaoma-hermes          Status and update helper
```

The website remains Chinese. This English document is published only on GitHub.
