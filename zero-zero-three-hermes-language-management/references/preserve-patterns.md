# Preservation and Classification Policy

## Translate

- CLI output from `print`, `input`, `Prompt.ask`, `Confirm.ask`, `console.print`, `_cprint`, `cprint`.
- TUI/Web display strings: labels, headings, buttons, toasts, dialog titles, placeholders, aria labels, tooltips, empty states, badges, status text.
- Slash command descriptions shown to users.
- Gateway/platform messages sent to Telegram, Discord, Matrix, WhatsApp, QQ, Slack, or web clients.
- Error/warning text authored by Hermes.

## Preserve

- Command names and examples: `/model`, `/help`, `hermes gateway install`, `npm ci`.
- Flags and subcommands: `--provider`, `--system`, `status`, `restart`.
- Config keys and YAML paths: `display.language`, `mcp_servers`, `agent.reasoning_effort`.
- Environment variables: `OPENAI_API_KEY`, `HERMES_LANGUAGE`, `BWS_ACCESS_TOKEN`.
- Model/provider/tool/skill IDs: `qwen/qwen3`, `openai-codex`, `browser_click`, `github:create_issue`.
- URLs, URI schemes, file paths, database paths, JSON keys, protocol values.
- Package names, binary names, import names, class/function names.
- External provider or subprocess output.
- Tests and fixtures unless assertions deliberately cover user-visible localized copy.
- Comments/docstrings unless they are displayed by argparse/help or generated docs.
- `SKILL.md` instruction bodies and model-facing prompts unless documentation localization is explicitly requested.

## Mixed Strings

Translate prose around protected tokens:

- `Start it with: hermes gateway install` -> `启动命令：hermes gateway install`
- `No project_id configured.` -> `未配置 project_id。`
- `Open this URL in your browser: {url}` -> `在浏览器中打开这个 URL：{url}`

Do not translate the protected token itself.

## Generated Files

Prefer source files:

- Web: edit `web/src/**`, then run `npm --prefix web run build`.
- TUI: edit `ui-tui/src/**`, then run `npm --prefix ui-tui run typecheck`.
- Python: edit source `.py`, then run `python3 -m py_compile`.

Avoid hand-editing minified bundles or generated assets unless no source exists.

## Risk Labels

- `translate`: safe user-facing prose.
- `mixed-preserve`: translate prose but preserve embedded identifiers.
- `review`: likely user-facing but context is ambiguous.
- `skip-identifier`: mostly technical identifier or command.
- `skip-model-facing`: prompt, skill instruction, or agent/tool schema text.
- `skip-generated`: generated output, build product, fixture, or vendored code.

## Scanner Profiles

Use `--profile hermes` for Hermes runtime localization. It skips CI workflows, docs, website, examples, generated directories, and lockfiles by default. Add `--include-ci` or `--include-docs` only when the user explicitly wants those surfaces localized too.

Use `--profile generic` for non-Hermes repositories when the caller wants a broader scan.

Use `--surfaces cli web tui gateway tools agent plugin locale` to narrow a pass. Prefer narrow passes when automatically patching a large repository.

## Baseline and Delta Policy

Maintain `localization-baseline.json` in the target repository after a successful localization pass.

Baseline items use:

- `key`: stable fingerprint from path, surface, kind, label, and normalized source text.
- `text_hash`: normalized source-text hash for move detection.
- `status`: one of `translated`, `preserved`, `review`, `pending`, or `removed`.
- `source_text`: original source string before localization.
- `translated_text`: optional final localized string when it is useful to preserve translation memory.

Delta handling:

- `new_candidates`: automatically translate if class is `translate`; translate prose around protected tokens if `mixed-preserve`.
- `changed_candidates`: re-evaluate and translate because upstream changed the source text.
- `moved_candidates`: do not re-translate when the text hash matches; update the baseline location after validation.
- `removed_candidates`: keep as `removed` in the updated baseline for history.
- `still_untranslated`: revisit only if the user asked for stricter coverage.

Never use the baseline as proof that current source is localized. Always run a fresh scan after patching and before reporting.

## Patch Plan Policy

Use `generate_patch_plan.py` before automatic edits. The patch plan is the execution queue for the agent.

Risk handling:

- `low`: pure user-facing prose. Patch automatically.
- `medium`: contains protected tokens. Translate surrounding prose and preserve every token listed in `preserve_tokens` exactly.
- `high`: possible prompt, long model/tool text, or review item. Inspect before editing; skip if model-facing or ambiguous.

Actions:

- `translate`: replace the source text with target-language prose.
- `translate_preserving_tokens`: preserve every protected token exactly and translate only surrounding language.
- `review_then_translate`: inspect context before patching; record skipped items in the report.

Translation memory:

- Use `translation_memory_hit` when it matches the exact source string and target language.
- Add only stable UI/CLI phrases to `translation-memory.json`.
- Do not store secrets, personal data, URLs containing credentials, or raw external output.
- Use `update_translation_memory.py` only with reviewed translations. Do not treat machine draft translations as memory until they have passed validation.

## Multilingual Consistency Policy

Use `check_i18n_consistency.py` after adding or changing locale resources.

Block release on:

- Missing target-locale keys that exist in the source locale.
- Empty target values.
- Placeholder mismatches between source and target values.

Review but do not automatically fail on:

- Extra target-locale keys.
- Values identical to the source locale.
- Target values that still look like English in CJK/Korean locales.

Use `apply_locale_consistency_fixes.py` only for deterministic repairs. It may add missing keys or fill empty values; it does not translate. Treat copied source text as a pending translation, not as completion.

## i18n Key Migration Policy

Use `generate_i18n_migration_plan.py` when the repository should support future language switching.

- Generate key suggestions from the scan, delta, or patch plan before editing.
- Read `references/i18n-migration-patterns.md` before applying migration changes.
- Follow the repository's existing i18n helper and locale-file structure.
- Add source and target locale entries before replacing hardcoded runtime strings.
- Keep source text in the source locale and translated text in the target locale.
- Do not migrate model-facing prompts, identifiers, command examples, or generated files unless the user explicitly asks for those surfaces.

## Closed Pipeline Policy

Use `run_localization_pipeline.py` when the user asks for an end-to-end update pass.

- The pipeline is non-mutating by default.
- It may write only artifact files under `--out-dir`.
- It may apply deterministic locale fixes only with both `--autofix-locales` and `--apply`.
- It must not rewrite source strings automatically from a model response without agent review.
- Use `export_translation_request.py` to create model batches, then verify placeholder parity before applying returned translations.
