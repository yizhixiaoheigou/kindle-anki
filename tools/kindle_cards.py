#!/usr/bin/env python3
"""Canonical card-pack format for the Kindle/KOReader Anki route.

Kindle packs are a text-first JSON format so they can carry choice lists,
arbitrary answer counts, and an optional AI profile.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


FORMAT_NAME = "kindle-anki"
FORMAT_NAME_LEGACY = "folo-kindle-anki"
FORMAT_NAMES = {FORMAT_NAME, FORMAT_NAME_LEGACY}
FORMAT_VERSION = 1
PACK_SUFFIX = ".kindle-anki.json"
PACK_SUFFIX_LEGACY = ".folo-kindle.json"
ZIP_SUFFIX = ".kindle-anki.zip"
ZIP_SUFFIX_LEGACY = ".folo-kindle.zip"
MEDIA_SUFFIX = ".kindle-anki.media"
MEDIA_SUFFIX_LEGACY = ".folo-kindle.media"
CARD_TYPES = {"short_answer", "choice"}
CHOICE_MODES = {"single", "multiple"}
MAX_OPTIONS = 64
MAX_CARDS = 100_000
MAX_IMAGES_PER_CARD = 8


class KindlePackageError(ValueError):
    """Raised when a Kindle pack cannot be represented safely."""


def pack_stem(path: Path) -> str:
    name = Path(path).name
    for suffix in (PACK_SUFFIX, PACK_SUFFIX_LEGACY, ".kindle-anki", ".folo-kindle"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return Path(path).stem


def _text(value: Any, label: str, *, required: bool = True) -> str:
    if not isinstance(value, str):
        if value is None and not required:
            return ""
        raise KindlePackageError(f"{label} must be text")
    value = value.strip()
    if required and not value:
        raise KindlePackageError(f"{label} must not be empty")
    return value


def _int(value: Any, label: str) -> int:
    if isinstance(value, bool):
        raise KindlePackageError(f"{label} must be an integer")
    try:
        number = int(value)
    except (TypeError, ValueError) as exc:
        raise KindlePackageError(f"{label} must be an integer") from exc
    if number < 1:
        raise KindlePackageError(f"{label} must be positive")
    return number


def _media_refs(raw: Any, label: str) -> list[dict[str, Any]]:
    if raw is None:
        return []
    if not isinstance(raw, list) or len(raw) > MAX_IMAGES_PER_CARD:
        raise KindlePackageError(f"{label} must contain at most {MAX_IMAGES_PER_CARD} images")
    result = []
    for index, item in enumerate(raw, start=1):
        if isinstance(item, str):
            name = _text(item, f"{label} image {index}")
            width, height = 600, 400
        elif isinstance(item, dict):
            name = _text(item.get("name"), f"{label} image {index} name")
            width = _int(item.get("width", 600), f"{label} image {index} width")
            height = _int(item.get("height", 400), f"{label} image {index} height")
        else:
            raise KindlePackageError(f"{label} image {index} must be an object")
        if name in {".", ".."} or "/" in name or "\\" in name:
            raise KindlePackageError(f"{label} image {index} name must be a plain filename")
        result.append({"name": name, "width": width, "height": height})
    return result


def _validate_ai(raw: Any) -> dict[str, str]:
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        raise KindlePackageError("ai must be an object")
    allowed = {"endpoint", "model", "system_prompt", "profile_id", "api_key"}
    unknown = sorted(set(raw) - allowed)
    if unknown:
        raise KindlePackageError(
            "ai has unsupported fields; use the canonical api_key field for credentials"
        )
    result: dict[str, str] = {}
    for field in ("endpoint", "model", "system_prompt", "profile_id", "api_key"):
        value = raw.get(field)
        if value is not None:
            result[field] = _text(value, f"ai.{field}")
    if "endpoint" in result and not result["endpoint"].startswith(("http://", "https://")):
        raise KindlePackageError("ai.endpoint must use http:// or https://")
    return result


def validate_package(package: dict[str, Any]) -> dict[str, Any]:
    """Validate and return a normalized Kindle pack."""

    if not isinstance(package, dict):
        raise KindlePackageError("package must be an object")
    if package.get("format") not in FORMAT_NAMES or package.get("version") != FORMAT_VERSION:
        raise KindlePackageError(
            f"unsupported Kindle pack format {package.get('format')!r} "
            f"version {package.get('version')!r}"
        )

    title = _text(package.get("title", "Untitled deck"), "title")
    media_dir = package.get("media_dir")
    if media_dir is not None:
        media_dir = _text(media_dir, "media_dir")
        if "/" in media_dir or "\\" in media_dir or media_dir in {".", ".."}:
            raise KindlePackageError("media_dir must be a relative directory name")
    raw_decks = package.get("decks")
    raw_cards = package.get("cards")
    if not isinstance(raw_decks, list) or not isinstance(raw_cards, list):
        raise KindlePackageError("package must contain decks and cards arrays")
    if len(raw_cards) > MAX_CARDS:
        raise KindlePackageError(f"package has more than {MAX_CARDS} cards")

    decks: list[dict[str, Any]] = []
    deck_ids: set[int] = set()
    for number, raw_deck in enumerate(raw_decks, start=1):
        if not isinstance(raw_deck, dict):
            raise KindlePackageError(f"deck {number} must be an object")
        deck_id = _int(raw_deck.get("id"), f"deck {number} id")
        if deck_id in deck_ids:
            raise KindlePackageError(f"duplicate deck id {deck_id}")
        deck_ids.add(deck_id)
        decks.append({
            "id": deck_id,
            "name": _text(raw_deck.get("name", f"Deck {deck_id}"), f"deck {deck_id} name"),
            "card_ids": [int(card_id) for card_id in raw_deck.get("card_ids", [])],
        })

    cards: list[dict[str, Any]] = []
    card_ids: set[int] = set()
    for number, raw_card in enumerate(raw_cards, start=1):
        if not isinstance(raw_card, dict):
            raise KindlePackageError(f"card {number} must be an object")
        card_id = _int(raw_card.get("id"), f"card {number} id")
        deck_id = _int(raw_card.get("deck_id"), f"card {card_id} deck_id")
        if card_id in card_ids:
            raise KindlePackageError(f"duplicate card id {card_id}")
        if deck_id not in deck_ids:
            raise KindlePackageError(f"card {card_id} refers to unknown deck {deck_id}")
        card_ids.add(card_id)

        card_type = raw_card.get("type")
        if card_type not in CARD_TYPES:
            raise KindlePackageError(
                f"card {card_id} type must be one of {', '.join(sorted(CARD_TYPES))}"
            )
        card: dict[str, Any] = {
            "id": card_id,
            "deck_id": deck_id,
            "type": card_type,
            "front": _text(raw_card.get("front"), f"card {card_id} front"),
            "back": _text(raw_card.get("back"), f"card {card_id} back"),
            "tags": [str(tag) for tag in raw_card.get("tags", [])],
        }
        for field in ("front_images", "back_images"):
            refs = _media_refs(raw_card.get(field), f"card {card_id} {field}")
            if refs:
                card[field] = refs
        if card_type == "short_answer":
            expected = raw_card.get("expected_answers", [])
            if not isinstance(expected, list):
                raise KindlePackageError(f"card {card_id} expected_answers must be an array")
            card["expected_answers"] = [
                _text(answer, f"card {card_id} expected answer") for answer in expected
            ]
        else:
            mode = raw_card.get("mode")
            if mode not in CHOICE_MODES:
                raise KindlePackageError(
                    f"card {card_id} choice mode must be single or multiple"
                )
            options = raw_card.get("options")
            if not isinstance(options, list) or not 2 <= len(options) <= MAX_OPTIONS:
                raise KindlePackageError(
                    f"card {card_id} must have between 2 and {MAX_OPTIONS} options"
                )
            card["mode"] = mode
            card["options"] = [
                _text(option, f"card {card_id} option {index + 1}")
                for index, option in enumerate(options)
            ]
            correct = raw_card.get("correct_indices")
            if not isinstance(correct, list) or not correct:
                raise KindlePackageError(f"card {card_id} needs correct_indices")
            if any(
                isinstance(index, bool)
                or not isinstance(index, int)
                or not 0 <= index < len(options)
                for index in correct
            ):
                raise KindlePackageError(f"card {card_id} has an invalid correct index")
            if len(set(correct)) != len(correct):
                raise KindlePackageError(f"card {card_id} has duplicate correct indices")
            if mode == "single" and len(correct) != 1:
                raise KindlePackageError(f"card {card_id} single choice needs one correct index")
            card["correct_indices"] = list(correct)

        for field in ("source_card_id", "source_note_id"):
            if field in raw_card:
                card[field] = raw_card[field]
        cards.append(card)

    ai = _validate_ai(package.get("ai"))
    normalized_decks = []
    for deck in decks:
        normalized_decks.append({
            **deck,
            "card_ids": [card["id"] for card in cards if card["deck_id"] == deck["id"]],
        })
    normalized = {
        "format": FORMAT_NAME,
        "version": FORMAT_VERSION,
        "title": title,
        "source": package.get("source", {"type": "manual"}),
        "ai": ai,
        "decks": normalized_decks,
        "cards": cards,
    }
    if media_dir is not None:
        normalized["media_dir"] = media_dir
    return normalized


def load_package(path: Path) -> dict[str, Any]:
    try:
        package = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise KindlePackageError(f"cannot read Kindle pack {path}: {exc}") from exc
    return validate_package(package)


def save_package(package: dict[str, Any], path: Path) -> None:
    normalized = validate_package(package)
    if isinstance(normalized.get("ai"), dict):
        normalized["ai"].pop("api_key", None)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(normalized, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
