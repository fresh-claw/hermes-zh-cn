# Hermes Agent 安全授权新手指南：为什么会弹危险命令，curl 安装怎么判断

新手最害怕的提示之一是危险命令授权。比如安装中文补丁、运行脚本、修改配置、执行 Python 管道时，Hermes 可能会要求确认。

## 为什么会弹授权

Hermes 看到命令可能修改本机文件、执行脚本、调用解释器、访问网络时，会提醒你确认。这不是错误，而是安全机制。

常见场景：

- `curl ... | bash`：从网络获取脚本并执行。
- `cat file | python3 ...`：把文件内容交给 Python 处理。
- 修改 `~/.hermes` 或 Hermes 程序目录。
- 重启 gateway 或变更模型配置。

## 怎么判断能不能同意

新手可以按三点看：

1. 来源是不是你主动访问的项目。
2. 命令是不是来自可信页面或仓库。
3. 它要做的事是不是符合你的目标。

小马AI中文增强包的安装入口是：

```bash
curl -fsSL https://useai.live/hermes/install.sh | bash
```

仓库入口是：

```text
https://github.com/fresh-claw/hermes-zh-cn
```

## 中文补丁的边界

中文增强包会修改 Hermes 的界面文案、启动页、快捷指令、网关提示和本地配置，不读取用户对话、API Key、命令历史或工作文件。

## 参考

- 官方 Security 文档入口：https://hermes-agent.nousresearch.com/docs/user-guide/security
- 小马AI Hermes 中文增强包：https://github.com/fresh-claw/hermes-zh-cn
