---
name: zero-zero-three-hermes-language-management
description: Hermes project localization workflow for automatically scanning, classifying, translating, patching, validating, consistency-checking, exporting model translation requests, autofixing locale-key gaps, and migrating user-visible language strings to i18n keys. Use when the user asks Hermes/Codex to localize Hermes or a Hermes-derived project into Chinese, Japanese, Korean, English, or another target language; to re-scan after upstream updates; to replace remaining English UI/CLI/TUI/Web strings; to check multilingual locale consistency; to run a one-command localization pipeline; or to maintain a localization map and i18n key migration plan for future language switching.
---

# 零点零三Hermes语言管理

## Goal

Localize Hermes user-facing text to the requested language while preserving runtime identifiers and agent instructions. Execute the workflow end to end: scan, classify, export translation work, patch or migrate to i18n keys, validate, report, and maintain a baseline so future Hermes updates are handled incrementally.

## Quick Start

1. Determine the target language from the user request. If missing, ask for it.
2. If the repository has `localization-baseline.json`, `docs/zh-localization-map.md`, or another localization map, read it before scanning.
3. Run the scanner. Use JSON for automated patch planning and Markdown for human review:

```bash
python scripts/scan_user_facing_text.py <repo-root> --profile hermes --format json --out localization-candidates.json
python scripts/scan_user_facing_text.py <repo-root> --profile hermes --format markdown --out localization-candidates.md
```

4. Read `references/preserve-patterns.md`.
5. Read the target-language glossary if one exists, such as `references/glossary.zh-CN.md` or `references/glossary.ja-JP.md`.
6. Patch only strings classified as user-facing. Preserve command names, flags, env vars, config keys, IDs, URLs, paths, protocol values, model/provider/tool/skill names, and model-facing skill instructions.
7. Update or create a localization map in the repo, recording every changed file and field category.
8. Validate with project-appropriate commands.
9. Generate a report with `scripts/render_localization_report.py`.
10. Create or update `localization-baseline.json` with `scripts/update_localization_baseline.py`.
11. If the project uses locale files or the user wants language switching, run Multilingual Consistency Mode and i18n Key Migration Mode.

## One-Command Pipeline

Use this mode when the user asks to handle a Hermes update end to end or wants a single command that produces all review artifacts.

```bash
python scripts/run_localization_pipeline.py . \
  --target-locale zh-CN \
  --mode both \
  --out-dir localization-work
```

The pipeline creates scan, delta, patch-plan, i18n migration, translation-request, consistency, and summary artifacts. It does not rewrite source code. Add `--surfaces tui web cli` for a focused pass. Add `--autofix-locales` to plan missing locale-key fixes. Add `--apply --autofix-locales` only after confirming deterministic locale key additions are desired.

Use the generated `localization-work/translation-request.json` as the model-facing translation batch, then review and apply returned translations through the existing patch or migration plan.

## Adaptive Update Mode

Use this mode after Hermes is updated and an existing baseline is available. It should be the default when `localization-baseline.json` exists.

```bash
python scripts/scan_user_facing_text.py . --profile hermes --format json --out localization-scan-new.json
python scripts/diff_localization_scan.py \
  --baseline localization-baseline.json \
  --scan localization-scan-new.json \
  --out localization-delta.json \
  --summary localization-delta.md
python scripts/generate_patch_plan.py \
  --input localization-delta.json \
  --language zh-CN \
  --translation-memory translation-memory.json \
  --out localization-patch-plan.json \
  --markdown localization-patch-plan.md
```

Then patch only:

1. `new_candidates`: newly discovered user-facing strings.
2. `changed_candidates`: existing locations whose source text changed.
3. `still_untranslated`: candidates previously left pending/review after confirming they are user-facing.

Do not re-translate `moved_candidates`; update their recorded location through the next baseline update. Mark `removed_candidates` as removed in the next baseline.

Before editing, read `localization-patch-plan.json`. Patch low-risk items directly, patch medium-risk items while preserving every `preserve_tokens` entry, and inspect high-risk items before changing them.

After patching and validation:

```bash
python scripts/update_localization_baseline.py \
  --scan localization-scan-new.json \
  --baseline localization-baseline.json \
  --language zh-CN \
  --repo . \
  --out localization-baseline.json
```

Use the requested target language in `--language`.

## Hermes Workflow

Use this order for Hermes and Hermes forks:

1. If `localization-baseline.json` exists, run Adaptive Update Mode first.
2. If no baseline exists, run a full scan.
3. Patch Python CLI/gateway/tool strings.
4. Patch TUI TypeScript strings.
5. Patch Web source strings.
6. Rebuild Web if `web/src/**` changed so `hermes_cli/web_dist` is refreshed.
7. Re-scan or diff again for remaining user-visible English.
8. Run validation.
9. Update the baseline.

