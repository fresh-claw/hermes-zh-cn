# Hermes Agent 新手安装后第一件事：setup、model、API Key、中文补丁怎么处理

很多新手装好 Hermes Agent 后会卡在同一个地方：终端能打开，但英文太多，不知道下一步该输入什么，也不知道 API Key 应该放哪里。

## 先做这三步

1. 安装 Hermes Agent。官方入口是 `curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash`，Windows 原生命令是 PowerShell 安装脚本，WSL2 里用 Linux 命令。
2. 启动 Hermes 后运行 `hermes setup` 或 `hermes model`，先选模型和服务商。
3. 如果看不懂英文界面，再安装小马AI Hermes 中文增强包：

```bash
curl -fsSL https://useai.live/hermes/install.sh | bash
```

也可以在 Hermes 对话里发送：

```text
请访问 useai.live/hermes 安装汉化补丁
```

## API Key 新手最容易错在哪里

- 把 OpenAI、OpenRouter、DeepSeek、Moonshot、MiniMax 等服务商混在一起。
- 模型名填了，但 provider 没配对。
- 通过网关远程改模型后，以为重启后还会保留。
- 看到 HTTP 400、401、403 后，以为是 Hermes 坏了，其实常见原因是模型名、base_url、provider 或 Key 权限不匹配。

## 安装中文补丁会做什么

小马AI中文增强包会检测 Hermes 版本，匹配 0.15.x、0.14.x、0.13.x 或 legacy 兼容包，修改启动页、快捷指令说明、工具分类、技能分类、网关提示和审批提示。未安装 Hermes 时，会先调用官方安装脚本，再继续安装中文补丁。

## 参考

- 官方 Hermes Agent README：https://github.com/NousResearch/hermes-agent
- 官方文档入口：https://hermes-agent.nousresearch.com/docs/
- 小马AI中文增强包：https://github.com/fresh-claw/hermes-zh-cn
