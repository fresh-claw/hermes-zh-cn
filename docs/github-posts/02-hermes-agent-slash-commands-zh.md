# Hermes Agent 斜杠命令中文说明：/new、/retry、/undo、/model、/topic 到底做什么

很多用户第一次在 Hermes Agent 里输入 `/`，看到一长串英文命令就不敢点。其实新手先记住几个高频命令就够用。

## 高频命令中文解释

| 命令 | 中文意思 | 适合什么时候用 |
| --- | --- | --- |
| `/new` 或 `/reset` | 开一个新会话 | 当前对话乱了，想重新开始 |
| `/retry` | 重试上一条消息 | 回复不满意，想让 Hermes 再来一次 |
| `/undo` | 撤回上一轮用户/助手消息 | 发错内容，想回到上一步 |
| `/model` | 切换模型 | 想从一个模型换成另一个模型 |
| `/topic` | 管理 Telegram 私聊主题会话 | 在 Telegram 里分开不同任务 |
| `/compress` | 压缩上下文 | 长对话变慢或上下文太多 |
| `/usage` | 查看用量 | 想知道当前上下文和消耗情况 |
| `/stop` | 停止当前任务 | Hermes 正在运行，但你想打断 |

## Windows 用户要注意

上游已有 issue 反馈：Windows PowerShell 里 `/reset` 和 `/new` 可能进入交互菜单后卡住。新手遇到这种情况，先关闭 PowerShell 重新启动 Hermes；更稳的方案是用 WSL2。

## 汉化补丁如何帮到这里

中文增强包会把常见斜杠命令说明翻译成中文，并补充更符合中文用户理解的描述。这样新手输入 `/` 后，不需要先猜英文含义。

## 参考

- 官方 CLI 与 Messaging Quick Reference：https://github.com/NousResearch/hermes-agent#cli-vs-messaging-quick-reference
- Windows `/new`、`/reset` 卡住反馈：https://github.com/NousResearch/hermes-agent/issues/30768
- 小马AI Hermes 中文增强包：https://github.com/fresh-claw/hermes-zh-cn
