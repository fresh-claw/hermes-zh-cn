#!/usr/bin/env python3
"""Render a compact localization report from scanner output and validation notes."""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


def load_candidates(path: Path) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise SystemExit(f"{path} does not contain a candidate list")
    return [item for item in data if isinstance(item, dict)]


def bullets(items: list[str]) -> list[str]:
    return [f"- {item}" for item in items] if items else ["- None recorded"]


def render(args: argparse.Namespace) -> str:
    candidates = load_candidates(args.candidates) if args.candidates else []
    classes = Counter(str(c.get("classification", "unknown")) for c in candidates)
    surfaces = Counter(str(c.get("surface", "unknown")) for c in candidates)
    by_class: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for candidate in candidates:
        by_class[str(candidate.get("classification", "unknown"))].append(candidate)

    changed_files = []
    if args.changed_files:
        changed_files = [
            line.strip()
            for line in args.changed_files.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    lines: list[str] = [
        "# Localization Report",
        "",
        f"- Target language: {args.language}",
        f"- Repository: {args.repo or 'not specified'}",
        f"- Scanner candidates reviewed: {len(candidates)}",
        "",
        "## Changed Files",
        "",
        *bullets([f"`{item}`" for item in changed_files]),
        "",
        "## Candidate Counts",
        "",
    ]

    if classes:
        for key, count in sorted(classes.items()):
            lines.append(f"- `{key}`: {count}")
    else:
        lines.append("- No candidate file supplied")

    lines.extend(["", "## Surface Counts", ""])
    if surfaces:
        for key, count in sorted(surfaces.items()):
            lines.append(f"- `{key}`: {count}")
    else:
        lines.append("- No candidate file supplied")

    lines.extend(["", "## Intentional English / Preserved Tokens", ""])
    preserved = [
        "command names and flags",
        "config keys and environment variables",
        "model/provider/tool/skill identifiers",
        "URLs, paths, JSON fields, and protocol values",
        "external provider or subprocess output",
        "model-facing instructions and skill bodies",
    ]
    lines.extend(f"- {item}" for item in preserved)

    review_items = by_class.get("review", [])[:20]
    lines.extend(["", "## Needs Review", ""])
    if review_items:
        for item in review_items:
            text = str(item.get("text", "")).replace("\n", "\\n")
            if len(text) > 160:
                text = text[:157] + "..."
            lines.append(f"- `{item.get('path')}`:{item.get('line')} {text}")
    else:
        lines.append("- No review candidates recorded")

    lines.extend(["", "## Validation", ""])
    if args.validation:
        lines.extend(f"- {entry}" for entry in args.validation)
    else:
        lines.append("- Validation not recorded")

    lines.extend([
        "",
        "## Notes",
        "",
        "Do not claim that every English token has been removed. Report only that scanned user-facing candidates were handled, and explain any preserved categories.",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Render a localization report.")
    parser.add_argument("--language", required=True, help="Target language, e.g. zh-CN or ja-JP")
    parser.add_argument("--repo", help="Repository path or name")
    parser.add_argument("--candidates", type=Path, help="JSON output from scan_user_facing_text.py")
    parser.add_argument("--changed-files", type=Path, help="Text file containing one changed file per line")
    parser.add_argument("--validation", action="append", help="Validation result line. May be repeated.")
    parser.add_argument("--out", type=Path, help="Output markdown file. Defaults to stdout.")
    args = parser.parse_args()

    output = render(args)
    if args.out:
        args.out.write_text(output + "\n", encoding="utf-8")
    else:
        print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
