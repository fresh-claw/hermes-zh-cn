# Hermes Agent Windows 新手避坑：PowerShell、WSL2、中文显示和命令卡住

Windows 用户安装 Hermes Agent，最容易遇到三类问题：PowerShell 看不懂、路径不一致、命令卡住。

## 官方推荐怎么装

官方 README 里写得很明确：Windows 原生支持还处于 early beta。PowerShell 可以安装，但更稳定的方案通常是 WSL2。新手如果没有特别原因，建议先走 WSL2。

PowerShell 安装命令：

```powershell
iex (irm https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1)
```

WSL2 安装命令：

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

中文补丁安装命令：

```bash
curl -fsSL https://useai.live/hermes/install.sh | bash
```

## Windows 常见问题

- `/new` 或 `/reset` 后进入选择菜单，无法继续输入。
- PowerShell 字体或编码导致中文显示不舒服。
- 原生 Windows 路径和 WSL2 路径不是同一套环境。
- 已经在 PowerShell 装过，又在 WSL2 装一次，结果不知道自己启动的是哪一个 Hermes。

## 新手建议

先选一个环境，不要 PowerShell 和 WSL2 来回切。能用 WSL2 就优先 WSL2。安装中文补丁后，重启 Hermes 再判断是否生效。

## 参考

- 官方 Windows 安装说明：https://github.com/NousResearch/hermes-agent#quick-install
- Windows `/new`、`/reset` 卡住反馈：https://github.com/NousResearch/hermes-agent/issues/30768
- 小马AI Hermes 中文增强包：https://github.com/fresh-claw/hermes-zh-cn
