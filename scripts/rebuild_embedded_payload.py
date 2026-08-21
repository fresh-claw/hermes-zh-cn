#!/usr/bin/env python3
"""Refresh the self-contained package archive embedded in an installer."""

import argparse
import base64
import re
import shutil
import tarfile
import tempfile
from pathlib import Path


DATA_RE = re.compile(r'(DATA = """\n)(.*?)(\n""")', re.DOTALL)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--installer", type=Path, required=True)
    parser.add_argument("--payload-root", type=Path, required=True)
    args = parser.parse_args()

    installer = args.installer.resolve()
    payload_root = args.payload_root.resolve()
    source_packages = payload_root / "packages"
    if not source_packages.is_dir():
        raise SystemExit(f"missing packages directory: {source_packages}")

    text = installer.read_text(encoding="utf-8")
    match = DATA_RE.search(text)
    if not match:
        raise SystemExit(f"embedded payload not found: {installer}")

    with tempfile.TemporaryDirectory(prefix="xiaoma-hermes-payload-") as temp:
        temp_root = Path(temp)
        archive = temp_root / "payload.tar.gz"
        archive.write_bytes(base64.b64decode("".join(match.group(2).split())))
        unpacked = temp_root / "payload"
        unpacked.mkdir()
        with tarfile.open(archive, "r:gz") as tar:
            tar.extractall(unpacked, filter="data")

        destination_packages = unpacked / "packages"
        if destination_packages.exists():
            shutil.rmtree(destination_packages)
        shutil.copytree(source_packages, destination_packages)

        rebuilt = temp_root / "rebuilt.tar.gz"
        with tarfile.open(rebuilt, "w:gz") as tar:
            for path in sorted(unpacked.rglob("*")):
                if path.is_file():
                    tar.add(path, arcname=path.relative_to(unpacked).as_posix())

        encoded = base64.b64encode(rebuilt.read_bytes()).decode("ascii")
        wrapped = "\n".join("\t" + encoded[i : i + 100] for i in range(0, len(encoded), 100))
        installer.write_text(text[: match.start(2)] + wrapped + text[match.end(2) :], encoding="utf-8")
    print(f"rebuilt embedded payload: {installer}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
