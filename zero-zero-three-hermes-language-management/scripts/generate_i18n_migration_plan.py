#!/usr/bin/env python3
"""Generate an i18n-key migration plan from localization scan artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any


PLACEHOLDER_RE = re.compile(
    r"(\{[^{}]+\}|%\([^)]+\)[sdif]|%[sdif]|\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*)"
)
URL_RE = re.compile(r"https?://[^\s\"'<>]+|wss?://[^\s\"'<>]+|file://[^\s\"'<>]+")
PATH_RE = re.compile(r"(?:(?:~?/|[A-Za-z]:\\|/)[^\s\"'<>]+)")
BACKTICK_RE = re.compile(r"`([^`]+)`")
WORD_RE = re.compile(r"[A-Za-z][A-Za-z0-9]+|[0-9]+")
NON_KEY_CHAR_RE = re.compile(r"[^A-Za-z0-9_.-]+")
STOP_WORDS = {
    "a",
    "an",
    "and",
    "are",
    "as",
    "at",
    "be",
    "by",
    "for",
    "from",
    "in",
    "is",
    "it",
    "of",
    "on",
    "or",
    "the",
    "this",
    "to",
    "with",
    "your",
}
RISK_RANK = {"low": 0, "medium": 1, "high": 2}


def load_json(path: Path | None, default: Any) -> Any:
    if not path:
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_text(text: str) -> str:
    return " ".join(str(text or "").split())


def short_hash(text: str, length: int = 8) -> str:
    return hashlib.sha256(normalize_text(text).encode("utf-8")).hexdigest()[:length]


def extract_preserve_tokens(text: str) -> list[str]:
    tokens: list[str] = []
    for regex in (PLACEHOLDER_RE, URL_RE, PATH_RE):
        for match in regex.finditer(text):
            value = match.group(0).strip()
            if value and value not in tokens:
                tokens.append(value)
    for match in BACKTICK_RE.finditer(text):
        value = match.group(1).strip()
        if value and value not in tokens:
            tokens.append(value)
    return tokens


def candidate_from_delta_item(item: dict[str, Any], source: str) -> dict[str, Any]:
    if source == "changed_candidates":
        candidate = dict(item.get("candidate") or {})
        candidate["delta_previous_texts"] = item.get("previous_texts") or []
        return candidate
    if source == "moved_candidates":
        candidate = dict(item.get("candidate") or {})
        candidate["delta_previous_locations"] = item.get("previous_locations") or []
        return candidate
    return dict(item)


def iter_candidates(data: Any) -> list[tuple[str, dict[str, Any]]]:
    if isinstance(data, list):
        return [("scan", item) for item in data if isinstance(item, dict)]
    if not isinstance(data, dict):
        return []
    if isinstance(data.get("items"), list):
        return [("patch_plan", item) for item in data["items"] if isinstance(item, dict)]
    if isinstance(data.get("candidates"), list):
        return [("candidates", item) for item in data["candidates"] if isinstance(item, dict)]
    items: list[tuple[str, dict[str, Any]]] = []
    for section in ("new_candidates", "changed_candidates", "still_untranslated"):
        for item in data.get(section, []) or []:
            if isinstance(item, dict):
                items.append((section, candidate_from_delta_item(item, section)))
    return items


def source_text_for(candidate: dict[str, Any]) -> str:
    return str(candidate.get("source_text") or candidate.get("text") or "")


def risk_for(candidate: dict[str, Any]) -> str:
    risk = str(candidate.get("risk") or "")
    if risk in RISK_RANK:
        return risk
    classification = str(candidate.get("classification", ""))
    text = source_text_for(candidate)
    path = str(candidate.get("path", "")).lower()
    if classification == "translate" and len(text) < 140:
        return "low"
    if classification == "mixed-preserve":
        return "medium"
    if "prompt" in path or classification in {"review", "skip-model-facing"}:
        return "high"
    return "medium"


def sanitize_namespace(namespace: str) -> str:
    namespace = NON_KEY_CHAR_RE.sub(".", namespace.strip())
    namespace = re.sub(r"\.+", ".", namespace).strip(".")
    return namespace or "common"


def namespace_for(candidate: dict[str, Any], configured: str) -> str:
    if configured != "auto":
        return sanitize_namespace(configured)
    surface = str(candidate.get("surface") or "common").strip().lower()
    if surface in {"cli", "gateway", "tui", "web", "tools", "agent", "plugin", "locale", "docs", "ci"}:
        return surface
    path = str(candidate.get("path") or "")
    if path.startswith("ui-tui/"):
        return "tui"
    if path.startswith("web/"):
        return "web"
    if path.startswith("hermes_cli/"):
        return "cli"
    return "common"


def key_words(text: str) -> list[str]:
    cleaned = PLACEHOLDER_RE.sub(" ", text)
    cleaned = URL_RE.sub(" ", cleaned)
    cleaned = PATH_RE.sub(" ", cleaned)
    cleaned = BACKTICK_RE.sub(lambda match: " " + match.group(1) + " ", cleaned)
    words = [word for word in WORD_RE.findall(cleaned) if word.lower() not in STOP_WORDS]
    return words[:8]


def camel_case(words: list[str]) -> str:
    if not words:
        return ""
    first = words[0].lower()
    rest = [word[:1].upper() + word[1:].lower() for word in words[1:]]
    return first + "".join(rest)


def make_key(candidate: dict[str, Any], namespace: str, used: Counter[str]) -> str:
    text = source_text_for(candidate)
    suffix = camel_case(key_words(text)) or f"text{short_hash(text, 6)}"
    base = f"{namespace}.{suffix}"
    if len(base) > 80:
        base = f"{namespace}.{suffix[:48]}{short_hash(text, 6)}"
    used[base] += 1
    if used[base] == 1:
        return base
    return f"{base}_{used[base]}"


def load_translation_memory(path: Path | None, locale: str) -> dict[str, str]:
    raw = load_json(path, {}) if path else {}
    if not isinstance(raw, dict):
        return {}
    if locale in raw and isinstance(raw[locale], dict):
        return {str(k): str(v) for k, v in raw[locale].items()}
    return {str(k): str(v) for k, v in raw.items() if isinstance(v, str)}


def replacement_family(path: str) -> str:
    suffix = Path(path).suffix.lower()
    if suffix == ".py":
        return "python"
    if suffix in {".ts", ".tsx", ".js", ".jsx"}:
        return "typescript"
    if suffix in {".json", ".yaml", ".yml"}:
        return "resource"
    return "unknown"


def replacement_guidance(family: str) -> str:
    if family == "python":
        return "Use the repository's existing Python i18n helper, e.g. t('key') or _('key'), and keep placeholders as formatting arguments."
    if family == "typescript":
        return "Use the existing TypeScript/React i18n helper, e.g. t('key') or <Trans i18nKey='key'>, matching local patterns."
    if family == "resource":
        return "Move hardcoded display text into the locale resource key if this file is part of an i18n resource set."
    return "Find the local i18n access pattern before replacing the hardcoded string."


def make_item(
    candidate: dict[str, Any],
    source: str,
    key: str,
    source_locale: str,
    target_locale: str,
    memory: dict[str, str],
) -> dict[str, Any]:
    text = source_text_for(candidate)
    risk = risk_for(candidate)
    preserve_tokens = candidate.get("preserve_tokens") or extract_preserve_tokens(text)
    family = replacement_family(str(candidate.get("path", "")))
    target_value = candidate.get("translation_memory_hit") or memory.get(text) or memory.get(normalize_text(text))
    action = "inspect_before_migration" if risk == "high" else "replace_with_i18n_key"
    return {
        "id": short_hash("\0".join([str(candidate.get("path", "")), str(candidate.get("line", "")), key, text]), 16),
        "source": source,
        "path": candidate.get("path", ""),
        "line": candidate.get("line", 0),
        "surface": candidate.get("surface", "unknown"),
        "kind": candidate.get("kind", ""),
        "label": candidate.get("label", ""),
        "classification": candidate.get("classification", "unknown"),
        "risk": risk,
        "action": action,
        "source_text": text,
        "suggested_key": key,
        "source_locale": source_locale,
        "source_locale_value": text,
        "target_locale": target_locale,
        "target_locale_value": target_value,
        "preserve_tokens": preserve_tokens,
        "replacement_family": family,
        "replacement_guidance": replacement_guidance(family),
        "notes": [
            "Inspect the repository's existing i18n helper before applying this migration.",
            "Add the key to source and target locale files before replacing runtime text.",
            "Preserve every placeholder and protected token exactly.",
        ],
    }


def write_markdown(plan: dict[str, Any]) -> str:
    lines = [
        "# i18n Key Migration Plan",
        "",
        f"- Source locale: `{plan.get('source_locale')}`",
        f"- Target locale: `{plan.get('target_locale')}`",
        f"- Namespace mode: `{plan.get('namespace')}`",
        f"- Item count: {plan.get('summary', {}).get('total_items', 0)}",
        "",
        "## Summary",
        "",
    ]
    for key, value in sorted(plan.get("summary", {}).get("counts_by_risk", {}).items()):
        lines.append(f"- `{key}` risk: {value}")
    lines.extend(
        [
            "",
            "## Items",
            "",
            "| File | Line | Key | Risk | Action | Source text |",
            "|---|---:|---|---|---|---|",
        ]
    )
    for item in plan.get("items", []):
        text = str(item.get("source_text", "")).replace("|", "\\|").replace("\n", "\\n")
        if len(text) > 120:
            text = text[:117] + "..."
        lines.append(
            f"| `{item.get('path')}` | {item.get('line')} | `{item.get('suggested_key')}` | "
            f"`{item.get('risk')}` | `{item.get('action')}` | {text} |"
        )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate an i18n-key migration plan from scan/delta/patch-plan JSON.")
    parser.add_argument("--input", required=True, type=Path, help="Localization scan, delta, or patch-plan JSON")
    parser.add_argument("--out", required=True, type=Path, help="Output migration plan JSON")
    parser.add_argument("--markdown", type=Path, help="Optional markdown migration plan")
    parser.add_argument("--namespace", default="auto", help="Key namespace, or 'auto' to use surface-based namespaces")
    parser.add_argument("--source-locale", default="en", help="Source locale key set, e.g. en")
    parser.add_argument("--target-locale", default="zh-CN", help="Target locale key set, e.g. zh-CN")
    parser.add_argument("--translation-memory", type=Path, help="Optional translation-memory JSON")
    parser.add_argument("--max-risk", choices=("low", "medium", "high"), default="high", help="Maximum risk to include")
    args = parser.parse_args()

    data = load_json(args.input, {})
    memory = load_translation_memory(args.translation_memory, args.target_locale)
    used_keys: Counter[str] = Counter()
    text_context_to_key: dict[str, str] = {}
    items: list[dict[str, Any]] = []
    max_rank = RISK_RANK[args.max_risk]

    for source, candidate in iter_candidates(data):
        text = source_text_for(candidate)
        if not text:
            continue
        risk = risk_for(candidate)
        if RISK_RANK[risk] > max_rank:
            continue
        namespace = namespace_for(candidate, args.namespace)
        context_key = f"{namespace}\0{normalize_text(text)}"
        key = text_context_to_key.get(context_key)
        if not key:
            key = make_key(candidate, namespace, used_keys)
            text_context_to_key[context_key] = key
        items.append(make_item(candidate, source, key, args.source_locale, args.target_locale, memory))

    risk_counts = Counter(item["risk"] for item in items)
    surface_counts = Counter(str(item.get("surface", "unknown")) for item in items)
    action_counts = Counter(item["action"] for item in items)
    plan = {
        "schema": "zero-zero-three.hermes-i18n-key-migration-plan",
        "source": str(args.input),
        "namespace": args.namespace,
        "source_locale": args.source_locale,
        "target_locale": args.target_locale,
        "summary": {
            "total_items": len(items),
            "counts_by_risk": dict(sorted(risk_counts.items())),
            "counts_by_surface": dict(sorted(surface_counts.items())),
            "counts_by_action": dict(sorted(action_counts.items())),
            "required_steps": [
                "Inspect existing i18n helper and locale file layout.",
                "Add source and target locale entries for approved keys.",
                "Replace hardcoded runtime strings with the existing i18n helper.",
                "Run check_i18n_consistency.py and project validation.",
            ],
        },
        "items": sorted(
            items,
            key=lambda item: (
                RISK_RANK[item["risk"]],
                str(item.get("surface", "")),
                str(item.get("path", "")),
                int(item.get("line") or 0),
            ),
        ),
    }
    args.out.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.write_text(write_markdown(plan) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
