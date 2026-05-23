# Hermes Agent 网关收不到消息怎么办：Telegram、飞书、Discord、Slack 新手排查

Hermes Agent 很强的一点是可以通过 Telegram、Discord、Slack、WhatsApp、Signal 等消息入口使用。但新手最常见的问题也是网关：机器人没回、重启后模型变了、平台一直报错。

## 先判断是哪一类问题

1. 机器人完全不回：先看 gateway 是否启动。
2. 重启网关后模型又变回旧模型：检查 `/model` 是否持久保存。
3. Discord 明明禁用了还在连接：看插件配置和平台凭据。
4. Telegram 或飞书能收到部分消息，但任务中断：看网关重启提示和日志。

## 新手排查顺序

```bash
hermes gateway status
hermes gateway restart
hermes doctor
```

如果通过手机端远程使用，建议先保证终端里的 Hermes 能正常对话，再配置网关。终端本身不通时，不要急着修 Telegram 或飞书。

## 模型切换的坑

上游 issue 提到：通过网关执行 `/model deepseek-v4-pro` 后，可能改的是当前会话，网关重启后仍回到旧配置。新手看到“已切换模型”后容易误判，以为永久生效。遇到这种情况，优先确认配置文件里的默认模型。

## 汉化补丁如何帮到这里

中文增强包会翻译网关状态、重启、配对、审批、平台配置和错误提示，让新手能看懂“正在重启网关”“会话继续”“没有配置 token”等提示。

## 参考

- 官方 Messaging Gateway 文档：https://hermes-agent.nousresearch.com/docs/user-guide/messaging
- Gateway `/model` 不持久反馈：https://github.com/NousResearch/hermes-agent/issues/30781
- Discord 禁用后仍连接反馈：https://github.com/NousResearch/hermes-agent/issues/30736
- 小马AI Hermes 中文增强包：https://github.com/fresh-claw/hermes-zh-cn
