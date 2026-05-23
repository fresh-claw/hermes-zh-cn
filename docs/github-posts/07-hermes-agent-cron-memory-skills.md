# Hermes Agent 自动任务、记忆和技能新手指南：cron、memory、skills 怎么理解

Hermes Agent 不单是聊天工具。它有自动任务、记忆和技能系统。但这些概念对新手很抽象，尤其是看到 cron、memory、skills、toolsets 这些英文时。

## 用中文理解三个概念

- `cron`：定时任务。比如每天早上让 Hermes 汇总信息，或者每周检查一次项目。
- `memory`：长期记忆。Hermes 会保存对你有用的偏好和项目背景。
- `skills`：可复用能力。复杂任务完成后，Hermes 可以沉淀成后续可调用的技能。

## 新手先怎么用

1. 先用普通对话把一个任务跑通。
2. 如果这个任务每周都要做，再考虑 cron。
3. 如果你反复解释同一件事，再考虑 memory。
4. 如果同类任务重复出现，再考虑 skills。

## 常见误区

- 一上来就配置很多自动任务，出了问题不知道是哪一个触发。
- 以为记忆会自动理解所有上下文，实际仍需要清楚说明任务边界。
- 看到技能列表很多英文，不知道哪个能用。
- `/cron list` 输出太密集，看不清每个任务。

## 汉化补丁如何帮到这里

中文增强包会翻译技能分类、工具分类、cron、memory、doctor、config 等常见说明，让新手先知道每块功能在干什么。

## 参考

- 官方 README 的 Scheduled automations、Skills System、Memory：https://github.com/NousResearch/hermes-agent
- `/cron list` 显示拥挤反馈：https://github.com/NousResearch/hermes-agent/issues/30782
- 小马AI Hermes 中文增强包：https://github.com/fresh-claw/hermes-zh-cn
