#!/usr/bin/env python3
"""Generate a structured localization patch plan.

The plan is an intermediate artifact for the agent. It does not modify files.
It identifies what to translate, what to preserve, risk level, and suggested
validation commands.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any

PLACEHOLDER_RE = re.compile(r"(\{[^{}]+\}|%\([^)]+\)s|%s|\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*)")
ENV_RE = re.compile(r"\b[A-Z][A-Z0-9_]{2,}\b")
URL_RE = re.compile(r"https?://[^\s\"'<>]+|wss?://[^\s\"'<>]+|file://[^\s\"'<>]+")
PATH_RE = re.compile(r"(?:(?:~?/|[A-Za-z]:\\|/)[^\s\"'<>]+)")
COMMAND_RE = re.compile(
    r"(?:^|\s)(?:/[A-Za-z][\w-]*|hermes|npm|python3?|pip|git|uv|systemctl|journalctl|launchctl|sudo|npx|node)(?:\s+[^\n\"']+)?"
)
BACKTICK_RE = re.compile(r"`([^`]+)`")
CONFIG_KEY_RE = re.compile(r"\b[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\b")
MODEL_PROVIDER_RE = re.compile(r"\b[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.:-]+\b|\b[a-zA-Z0-9_.-]+:[a-zA-Z0-9_.:-]+\b")
TECH_LABEL_RE = re.compile(r"\b(?:[A-Za-z][A-Za-z0-9_.-]*\s+){0,3}(?:ID|URL|API|SDK|CLI|OAuth|MCP|JSON|YAML|HTTP|HTTPS|SSE|SSH|STDIO|PID|TTL|DB|UI|TUI)\b")

VALIDATION_BY_SURFACE = {
    "cli": ["python changed files: python3 -m py_compile"],
    "gateway": ["python changed files: python3 -m py_compile", "gateway focused tests if touched"],
    "agent": ["python changed files: python3 -m py_compile", "agent focused tests if touched"],
    "tools": ["python changed files: python3 -m py_compile"],
    "plugin": ["python changed files: python3 -m py_compile"],
    "tui": ["npm_config_script_shell=/bin/bash npm --prefix ui-tui run typecheck"],
    "web": ["npm_config_script_shell=/bin/bash npm --prefix web run build"],
    "locale": ["locale parser/load check if available"],
}


def load_json(path: Path | None, default: Any) -> Any:
    if not path:
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_text(text: str) -> str:
    return " ".join(str(text or "").split())


def text_hash(text: str) -> str:
    return hashlib.sha256(normalize_text(text).encode("utf-8")).hexdigest()[:24]


def extract_preserve_tokens(text: str) -> list[str]:
    tokens: list[str] = []
    for regex in (PLACEHOLDER_RE, URL_RE, PATH_RE, ENV_RE, CONFIG_KEY_RE, MODEL_PROVIDER_RE, COMMAND_RE, TECH_LABEL_RE):
        for match in regex.finditer(text):
            value = match.group(0).strip()
            if value and value not in tokens:
                tokens.append(value)
    for match in BACKTICK_RE.finditer(text):
        value = match.group(1).strip()
        if value and value not in tokens:
            tokens.append(value)
    return tokens


def load_translation_memory(path: Path | None, language: str) -> dict[str, str]:
    raw = load_json(path, {}) if path else {}
    if not isinstance(raw, dict):
        return {}
    if language in raw and isinstance(raw[language], dict):
        return {str(k): str(v) for k, v in raw[language].items()}
    return {str(k): str(v) for k, v in raw.items() if isinstance(v, str)}


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


def iter_plan_candidates(data: Any) -> list[tuple[str, dict[str, Any]]]:
    if isinstance(data, list):
        return [("scan", item) for item in data if isinstance(item, dict)]
    if not isinstance(data, dict):
        return []
    items: list[tuple[str, dict[str, Any]]] = []
    for section in ("new_candidates", "changed_candidates", "still_untranslated"):
        for item in data.get(section, []) or []:
            if isinstance(item, dict):
                items.append((section, candidate_from_delta_item(item, section)))
    return items


def risk_for(candidate: dict[str, Any], preserve_tokens: list[str], source: str) -> tuple[str, list[str]]:
    reasons: list[str] = []
    classification = str(candidate.get("classification", ""))
    text = str(candidate.get("text", ""))
    path = str(candidate.get("path", ""))
    surface = str(candidate.get("surface", ""))
    if source == "still_untranslated" or classification == "review":
        reasons.append("requires review")
    if preserve_tokens:
        reasons.append("contains protected tokens")
    if len(text) > 180:
        reasons.append("long text")
    if "prompt" in path.lower():
        reasons.append("possible prompt file")
    if surface in {"agent", "plugin"} and len(text) > 80:
        reasons.append("may affect agent/tool behavior")
    if classification == "translate" and not reasons:
        return "low", []
    if reasons == ["contains protected tokens"]:
        return "medium", reasons
    return "high" if any(r in reasons for r in ("requires review", "possible prompt file", "may affect agent/tool behavior")) else "medium", reasons


def action_for(candidate: dict[str, Any], risk: str, preserve_tokens: list[str], source: str) -> str:
    classification = str(candidate.get("classification", ""))
    if source == "still_untranslated" or risk == "high":
        return "review_then_translate"
    if classification == "mixed-preserve" or preserve_tokens:
        return "translate_preserving_tokens"
    return "translate"


def validation_for(surface: str) -> list[str]:
    return VALIDATION_BY_SURFACE.get(surface, ["git diff --check"])


def make_plan_item(
    candidate: dict[str, Any],
    source: str,
    language: str,
    memory: dict[str, str],
) -> dict[str, Any]:
    text = str(candidate.get("text") or candidate.get("source_text") or "")
    preserve_tokens = extract_preserve_tokens(text)
    risk, risk_reasons = risk_for(candidate, preserve_tokens, source)
    action = action_for(candidate, risk, preserve_tokens, source)
    surface = str(candidate.get("surface", "unknown"))
    memory_hit = memory.get(text) or memory.get(normalize_text(text))
    item = {
        "id": text_hash("\0".join([
            str(candidate.get("path", "")),
            str(candidate.get("line", "")),
            surface,
            str(candidate.get("label", "")),
            text,
        ])),
        "source": source,
        "path": candidate.get("path", ""),
        "line": candidate.get("line", 0),
        "surface": surface,
        "kind": candidate.get("kind", ""),
        "label": candidate.get("label", ""),
        "classification": candidate.get("classification", "unknown"),
        "source_text": text,
        "target_language": language,
        "action": action,
        "risk": risk,
        "risk_reasons": risk_reasons,
        "preserve_tokens": preserve_tokens,
        "translation_memory_hit": memory_hit,
        "suggested_validation": validation_for(surface),
    }
    if candidate.get("delta_previous_texts"):
        item["previous_texts"] = candidate["delta_previous_texts"]
    if candidate.get("delta_previous_locations"):
        item["previous_locations"] = candidate["delta_previous_locations"]
    return item


def write_markdown(plan: dict[str, Any]) -> str:
    lines = [
        "# Localization Patch Plan",
        "",
        f"- Target language: {plan.get('target_language')}",
        f"- Item count: {len(plan.get('items', []))}",
        "",
        "## Summary",
        "",
    ]
    for key, value in sorted(plan.get("summary", {}).get("counts_by_risk", {}).items()):
        lines.append(f"- `{key}` risk: {value}")
    lines.extend(["", "## Items", "", "| File | Line | Risk | Action | Text | Preserve |", "|---|---:|---|---|---|---|"])
    for item in plan.get("items", []):
        text = str(item.get("source_text", "")).replace("|", "\\|").replace("\n", "\\n")
        if len(text) > 140:
            text = text[:137] + "..."
        preserve = ", ".join(item.get("preserve_tokens") or [])
        if len(preserve) > 80:
            preserve = preserve[:77] + "..."
        lines.append(
            f"| `{item.get('path')}` | {item.get('line')} | `{item.get('risk')}` | `{item.get('action')}` | {text} | {preserve} |"
        )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a localization patch plan from scan or delta JSON.")
    parser.add_argument("--input", required=True, type=Path, help="scan JSON list or delta JSON object")
    parser.add_argument("--out", required=True, type=Path, help="Output patch plan JSON")
    parser.add_argument("--markdown", type=Path, help="Optional markdown patch plan")
    parser.add_argument("--language", required=True, help="Target language, e.g. zh-CN or ja-JP")
    parser.add_argument("--translation-memory", type=Path, help="Optional translation-memory JSON")
    parser.add_argument("--max-risk", choices=("low", "medium", "high"), default="high", help="Maximum risk to include")
    parser.add_argument("--include-review", action="store_true", help="Include review/still_untranslated items")
    args = parser.parse_args()

    data = load_json(args.input, {})
    memory = load_translation_memory(args.translation_memory, args.language)
    risk_rank = {"low": 0, "medium": 1, "high": 2}
    max_rank = risk_rank[args.max_risk]

    items = []
    for source, candidate in iter_plan_candidates(data):
        if source == "still_untranslated" and not args.include_review:
            continue
        plan_item = make_plan_item(candidate, source, args.language, memory)
        if risk_rank[plan_item["risk"]] <= max_rank:
            items.append(plan_item)

    risk_counts = Counter(item["risk"] for item in items)
    action_counts = Counter(item["action"] for item in items)
    surface_counts = Counter(item["surface"] for item in items)
    validation = sorted({cmd for item in items for cmd in item.get("suggested_validation", [])})
    plan = {
        "schema": "zero-zero-three.hermes-localization-patch-plan",
        "target_language": args.language,
        "source": str(args.input),
        "summary": {
            "total_items": len(items),
            "counts_by_risk": dict(sorted(risk_counts.items())),
            "counts_by_action": dict(sorted(action_counts.items())),
            "counts_by_surface": dict(sorted(surface_counts.items())),
            "suggested_validation": validation,
        },
        "items": sorted(items, key=lambda item: (risk_rank[item["risk"]], item.get("surface", ""), item.get("path", ""), int(item.get("line") or 0))),
    }
    args.out.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.write_text(write_markdown(plan) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
