#!/usr/bin/env python3
"""Export patch or i18n migration plans as a model-friendly translation request."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


RISK_ORDER = {"low": 0, "medium": 1, "high": 2}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def read_optional(path: Path | None) -> str | None:
    if path and path.exists():
        return path.read_text(encoding="utf-8")
    return None


def plan_items(data: Any) -> list[dict[str, Any]]:
    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    if isinstance(data, dict) and isinstance(data.get("items"), list):
        return [item for item in data["items"] if isinstance(item, dict)]
    return []


def item_text(item: dict[str, Any]) -> str:
    return str(item.get("source_text") or item.get("text") or "")


def should_include(item: dict[str, Any], risks: set[str]) -> bool:
    risk = str(item.get("risk") or "medium")
    if risk not in risks:
        return False
    text = item_text(item)
    return bool(text.strip())


def normalize_item(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": item.get("id"),
        "source_text": item_text(item),
        "context": {
            "path": item.get("path", ""),
            "line": item.get("line", 0),
            "surface": item.get("surface", "unknown"),
            "kind": item.get("kind", ""),
            "label": item.get("label", ""),
            "classification": item.get("classification", "unknown"),
            "risk": item.get("risk", "medium"),
            "action": item.get("action", ""),
            "suggested_key": item.get("suggested_key"),
        },
        "preserve_tokens": item.get("preserve_tokens") or [],
        "existing_translation": item.get("translation_memory_hit") or item.get("target_locale_value"),
        "requirements": [
            "Translate only user-facing prose.",
            "Preserve every token in preserve_tokens exactly.",
            "Do not translate commands, flags, model IDs, provider IDs, URLs, paths, or config keys.",
            "Keep placeholders in the translated text with the same spelling and count.",
        ],
    }


def build_request(
    data: Any,
    source_language: str,
    target_language: str,
    target_locale: str,
    risks: set[str],
    max_items: int,
    glossary: str | None,
) -> dict[str, Any]:
    raw_items = [item for item in plan_items(data) if should_include(item, risks)]
    raw_items.sort(key=lambda item: (RISK_ORDER.get(str(item.get("risk") or "medium"), 1), str(item.get("path", "")), int(item.get("line") or 0)))
    if max_items > 0:
        raw_items = raw_items[:max_items]
    return {
        "schema": "zero-zero-three.translation-request",
        "source_language": source_language,
        "target_language": target_language,
        "target_locale": target_locale,
        "instructions": [
            "Return JSON only.",
            "Return one translation per input item.",
            "Use natural, concise product UI language for the target locale.",
            "Keep protected tokens and placeholders unchanged.",
            "If an item is unsafe or model-facing, return skip=true with a short reason.",
        ],
        "response_schema": {
            "translations": [
                {
                    "id": "same id as input item",
                    "translated_text": "target-language translation with placeholders preserved",
                    "skip": False,
                    "reason": "",
                }
            ]
        },
        "glossary": glossary,
        "items": [normalize_item(item) for item in raw_items],
    }


def write_prompt(request: dict[str, Any]) -> str:
    return "\n".join(
        [
            "# Translation Request",
            "",
            f"Source language: {request['source_language']}",
            f"Target language: {request['target_language']} ({request['target_locale']})",
            "",
            "Return JSON matching `response_schema`. Preserve every protected token.",
            "",
            "```json",
            json.dumps(request, ensure_ascii=False, indent=2),
            "```",
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Export a localization plan as a model translation request.")
    parser.add_argument("--input", required=True, type=Path, help="Patch plan or i18n migration plan JSON")
    parser.add_argument("--out", required=True, type=Path, help="Output request JSON")
    parser.add_argument("--prompt-out", type=Path, help="Optional Markdown prompt wrapper")
    parser.add_argument("--source-language", default="English")
    parser.add_argument("--target-language", required=True, help="Human-readable target language, e.g. Simplified Chinese")
    parser.add_argument("--target-locale", required=True, help="Target locale code, e.g. zh-CN")
    parser.add_argument("--include-risk", nargs="*", default=["low", "medium"], choices=("low", "medium", "high"))
    parser.add_argument("--max-items", type=int, default=200, help="Maximum items to include. Use 0 for no limit.")
    parser.add_argument("--glossary", type=Path, help="Optional target-language glossary")
    args = parser.parse_args()

    data = load_json(args.input)
    request = build_request(
        data,
        source_language=args.source_language,
        target_language=args.target_language,
        target_locale=args.target_locale,
        risks=set(args.include_risk),
        max_items=args.max_items,
        glossary=read_optional(args.glossary),
    )
    args.out.write_text(json.dumps(request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.prompt_out:
        args.prompt_out.write_text(write_prompt(request) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
