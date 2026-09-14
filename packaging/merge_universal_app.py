#!/usr/bin/env python3
"""Merge two thin-arch .app trees into one universal2 .app."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


MACHO_MAGICS = {
    b"\xca\xfe\xba\xbe",
    b"\xbe\xba\xfe\xca",
    b"\xcf\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf",
    b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xce",
}


def is_macho(path: Path) -> bool:
    if not path.is_file() or path.is_symlink():
        return False
    try:
        with path.open("rb") as handle:
            magic = handle.read(4)
    except OSError:
        return False
    return magic in MACHO_MAGICS


def relative_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if path.is_file() and not path.is_symlink():
            files.append(path.relative_to(root))
    return files


def lipo(arm: Path, x86: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + ".universal-tmp")
    subprocess.run(
        ["lipo", "-create", str(arm), str(x86), "-output", str(tmp)],
        check=True,
        capture_output=True,
    )
    tmp.replace(dest)
    dest.chmod(arm.stat().st_mode)


def merge(arm_app: Path, x86_app: Path, dest_app: Path) -> None:
    if dest_app.exists():
        shutil.rmtree(dest_app)
    shutil.copytree(arm_app, dest_app, symlinks=True)

    arm_files = set(relative_files(arm_app))
    x86_files = set(relative_files(x86_app))
    merged = 0
    copied_x86_only = 0
    for rel in sorted(arm_files | x86_files):
        arm_path = arm_app / rel
        x86_path = x86_app / rel
        dest_path = dest_app / rel
        if rel in arm_files and rel in x86_files and is_macho(arm_path) and is_macho(x86_path):
            lipo(arm_path, x86_path, dest_path)
            merged += 1
        elif rel in x86_files and rel not in arm_files:
            dest_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(x86_path, dest_path)
            copied_x86_only += 1

    subprocess.run(
        ["codesign", "--force", "--deep", "--sign", "-", str(dest_app)],
        check=True,
        capture_output=True,
    )
    print(f"universal2 app: {dest_app}")
    print(f"lipo merged {merged} Mach-O files; copied {copied_x86_only} x86-only files")


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: merge_universal_app.py ARM64.app X86_64.app DEST.app", file=sys.stderr)
        return 2
    arm_app, x86_app, dest_app = map(Path, sys.argv[1:])
    if not arm_app.is_dir() or not x86_app.is_dir():
        print("both inputs must be .app directories", file=sys.stderr)
        return 2
    merge(arm_app, x86_app, dest_app)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
