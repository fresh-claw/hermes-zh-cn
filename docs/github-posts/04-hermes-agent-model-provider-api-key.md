# Hermes Agent 模型和 API Key 配置：DeepSeek、OpenRouter、自定义接口怎么选

Hermes Agent 支持很多模型服务商，对高手是自由度，对新手就是选择困难。最常见的问题不是安装，而是 provider、model、base_url、api_key 没有配成一组。

## 新手先理解四个词

- `provider`：你用哪家服务商，例如 OpenRouter、DeepSeek、OpenAI、Moonshot。
- `model`：具体模型名，例如某个 deepseek、gpt、kimi、glm 模型。
- `base_url`：接口地址。官方服务商通常不用改，自定义服务商才需要填。
- `api_key`：服务商后台生成的密钥，不同服务商不能混用。

## 新手推荐路径

1. 有 OpenRouter：先用 OpenRouter，模型多，切换方便。
2. 有 DeepSeek：确认 provider 和接口格式是否匹配。
3. 有国内中转：按自定义 OpenAI 兼容接口配置。
4. 还没有 Key：先去模型服务商官网开通，再回 Hermes 配置。

## DeepSeek 相关问题

上游近期有反馈：`provider: deepseek` 搭配某些 DeepSeek 模型时可能返回 HTTP 400，改成自定义 OpenAI 兼容接口后可绕过。这类问题新手很容易误解为“汉化补丁没装好”，其实它属于模型接口配置问题。

## 中文补丁能解决什么，不能解决什么

能解决：英文提示看不懂、命令说明看不懂、启动页和网关提示英文太多。

不能代替：购买 API Key、判断模型服务商是否可用、解决服务商限流、处理 Key 欠费或权限不足。

## 参考

- 官方模型说明入口：https://github.com/NousResearch/hermes-agent#hermes-agent-
- DeepSeek provider HTTP 400 反馈：https://github.com/NousResearch/hermes-agent/issues/30818
- 小马AI Hermes 中文增强包：https://github.com/fresh-claw/hermes-zh-cn
