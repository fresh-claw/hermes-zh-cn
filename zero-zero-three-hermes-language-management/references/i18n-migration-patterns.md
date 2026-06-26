# i18n Key Migration Patterns

Use this reference when the user wants language switching, durable localization, or migration away from hardcoded UI text.

## Migration Order

1. Run a fresh scan or adaptive delta.
2. Generate an i18n key migration plan.
3. Inspect the repository for the existing i18n mechanism before editing:
   - Python helpers such as `t(...)`, `_ (...)`, `gettext`, or a local locale loader.
   - TypeScript helpers such as `t(...)`, `i18n.t(...)`, `<Trans>`, or context hooks.
   - Locale resource layout such as `locales/en.json`, `locales/zh-CN.yaml`, or `web/src/i18n/**`.
4. Add source-locale and target-locale entries first.
5. Replace only approved hardcoded runtime strings with the existing helper pattern.
6. Run `check_i18n_consistency.py` and project validation.

For a full artifact pass, use:

```bash
python scripts/run_localization_pipeline.py . --target-locale zh-CN --mode both --out-dir localization-work
```

Review `localization-work/i18n-migration-plan.json` and `localization-work/translation-request.json` before editing source.

## Key Style

- Prefer stable semantic keys: `cli.startNewSession`, `tui.modelPicker.selectProvider`, `web.settings.language`.
- Use surface namespaces when no local convention exists: `cli`, `gateway`, `tui`, `web`, `tools`.
- Do not encode the target language in the key.
- Avoid keys based on file line numbers; they churn after upstream updates.
- Reuse the same key for identical text only when the meaning and grammar are identical in context.

## Replacement Policy

- Follow local code patterns. Do not invent a new i18n runtime when the repository already has one.
- Keep placeholders intact in locale values and in code formatting arguments.
- Keep commands, flags, model/provider IDs, URLs, and config keys out of translation keys unless they are part of surrounding display prose.
- For ambiguous or model-facing strings, leave the hardcoded text unchanged and record it for review.

## Locale Consistency

After migration, every target locale must have the same keys as the source locale, unless the project intentionally allows partial locale bundles. Placeholder sets must match exactly across locales.

Use `apply_locale_consistency_fixes.py` to plan or add missing keys, then translate the copied source values before release.
