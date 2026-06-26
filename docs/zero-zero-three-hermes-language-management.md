# 零点零三 Hermes 语言管理 Skill

`zero-zero-three-hermes-language-management` 是一个面向 Hermes / Hermes fork 的本地化 skill。它帮助 agent 自动扫描用户可见文案、生成翻译计划、维护多语言 locale、一致性检查，并把硬编码文案迁移到稳定的 i18n key。

当前建议作为 Beta / v0.1.0 使用。

## 功能

- 扫描 CLI、TUI、Web、gateway、tools 等用户可见文案。
- 基于 baseline 做 Hermes 更新后的增量检测。
- 生成风险分级 patch plan，保护命令、路径、URL、变量、模型 ID、provider ID。
- 生成 i18n key 迁移计划。
- 检查多语言 locale key、占位符、空值和疑似未翻译文本。
- 导出适合大模型处理的翻译请求 JSON。
- 一键生成扫描、迁移、翻译和一致性检查报告。
- 可选补齐缺失 locale key，默认 dry-run，不自动改源码。

## 安装

把 skill 文件夹复制到 Hermes / Codex 可发现的 skills 目录：

```bash
mkdir -p ~/.agents/skills
cp -R zero-zero-three-hermes-language-management ~/.agents/skills/
```

如果使用 Codex 默认 skill 目录，也可以复制到：

```bash
mkdir -p ~/.codex/skills
cp -R zero-zero-three-hermes-language-management ~/.codex/skills/
```

## 一键 Pipeline

在 Hermes 项目根目录运行：

```bash
python ~/.agents/skills/zero-zero-three-hermes-language-management/scripts/run_localization_pipeline.py . \
  --target-locale zh-CN \
  --mode both \
  --out-dir localization-work
```

常用输出：

- `localization-work/localization-scan.json`
- `localization-work/localization-patch-plan.json`
- `localization-work/i18n-migration-plan.json`
- `localization-work/translation-request.json`
- `localization-work/i18n-consistency.json`
- `localization-work/pipeline-report.md`

## 多语言一致性检查

```bash
python ~/.agents/skills/zero-zero-three-hermes-language-management/scripts/check_i18n_consistency.py \
  --locales-dir locales \
  --source-locale en \
  --format markdown \
  --out i18n-consistency.md
```

CI 中可以阻断缺失 key、空值、占位符不一致：

```bash
python ~/.agents/skills/zero-zero-three-hermes-language-management/scripts/check_i18n_consistency.py \
  --locales-dir locales \
  --source-locale en \
  --fail-on errors
```

## i18n Key 迁移

```bash
python ~/.agents/skills/zero-zero-three-hermes-language-management/scripts/generate_i18n_migration_plan.py \
  --input localization-patch-plan.json \
  --namespace auto \
  --source-locale en \
  --target-locale zh-CN \
  --out i18n-migration-plan.json \
  --markdown i18n-migration-plan.md
```

迁移脚本只生成计划，不直接改源码。真正替换源码前，需要让 Hermes agent 识别项目已有的 `t(...)`、`gettext`、locale loader 或前端 i18n helper。

## 翻译请求导出

```bash
python ~/.agents/skills/zero-zero-three-hermes-language-management/scripts/export_translation_request.py \
  --input localization-patch-plan.json \
  --target-language "Simplified Chinese" \
  --target-locale zh-CN \
  --glossary ~/.agents/skills/zero-zero-three-hermes-language-management/references/glossary.zh-CN.md \
  --out translation-request.json \
  --prompt-out translation-request.md
```

返回的翻译结果必须再次校验占位符和保留 token，不能直接盲写。

## 安全边界

- 默认只生成计划和报告。
- 只有 `apply_locale_consistency_fixes.py --apply` 会写 locale 文件。
- 不自动改源码中的硬编码字符串。
- 不翻译模型提示词、skill 指令、命令、flags、URL、路径、provider/model/tool ID。
- 不把真实密钥、私有 URL、用户数据写入 translation memory。

## 发布前测试

```bash
python -m py_compile zero-zero-three-hermes-language-management/scripts/*.py
python tests/smoke_test.py
```
