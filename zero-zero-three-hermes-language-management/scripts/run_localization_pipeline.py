#!/usr/bin/env python3
"""Run the Hermes localization workflow as a deterministic artifact pipeline."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


LANGUAGE_NAMES = {
    "zh": "Simplified Chinese",
    "zh-CN": "Simplified Chinese",
    "zh-Hans": "Simplified Chinese",
    "zh-Hant": "Traditional Chinese",
    "ja": "Japanese",
    "ja-JP": "Japanese",
    "ko": "Korean",
    "ko-KR": "Korean",
    "en": "English",
    "en-US": "English",
}


def script_dir() -> Path:
    return Path(__file__).resolve().parent


def run_step(name: str, command: list[str], cwd: Path) -> dict[str, Any]:
    started = datetime.now(timezone.utc).isoformat()
    proc = subprocess.run(command, cwd=str(cwd), text=True, capture_output=True)
    return {
        "name": name,
        "command": command,
        "returncode": proc.returncode,
        "started_at": started,
        "stdout": proc.stdout[-4000:],
        "stderr": proc.stderr[-4000:],
    }


def require_ok(step: dict[str, Any]) -> None:
    if step["returncode"] != 0:
        cmd = " ".join(step["command"])
        raise RuntimeError(f"Step failed: {step['name']} ({cmd})\n{step.get('stderr') or step.get('stdout')}")


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def maybe_count(path: Path, key: str | None = None) -> int | None:
    if not path.exists():
        return None
    data = load_json(path)
    if isinstance(data, list):
        return len(data)
    if key and isinstance(data, dict):
        value = data.get(key)
        if isinstance(value, list):
            return len(value)
    if isinstance(data, dict) and isinstance(data.get("items"), list):
        return len(data["items"])
    return None


def default_target_language(locale: str) -> str:
    return LANGUAGE_NAMES.get(locale, locale)


def locale_glossary(skill_root: Path, target_locale: str) -> Path | None:
    candidates = [
        skill_root / "references" / f"glossary.{target_locale}.md",
        skill_root / "references" / f"glossary.{target_locale.split('-')[0]}.md",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def write_summary(path: Path, report: dict[str, Any]) -> None:
    lines = [
        "# Localization Pipeline Report",
        "",
        f"- Repository: `{report['repo']}`",
        f"- Target locale: `{report['target_locale']}`",
        f"- Mode: `{report['mode']}`",
        f"- Output directory: `{report['out_dir']}`",
        "",
        "## Artifacts",
        "",
    ]
    for name, value in report.get("artifacts", {}).items():
        if value:
            lines.append(f"- `{name}`: `{value}`")
    lines.extend(["", "## Counts", ""])
    for name, value in report.get("counts", {}).items():
        if value is not None:
            lines.append(f"- `{name}`: {value}")
    lines.extend(["", "## Steps", "", "| Step | Result |", "|---|---|"])
    for step in report.get("steps", []):
        status = "passed" if step["returncode"] == 0 else f"failed ({step['returncode']})"
        lines.append(f"| `{step['name']}` | `{status}` |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the Hermes localization artifact pipeline.")
    parser.add_argument("repo", nargs="?", default=".", type=Path, help="Repository root")
    parser.add_argument("--target-locale", default="zh-CN")
    parser.add_argument("--target-language", help="Human-readable target language")
    parser.add_argument("--source-locale", default="en")
    parser.add_argument("--mode", choices=("hardcoded-replace", "i18n-key-migration", "both"), default="both")
    parser.add_argument("--out-dir", type=Path, default=Path("localization-work"))
    parser.add_argument("--profile", choices=("hermes", "generic"), default="hermes")
    parser.add_argument("--classes", nargs="*", default=["translate", "mixed-preserve", "review"])
    parser.add_argument("--surfaces", nargs="*", help="Optional scan surfaces")
    parser.add_argument("--include-tests", action="store_true")
    parser.add_argument("--include-ci", action="store_true")
    parser.add_argument("--include-docs", action="store_true")
    parser.add_argument("--baseline", type=Path, default=Path("localization-baseline.json"))
    parser.add_argument("--translation-memory", type=Path, default=Path("translation-memory.json"))
    parser.add_argument("--locales-dir", type=Path, default=Path("locales"))
    parser.add_argument("--skip-consistency", action="store_true")
    parser.add_argument("--autofix-locales", action="store_true", help="Plan deterministic locale missing-key fixes.")
    parser.add_argument("--apply", action="store_true", help="Apply deterministic locale fixes when used with --autofix-locales.")
    parser.add_argument("--fail-fast", action="store_true", help="Stop immediately when a sub-step fails.")
    args = parser.parse_args()

    repo = args.repo.resolve()
    skill_scripts = script_dir()
    skill_root = skill_scripts.parent
    out_dir = args.out_dir if args.out_dir.is_absolute() else repo / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    target_language = args.target_language or default_target_language(args.target_locale)

    scan_json = out_dir / "localization-scan.json"
    scan_md = out_dir / "localization-scan.md"
    delta_json = out_dir / "localization-delta.json"
    delta_md = out_dir / "localization-delta.md"
    patch_plan_json = out_dir / "localization-patch-plan.json"
    patch_plan_md = out_dir / "localization-patch-plan.md"
    migration_json = out_dir / "i18n-migration-plan.json"
    migration_md = out_dir / "i18n-migration-plan.md"
    consistency_json = out_dir / "i18n-consistency.json"
    consistency_md = out_dir / "i18n-consistency.md"
    locale_fix_json = out_dir / "locale-consistency-fixes.json"
    locale_fix_md = out_dir / "locale-consistency-fixes.md"
    translation_request_json = out_dir / "translation-request.json"
    translation_request_md = out_dir / "translation-request.md"
    pipeline_json = out_dir / "pipeline-report.json"
    pipeline_md = out_dir / "pipeline-report.md"

    steps: list[dict[str, Any]] = []

    def call(name: str, command: list[str]) -> dict[str, Any]:
        step = run_step(name, command, repo)
        steps.append(step)
        if args.fail_fast:
            require_ok(step)
        return step

    scan_base = [
        sys.executable,
        str(skill_scripts / "scan_user_facing_text.py"),
        str(repo),
        "--profile",
        args.profile,
        "--classes",
        *args.classes,
    ]
    if args.surfaces:
        scan_base.extend(["--surfaces", *args.surfaces])
    if args.include_tests:
        scan_base.append("--include-tests")
    if args.include_ci:
        scan_base.append("--include-ci")
    if args.include_docs:
        scan_base.append("--include-docs")

    require_ok(call("scan-json", [*scan_base, "--format", "json", "--out", str(scan_json)]))
    require_ok(call("scan-markdown", [*scan_base, "--format", "markdown", "--out", str(scan_md)]))

    baseline = args.baseline if args.baseline.is_absolute() else repo / args.baseline
    plan_input = scan_json
    if baseline.exists():
        require_ok(
            call(
                "diff-baseline",
                [
                    sys.executable,
                    str(skill_scripts / "diff_localization_scan.py"),
                    "--baseline",
                    str(baseline),
                    "--scan",
                    str(scan_json),
                    "--out",
                    str(delta_json),
                    "--summary",
                    str(delta_md),
                ],
            )
        )
        plan_input = delta_json

    patch_cmd = [
        sys.executable,
        str(skill_scripts / "generate_patch_plan.py"),
        "--input",
        str(plan_input),
        "--language",
        args.target_locale,
        "--out",
        str(patch_plan_json),
        "--markdown",
        str(patch_plan_md),
        "--include-review",
    ]
    memory = args.translation_memory if args.translation_memory.is_absolute() else repo / args.translation_memory
    if memory.exists():
        patch_cmd.extend(["--translation-memory", str(memory)])
    require_ok(call("patch-plan", patch_cmd))

    translation_source = patch_plan_json
    if args.mode in {"i18n-key-migration", "both"}:
        migration_cmd = [
            sys.executable,
            str(skill_scripts / "generate_i18n_migration_plan.py"),
            "--input",
            str(patch_plan_json),
            "--namespace",
            "auto",
            "--source-locale",
            args.source_locale,
            "--target-locale",
            args.target_locale,
            "--out",
            str(migration_json),
            "--markdown",
            str(migration_md),
        ]
        if memory.exists():
            migration_cmd.extend(["--translation-memory", str(memory)])
        require_ok(call("i18n-migration-plan", migration_cmd))
        translation_source = migration_json

    glossary = locale_glossary(skill_root, args.target_locale)
    request_cmd = [
        sys.executable,
        str(skill_scripts / "export_translation_request.py"),
        "--input",
        str(translation_source),
        "--target-language",
        target_language,
        "--target-locale",
        args.target_locale,
        "--out",
        str(translation_request_json),
        "--prompt-out",
        str(translation_request_md),
    ]
    if glossary:
        request_cmd.extend(["--glossary", str(glossary)])
    require_ok(call("translation-request", request_cmd))

    locales_dir = args.locales_dir if args.locales_dir.is_absolute() else repo / args.locales_dir
    if locales_dir.exists() and not args.skip_consistency:
        require_ok(
            call(
                "i18n-consistency-json",
                [
                    sys.executable,
                    str(skill_scripts / "check_i18n_consistency.py"),
                    "--locales-dir",
                    str(locales_dir),
                    "--source-locale",
                    args.source_locale,
                    "--format",
                    "json",
                    "--out",
                    str(consistency_json),
                ],
            )
        )
        require_ok(
            call(
                "i18n-consistency-markdown",
                [
                    sys.executable,
                    str(skill_scripts / "check_i18n_consistency.py"),
                    "--locales-dir",
                    str(locales_dir),
                    "--source-locale",
                    args.source_locale,
                    "--format",
                    "markdown",
                    "--out",
                    str(consistency_md),
                ],
            )
        )
        if args.autofix_locales:
            fix_cmd = [
                sys.executable,
                str(skill_scripts / "apply_locale_consistency_fixes.py"),
                "--locales-dir",
                str(locales_dir),
                "--source-locale",
                args.source_locale,
                "--fill",
                "source",
                "--out",
                str(locale_fix_json),
                "--markdown",
                str(locale_fix_md),
            ]
            if args.apply:
                fix_cmd.append("--apply")
            require_ok(call("locale-consistency-fixes", fix_cmd))

    report = {
        "schema": "zero-zero-three.localization-pipeline-report",
        "repo": str(repo),
        "target_locale": args.target_locale,
        "target_language": target_language,
        "mode": args.mode,
        "out_dir": str(out_dir),
        "applied": bool(args.apply),
        "artifacts": {
            "scan_json": str(scan_json),
            "scan_markdown": str(scan_md),
            "delta_json": str(delta_json) if delta_json.exists() else None,
            "patch_plan_json": str(patch_plan_json),
            "i18n_migration_plan_json": str(migration_json) if migration_json.exists() else None,
            "translation_request_json": str(translation_request_json),
            "consistency_json": str(consistency_json) if consistency_json.exists() else None,
            "locale_fix_json": str(locale_fix_json) if locale_fix_json.exists() else None,
        },
        "counts": {
            "scan_candidates": maybe_count(scan_json),
            "patch_plan_items": maybe_count(patch_plan_json),
            "migration_items": maybe_count(migration_json),
            "translation_request_items": maybe_count(translation_request_json, "items"),
        },
        "steps": steps,
    }
    pipeline_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_summary(pipeline_md, report)
    print(f"Pipeline report: {pipeline_md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
