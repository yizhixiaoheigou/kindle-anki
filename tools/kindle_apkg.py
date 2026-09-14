#!/usr/bin/env python3
"""Read the collection database inside an Anki ``.apkg``.

Portions derived from FoloToy AI Passport tools/anki_importer.py
(MIT License, Copyright (c) 2026 FoloToy).
"""

from __future__ import annotations

from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sqlite3
import tempfile
from typing import Any
import zipfile


class AnkiImportError(ValueError):
    """Raised when an .apkg cannot be read by the Kindle importer."""


MAX_ZIP_ENTRY_BYTES = 512 * 1024 * 1024


def read_checked(archive: zipfile.ZipFile, name: str) -> bytes:
    """Read a zip entry with a decompressed-size guard against zip bombs."""
    info = archive.getinfo(name)
    if info.file_size > MAX_ZIP_ENTRY_BYTES:
        raise AnkiImportError(f"zip entry {name!r} is too large to read")
    return archive.read(name)


class _TextExtractor(HTMLParser):
    """Turn the safe, text-only part of Anki's HTML into readable card text."""

    BLOCK_TAGS = {
        "address",
        "article",
        "aside",
        "blockquote",
        "div",
        "dl",
        "fieldset",
        "footer",
        "form",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "header",
        "hr",
        "li",
        "main",
        "nav",
        "ol",
        "p",
        "pre",
        "section",
        "table",
        "td",
        "th",
        "tr",
        "ul",
    }

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        del attrs
        if tag == "br" or tag in self.BLOCK_TAGS:
            self.parts.append("\n")

    def handle_startendtag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        del attrs
        if tag == "br" or tag in self.BLOCK_TAGS:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in self.BLOCK_TAGS:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


_UNSUPPORTED_MARKUP = re.compile(
    r"<\s*(?:script|style|math|canvas)\b|\{\{\s*cloze\s*:|\{\{\s*c\d+\s*::",
    re.IGNORECASE,
)

_LEGACY_EXPORT_HINT = (
    'Re-export from Anki with "Support older Anki versions" enabled.'
)


def html_to_text(value: str) -> str:
    """Convert common Anki formatting while keeping the result device-friendly."""

    parser = _TextExtractor()
    parser.feed(value)
    parser.close()
    text = "".join(parser.parts).replace("\r\n", "\n").replace("\r", "\n")
    lines = [" ".join(line.split()) for line in text.split("\n")]
    compact: list[str] = []
    for line in lines:
        if line or (compact and compact[-1]):
            compact.append(line)
    return "\n".join(compact).strip()


def _deck_name(decks: dict[str, Any], deck_id: int) -> str | None:
    raw_deck = decks.get(str(deck_id))
    if not raw_deck:
        return None
    name = raw_deck.get("name")
    return str(name) if name else None


def _parse_tags(raw_tags: str) -> list[str]:
    return [tag for tag in str(raw_tags or "").split() if tag]


def _extract_field(fields: list[str], index: int) -> str:
    return fields[index] if 0 <= index < len(fields) else ""


def _card_text(value: str) -> tuple[str | None, str | None]:
    """Plain text for a field. Images are extracted separately; cloze is skipped."""

    if _UNSUPPORTED_MARKUP.search(value):
        return None, "unsupported_markup"
    return html_to_text(value), None


def _read_collection(apkg_path: Path) -> tuple[sqlite3.Connection, tempfile.TemporaryDirectory[str]]:
    try:
        archive = zipfile.ZipFile(apkg_path)
    except (OSError, zipfile.BadZipFile) as exc:
        raise AnkiImportError(f"cannot open {apkg_path}: {exc}") from exc

    temp_dir = tempfile.TemporaryDirectory(prefix="kindle-anki-")
    try:
        names = set(archive.namelist())
        collection_name = next(
            (name for name in ("collection.anki21", "collection.anki2") if name in names),
            None,
        )
        if collection_name is None:
            if "collection.anki21b" in names:
                raise AnkiImportError(
                    "cannot decompress collection.anki21b; "
                    "export an .apkg compatible with collection.anki21. "
                    + _LEGACY_EXPORT_HINT
                )
            raise AnkiImportError(".apkg has no collection.anki21 or collection.anki2")

        collection_path = Path(temp_dir.name) / collection_name
        collection_path.write_bytes(read_checked(archive, collection_name))
        archive.close()
        return sqlite3.connect(collection_path), temp_dir
    except Exception:
        archive.close()
        temp_dir.cleanup()
        raise