Recommended commands from repo root:

```bash
python scripts/scan_user_facing_text.py . --profile hermes --format json --out localization-candidates.json
python scripts/scan_user_facing_text.py . --profile hermes --format markdown --out localization-candidates.md
git diff --name-only -- '*.py' | xargs -r python3 -m py_compile
npm_config_script_shell=/bin/bash npm --prefix ui-tui run typecheck
npm_config_script_shell=/bin/bash npm --prefix web run build
git diff --check
```

If tests assert old English copy, do not blindly update all tests. Update only tests that intentionally cover user-visible localized output.

## Translation Rules

- Translate UI labels, buttons, dialogs, toasts, headings, status text, warnings, errors, empty states, help text, CLI prompts, and gateway messages sent to users.
- Keep placeholders intact: `{name}`, `{count}`, `%s`, `$VAR`, `${value}`, `{0}`, `<path>`.
- Keep command examples executable.
- Do not translate external provider output or subprocess stdout/stderr unless Hermes itself authored that text.
- Do not translate `SKILL.md` bodies used as model instructions unless the user explicitly asks to localize documentation rather than runtime UI.
- Prefer source-level changes. Avoid patching `dist`, `build`, `web_dist`, or generated assets unless the repo's build process regenerates them.

## Automatic Patching Behavior

When the user asks to automatically replace strings, proceed without proposing every individual translation. Still protect high-risk strings:

- If a candidate includes a command, config key, env var, URL, path, model ID, provider ID, or protocol value, translate only surrounding prose.
- If a string is model-facing prompt/instruction content, skip it and record it in the report.
- If a file is generated, patch the source file and rebuild.
- If a string's purpose is unclear, leave it unchanged and list it under "needs review".

Use this candidate priority:

1. In update mode, patch `new_candidates` and `changed_candidates` before doing any full-scan work.
2. Generate `localization-patch-plan.json`.
3. Patch `low` risk plan items first.
4. Patch `medium` risk items by translating prose around protected tokens.
5. Inspect `high` risk and `review_then_translate` items and patch only when clearly user-facing.
6. Do not patch `skip-*` candidates unless the user explicitly requests documentation or test localization.

## Patch Plan and Translation Memory

Generate a patch plan from either a full scan or an update delta:

```bash
python scripts/generate_patch_plan.py \
  --input localization-delta.json \
  --language zh-CN \
  --translation-memory translation-memory.json \
  --out localization-patch-plan.json \
  --markdown localization-patch-plan.md
```

If there is no `translation-memory.json`, proceed without it. If one exists, reuse `translation_memory_hit` exactly unless local grammar requires minor adjustment. Keep all `preserve_tokens` unchanged.

Translation memory shape:

```json
{
  "zh-CN": {
    "Start chatting": "开始聊天"
  },
  "ja-JP": {
    "Start chatting": "チャットを開始"
  }
}
```

After applying translations, add stable repeated source strings and their final translations to `translation-memory.json` when the repository owner wants persistent terminology. Do not add secrets, user data, URLs with credentials, or external provider output to translation memory.

If the baseline contains `translated_text` fields, update memory with:

```bash
python scripts/update_translation_memory.py \
  --memory translation-memory.json \
  --input localization-baseline.json \
  --language zh-CN
```

## Multilingual Consistency Mode

Use this mode when Hermes already has locale resources or after migrating hardcoded text into i18n keys.

```bash
python scripts/check_i18n_consistency.py \
  --locales-dir locales \
  --source-locale en \
  --format markdown \
  --out i18n-consistency.md
python scripts/check_i18n_consistency.py \
  --locales-dir locales \
  --source-locale en \
  --format json \
  --out i18n-consistency.json
```

Treat `missing-key`, `empty-value`, and `placeholder-mismatch` as blockers before claiming a locale is complete. Treat `identical-to-source`, `likely-untranslated`, and `extra-key` as review items. Use `--target-locales zh-CN ja-JP` for a focused check and `--fail-on errors` in CI.

For deterministic missing-key repair, generate a fix plan:

```bash
python scripts/apply_locale_consistency_fixes.py \
  --locales-dir locales \
  --source-locale en \
  --out locale-consistency-fixes.json \
  --markdown locale-consistency-fixes.md
```

Only add `--apply` when the user wants the script to write locale files. This script fills missing keys from the source locale by default, so follow it with translation-request export and review before considering the target language complete.

## Translation Request Mode

Use this mode when the next step is model translation rather than direct manual editing.

