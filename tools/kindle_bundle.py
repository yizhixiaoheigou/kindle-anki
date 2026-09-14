#!/usr/bin/env python3
"""Write a Kindle pack as JSON, a sibling media folder, and a zip bundle."""

from __future__ import annotations

from pathlib import Path
import re
import zipfile
from typing import Any

from kindle_anki_importer import extract_media
from kindle_cards import MEDIA_SUFFIX, PACK_SUFFIX, ZIP_SUFFIX, pack_stem, save_package

_WINDOWS_RESERVED = frozenset(
    ["CON", "PRN", "AUX", "NUL"]
    + [f"COM{index}" for index in range(1, 10)]
    + [f"LPT{index}" for index in range(1, 10)]
)


def safe_stem(title: str, *, fallback: str = "kindle-anki") -> str:
    """Turn a pack title into a filename stem that Windows and macOS both accept."""

    cleaned = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', " ", str(title))
    cleaned = re.sub(r"\s+", " ", cleaned).strip().strip(". ")
    if not cleaned:
        return fallback
    if cleaned.upper() in _WINDOWS_RESERVED:
        cleaned = f"_{cleaned}"
    return cleaned[:80].rstrip(". ") or fallback


def write_kindle_bundle(
    package: dict[str, Any],
    apkg_path: Path,
    output_dir: Path,
    stem: str | None = None,
) -> dict[str, Any]:
    """Save JSON + media + zip under output_dir. The zip is what users copy."""

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    if stem is None:
        stem = safe_stem(
            str(package.get("title") or "").strip(),
            fallback=pack_stem(Path(apkg_path)),
        )
    json_path = output_dir / f"{stem}{PACK_SUFFIX}"
    media_name = f"{stem}{MEDIA_SUFFIX}"
    media_dir = output_dir / media_name
    package["media_dir"] = media_name
    save_package(package, json_path)
    extracted = extract_media(apkg_path, package, media_dir)
    zip_path = output_dir / f"{stem}{ZIP_SUFFIX}"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.write(json_path, json_path.name)
        if media_dir.is_dir():
            for file in sorted(media_dir.iterdir()):
                if file.is_file():
                    archive.write(file, f"{media_name}/{file.name}")
    return {
        "json": json_path,
        "media_dir": media_dir,
        "zip": zip_path,
        "extracted": extracted,
        "media_name": media_name,
    }
