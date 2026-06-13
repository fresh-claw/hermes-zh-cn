#!/usr/bin/env python3
import argparse
import hashlib
import json
import time
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "web"
OUTPUTS = ROOT / "outputs"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", default=f"hermes-web-deploy-{time.strftime('%Y%m%d-%H%M%S')}")
    parser.add_argument("--target", default="/www/wwwroot/aimap.live/hermes/")
    args = parser.parse_args()

    OUTPUTS.mkdir(exist_ok=True)
    zip_path = OUTPUTS / f"{args.name}.zip"
    json_path = OUTPUTS / f"{args.name}.json"
    if zip_path.exists():
        zip_path.unlink()

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(WEB.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(WEB).as_posix())

    manifest = {
        "file": str(zip_path),
        "sha256": sha256(zip_path),
        "size": zip_path.stat().st_size,
        "target": args.target,
        "source": str(WEB),
        "windows_exe_sha256": sha256(WEB / "Hermes-zh-CN-Setup.exe"),
        "macos_zip_sha256": sha256(WEB / "hermes-macos-installer.zip"),
        "install_ps1_sha256": sha256(WEB / "install.ps1"),
        "install_sh_sha256": sha256(WEB / "install.sh"),
    }
    json_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
