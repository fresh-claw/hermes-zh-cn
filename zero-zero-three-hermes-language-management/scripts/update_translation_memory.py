#!/usr/bin/env python3
"""Merge stable translations into translation-memory.json.

Input can be a baseline JSON with items containing `translated_text`, or a
simple JSON list/object containing `source_text` and `translated_text` pairs.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

SECRETISH_RE = re.compile(r"(token|secret|password|credential|api[_ -]?key)", re.I)
URL_WITH_QUERY_RE = re.compile(r"https?://[^\s\"']+[?&][^\s\"']+")


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_text(text: str) -> str:
    return " ".join(str(text or "").split())


def is_safe_memory_pair(source: str, translated: str) -> bool:
    if not source or not translated:
        return False
    if len(source) > 240 or len(translated) > 300:
        return False
    if SECRETISH_RE.search(source) or SECRETISH_RE.search(translated):
        return False
    if URL_WITH_QUERY_RE.search(source) or URL_WITH_QUERY_RE.search(translated):
        return False
    return True


def extract_pairs(data: Any) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    if isinstance(data, dict) and isinstance(data.get("items"), list):
        iterable = data["items"]
    elif isinstance(data, list):
        iterable = data
    elif isinstance(data, dict):
        iterable = [
            {"source_text": key, "translated_text": value}
            for key, value in data.items()
            if isinstance(value, str)
        ]
    else:
        iterable = []

    for item in iterable:
        if not isinstance(item, dict):
            continue
        source = normalize_text(str(item.get("source_text") or item.get("source") or ""))
        translated = normalize_text(str(item.get("translated_text") or item.get("translation") or ""))
        if is_safe_memory_pair(source, translated):
            pairs.append((source, translated))
    return pairs


def main() -> int:
    parser = argparse.ArgumentParser(description="Update translation-memory.json from translated pairs.")
    parser.add_argument("--memory", required=True, type=Path, help="Translation memory JSON to update")
    parser.add_argument("--input", required=True, type=Path, help="Baseline or translation pairs JSON")
    parser.add_argument("--language", required=True, help="Target language key, e.g. zh-CN or ja-JP")
    parser.add_argument("--out", type=Path, help="Output path. Defaults to --memory")
    args = parser.parse_args()

    memory = load_json(args.memory, {})
    if not isinstance(memory, dict):
        memory = {}
    bucket = memory.setdefault(args.language, {})
    if not isinstance(bucket, dict):
        bucket = {}
        memory[args.language] = bucket

    pairs = extract_pairs(load_json(args.input, {}))
    added = 0
    updated = 0
    for source, translated in pairs:
        if source in bucket:
            if bucket[source] != translated:
                bucket[source] = translated
                updated += 1
        else:
            bucket[source] = translated
            added += 1

    out = args.out or args.memory
    out.write_text(json.dumps(memory, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"added": added, "updated": updated, "total": len(bucket)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
