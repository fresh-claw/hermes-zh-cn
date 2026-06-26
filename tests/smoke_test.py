#!/usr/bin/env python3
"""Release smoke tests for the Hermes language-management skill."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "zero-zero-three-hermes-language-management"
SCRIPTS = SKILL / "scripts"
FIXTURE = ROOT / "tests" / "fixtures" / "hermes-mini"


def run(command: list[str], cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(command, cwd=str(cwd), text=True, capture_output=True)
    if proc.returncode != 0:
        raise AssertionError(
            "command failed: {}\nstdout:\n{}\nstderr:\n{}".format(" ".join(command), proc.stdout, proc.stderr)
        )
    return proc


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def validate_skill_shape() -> None:
    skill_md = SKILL / "SKILL.md"
    text = skill_md.read_text(encoding="utf-8")
    assert text.startswith("---\n"), "SKILL.md must start with YAML frontmatter"
    assert "\nname: zero-zero-three-hermes-language-management\n" in text
    assert "\ndescription:" in text
    forbidden = {"README.md", "INSTALLATION_GUIDE.md", "QUICK_REFERENCE.md", "CHANGELOG.md", "LICENSE"}
    present = {path.name for path in SKILL.iterdir()}
    assert not (present & forbidden), f"skill folder contains release-only files: {present & forbidden}"


def check_release_boundary() -> None:
    forbidden = [
        re.compile("C:" + r"\\Users\\" + "aaaa", re.IGNORECASE),
        re.compile("/home/" + "aaaa"),
        re.compile("wsl" + r"\.localhost", re.IGNORECASE),
        re.compile("AppData" + r"[\\/]+Local[\\/]+Temp", re.IGNORECASE),
    ]
    allow = {".git"}
    for path in ROOT.rglob("*"):
        if any(part in allow for part in path.parts):
            continue
        if path.is_dir() or path.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".ico"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for pattern in forbidden:
            assert not pattern.search(text), f"local machine path leaked in {path}"


def main() -> int:
    validate_skill_shape()
    check_release_boundary()

    run([sys.executable, "-m", "py_compile", *[str(path) for path in sorted(SCRIPTS.glob("*.py"))]])

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        scan = tmp_path / "scan.json"
        scan_md = tmp_path / "scan.md"
        patch_plan = tmp_path / "patch-plan.json"
        patch_md = tmp_path / "patch-plan.md"
        migration = tmp_path / "migration.json"
        migration_md = tmp_path / "migration.md"
        request = tmp_path / "translation-request.json"
        consistency = tmp_path / "consistency.json"
        locale_fix = tmp_path / "locale-fix.json"
        pipeline_dir = tmp_path / "pipeline"

        run(
            [
                sys.executable,
                str(SCRIPTS / "scan_user_facing_text.py"),
                str(FIXTURE),
                "--profile",
                "hermes",
                "--format",
                "json",
                "--classes",
                "translate",
                "mixed-preserve",
                "review",
                "--out",
                str(scan),
            ]
        )
        candidates = load_json(scan)
        assert candidates, "scanner should find fixture candidates"

        run(
            [
                sys.executable,
                str(SCRIPTS / "scan_user_facing_text.py"),
                str(FIXTURE),
                "--profile",
                "hermes",
                "--format",
                "markdown",
                "--classes",
                "translate",
                "mixed-preserve",
                "review",
                "--out",
                str(scan_md),
            ]
        )
        assert scan_md.exists()

        run(
            [
                sys.executable,
                str(SCRIPTS / "generate_patch_plan.py"),
                "--input",
                str(scan),
                "--language",
                "zh-CN",
                "--out",
                str(patch_plan),
                "--markdown",
                str(patch_md),
                "--include-review",
            ]
        )
        assert load_json(patch_plan)["items"], "patch plan should contain items"

        run(
            [
                sys.executable,
                str(SCRIPTS / "generate_i18n_migration_plan.py"),
                "--input",
                str(patch_plan),
                "--namespace",
                "auto",
                "--source-locale",
                "en",
                "--target-locale",
                "zh-CN",
                "--out",
                str(migration),
                "--markdown",
                str(migration_md),
            ]
        )
        assert load_json(migration)["items"], "migration plan should contain items"

        run(
            [
                sys.executable,
                str(SCRIPTS / "export_translation_request.py"),
                "--input",
                str(migration),
                "--target-language",
                "Simplified Chinese",
                "--target-locale",
                "zh-CN",
                "--out",
                str(request),
            ]
        )
        assert load_json(request)["items"], "translation request should contain items"

        run(
            [
                sys.executable,
                str(SCRIPTS / "check_i18n_consistency.py"),
                "--locales-dir",
                str(FIXTURE / "locales"),
                "--source-locale",
                "en",
                "--format",
                "json",
                "--out",
                str(consistency),
            ]
        )
        consistency_report = load_json(consistency)
        assert consistency_report["summary"]["issue_count"] >= 1

        run(
            [
                sys.executable,
                str(SCRIPTS / "apply_locale_consistency_fixes.py"),
                "--locales-dir",
                str(FIXTURE / "locales"),
                "--source-locale",
                "en",
                "--out",
                str(locale_fix),
            ]
        )
        assert load_json(locale_fix)["plan"]["summary"]["change_count"] >= 1

        run(
            [
                sys.executable,
                str(SCRIPTS / "run_localization_pipeline.py"),
                str(FIXTURE),
                "--target-locale",
                "zh-CN",
                "--mode",
                "both",
                "--out-dir",
                str(pipeline_dir),
            ]
        )
        pipeline = load_json(pipeline_dir / "pipeline-report.json")
        assert pipeline["counts"]["scan_candidates"] >= 1
        assert pipeline["counts"]["translation_request_items"] >= 1

    print("smoke tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
