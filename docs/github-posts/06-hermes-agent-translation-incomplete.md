# Hermes Agent 汉化不完整怎么办：哪些内容还会英文，怎么反馈补丁

很多用户装完 Hermes Agent 中文补丁后会问：为什么还有 browser、clarify、Start a new session、Gateway restarted successfully 这类英文？

原因很简单：Hermes 的界面文案不在一个文件里。它分散在 TUI、命令系统、网关、插件、审批、工具分类、技能分类、API 服务、错误处理和不同版本的兼容代码里。

## 汉化不完整的常见位置

- 启动页顶部标题和点阵图。
- Available Tools、MCP Servers、Available Skills。
- `/` 开头的快捷指令和解释。
- Telegram、飞书、Discord、Slack 网关消息。
- API Key、provider、model 相关错误。
- 命令审批、危险命令提示、allow once、deny 等按钮。
- cron、memory、skills、doctor、config 相关长文本。

## 为什么同一个补丁在不同电脑效果不同

Hermes Agent 版本更新很快，0.12.0、0.13.x、0.14.x 的文件位置和文案可能不同。小马AI中文增强包会先识别版本，再匹配对应中文包。检测失败时会走 legacy 兼容包。

## 遇到未翻译内容怎么反馈

截图时尽量包含：

1. Hermes 顶部版本号。
2. 未翻译英文原文。
3. 你是在终端、Telegram、飞书、Discord 还是网页里看到的。
4. 执行 `~/.xiaoma-hermes/bin/xiaoma-hermes status` 的结果。

## 参考

- 小马AI Hermes 中文增强包：https://github.com/fresh-claw/hermes-zh-cn
- 官方 Hermes Agent 仓库：https://github.com/NousResearch/hermes-agent
- 日文字体与多语言相关反馈：https://github.com/NousResearch/hermes-agent/issues/30756
