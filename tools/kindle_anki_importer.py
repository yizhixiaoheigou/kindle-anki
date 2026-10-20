#!/usr/bin/env python3
"""Convert legacy Anki ``.apkg`` exports into a Kindle/KOReader pack.

This importer intentionally handles the two first Kindle card families:
Basic-style front/back notes become short-answer cards, while note types with
named option fields become single- or multiple-choice cards. Basic notes whose
text contains labelled options are also promoted to choice cards. Cloze notes
become one short-answer card per cloze number. Referenced images are copied
as separate Kindle files and loaded on demand.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, replace
import html
import json
from pathlib import Path
import re
import sqlite3
import zipfile
from typing import Any, Iterable
from urllib.parse import unquote

from kindle_apkg import (
    AnkiImportError,
    MAX_ZIP_ENTRY_BYTES,
    NewFormatExportError,
    NoImportableCardsError,
    _card_text,
    _deck_name,
    _extract_field,
    _parse_tags,
    _read_collection,
    read_checked,
)
from kindle_cards import (
    FORMAT_NAME,
    FORMAT_VERSION,
    MAX_IMAGES_PER_CARD,
    PACK_SUFFIX,
    KindlePackageError,
    pack_stem,
    save_package,
)


@dataclass(frozen=True)
class KindleModel:
    model_id: int
    name: str
    kind: str
    front_index: int | None = None
    back_index: int | None = None
    front_indexes: tuple[int, ...] = ()
    back_indexes: tuple[int, ...] = ()
    question_index: int | None = None
    option_indexes: tuple[int, ...] = ()
    correct_index: int | None = None
    explanation_index: int | None = None
    packed_options_index: int | None = None
    forced_multiple: bool = False
    # Template ords whose question shows the back fields ("Basic (and
    # reversed card)"); those cards import with front and back swapped.
    reverse_ords: tuple[int, ...] = ()
    # The field a {{type:Field}} box on the first template checks.
    type_answer_index: int | None = None


_MEDIA_MARKUP = re.compile(
    r"<\s*(?:img|audio|video|iframe|object|embed|svg)\b[^>]*>", re.IGNORECASE
)
_MEDIA_SHORTCODE = re.compile(r"\[(?:sound|ankiimage):[^\]]*\]?", re.IGNORECASE)
_IMAGE_SRC = re.compile(
    r"<\s*img\b[^>]*\bsrc\s*=\s*(?:\"([^\"]+)\"|'([^']+)'|([^\s>]+))",
    re.IGNORECASE,
)
_IMAGE_SHORTCODE = re.compile(r"\[ankiimage:([^\]]+)\]", re.IGNORECASE)
_EMBEDDED_OPTION = re.compile(
    r"^\s*([A-Z])\s*[\.．、:：]\s*(.+?)\s*$", re.MULTILINE
)
# Answer labels at the start of the back ("A", "A、C", "B. ..."), but not an
# English sentence that starts with "A" ("A good plan").
_ANSWER_LABELS = re.compile(
    r"^\s*([A-Z](?:\s*[,，、/]\s*[A-Z])*)(?!\s+[a-z])\s*[\.．、:：]?\s*(?:\s|$)"
)
# One cloze deletion with no nested "{{" or "}}" inside, so repeated passes
# resolve nested clozes from the innermost out.
_CLOZE = re.compile(
    r"\{\{c(\d+)::((?:(?!\{\{|\}\}).)*?)(?:::((?:(?!\{\{|\}\}).)*?))?\}\}",
    re.DOTALL,
)
_CLOZE_TEMPLATE_FIELD = re.compile(r"\{\{cloze:([^}]+)\}\}", re.IGNORECASE)
_TEMPLATE_REF = re.compile(r"\{\{([^{}]+)\}\}")
_IMAGE_OCCLUSION = "image-occlusion:"
# Field names that usually hold the answer, for note types nothing else
# recognised. Checked in this order.
_BACK_HINTS = (
    "back", "answer", "背面", "后面", "答案", "response", "解析", "解释", "释义",
    "meaning", "definition", "translation", "翻译", "意思", "explanation",
)


def _key(value: str) -> str:
    return re.sub(r"[\s_-]+", "", value.casefold())


def _find_index(indexes: dict[str, int], names: Iterable[str]) -> int | None:
    for name in names:
        if _key(name) in indexes:
            return indexes[_key(name)]
    return None


def _option_order(value: str) -> int | None:
    normalized = re.sub(r"[\s_-]+", "", value.casefold())
    numeric = re.fullmatch(r"(?:option|choice|select|选项)(\d+)", normalized)
    if numeric:
        return int(numeric.group(1))
    match = re.fullmatch(r"(?:option|choice|select|选项)([a-z])", normalized)
    if match:
        return ord(match.group(1).upper()) - 64
    if re.fullmatch(r"[a-z]", normalized):
        return ord(normalized.upper()) - 64
    return None


def _parse_mapping_indexes(value: Any, field_count: int, label: str) -> tuple[int, ...]:
    if value is None:
        return ()
    if not isinstance(value, list):
        raise AnkiImportError(f"{label} must be a list of field indexes")
    indexes: list[int] = []
    for item in value:
        try:
            index = int(item)
        except (TypeError, ValueError) as exc:
            raise AnkiImportError(f"{label} contains a non-integer field index") from exc
        if index < 0 or index >= field_count:
            raise AnkiImportError(f"{label} field index {index} is out of range")
        indexes.append(index)
    return tuple(indexes)


def _joined_text(fields: list[str], indexes: tuple[int, ...]) -> str:
    parts = [_clean(_field(fields, index)) for index in indexes]
    return "\n".join(part for part in parts if part)


def _joined_raw(fields: list[str], indexes: tuple[int, ...]) -> str:
    return "".join(_field(fields, index) for index in indexes)


def _suggest_back(names: list[str], sample: list[str]) -> list[int]:
    """Back field for an unrecognised note type: a field named like an
    answer, else the first later field with text or an image in the first
    note."""

    if len(names) < 2:
        return []
    keyed = {_key(name): index for index, name in enumerate(names) if index > 0}
    for hint in _BACK_HINTS:
        if _key(hint) in keyed:
            return [keyed[_key(hint)]]
    for index in range(1, len(names)):
        value = _extract_field(sample, index)
        if _clean(value) or _IMAGE_SRC.search(value) or _IMAGE_SHORTCODE.search(value):
            return [index]
    return [len(names) - 1]


def _template_refs(
    model: dict[str, Any], indexes: dict[str, int]
) -> dict[int, tuple[set[int], int | None]]:
    """Per template ord: the fields its question side shows, and the field
    its {{type:Field}} box checks."""

    result: dict[int, tuple[set[int], int | None]] = {}
    templates = model.get("tmpls")
    for position, template in enumerate(templates if isinstance(templates, list) else []):
        if not isinstance(template, dict):
            continue
        template_ord = template.get("ord", position)
        if not isinstance(template_ord, int) or isinstance(template_ord, bool):
            template_ord = position
        shown: set[int] = set()
        typed = None
        for match in _TEMPLATE_REF.finditer(str(template.get("qfmt") or "")):
            ref = match.group(1).strip()
            if not ref or ref[0] in "#^/!":
                continue
            parts = [part.strip() for part in ref.split(":")]
            index = indexes.get(_key(parts[-1]))
            if index is None:
                continue
            shown.add(index)
            if parts[0].casefold() == "type" and "cloze" not in (part.casefold() for part in parts):
                typed = index
        result[template_ord] = (shown, typed)
    return result


def _is_cloze_model(model: dict[str, Any]) -> bool:
    kind = model.get("type")
    return isinstance(kind, (int, float)) and not isinstance(kind, bool) and kind == 1


def _cloze_field_indexes(model: dict[str, Any], indexes: dict[str, int]) -> tuple[int, ...]:
    """Fields the cloze template reads ({{cloze:Text}}), in field order."""

    found: set[int] = set()
    templates = model.get("tmpls")
    for template in templates if isinstance(templates, list) else []:
        if not isinstance(template, dict):
            continue
        for match in _CLOZE_TEMPLATE_FIELD.finditer(str(template.get("qfmt") or "")):
            field_name = match.group(1).split(":")[-1]
            index = indexes.get(_key(field_name))
            if index is not None:
                found.add(index)
    if found:
        return tuple(sorted(found))
    text_index = _find_index(indexes, ("text", "文字", "正文"))
    if text_index is not None:
        return (text_index,)
    return (0,) if indexes else ()


def _render_cloze(value: str, number: int, reveal: bool) -> tuple[str, list[str]]:
    """Render cloze ``number`` hidden (front) or revealed (back).

    Other cloze numbers show their text. Returns the rendered HTML and the
    raw answers of the active cloze.
    """

    answers: list[str] = []

    def replace(match: re.Match[str]) -> str:
        answer = match.group(2)
        if int(match.group(1)) != number:
            return answer
        answers.append(answer)
        if reveal:
            return "[" + answer + "]"
        hint = match.group(3)
        return "[" + hint + "]" if hint else "[...]"

    previous = None
    while previous != value:
        previous = value
        value = _CLOZE.sub(replace, value)
    return value, answers


def _cloze_card(
    fields: list[str], model: KindleModel, number: int
) -> tuple[str, str, str, str, list[str]] | str:
    """Raw/clean front and back for one cloze card, or a skip reason."""

    raw_front_parts: list[str] = []
    raw_back_parts: list[str] = []
    answers: list[str] = []
    for index in model.front_indexes:
        hidden, found = _render_cloze(_field(fields, index), number, reveal=False)
        revealed, _ = _render_cloze(_field(fields, index), number, reveal=True)
        raw_front_parts.append(hidden)
        raw_back_parts.append(revealed)
        answers.extend(found)
    if not answers:
        return "cloze_not_found"
    if any(html.unescape(answer).strip().startswith(_IMAGE_OCCLUSION) for answer in answers):
        return "image_occlusion"
    front = "\n".join(part for part in (_clean(raw) for raw in raw_front_parts) if part)
    back_parts = [part for part in (_clean(raw) for raw in raw_back_parts) if part]
    extra = _joined_text(fields, model.back_indexes)
    if extra:
        back_parts.append(extra)
    raw_front = "".join(raw_front_parts)
    raw_back = "".join(raw_back_parts) + _joined_raw(fields, model.back_indexes)
    expected = list(dict.fromkeys(text for text in (_clean(answer) for answer in answers) if text))
    return raw_front, raw_back, front, "\n".join(back_parts), expected


def _models(
    raw_models: str,
    field_mapping: dict[str, Any] | None = None,
) -> tuple[dict[int, KindleModel], list[str]]:
    if not raw_models or raw_models.strip() in {"", "{}"}:
        raise NewFormatExportError(
            "this export uses the newer Anki format (schema 18+), which is not "
            "supported by this first importer yet. Re-export with Anki's older "
            "format compatibility option."
        )
    try:
        raw = json.loads(raw_models)
    except json.JSONDecodeError as exc:
        raise AnkiImportError(f"collection models JSON is invalid: {exc}") from exc
    if not isinstance(raw, dict):
        raise AnkiImportError("collection models are not a note-type table")

    mapping = field_mapping or {}
    supported: dict[int, KindleModel] = {}
    unsupported: list[str] = []
    for model in raw.values():
        if not isinstance(model, dict):
            unsupported.append("Unnamed: malformed_note_type")
            continue
        name = str(model.get("name", "Unnamed"))
        try:
            model_id = int(model["id"])
        except (KeyError, TypeError, ValueError):
            unsupported.append(f"{name}: malformed_id")
            continue
        fields = model.get("flds") or []
        if not isinstance(fields, list):
            unsupported.append(f"{name}: malformed_fields")
            continue
        indexes = {
            _key(str(field.get("name", ""))): index
            for index, field in enumerate(fields)
            if isinstance(field, dict)
        }
        names = [str(field.get("name", "")) for field in fields if isinstance(field, dict)]
        option_pairs = sorted(
            (
                _option_order(field_name),
                index,
            )
            for index, field_name in enumerate(names)
            if _option_order(field_name) is not None
        )
        option_indexes = tuple(index for _, index in option_pairs)
        question_index = _find_index(indexes, ("question", "front", "prompt", "题目", "问题"))
        correct_index = _find_index(
            indexes,
            ("correct", "correct answer", "answer", "答案", "正确选项", "正确答案"),
        )
        explanation_index = _find_index(
            indexes,
            ("explanation", "解析", "notes", "back", "说明", "answer explanation"),
        )
        packed_options_index = _find_index(indexes, ("options", "选项", "choices", "optionlist"))
        name_hint = name.casefold()
        forced_multiple = any(token in name_hint for token in ("multiple", "multi", "多选"))
        detected: KindleModel | None = None
        reason = None
        if _is_cloze_model(model):
            cloze_indexes = _cloze_field_indexes(model, indexes)
            extra_index = _find_index(indexes, ("back extra", "extra", "背面额外"))
            detected = KindleModel(
                model_id=model_id,
                name=name,
                kind="cloze",
                front_indexes=cloze_indexes,
                back_indexes=(
                    (extra_index,)
                    if extra_index is not None and extra_index not in cloze_indexes
                    else ()
                ),
            )
        elif len(option_indexes) > 64:
            reason = f"{name}: too_many_options"
        elif len(option_indexes) >= 2 and question_index is not None and correct_index is not None:
            detected = KindleModel(
                model_id=model_id,
                name=name,
                kind="choice",
                question_index=question_index,
                option_indexes=option_indexes,
                correct_index=correct_index,
                explanation_index=explanation_index,
                forced_multiple=forced_multiple,
                front_indexes=(question_index,),
                back_indexes=(explanation_index,) if explanation_index is not None else (),
            )
        elif (
            packed_options_index is not None
            and question_index is not None
            and correct_index is not None
        ):
            detected = KindleModel(
                model_id=model_id,
                name=name,
                kind="choice",
                question_index=question_index,
                option_indexes=(),
                packed_options_index=packed_options_index,
                correct_index=correct_index,
                explanation_index=explanation_index,
                forced_multiple=forced_multiple,
                front_indexes=(question_index,),
                back_indexes=(explanation_index,) if explanation_index is not None else (),
            )
        else:
            front_index = _find_index(
                indexes, ("front", "question", "prompt", "正面", "前面", "题目", "问题")
            )
            back_index = _find_index(
                indexes, ("back", "answer", "背面", "后面", "答案", "response", "解析")
            )
            if front_index is not None and back_index is not None:
                detected = KindleModel(
                    model_id=model_id,
                    name=name,
                    kind="short_answer",
                    front_index=front_index,
                    back_index=back_index,
                    front_indexes=(front_index,),
                    back_indexes=(back_index,),
                )
            else:
                reason = f"{name}: no_supported_card_shape"

        spec = mapping.get(str(model_id), mapping.get(model_id))
        if isinstance(spec, dict):
            mapped_front = _parse_mapping_indexes(spec.get("front"), len(names), f"{name} front")
            mapped_back = _parse_mapping_indexes(spec.get("back"), len(names), f"{name} back")
            if mapped_front:
                if detected and detected.kind == "cloze":
                    detected = KindleModel(
                        model_id=model_id,
                        name=name,
                        kind="cloze",
                        front_indexes=mapped_front,
                        back_indexes=mapped_back,
                    )
                elif detected and detected.kind == "choice":
                    detected = KindleModel(
                        model_id=model_id,
                        name=name,
                        kind="choice",
                        question_index=mapped_front[0],
                        option_indexes=detected.option_indexes,
                        packed_options_index=detected.packed_options_index,
                        correct_index=detected.correct_index,
                        explanation_index=mapped_back[0] if mapped_back else detected.explanation_index,
                        forced_multiple=detected.forced_multiple,
                        front_indexes=mapped_front,
                        back_indexes=mapped_back,
                    )
                else:
                    detected = KindleModel(
                        model_id=model_id,
                        name=name,
                        kind="short_answer",
                        front_index=mapped_front[0],
                        back_index=mapped_back[0] if mapped_back else None,
                        front_indexes=mapped_front,
                        back_indexes=mapped_back,
                    )
        if detected and detected.kind == "short_answer":
            refs = _template_refs(model, indexes)
            front_set, back_set = set(detected.front_indexes), set(detected.back_indexes)
            detected = replace(
                detected,
                reverse_ords=tuple(sorted(
                    template_ord
                    for template_ord, (shown, _) in refs.items()
                    if template_ord != 0 and shown & back_set and not shown & front_set
                )),
                type_answer_index=refs.get(0, (set(), None))[1],
            )
        if detected:
            supported[model_id] = detected
        elif reason:
            unsupported.append(reason)
    return supported, unsupported


def _safe_media_name(value: str) -> str:
    name = Path(value).name
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", name)
    return name or "image"


def _image_dimensions(data: bytes) -> tuple[int, int] | None:
    if data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24:
        return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
    if data[:3] == b"GIF" and len(data) >= 10:
        return int.from_bytes(data[6:8], "little"), int.from_bytes(data[8:10], "little")
    if not data.startswith(b"\xff\xd8"):
        return None
    offset = 2
    sof_markers = set(range(0xC0, 0xC4)) | set(range(0xC5, 0xC8)) | set(range(0xC9, 0xCC)) | set(range(0xCD, 0xD0))
    while offset + 9 < len(data):
        while offset < len(data) and data[offset] != 0xFF:
            offset += 1
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            break
        marker = data[offset]
        offset += 1
        if marker in {0xD8, 0xD9} or 0xD0 <= marker <= 0xD7:
            continue
        if offset + 2 > len(data):
            break
        length = int.from_bytes(data[offset:offset + 2], "big")
        if length < 2 or offset + length > len(data):
            break
        if marker in sof_markers and length >= 7:
            height = int.from_bytes(data[offset + 3:offset + 5], "big")
            width = int.from_bytes(data[offset + 5:offset + 7], "big")
            return width, height
        offset += length
    return None


def _media_catalog(apkg_path: Path) -> dict[str, dict[str, Any]]:
    try:
        with zipfile.ZipFile(apkg_path) as archive:
            archive_names = set(archive.namelist())
            if "media" not in archive_names:
                return {}
            raw = json.loads(read_checked(archive, "media").decode("utf-8"))
            if not isinstance(raw, dict):
                return {}
            raw_items = [
                (str(archive_name), html.unescape(str(source_name)))
                for archive_name, source_name in raw.items()
                if str(archive_name) in archive_names
            ]
            # Allocate unique output names against the full name set up front so
            # a deduplicated name can never collide with a later real name.
            taken: set[str] = set()
            final_names: list[str] = []
            for _, source_name in raw_items:
                base = _safe_media_name(source_name)
                candidate, counter = base, 1
                while candidate in taken:
                    counter += 1
                    candidate = f"{Path(base).stem}_{counter}{Path(base).suffix}"
                taken.add(candidate)
                final_names.append(candidate)
            catalog: dict[str, dict[str, Any]] = {}
            for (archive_name, source_name), safe_name in zip(raw_items, final_names):
                dimensions = _image_dimensions(read_checked(archive, archive_name))
                if dimensions is None:
                    dimensions = (600, 400)
                catalog[source_name] = {
                    "archive_name": archive_name,
                    "name": safe_name,
                    "width": dimensions[0],
                    "height": dimensions[1],
                }
            return catalog
    except (OSError, KeyError, json.JSONDecodeError, UnicodeDecodeError, zipfile.BadZipFile):
        return {}


def _image_refs(value: str, catalog: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    names: list[str] = []
    for match in _IMAGE_SRC.finditer(value):
        names.append(next(group for group in match.groups() if group is not None))
    names.extend(match.group(1) for match in _IMAGE_SHORTCODE.finditer(value))
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw_name in names:
        source_name = html.unescape(raw_name).strip()
        asset = catalog.get(source_name) or catalog.get(Path(source_name).name)
        if asset is None:
            # Anki's editor stores names with spaces or CJK URL-encoded.
            decoded = unquote(source_name)
            asset = catalog.get(decoded) or catalog.get(Path(decoded).name)
        if asset is None or asset["name"] in seen:
            continue
        seen.add(asset["name"])
        result.append({
            "name": asset["name"],
            "width": asset["width"],
            "height": asset["height"],
        })
    # A pack allows this many images per side; more would fail the whole pack.
    return result[:MAX_IMAGES_PER_CARD]


def _has_media(value: str) -> bool:
    return bool(_MEDIA_MARKUP.search(value) or _MEDIA_SHORTCODE.search(value))


def _clean(value: str) -> str | None:
    # Drop media tags while preserving the question, options, and explanation
    # that surround them. Referenced image files are stored separately.
    value = _MEDIA_MARKUP.sub(" ", value)
    value = _MEDIA_SHORTCODE.sub(" ", value)
    text, reason = _card_text(value)
    return None if reason else text


_OPTION_LINE_START = re.compile(r"^\s*([A-Z])\s*[\.．、:：]")


def _split_inline_options(text: str) -> str:
    """Put options written on one line ("A. 30% B. 20% C. 40%") on lines of
    their own. Only the next letter in order splits a line, and only after a
    space and not before a letter, so "采用 B.O.T 模式" stays whole."""

    lines: list[str] = []
    expected = None
    for line in text.split("\n"):
        start = _OPTION_LINE_START.match(line)
        if not start or start.group(1) not in ("A", expected):
            lines.append(line)
            expected = None
            continue
        label = start.group(1)
        while label < "Z":
            following = chr(ord(label) + 1)
            split = re.search(r"\s" + following + r"\s*[\.．、:：](?![A-Za-z.])", line[start.end():])
            if not split:
                break
            cut = start.end() + split.start()
            lines.append(line[:cut])
            line = line[cut:].lstrip()
            start = _OPTION_LINE_START.match(line)
            label = following
        lines.append(line)
        expected = chr(ord(label) + 1)
    return "\n".join(lines)


def _embedded_choice(front: str, back: str) -> tuple[str, list[str], list[int]] | None:
    front = _split_inline_options(front)
    matches = list(_EMBEDDED_OPTION.finditer(front))
    if len(matches) < 2 or matches[0].group(1) != "A":
        return None
    labels = [match.group(1) for match in matches]
    if labels != [chr(ord("A") + index) for index in range(len(labels))]:
        return None
    question = front[: matches[0].start()].strip()
    options = [match.group(2).strip() for match in matches]
    if not question or any(not option for option in options):
        return None

    answer_match = _ANSWER_LABELS.match(back)
    if not answer_match:
        return None
    answer_labels = re.findall(r"[A-Z]", answer_match.group(1).upper())
    correct = [ord(label) - ord("A") for label in answer_labels]
    if not correct or any(index >= len(options) for index in correct):
        return None
    return question, options, sorted(set(correct))


def _field(fields: list[str], index: int | None) -> str:
    return _extract_field(fields, index if index is not None else -1)


def _option_label(index: int) -> str:
    label = ""
    index += 1
    while index:
        index, remainder = divmod(index - 1, 26)
        label = chr(65 + remainder) + label
    return label


def _correct_indices(raw: str, options: list[str]) -> list[int]:
    value = re.sub(r"<[^>]+>", " ", raw or "").strip()
    upper = value.upper()

    # Some decks encode the answer as the option text (for example ``A,E``)
    # rather than as the option labels.  Check delimited tokens first so that
    # a five-option deck can use values that happen to be letters too.
    option_by_text = {
        re.sub(r"\s+", "", option).casefold(): index
        for index, option in enumerate(options)
    }
    tokens = [token for token in re.split(r"[,，;；/、\s]+", value) if token]
    token_matches = [
        option_by_text[re.sub(r"\s+", "", token).casefold()]
        for token in tokens
        if re.sub(r"\s+", "", token).casefold() in option_by_text
    ]
    if token_matches and len(token_matches) == len(tokens):
        return sorted(set(token_matches))
    normalized = re.sub(r"\s+", "", value).casefold()
    for index, option in enumerate(options):
        if normalized == re.sub(r"\s+", "", option).casefold():
            return [index]

    # Run-together labels ("ACD") only when short and every letter is an
    # option, so a word such as "MITOCHONDRIA" is not read as labels.
    condensed = upper.replace(" ", "")
    run_together = (
        re.fullmatch(r"[A-Z]+", condensed) is not None
        and len(condensed) <= len(options)
        and all(ord(letter) - 65 < len(options) for letter in condensed)
    )
    found: list[int] = []
    for letter, index in ((chr(65 + i), i) for i in range(len(options))):
        if re.search(rf"(?:^|[^A-Z]){letter}(?:$|[^A-Z])", upper) or (
            run_together and letter in condensed
        ):
            found.append(index)
    if found:
        return sorted(set(found))

    numbers = [int(number) for number in re.findall(r"\d+", value)]
    if numbers and all(1 <= number <= len(options) for number in numbers):
        return sorted(set(number - 1 for number in numbers))
    return []


def _packed_option_parts(raw: str) -> list[str]:
    text = re.sub(r"<br\s*/?>", "\n", raw or "", flags=re.I)
    return [part.strip() for part in re.split(r"\|\|", text) if part.strip()]


def _packed_options(raw: str) -> list[str]:
    options: list[str] = []
    for part in _packed_option_parts(raw):
        item = _clean(part)
        if item:
            options.append(item)
    return options


def _options_with_images(
    raw_options: list[str], front_images: list[dict[str, Any]], catalog: dict[str, dict[str, Any]]
) -> list[str]:
    """Option texts; an option's images join the question's images and the
    option says which ones ("（见图）（图2）"), so an image-only option keeps
    its place."""

    options: list[str] = []
    for raw in raw_options:
        text = _clean(raw) or ""
        numbers: list[str] = []
        for image in _image_refs(raw, catalog):
            names = [item["name"] for item in front_images]
            if image["name"] not in names:
                if len(front_images) >= MAX_IMAGES_PER_CARD:
                    continue
                front_images.append(image)
                names.append(image["name"])
            numbers.append(str(names.index(image["name"]) + 1))
        if numbers:
            text = (text + " " if text else "") + "（图" + "、".join(numbers) + "）"
        if text:
            options.append(text)
    return options


def _format_choice_answer(raw: str, options: list[str]) -> str:
    indices = _correct_indices(raw, options)
    if not indices:
        return _clean(raw) or ""
    return "、".join(f"{_option_label(index)}. {options[index]}" for index in indices)


def inspect_apkg(apkg_path: Path) -> dict[str, Any]:
    """Return note types, field names, suggested front/back indexes, and samples."""

    if apkg_path.suffix.casefold() != ".apkg":
        raise AnkiImportError("the Kindle importer accepts an .apkg file")
    connection, temp_dir = _read_collection(apkg_path)
    try:
        connection.row_factory = sqlite3.Row
        collection = connection.execute("SELECT models, decks FROM col").fetchone()
        if collection is None:
            raise AnkiImportError("collection database has no col row")
        supported, unsupported = _models(collection["models"])
        try:
            raw = json.loads(collection["models"])
        except json.JSONDecodeError as exc:
            raise AnkiImportError(f"collection models JSON is invalid: {exc}") from exc
        try:
            decks = json.loads(collection["decks"])
        except (TypeError, json.JSONDecodeError):
            decks = {}
        samples: dict[int, list[str]] = {}
        try:
            for row in connection.execute("SELECT mid, flds FROM notes ORDER BY id"):
                if row["mid"] is None:
                    continue
                model_id = int(row["mid"])
                if model_id not in samples:
                    samples[model_id] = str(row["flds"] or "").split("\x1f")
        except sqlite3.Error:
            samples = {}
        card_decks: dict[str, int] = {}
        try:
            for row in connection.execute("SELECT did, COUNT(*) FROM cards GROUP BY did"):
                if row[0] is not None:
                    card_decks[str(int(row[0]))] = int(row[1])
        except sqlite3.Error:
            card_decks = {}
        models = []
        if isinstance(raw, dict):
            for model in raw.values():
                if not isinstance(model, dict):
                    continue
                try:
                    model_id = int(model["id"])
                except (KeyError, TypeError, ValueError):
                    continue
                fields = model.get("flds") or []
                names = [str(field.get("name", "")) for field in fields if isinstance(field, dict)]
                detected = supported.get(model_id)
                suggested_front = list(detected.front_indexes) if detected else ([0] if names else [])
                suggested_back = (
                    list(detected.back_indexes)
                    if detected
                    else _suggest_back(names, samples.get(model_id, []))
                )
                models.append({
                    "id": model_id,
                    "name": str(model.get("name", "Unnamed")),
                    "fields": names,
                    "kind": detected.kind if detected else "unknown",
                    "suggested_front": suggested_front,
                    "suggested_back": suggested_back,
                    "sample": samples.get(model_id, []),
                })
        deck_names = {
            str(deck_id): str(raw_deck.get("name") or f"Deck {deck_id}")
            for deck_id, raw_deck in decks.items()
            if isinstance(raw_deck, dict)
        } if isinstance(decks, dict) else {}
        ranked = sorted(
            deck_names.items(),
            key=lambda item: (-card_decks.get(item[0], 0), item[1]),
        )
        suggested_title = _title_for_decks([
            (name, card_decks[deck_id], int(deck_id))
            for deck_id, name in deck_names.items()
            if card_decks.get(deck_id, 0) > 0
        ])
        return {
            "title": apkg_path.stem,
            "file_name": apkg_path.name,
            "deck_names": [name for _, name in ranked],
            "suggested_title": suggested_title,
            "models": models,
            "unsupported_models": sorted(unsupported),
        }
    finally:
        connection.close()
        temp_dir.cleanup()


def _natural_key(name: str) -> list[tuple[int, int, str]]:
    """Sort key that orders "第2章" before "第10章"."""
    return [
        (0, int(part), "") if part[0] in "0123456789" else (1, 0, part)
        for part in re.split(r"([0-9]+)", name)
        if part
    ]


def _deck_order(name: str, deck_id: int) -> tuple[list[tuple[int, int, str]], str, int]:
    return _natural_key(name), name, deck_id


def _title_for_decks(decks: list[tuple[str, int, int]]) -> str:
    """Pack title from (name, card count, id) of the decks that hold cards.

    Several decks under one parent ("高项合并::01 …", "高项合并::02 …") take
    the parent's name; otherwise the deck with the most cards names the pack.
    """

    if not decks:
        return ""
    if len(decks) > 1:
        common: list[str] = []
        for parts in zip(*(name.split("::") for name, _, _ in decks)):
            if any(part != parts[0] for part in parts):
                break
            common.append(parts[0])
        prefix = "::".join(common).strip()
        if prefix:
            return prefix
    return min(decks, key=lambda deck: (-deck[1], deck[0], deck[2]))[0]


def import_apkg(
    apkg_path: Path,
    ai: dict[str, str] | None = None,
    field_mapping: dict[str, Any] | None = None,
    title: str | None = None,
) -> dict[str, Any]:
    if apkg_path.suffix.casefold() != ".apkg":
        raise AnkiImportError("the Kindle importer accepts an .apkg file")
    media_catalog = _media_catalog(apkg_path)
    connection, temp_dir = _read_collection(apkg_path)
    try:
        connection.row_factory = sqlite3.Row
        try:
            collection = connection.execute("SELECT models, decks FROM col").fetchone()
        except sqlite3.Error as exc:
            raise AnkiImportError(f"collection database is missing the col table: {exc}") from exc
        if collection is None:
            raise AnkiImportError("collection database has no col row")
        supported, unsupported = _models(collection["models"], field_mapping)
        try:
            decks = json.loads(collection["decks"])
        except (TypeError, json.JSONDecodeError) as exc:
            raise AnkiImportError(f"collection decks JSON is invalid: {exc}") from exc
        if not isinstance(decks, dict):
            raise AnkiImportError("collection decks are not an object")

        card_columns = {str(column[1]) for column in connection.execute("PRAGMA table_info(cards)")}
        odid = "c.odid" if "odid" in card_columns else "NULL"
        rows = connection.execute(
            f"""
            SELECT c.id AS card_id, c.nid AS note_id, c.did AS deck_id,
                   {odid} AS original_deck_id, c.ord AS card_ord,
                   n.mid AS model_id, n.tags AS tags, n.flds AS fields
            FROM cards c LEFT JOIN notes n ON n.id = c.nid
            ORDER BY c.did, c.id
            """
        ).fetchall()

        skipped = Counter[str]()
        cards: list[dict[str, Any]] = []
        media_cards = 0
        media_files: set[str] = set()
        deck_names: dict[int, str] = {}
        deck_cards: dict[int, list[int]] = {}
        deck_map: dict[int, int] = {}
        for row in rows:
            model = supported.get(int(row["model_id"]) if row["model_id"] is not None else -1)
            if model is None:
                skipped["unsupported_model"] += 1
                continue
            # A cloze note's card ord is its cloze number minus one, not a
            # second template; a reverse template swaps front and back.
            card_ord = int(row["card_ord"] or 0)
            reverse = model.kind == "short_answer" and card_ord in model.reverse_ords
            if model.kind != "cloze" and card_ord != 0 and not reverse:
                skipped["non_primary_template"] += 1
                continue
            source_deck = row["original_deck_id"] or row["deck_id"]
            if source_deck is None or _deck_name(decks, int(source_deck)) is None:
                skipped["missing_deck"] += 1
                continue
            fields = str(row["fields"] or "").split("\x1f")
            card_has_media = False
            if model.kind == "cloze":
                rendered = _cloze_card(fields, model, card_ord + 1)
                if isinstance(rendered, str):
                    skipped[rendered] += 1
                    continue
                raw_front, raw_back, front, back, expected = rendered
                card_has_media = _has_media(raw_front) or _has_media(raw_back)
                front_images = _image_refs(raw_front, media_catalog)
                back_images = _image_refs(raw_back, media_catalog)
                if not front and not front_images:
                    skipped["empty_front"] += 1
                    continue
                if not back and not back_images:
                    skipped["empty_back"] += 1
                    continue
                card_fields: dict[str, Any] = {"type": "short_answer", "front": front, "back": back}
                if len(expected) == 1:
                    card_fields["expected_answers"] = expected
            elif model.kind == "choice":
                raw_question = _joined_raw(fields, model.front_indexes)
                raw_back = _joined_raw(fields, model.back_indexes)
                card_has_media = _has_media(raw_question) or _has_media(raw_back)
                front_images = _image_refs(raw_question, media_catalog)
                back_images = _image_refs(raw_back, media_catalog)
                front = _joined_text(fields, model.front_indexes)
                if model.packed_options_index is not None:
                    raw_options = _packed_option_parts(_field(fields, model.packed_options_index))
                else:
                    raw_options = [_extract_field(fields, index) for index in model.option_indexes]
                card_has_media = card_has_media or any(_has_media(raw) for raw in raw_options)
                options = _options_with_images(raw_options, front_images, media_catalog)
                correct_raw = _field(fields, model.correct_index)
                correct = _correct_indices(correct_raw, options)
                back_parts = []
                for index in model.back_indexes:
                    if model.correct_index is not None and index == model.correct_index:
                        part = _format_choice_answer(_field(fields, index), options)
                    else:
                        part = _clean(_field(fields, index))
                    if part:
                        back_parts.append(part)
                back = "\n".join(back_parts)
                if not front and not front_images:
                    skipped["empty_front"] += 1
                    continue
                if len(options) < 2:
                    skipped["not_enough_options"] += 1
                    continue
                if not correct:
                    skipped["unreadable_correct_answer"] += 1
                    continue
                if not back:
                    back = "Correct option(s): " + ", ".join(_option_label(index) for index in correct)
                mode = "multiple" if model.forced_multiple or len(correct) > 1 else "single"
                card_fields = {
                    "type": "choice",
                    "mode": mode,
                    "front": front,
                    "back": back,
                    "options": options,
                    "correct_indices": correct,
                }
            else:
                front_indexes, back_indexes = model.front_indexes, model.back_indexes
                if reverse:
                    front_indexes, back_indexes = back_indexes, front_indexes
                raw_front = _joined_raw(fields, front_indexes)
                raw_back = _joined_raw(fields, back_indexes)
                card_has_media = _has_media(raw_front) or _has_media(raw_back)
                front_images = _image_refs(raw_front, media_catalog)
                back_images = _image_refs(raw_back, media_catalog)
                front = _joined_text(fields, front_indexes)
                back = _joined_text(fields, back_indexes)
                # A side may be only images; it still needs one or the other.
                if not front and not front_images:
                    skipped["empty_front"] += 1
                    continue
                if not back and not back_images:
                    skipped["empty_back"] += 1
                    continue
                embedded = _embedded_choice(front, back)
                if embedded:
                    question, options, correct = embedded
                    card_fields = {
                        "type": "choice",
                        "mode": "multiple" if len(correct) > 1 else "single",
                        "front": question,
                        "back": back,
                        "options": options,
                        "correct_indices": correct,
                    }
                else:
                    card_fields = {"type": "short_answer", "front": front, "back": back}
                    typed = None
                    if not reverse and model.type_answer_index is not None:
                        typed = _clean(_field(fields, model.type_answer_index))
                    if typed:
                        card_fields["expected_answers"] = [typed]

            if front_images:
                card_fields["front_images"] = front_images
            if back_images:
                card_fields["back_images"] = back_images

            source_deck_id = int(source_deck)
            device_deck_id = deck_map.setdefault(source_deck_id, len(deck_map) + 1)
            card_id = len(cards) + 1
            card = {
                "id": card_id,
                "source_card_id": int(row["card_id"]),
                "source_note_id": int(row["note_id"]),
                "deck_id": device_deck_id,
                "tags": _parse_tags(row["tags"]),
                **card_fields,
            }
            cards.append(card)
            if card_has_media:
                media_cards += 1
            media_files.update(image["name"] for image in front_images + back_images)
            deck_names[device_deck_id] = _deck_name(decks, source_deck_id) or f"Deck {source_deck_id}"
            deck_cards.setdefault(device_deck_id, []).append(card_id)

        if not cards:
            reasons = dict(sorted(skipped.items()))
            detail = ", ".join(f"{key}={value}" for key, value in reasons.items())
            raise NoImportableCardsError(
                "no importable cards in this .apkg (all notes were skipped or unsupported)"
                + (f": {detail}" if detail else ""),
                {
                    "total_cards": len(rows),
                    "skipped_reasons": reasons,
                    "unsupported_models": sorted(unsupported),
                },
            )
        normalized_decks = [
            {"id": deck_id, "name": deck_names[deck_id], "card_ids": deck_cards[deck_id]}
            for deck_id in sorted(deck_names, key=lambda item: _deck_order(deck_names[item], item))
        ]
        pack_title = (
            (title or "").strip()
            or _title_for_decks([
                (name, len(deck_cards[deck_id]), deck_id) for deck_id, name in deck_names.items()
            ])
            or apkg_path.stem
        )
        return {
            "format": FORMAT_NAME,
            "version": FORMAT_VERSION,
            "title": pack_title,
            "source": {"type": "anki_apkg", "file_name": apkg_path.name},
            "ai": ai or {},
            "decks": normalized_decks,
            "cards": cards,
            "report": {
                "total_cards": len(rows),
                "imported_cards": len(cards),
                "skipped_cards": sum(skipped.values()),
                "skipped_reasons": dict(sorted(skipped.items())),
                "unsupported_models": sorted(unsupported),
                "scheduling": "reset_to_new",
                "html_conversion": "plain_text",
                "media_cards": media_cards,
                "media_files": len(media_files),
            },
        }
    except sqlite3.Error as exc:
        raise AnkiImportError(f"cannot read Anki collection tables: {exc}") from exc
    finally:
        connection.close()
        temp_dir.cleanup()


def extract_media(apkg_path: Path, package: dict[str, Any], target_dir: Path) -> int:
    """Extract only the image files referenced by the normalized package."""

    references = {
        image["name"]
        for card in package.get("cards", [])
        for field in ("front_images", "back_images")
        for image in card.get(field, [])
    }
    if not references:
        return 0
    catalog = _media_catalog(apkg_path)
    by_output_name = {asset["name"]: asset for asset in catalog.values()}
    target_dir.mkdir(parents=True, exist_ok=True)
    extracted = 0
    total_bytes = 0
    with zipfile.ZipFile(apkg_path) as archive:
        for name in sorted(references):
            asset = by_output_name.get(name)
            if asset is None:
                continue
            payload = read_checked(archive, asset["archive_name"])
            total_bytes += len(payload)
            if total_bytes > MAX_ZIP_ENTRY_BYTES * 4:
                raise AnkiImportError("extracted media exceeds the total size limit")
            (target_dir / name).write_bytes(payload)
            extracted += 1
    return extracted


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Anki .apkg file")
    parser.add_argument("-o", "--output", type=Path, help="Kindle JSON pack")
    parser.add_argument(
        "--endpoint",
        help="OpenAI-compatible base URL stored in the pack's ai block "
        "(for other tools; the Kindle plugin uses only its own AI settings)",
    )
    parser.add_argument("--model", help="model name stored in the pack's ai block")
    parser.add_argument("--system-prompt", help="system prompt stored in the pack's ai block")
    parser.add_argument("--api-key", help=argparse.SUPPRESS)
    parser.add_argument("--report-only", action="store_true")
    parser.add_argument(
        "--map",
        type=Path,
        help="JSON object of note-type id -> {front: [indexes], back: [indexes]}",
    )
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        ai = {
            key: value
            for key, value in (
                ("endpoint", args.endpoint),
                ("model", args.model),
                ("system_prompt", args.system_prompt),
                ("api_key", args.api_key),
            )
            if value
        }
        field_mapping = None
        if args.map:
            field_mapping = json.loads(args.map.read_text(encoding="utf-8"))
            if not isinstance(field_mapping, dict):
                raise AnkiImportError("field mapping must be a JSON object")
        package = import_apkg(args.input, ai, field_mapping)
        output = None if args.report_only else (args.output or args.input.with_name(args.input.stem + PACK_SUFFIX))
        if output is not None:
            from kindle_bundle import write_kindle_bundle
            bundle = write_kindle_bundle(package, args.input, output.parent, stem=pack_stem(output))
            print(f"Wrote {bundle['json']}")
            print(f"Wrote {bundle['zip']}")
            if bundle["extracted"]:
                print(f"Extracted {bundle['extracted']} media file(s) to {bundle['media_dir']}")
        report = package["report"]
        print(f"Imported {report['imported_cards']}/{report['total_cards']} cards into {len(package['decks'])} deck(s).")
        if report["skipped_reasons"]:
            print("Skipped: " + ", ".join(f"{key}={value}" for key, value in report["skipped_reasons"].items()))
        if report["media_cards"]:
            print(f"Referenced {report['media_files']} media file(s) from {report['media_cards']} card(s).")
        return 0
    except (AnkiImportError, KindlePackageError, OSError, sqlite3.Error) as exc:
        print(f"Kindle import failed: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
