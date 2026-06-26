#!/usr/bin/env python3
"""Create or update a localization baseline from scanner output.

The baseline records stable fingerprints for candidates so future Hermes
updates can be handled incrementally.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

BASELINE_VERSION = 1


def load_json(path: Path, default: Any) -> Any:
    if not path or not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_text(text: str) -> str:
    return " ".join(str(text or "").split())


def digest(value: str, length: int = 16) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:length]


def item_key(candidate: dict[str, Any]) -> str:
    parts = [
        str(candidate.get("path", "")),
        str(candidate.get("surface", "")),
        str(candidate.get("kind", "")),
        str(candidate.get("label", "")),
        digest(normalize_text(str(candidate.get("text", "")))),
    ]
    return digest("\0".join(parts), 24)


def text_hash(candidate: dict[str, Any]) -> str:
    return digest(normalize_text(str(candidate.get("text", ""))), 24)


def make_item(candidate: dict[str, Any], status: str, existing: dict[str, Any] | None = None) -> dict[str, Any]:
    existing = existing or {}
    now = datetime.now(timezone.utc).isoformat()
    first_seen = existing.get("first_seen_at") or now
    item = {
        "key": item_key(candidate),
        "text_hash": text_hash(candidate),
        "path": candidate.get("path", ""),
        "line": candidate.get("line", 0),
        "surface": candidate.get("surface", "unknown"),
        "kind": candidate.get("kind", ""),
        "label": candidate.get("label", ""),
        "source_text": candidate.get("text", ""),
        "classification": candidate.get("classification", "unknown"),
        "reason": candidate.get("reason", ""),
        "status": status,
        "first_seen_at": first_seen,
        "last_seen_at": now,
    }
    for field in ("target_language", "translated_text", "notes"):
        if field in existing:
            item[field] = existing[field]
    return item


def main() -> int:
    parser = argparse.ArgumentParser(description="Create or update a localization baseline.")
    parser.add_argument("--scan", required=True, type=Path, help="JSON output from scan_user_facing_text.py")
    parser.add_argument("--baseline", type=Path, help="Existing baseline to update")
    parser.add_argument("--out", required=True, type=Path, help="Output baseline JSON")
    parser.add_argument("--language", required=True, help="Target language, e.g. zh-CN or ja-JP")
    parser.add_argument("--repo", default="", help="Repository name or path")
    parser.add_argument(
        "--translated-status",
        choices=("translated", "preserved", "review", "pending"),
        default="translated",
        help="Status assigned to scan items in the new baseline",
    )
    parser.add_argument(
        "--preserve-classes",
        nargs="*",
        default=["mixed-preserve"],
        help="Classes that should default to preserved instead of translated",
    )
    args = parser.parse_args()

    scan = load_json(args.scan, [])
    if not isinstance(scan, list):
        raise SystemExit("--scan must contain a JSON list")

    old = load_json(args.baseline, {}) if args.baseline else {}
    old_items = old.get("items", []) if isinstance(old, dict) else []
    old_by_key = {
        str(item.get("key")): item
        for item in old_items
        if isinstance(item, dict) and item.get("key")
    }
    seen_keys: set[str] = set()
    items: list[dict[str, Any]] = []
    preserve_classes = set(args.preserve_classes or [])

    for candidate in scan:
        if not isinstance(candidate, dict):
            continue
        key = item_key(candidate)
        existing = old_by_key.get(key)
        if candidate.get("classification") in preserve_classes:
            status = existing.get("status", "preserved") if existing else "preserved"
        else:
            status = existing.get("status", args.translated_status) if existing else args.translated_status
        item = make_item(candidate, status=status, existing=existing)
        seen_keys.add(key)
        items.append(item)

    for item in old_items:
        if not isinstance(item, dict):
            continue
        key = str(item.get("key", ""))
        if key and key not in seen_keys:
            removed = dict(item)
            removed["status"] = "removed"
            removed["removed_at"] = datetime.now(timezone.utc).isoformat()
            items.append(removed)

    output = {
        "schema": "zero-zero-three.hermes-localization-baseline",
        "version": BASELINE_VERSION,
        "language": args.language,
        "repo": args.repo,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "items": sorted(items, key=lambda item: (item.get("path", ""), int(item.get("line") or 0), item.get("key", ""))),
    }
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