```bash
python scripts/export_translation_request.py \
  --input localization-patch-plan.json \
  --target-language "Simplified Chinese" \
  --target-locale zh-CN \
  --glossary references/glossary.zh-CN.md \
  --out translation-request.json \
  --prompt-out translation-request.md
```

The request JSON includes source text, file context, risk, action, preserve tokens, and response schema. Ask the model to return JSON only, then verify placeholders before applying the translations.

## i18n Key Migration Mode

Use this mode when the user wants durable language switching instead of one-off hardcoded replacements.

1. Read `references/i18n-migration-patterns.md`.
2. Generate or refresh a scan, delta, or patch plan.
3. Generate a migration plan:

```bash
python scripts/generate_i18n_migration_plan.py \
  --input localization-patch-plan.json \
  --namespace auto \
  --source-locale en \
  --target-locale zh-CN \
  --translation-memory translation-memory.json \
  --out i18n-migration-plan.json \
  --markdown i18n-migration-plan.md
```

4. Inspect the repository for its existing i18n helper and locale-file layout.
5. Add source and target locale entries before replacing runtime strings.
6. Replace only approved `replace_with_i18n_key` items with the local helper pattern.
7. Inspect `inspect_before_migration` items before editing; skip model-facing or ambiguous strings.
8. Run Multilingual Consistency Mode and project validation.

Do not invent a new i18n runtime unless the user explicitly requests it. If no helper exists, report the required integration points and keep the migration plan as the handoff artifact.

## CI Gate Mode

Use these commands in CI or release checks:

```bash
python scripts/check_i18n_consistency.py --locales-dir locales --source-locale en --fail-on errors
python scripts/run_localization_pipeline.py . --target-locale zh-CN --mode both --out-dir localization-work --skip-consistency
```

The first command blocks missing keys, empty values, and placeholder mismatches. The second command refreshes localization artifacts for review; keep it non-mutating in CI unless the workflow opens a bot PR.

## Reporting

At the end, summarize:

- Target language.
- Files changed by surface: CLI, gateway, TUI, Web, tools, docs/map.
- Validation commands and results.
- Remaining English categories intentionally preserved.
- Any low-confidence candidates left for review.

Keep the final report concise and do not claim all English is gone. Say that all scanned user-facing candidates were handled, and list intentional remaining English categories.

Generate an artifact report when useful:

```bash
git diff --name-only > localization-changed-files.txt
python scripts/render_localization_report.py \
  --language zh-CN \
  --repo . \
  --candidates localization-candidates.json \
  --changed-files localization-changed-files.txt \
  --validation "py_compile: passed" \
  --validation "ui-tui typecheck: passed" \
  --validation "web build: passed" \
  --validation "git diff --check: passed" \
  --out localization-report.md
```

Create/update a baseline:

```bash
python scripts/update_localization_baseline.py \
  --scan localization-candidates.json \
  --language zh-CN \
  --repo . \
  --out localization-baseline.json
```

When updating an existing baseline, pass `--baseline localization-baseline.json`.

## Resources

- `scripts/scan_user_facing_text.py`: deterministic scanner for likely user-facing strings.
- `scripts/diff_localization_scan.py`: compares a fresh scan with a baseline and emits update-only deltas.
- `scripts/generate_patch_plan.py`: creates a risk-ranked patch plan with preserve tokens, memory hits, and validation suggestions.
- `scripts/generate_i18n_migration_plan.py`: converts scan, delta, or patch-plan artifacts into stable i18n key migration work items.
- `scripts/export_translation_request.py`: exports patch or migration plans as model-facing translation batches.
- `scripts/run_localization_pipeline.py`: runs the scan, delta, plan, migration, translation-request, consistency, and summary artifact pipeline.
- `scripts/check_i18n_consistency.py`: checks locale files for missing keys, extra keys, placeholder mismatches, empty values, and likely untranslated text.
- `scripts/apply_locale_consistency_fixes.py`: plans or applies deterministic locale missing-key and empty-value fixes.
- `scripts/update_localization_baseline.py`: creates or refreshes a stable localization baseline.
- `scripts/update_translation_memory.py`: merges reviewed translations into translation memory.
- `scripts/render_localization_report.py`: report renderer for candidate counts, changed files, validation, and review items.
- `references/preserve-patterns.md`: exact preservation and classification policy.
- `references/i18n-migration-patterns.md`: i18n key naming, replacement, and locale consistency policy.
- `references/glossary.zh-CN.md`: Simplified Chinese terminology.
- `references/glossary.ja-JP.md`: Japanese terminology.
- `references/translation-memory.example.json`: example translation memory format.
