#!/usr/bin/env python3
"""Plan or apply deterministic locale-key consistency fixes."""

from __future__ import annotations

import argparse
import json
from copy import deepcopy
from pathlib import Path
from typing import Any

from check_i18n_consistency import discover_locales, flatten, load_locale_file, pick_locale


LOCALE_EXTENSIONS = (".yaml", ".yml", ".json")


def find_locale_file(locales_dir: Path, locale: str) -> Path | None:
    for suffix in LOCALE_EXTENSIONS:
        candidate = locales_dir / f"{locale}{suffix}"
        if candidate.exists():
            return candidate
    lower = locale.lower()
    for path in locales_dir.iterdir() if locales_dir.exists() else []:
        if path.is_file() and path.suffix.lower() in LOCALE_EXTENSIONS and path.stem.lower() == lower:
            return path
    return None


def set_nested(data: dict[str, Any], dotted_key: str, value: str) -> None:
    current = data
    parts = dotted_key.split(".")
    for part in parts[:-1]:
        existing = current.get(part)
        if not isinstance(existing, dict):
            existing = {}
            current[part] = existing
        current = existing
    current[parts[-1]] = value


def quote_yaml(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def dump_yaml(data: dict[str, Any], indent: int = 0) -> str:
    lines: list[str] = []
    pad = " " * indent
    for key, value in data.items():
        if isinstance(value, dict):
            lines.append(f"{pad}{key}:")
            lines.append(dump_yaml(value, indent + 2))
        else:
            lines.append(f"{pad}{key}: {quote_yaml('' if value is None else str(value))}")
    return "\n".join(line for line in lines if line != "")


def write_locale_file(path: Path, data: dict[str, Any]) -> None:
    if path.suffix.lower() == ".json":
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    else:
        path.write_text(dump_yaml(data) + "\n", encoding="utf-8")


def value_for_missing(source_value: str, fill: str) -> str:
    if fill == "empty":
        return ""
    if fill == "todo":
        return f"TODO: {source_value}"
    return source_value


def build_fix_plan(
    locales_dir: Path,
    source_locale: str,
    target_locales: list[str] | None,
    fill: str,
    fix_empty: bool,
) -> dict[str, Any]:
    locales = discover_locales(locales_dir)
    source_name = pick_locale(locales, source_locale)
    if source_name is None:
        return {
            "schema": "zero-zero-three.locale-consistency-fix-plan",
            "status": "error",
            "error": f"source locale not found: {source_locale}",
            "changes": [],
        }
    source = locales[source_name]
    targets = target_locales or [locale for locale in sorted(locales) if locale != source_name]
    changes: list[dict[str, Any]] = []
    for requested in targets:
        locale = pick_locale(locales, requested) or requested
        target = locales.get(locale, {})
        source_keys = set(source)
        target_keys = set(target)
        for key in sorted(source_keys - target_keys):
            changes.append(
                {
                    "locale": locale,
                    "key": key,
                    "action": "add-missing-key",
                    "value": value_for_missing(source[key], fill),
                    "source_value": source[key],
                }
            )
        if fix_empty:
            for key in sorted(source_keys & target_keys):
                if not str(target.get(key, "")).strip():
                    changes.append(
                        {
                            "locale": locale,
                            "key": key,
                            "action": "fill-empty-value",
                            "value": value_for_missing(source[key], fill),
                            "source_value": source[key],
                        }
                    )
    return {
        "schema": "zero-zero-three.locale-consistency-fix-plan",
        "status": "planned",
        "source_locale": source_name,
        "target_locales": targets,
        "fill": fill,
        "fix_empty": fix_empty,
        "summary": {"change_count": len(changes)},
        "changes": changes,
    }


def apply_fix_plan(locales_dir: Path, plan: dict[str, Any]) -> dict[str, Any]:
    by_locale: dict[str, list[dict[str, Any]]] = {}
    for change in plan.get("changes", []):
        by_locale.setdefault(str(change["locale"]), []).append(change)

    applied: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    source_file = find_locale_file(locales_dir, str(plan.get("source_locale", "")))
    source_suffix = source_file.suffix if source_file else ".yaml"

    for locale, changes in by_locale.items():
        path = find_locale_file(locales_dir, locale)
        if path is None:
            path = locales_dir / f"{locale}{source_suffix}"
            data: dict[str, Any] = {}
        else:
            data = deepcopy(load_locale_file(path))
            if not isinstance(data, dict):
                skipped.append({"locale": locale, "path": str(path), "reason": "locale root is not a mapping"})
                continue
        current_flat = flatten(data)
        for change in changes:
            key = str(change["key"])
            action = str(change["action"])
            if action == "add-missing-key" and key in current_flat:
                skipped.append({**change, "path": str(path), "reason": "key already exists"})
                continue
            if action == "fill-empty-value" and str(current_flat.get(key, "")).strip():
                skipped.append({**change, "path": str(path), "reason": "key is no longer empty"})
                continue
            set_nested(data, key, str(change["value"]))
            applied.append({**change, "path": str(path)})
        write_locale_file(path, data)
    return {"applied": applied, "skipped": skipped}


def write_markdown(plan: dict[str, Any], result: dict[str, Any] | None = None) -> str:
    lines = [
        "# Locale Consistency Fix Plan",
        "",
        f"- Status: `{plan.get('status')}`",
        f"- Source locale: `{plan.get('source_locale', '')}`",
        f"- Changes: {len(plan.get('changes', []))}",
        "",
        "| Locale | Key | Action | Value |",
        "|---|---|---|---|",
    ]
    for change in plan.get("changes", []):
        value = str(change.get("value", "")).replace("|", "\\|").replace("\n", "\\n")
        if len(value) > 100:
            value = value[:97] + "..."
        lines.append(f"| `{change.get('locale')}` | `{change.get('key')}` | `{change.get('action')}` | {value} |")
    if result is not None:
        lines.extend(
            [
                "",
                "## Apply Result",
                "",
                f"- Applied: {len(result.get('applied', []))}",
                f"- Skipped: {len(result.get('skipped', []))}",
            ]
        )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Plan or apply deterministic locale consistency fixes.")
    parser.add_argument("--locales-dir", type=Path, default=Path("locales"))
    parser.add_argument("--source-locale", default="en")
    parser.add_argument("--target-locales", nargs="*", help="Defaults to all non-source locales.")
    parser.add_argument("--fill", choices=("source", "empty", "todo"), default="source")
    parser.add_argument("--fix-empty", action="store_true", help="Also fill empty target values.")
    parser.add_argument("--apply", action="store_true", help="Write changes. Without this flag, only a plan is produced.")
    parser.add_argument("--out", type=Path, required=True, help="Output JSON plan/result")
    parser.add_argument("--markdown", type=Path, help="Optional Markdown plan/result")
    args = parser.parse_args()

    plan = build_fix_plan(args.locales_dir.resolve(), args.source_locale, args.target_locales, args.fill, args.fix_empty)
    result = apply_fix_plan(args.locales_dir.resolve(), plan) if args.apply and plan.get("status") == "planned" else None
    output = {"plan": plan, "result": result, "applied": bool(args.apply and result is not None)}
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.write_text(write_markdown(plan, result) + "\n", encoding="utf-8")
    return 0 if plan.get("status") != "error" else 1


if __name__ == "__main__":
    raise SystemExit(main())
