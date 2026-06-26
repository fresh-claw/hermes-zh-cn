#!/usr/bin/env python3
"""Check locale files for key, placeholder, and untranslated-text consistency."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any

try:
    import yaml  # type: ignore
except Exception:  # pragma: no cover - optional dependency
    yaml = None


LOCALE_EXTENSIONS = {".json", ".yaml", ".yml"}
PLACEHOLDER_RE = re.compile(
    r"(\{[A-Za-z0-9_.-]+\}|\{[0-9]+\}|%\([^)]+\)[sdif]|%[sdif]|\$\{[^}]+\})"
)
LATIN_WORD_RE = re.compile(r"\b[A-Za-z]{3,}\b")
CJK_RE = re.compile(r"[\u3400-\u9fff]")
KANA_RE = re.compile(r"[\u3040-\u30ff]")
HANGUL_RE = re.compile(r"[\uac00-\ud7af]")


def parse_scalar(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    if " #" in value:
        value = value.split(" #", 1)[0].rstrip()
    return value


def load_simple_yaml(text: str) -> dict[str, Any]:
    """Small YAML mapping parser used when PyYAML is unavailable.

    It supports the common locale-file subset: nested mappings, scalar values,
    and literal/folded block strings. Lists and anchors are intentionally not
    interpreted because locale resources should be key-value data.
    """

    root: dict[str, Any] = {}
    stack: list[tuple[int, dict[str, Any]]] = [(-1, root)]
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        raw = lines[index]
        stripped = raw.strip()
        if not stripped or stripped.startswith("#") or ":" not in stripped:
            index += 1
            continue

        indent = len(raw) - len(raw.lstrip(" "))
        key, value = stripped.split(":", 1)
        key = key.strip().strip("'\"")
        value = value.strip()
        while stack and stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1]

        if value in {"|", "|-", "|+", ">", ">-", ">+"}:
            block_lines: list[str] = []
            join_with = "\n" if value.startswith("|") else " "
            index += 1
            while index < len(lines):
                next_raw = lines[index]
                if next_raw.strip():
                    next_indent = len(next_raw) - len(next_raw.lstrip(" "))
                    if next_indent <= indent:
                        break
                    block_lines.append(next_raw[indent + 2 :])
                else:
                    block_lines.append("")
                index += 1
            parent[key] = join_with.join(block_lines).strip()
            continue

        if not value:
            child: dict[str, Any] = {}
            parent[key] = child
            stack.append((indent, child))
        else:
            parent[key] = parse_scalar(value)
        index += 1
    return root


def load_locale_file(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        data = json.loads(text)
    elif yaml is not None:
        data = yaml.safe_load(text)
    else:
        data = load_simple_yaml(text)
    return data if isinstance(data, dict) else {}


def flatten(data: Any, prefix: str = "") -> dict[str, str]:
    items: dict[str, str] = {}
    if isinstance(data, dict):
        for key, value in data.items():
            next_key = f"{prefix}.{key}" if prefix else str(key)
            items.update(flatten(value, next_key))
        return items
    if isinstance(data, list):
        items[prefix] = json.dumps(data, ensure_ascii=False)
    else:
        items[prefix] = "" if data is None else str(data)
    return items


def file_prefix_for(rel_parts: tuple[str, ...]) -> str:
    if len(rel_parts) <= 1:
        return ""
    stem_parts = list(rel_parts[1:])
    stem_parts[-1] = Path(stem_parts[-1]).stem
    if stem_parts == ["index"]:
        return ""
    return ".".join(stem_parts)


def discover_locales(locales_dir: Path) -> dict[str, dict[str, str]]:
    files = sorted(path for path in locales_dir.rglob("*") if path.suffix.lower() in LOCALE_EXTENSIONS)
    locales: dict[str, dict[str, str]] = {}
    for path in files:
        rel_parts = path.relative_to(locales_dir).parts
        if len(rel_parts) == 1:
            locale = path.stem
            prefix = ""
        else:
            locale = rel_parts[0]
            prefix = file_prefix_for(rel_parts)
        data = flatten(load_locale_file(path))
        target = locales.setdefault(locale, {})
        for key, value in data.items():
            full_key = f"{prefix}.{key}" if prefix else key
            target[full_key] = value
    return locales


def pick_locale(locales: dict[str, dict[str, str]], requested: str) -> str | None:
    if requested in locales:
        return requested
    requested_lower = requested.lower()
    for locale in locales:
        if locale.lower() == requested_lower:
            return locale
    for locale in locales:
        if locale.lower().startswith(requested_lower + "-"):
            return locale
    return None


def placeholders(text: str) -> list[str]:
    seen: list[str] = []
    for match in PLACEHOLDER_RE.finditer(text or ""):
        token = match.group(0)
        if token not in seen:
            seen.append(token)
    return seen


def has_target_script(value: str, locale: str) -> bool:
    lower = locale.lower()
    if lower.startswith("zh"):
        return bool(CJK_RE.search(value))
    if lower.startswith("ja"):
        return bool(CJK_RE.search(value) or KANA_RE.search(value))
    if lower.startswith("ko"):
        return bool(HANGUL_RE.search(value))
    return True


def likely_english(value: str, locale: str) -> bool:
    lower = locale.lower()
    if lower.startswith("en"):
        return False
    stripped = PLACEHOLDER_RE.sub(" ", value or "")
    if not LATIN_WORD_RE.search(stripped):
        return False
    if lower.startswith(("zh", "ja", "ko")):
        return not has_target_script(stripped, locale)
    return False


def add_issue(
    issues: list[dict[str, Any]],
    issue_type: str,
    severity: str,
    locale: str,
    key: str,
    message: str,
    source_value: str | None = None,
    target_value: str | None = None,
    details: dict[str, Any] | None = None,
) -> None:
    issues.append(
        {
            "type": issue_type,
            "severity": severity,
            "locale": locale,
            "key": key,
            "message": message,
            "source_value": source_value,
            "target_value": target_value,
            "details": details or {},
        }
    )


def check_consistency(
    locales: dict[str, dict[str, str]],
    source_locale: str,
    target_locales: list[str] | None,
) -> dict[str, Any]:
    source_name = pick_locale(locales, source_locale)
    if source_name is None:
        return {
            "schema": "zero-zero-three.i18n-consistency-report",
            "status": "error",
            "summary": {"error": f"source locale not found: {source_locale}"},
            "locales": sorted(locales),
            "issues": [],
        }

    source = locales[source_name]
    targets = target_locales or [locale for locale in sorted(locales) if locale != source_name]
    resolved_targets = [pick_locale(locales, locale) or locale for locale in targets]
    issues: list[dict[str, Any]] = []

    source_keys = set(source)
    for locale in resolved_targets:
        if locale not in locales:
            add_issue(issues, "missing-locale", "error", locale, "", f"Locale file set not found: {locale}")
            continue
        target = locales[locale]
        target_keys = set(target)
        for key in sorted(source_keys - target_keys):
            add_issue(issues, "missing-key", "error", locale, key, "Target locale is missing source key.", source.get(key))
        for key in sorted(target_keys - source_keys):
            add_issue(issues, "extra-key", "warning", locale, key, "Target locale has a key not present in source.")
        for key in sorted(source_keys & target_keys):
            source_value = source.get(key, "")
            target_value = target.get(key, "")
            if not str(target_value).strip():
                add_issue(issues, "empty-value", "error", locale, key, "Target value is empty.", source_value, target_value)
            source_placeholders = placeholders(source_value)
            target_placeholders = placeholders(target_value)
            if Counter(source_placeholders) != Counter(target_placeholders):
                add_issue(
                    issues,
                    "placeholder-mismatch",
                    "error",
                    locale,
                    key,
                    "Target placeholders differ from source.",
                    source_value,
                    target_value,
                    {"source_placeholders": source_placeholders, "target_placeholders": target_placeholders},
                )
            if source_value and target_value == source_value and not locale.lower().startswith("en"):
                add_issue(
                    issues,
                    "identical-to-source",
                    "warning",
                    locale,
                    key,
                    "Target value is identical to source.",
                    source_value,
                    target_value,
                )
            elif likely_english(target_value, locale):
                add_issue(
                    issues,
                    "likely-untranslated",
                    "warning",
                    locale,
                    key,
                    "Target value still looks like English.",
                    source_value,
                    target_value,
                )

    counts_by_type = Counter(issue["type"] for issue in issues)
    counts_by_severity = Counter(issue["severity"] for issue in issues)
    status = "fail" if counts_by_severity.get("error") else ("warn" if issues else "pass")
    return {
        "schema": "zero-zero-three.i18n-consistency-report",
        "status": status,
        "source_locale": source_name,
        "target_locales": resolved_targets,
        "summary": {
            "locale_count": len(locales),
            "source_key_count": len(source_keys),
            "issue_count": len(issues),
            "counts_by_type": dict(sorted(counts_by_type.items())),
            "counts_by_severity": dict(sorted(counts_by_severity.items())),
        },
        "locales": sorted(locales),
        "issues": issues,
    }


def write_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# i18n Consistency Report",
        "",
        f"- Status: `{report.get('status')}`",
        f"- Source locale: `{report.get('source_locale', '')}`",
        f"- Target locales: {', '.join(f'`{locale}`' for locale in report.get('target_locales', []))}",
        f"- Issues: {report.get('summary', {}).get('issue_count', 0)}",
        "",
        "## Counts",
        "",
    ]
    for key, value in sorted(report.get("summary", {}).get("counts_by_type", {}).items()):
        lines.append(f"- `{key}`: {value}")
    if not report.get("issues"):
        lines.extend(["", "No consistency issues found."])
        return "\n".join(lines)
    lines.extend(["", "## Issues", "", "| Locale | Key | Severity | Type | Message |", "|---|---|---|---|---|"])
    for issue in report["issues"]:
        key = str(issue.get("key", "")).replace("|", "\\|")
        message = str(issue.get("message", "")).replace("|", "\\|")
        lines.append(
            f"| `{issue.get('locale')}` | `{key}` | `{issue.get('severity')}` | `{issue.get('type')}` | {message} |"
        )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Check consistency across i18n locale files.")
    parser.add_argument("--locales-dir", type=Path, default=Path("locales"), help="Locale directory to scan")
    parser.add_argument("--source-locale", default="en", help="Source locale, e.g. en or en-US")
    parser.add_argument("--target-locales", nargs="*", help="Target locales. Defaults to all non-source locales.")
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    parser.add_argument("--out", type=Path, help="Output file. Defaults to stdout.")
    parser.add_argument(
        "--fail-on",
        choices=("never", "errors", "warnings"),
        default="never",
        help="Exit non-zero when the selected issue level is present.",
    )
    args = parser.parse_args()

    locales = discover_locales(args.locales_dir.resolve())
    report = check_consistency(locales, args.source_locale, args.target_locales)
    output = json.dumps(report, ensure_ascii=False, indent=2) if args.format == "json" else write_markdown(report)
    if args.out:
        args.out.write_text(output + "\n", encoding="utf-8")
    else:
        print(output)

    severity = report.get("summary", {}).get("counts_by_severity", {})
    if args.fail_on == "errors" and severity.get("error"):
        return 1
    if args.fail_on == "warnings" and (severity.get("error") or severity.get("warning")):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
