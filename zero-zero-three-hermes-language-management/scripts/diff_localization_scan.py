#!/usr/bin/env python3
"""Compare a fresh localization scan with a baseline.

Outputs the delta needed after a Hermes update:
- new_candidates: text not seen in the baseline
- moved_candidates: same text and surface moved to another location
- changed_candidates: same location/label but changed text
- removed_candidates: baseline items no longer present
- still_untranslated: baseline items still marked pending/review
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_text(text: str) -> str:
    return " ".join(str(text or "").split())


def digest(value: str, length: int = 16) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:length]


def text_hash(obj: dict[str, Any]) -> str:
    return str(obj.get("text_hash") or digest(normalize_text(str(obj.get("text") or obj.get("source_text") or "")), 24))


def candidate_key(candidate: dict[str, Any]) -> str:
    parts = [
        str(candidate.get("path", "")),
        str(candidate.get("surface", "")),
        str(candidate.get("kind", "")),
        str(candidate.get("label", "")),
        digest(normalize_text(str(candidate.get("text", "")))),
    ]
    return digest("\0".join(parts), 24)


def location_key(obj: dict[str, Any]) -> str:
    return "\0".join([
        str(obj.get("path", "")),
        str(obj.get("surface", "")),
        str(obj.get("kind", "")),
        str(obj.get("label", "")),
    ])


def text_surface_key(obj: dict[str, Any]) -> str:
    return "\0".join([
        str(obj.get("surface", "")),
        str(obj.get("kind", "")),
        str(obj.get("label", "")),
        text_hash(obj),
    ])


def normalize_candidate(candidate: dict[str, Any]) -> dict[str, Any]:
    output = dict(candidate)
    output["key"] = candidate_key(candidate)
    output["text_hash"] = text_hash(candidate)
    return output


def summarize(delta: dict[str, Any]) -> dict[str, Any]:
    counts = {}
    for key, value in delta.items():
        if isinstance(value, list):
            counts[key] = len(value)
    classes = Counter()
    surfaces = Counter()
    for item in delta.get("new_candidates", []) + delta.get("changed_candidates", []):
        classes[str(item.get("classification", "unknown"))] += 1
        surfaces[str(item.get("surface", "unknown"))] += 1
    return {
        "counts": counts,
        "new_or_changed_by_class": dict(sorted(classes.items())),
        "new_or_changed_by_surface": dict(sorted(surfaces.items())),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Diff a localization scan against a baseline.")
    parser.add_argument("--baseline", required=True, type=Path, help="Baseline JSON from update_localization_baseline.py")
    parser.add_argument("--scan", required=True, type=Path, help="Fresh scan JSON from scan_user_facing_text.py")
    parser.add_argument("--out", required=True, type=Path, help="Output delta JSON")
    parser.add_argument("--summary", type=Path, help="Optional markdown summary output")
    parser.add_argument(
        "--actionable-classes",
        nargs="*",
        default=["translate", "mixed-preserve", "review"],
        help="Candidate classes to include in new/changed actionable deltas",
    )
    args = parser.parse_args()

    baseline = load_json(args.baseline)
    scan_raw = load_json(args.scan)
    if not isinstance(scan_raw, list):
        raise SystemExit("--scan must contain a JSON list")
    if not isinstance(baseline, dict):
        raise SystemExit("--baseline must contain a JSON object")

    scan = [normalize_candidate(c) for c in scan_raw if isinstance(c, dict)]
    baseline_items = [
        item for item in baseline.get("items", [])
        if isinstance(item, dict) and item.get("status") != "removed"
    ]
    actionable = set(args.actionable_classes or [])

    base_by_key = {str(item.get("key")): item for item in baseline_items if item.get("key")}
    scan_by_key = {str(item.get("key")): item for item in scan if item.get("key")}
    base_by_text_surface: dict[str, list[dict[str, Any]]] = {}
    base_by_location: dict[str, list[dict[str, Any]]] = {}
    for item in baseline_items:
        base_by_text_surface.setdefault(text_surface_key(item), []).append(item)
        base_by_location.setdefault(location_key(item), []).append(item)

    new_candidates: list[dict[str, Any]] = []
    moved_candidates: list[dict[str, Any]] = []
    changed_candidates: list[dict[str, Any]] = []

    for candidate in scan:
        if candidate["key"] in base_by_key:
            continue
        moved_from = base_by_text_surface.get(text_surface_key(candidate), [])
        if moved_from:
            moved_candidates.append({
                "candidate": candidate,
                "previous_locations": [
                    {
                        "path": item.get("path"),
                        "line": item.get("line"),
                        "status": item.get("status"),
                    }
                    for item in moved_from
                ],
            })
            continue
        changed_from = [
            item for item in base_by_location.get(location_key(candidate), [])
            if text_hash(item) != text_hash(candidate)
        ]
        if changed_from:
            if candidate.get("classification") in actionable:
                changed_candidates.append({
                    "candidate": candidate,
                    "previous_texts": [
                        {
                            "source_text": item.get("source_text"),
                            "text_hash": text_hash(item),
                            "status": item.get("status"),
                        }
                        for item in changed_from
                    ],
                })
            continue
        if candidate.get("classification") in actionable:
            new_candidates.append(candidate)

    removed_candidates = [
        item for item in baseline_items
        if str(item.get("key")) not in scan_by_key
        and not base_by_text_surface.get(text_surface_key(item), [])
    ]
    still_untranslated = [
        item for item in baseline_items
        if item.get("status") in {"pending", "review"}
        and str(item.get("key")) in scan_by_key
    ]

    delta = {
        "schema": "zero-zero-three.hermes-localization-delta",
        "baseline_language": baseline.get("language"),
        "baseline_repo": baseline.get("repo"),
        "new_candidates": new_candidates,
        "moved_candidates": moved_candidates,
        "changed_candidates": changed_candidates,
        "removed_candidates": removed_candidates,
        "still_untranslated": still_untranslated,
    }
    delta["summary"] = summarize(delta)
    args.out.write_text(json.dumps(delta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if args.summary:
        summary = delta["summary"]
        lines = [
            "# Localization Delta Summary",
            "",
            f"- Baseline language: {delta.get('baseline_language')}",
            f"- Baseline repo: {delta.get('baseline_repo')}",
            "",
            "## Counts",
            "",
        ]
        for key, count in sorted(summary["counts"].items()):
            lines.append(f"- `{key}`: {count}")
        lines.extend(["", "## New or Changed by Surface", ""])
        for key, count in sorted(summary["new_or_changed_by_surface"].items()):
            lines.append(f"- `{key}`: {count}")
        lines.extend(["", "Patch `new_candidates` and `changed_candidates`; update locations for `moved_candidates`; mark `removed_candidates` as removed in the next baseline."])
        args.summary.write_text("\n".join(lines) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
