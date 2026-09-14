#!/usr/bin/env python3
"""Host coverage for the Kindle pack format and Anki card-shape importer."""

from __future__ import annotations

import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from kindle_anki_importer import AnkiImportError, extract_media, import_apkg, inspect_apkg  # noqa: E402
from kindle_bundle import safe_stem, write_kindle_bundle  # noqa: E402
from kindle_cards import load_package, save_package, validate_package  # noqa: E402


def _model(model_id: int, name: str, fields: list[str]) -> dict:
    return {
        "id": model_id,
        "name": name,
        "flds": [{"name": field, "ord": index} for index, field in enumerate(fields)],
        "tmpls": [{"name": "Card 1", "ord": 0, "qfmt": "{{Question}}", "afmt": "{{Answer}}"}],
    }


def _make_apkg(path: Path) -> None:
    basic = _model(1, "Basic", ["Front", "Back"])
    single = _model(2, "Single Choice", ["Question", "Option A", "Option B", "Option C", "Option D", "Option E", "Option F", "Correct", "Explanation"])
    multiple = _model(3, "Multiple Choice", ["Question", "A", "B", "C", "D", "Answer", "Explanation"])
    chinese_basic = _model(4, "驾照", ["正面", "背面"])
    packed = _model(5, "Packed Choice", ["question", "options", "answer", "notes"])
    deck_id = 1_700_000_000_001
    decks = {str(deck_id): {"id": deck_id, "name": "Kindle::Demo"}}
    models = {"1": basic, "2": single, "3": multiple, "4": chinese_basic, "5": packed}

    with tempfile.TemporaryDirectory(prefix="kindle-anki-fixture-") as temp:
        db_path = Path(temp) / "collection.anki2"
        connection = sqlite3.connect(db_path)
        connection.executescript(
            """
            CREATE TABLE col (id INTEGER PRIMARY KEY, models TEXT NOT NULL, decks TEXT NOT NULL);
            CREATE TABLE notes (id INTEGER PRIMARY KEY, mid INTEGER NOT NULL, tags TEXT, flds TEXT);
            CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER NOT NULL, did INTEGER NOT NULL, ord INTEGER NOT NULL);
            """
        )
        connection.execute(
            "INSERT INTO col (id, models, decks) VALUES (1, ?, ?)",
            (json.dumps(models), json.dumps(decks)),
        )
        connection.executemany(
            "INSERT INTO notes (id, mid, tags, flds) VALUES (?, ?, ?, ?)",
            [
                (100, 1, "basic", "2 + 2\x1f4"),
                (101, 2, "single", "Which letter comes first?\x1fA\x1fB\x1fC\x1fD\x1fE\x1fF\x1fF\x1fF is sixth"),
                (102, 3, "multiple", "Select vowels\x1fA\x1fB\x1fE\x1fI\x1fA,E\x1fA and E"),
                (103, 4, "驾照", "中文题目<br><img src=\"question.jpg\"><br>A. 一\nB. 二\nC. 三\nD. 四\x1fC. 三\n解析"),
                (104, 5, "packed", "水泥项目最低资本金比例是（）。\x1f30%||35%||40%||45%\x1f2\x1f项目资本金制度"),
            ],
        )
        connection.executemany(
            "INSERT INTO cards (id, nid, did, ord) VALUES (?, ?, ?, 0)",
            [(200, 100, deck_id), (201, 101, deck_id), (202, 102, deck_id), (203, 103, deck_id), (204, 104, deck_id)],
        )
        connection.commit()
        connection.close()
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.write(db_path, "collection.anki2")
            archive.writestr("media", json.dumps({"0": "question.jpg"}))
            archive.writestr("0", b"test-image")


class KindlePackTests(unittest.TestCase):
    def _package(self) -> dict:
        return {
            "format": "folo-kindle-anki",
            "version": 1,
            "title": "Demo",
            "ai": {
                "endpoint": "https://example.test/v1",
                "model": "demo-model",
                "system_prompt": "Explain clearly.",
                "api_key": "pack-test-key",
            },
            "decks": [{"id": 1, "name": "Demo"}],
            "cards": [
                {"id": 1, "deck_id": 1, "type": "short_answer", "front": "Q", "back": "A"},
                {
                    "id": 2,
                    "deck_id": 1,
                    "type": "choice",
                    "mode": "multiple",
                    "front": "Pick",
                    "options": ["A", "B", "C", "D", "E"],
                    "correct_indices": [0, 4],
                    "back": "A and E",
                },
            ],
        }

    def test_round_trip_and_rebuild_deck_card_ids(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-pack-") as temp:
            path = Path(temp) / "demo.folo-kindle.json"
            save_package(self._package(), path)
            loaded = load_package(path)
        self.assertEqual(loaded["decks"][0]["card_ids"], [1, 2])
        self.assertEqual(loaded["cards"][1]["correct_indices"], [0, 4])
        self.assertNotIn("api_key", loaded.get("ai") or {})

    def test_api_key_round_trips_when_explicitly_configured(self) -> None:
        package = self._package()
        self.assertEqual(validate_package(package)["ai"]["api_key"], "pack-test-key")

    def test_save_package_strips_api_key(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-key-") as temp:
            path = Path(temp) / "demo.kindle-anki.json"
            save_package(self._package(), path)
            written = json.loads(path.read_text(encoding="utf-8"))
        self.assertNotIn("api_key", written.get("ai") or {})
        self.assertEqual(validate_package(self._package())["ai"]["api_key"], "pack-test-key")

    def test_imports_basic_single_and_multiple_cards(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-apkg-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            package = import_apkg(apkg, {
                "endpoint": "https://api.example/v1",
                "model": "demo-model",
                "api_key": "pack-test-key",
            })
        self.assertEqual(package["report"]["imported_cards"], 5)
        self.assertEqual(
            [card["type"] for card in package["cards"]],
            ["short_answer", "choice", "choice", "choice", "choice"],
        )
        self.assertEqual(package["cards"][1]["mode"], "single")
        self.assertEqual(len(package["cards"][1]["options"]), 6)
        self.assertEqual(package["cards"][1]["correct_indices"], [5])
        self.assertEqual(package["cards"][2]["mode"], "multiple")
        self.assertEqual(package["cards"][2]["correct_indices"], [0, 2])
        self.assertEqual(package["cards"][3]["type"], "choice")
        self.assertEqual(package["cards"][3]["options"], ["一", "二", "三", "四"])
        self.assertEqual(package["cards"][3]["correct_indices"], [2])
        self.assertEqual(package["report"]["media_cards"], 1)
        self.assertEqual(package["report"]["media_files"], 1)
        self.assertEqual(package["cards"][3]["front_images"][0]["name"], "question.jpg")
        self.assertEqual(package["ai"]["api_key"], "pack-test-key")

    def test_inspect_lists_fields_and_suggested_mapping(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-inspect-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            info = inspect_apkg(apkg)
        basic = next(model for model in info["models"] if model["name"] == "Basic")
        self.assertEqual(basic["fields"], ["Front", "Back"])
        self.assertEqual(basic["suggested_front"], [0])
        self.assertEqual(basic["suggested_back"], [1])
        self.assertEqual(basic["sample"][0], "2 + 2")

    def test_empty_front_mapping_keeps_autodetect(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-empty-front-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            package = import_apkg(apkg, None, {"1": {"front": [], "back": [1]}})
        basic = next(card for card in package["cards"] if card["front"] == "2 + 2")
        self.assertEqual(basic["back"], "4")

    def test_packed_double_bar_options_become_choice_cards(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-packed-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            package = import_apkg(
                apkg,
                field_mapping={"5": {"front": [0], "back": [0, 2, 3]}},
            )
        packed = next(card for card in package["cards"] if "水泥" in card["front"])
        self.assertEqual(packed["type"], "choice")
        self.assertEqual(packed["mode"], "single")
        self.assertEqual(packed["options"], ["30%", "35%", "40%", "45%"])
        self.assertEqual(packed["correct_indices"], [1])
        self.assertIn("水泥", packed["front"])
        self.assertIn("水泥", packed["back"])
        self.assertIn("B. 35%", packed["back"])
        self.assertIn("项目资本金制度", packed["back"])

    def test_field_mapping_can_keep_front_out_of_the_back(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-map-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            only_back = import_apkg(apkg, field_mapping={"1": {"front": [0], "back": [1]}})
            with_front = import_apkg(apkg, field_mapping={"1": {"front": [0], "back": [0, 1]}})
        basic_only = next(card for card in only_back["cards"] if card["front"] == "2 + 2")
        basic_with = next(card for card in with_front["cards"] if card["front"] == "2 + 2")
        self.assertEqual(basic_only["back"], "4")
        self.assertIn("2 + 2", basic_with["back"])
        self.assertIn("4", basic_with["back"])

    def test_bundle_writes_json_media_and_zip(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-bundle-") as temp:
            apkg = Path(temp) / "demo.apkg"
            out = Path(temp) / "out"
            _make_apkg(apkg)
            package = import_apkg(apkg)
            result = write_kindle_bundle(package, apkg, out)
            self.assertTrue(result["json"].is_file())
            self.assertTrue(result["zip"].is_file())
            self.assertEqual(result["json"].name, "Kindle Demo.kindle-anki.json")
            self.assertEqual(result["zip"].name, "Kindle Demo.kindle-anki.zip")
            loaded = json.loads(result["json"].read_text(encoding="utf-8"))
            self.assertEqual(loaded["format"], "kindle-anki")
            with zipfile.ZipFile(result["zip"]) as archive:
                names = set(archive.namelist())
            self.assertIn("Kindle Demo.kindle-anki.json", names)
            self.assertTrue(any(name.startswith("Kindle Demo.kindle-anki.media/") for name in names))

    def test_import_titles_pack_after_largest_deck(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-title-") as temp:
            apkg = Path(temp) / "Anki-export-2026-09-14.apkg"
            _make_apkg(apkg)
            package = import_apkg(apkg)
            self.assertEqual(package["title"], "Kindle::Demo")
            self.assertNotEqual(package["title"], apkg.stem)

    def test_import_title_override_wins(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-title-") as temp:
            apkg = Path(temp) / "Anki-export.apkg"
            _make_apkg(apkg)
            package = import_apkg(apkg, title="我的错题本")
            self.assertEqual(package["title"], "我的错题本")
            result = write_kindle_bundle(package, apkg, Path(temp) / "out")
            self.assertEqual(result["zip"].name, "我的错题本.kindle-anki.zip")

    def test_import_blank_title_falls_back_to_deck_name(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-title-") as temp:
            apkg = Path(temp) / "Anki-export.apkg"
            _make_apkg(apkg)
            package = import_apkg(apkg, title="   ")
            self.assertEqual(package["title"], "Kindle::Demo")

    def test_import_all_skipped_raises_clear_error(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-skip-") as temp:
            apkg = Path(temp) / "broken.apkg"
            with tempfile.TemporaryDirectory() as tmp:
                db_path = Path(tmp) / "collection.anki2"
                connection = sqlite3.connect(db_path)
                connection.executescript(
                    """
                    CREATE TABLE col (id INTEGER PRIMARY KEY, models TEXT NOT NULL, decks TEXT NOT NULL);
                    CREATE TABLE notes (id INTEGER PRIMARY KEY, mid INTEGER NOT NULL, tags TEXT, flds TEXT);
                    CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER NOT NULL, did INTEGER NOT NULL, ord INTEGER NOT NULL);
                    """
                )
                connection.execute(
                    "INSERT INTO col (id, models, decks) VALUES (1, ?, ?)",
                    (json.dumps({"9": "broken"}), json.dumps({"1": {"id": 1, "name": "Deck"}})),
                )
                connection.execute("INSERT INTO notes (id, mid, tags, flds) VALUES (10, 9, '', 'q\x1fa')")
                connection.execute("INSERT INTO cards (id, nid, did, ord) VALUES (20, 10, 1, 0)")
                connection.commit()
                connection.close()
                with zipfile.ZipFile(apkg, "w", zipfile.ZIP_DEFLATED) as archive:
                    archive.write(db_path, "collection.anki2")
            with self.assertRaises(AnkiImportError) as ctx:
                import_apkg(apkg)
            self.assertIn("no importable cards", str(ctx.exception))

    def test_inspect_suggests_deck_title(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-title-") as temp:
            apkg = Path(temp) / "Anki-export.apkg"
            _make_apkg(apkg)
            info = inspect_apkg(apkg)
            self.assertEqual(info["suggested_title"], "Kindle::Demo")
            self.assertIn("Kindle::Demo", info["deck_names"])

    def test_extracts_only_referenced_media_files(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-media-") as temp:
            apkg = Path(temp) / "demo.apkg"
            target = Path(temp) / "media"
            _make_apkg(apkg)
            package = import_apkg(apkg)
            extracted = extract_media(apkg, package, target)
            self.assertEqual(extracted, 1)
            self.assertEqual((target / "question.jpg").read_bytes(), b"test-image")

    def test_loads_legacy_folo_kindle_format(self) -> None:
        package = self._package()
        self.assertEqual(package["format"], "folo-kindle-anki")
        loaded = validate_package(package)
        self.assertEqual(loaded["title"], "Demo")
        self.assertEqual(loaded["cards"][0]["front"], "Q")

    def test_pack_stem_strips_new_and_legacy_suffixes(self) -> None:
        from kindle_cards import pack_stem

        self.assertEqual(pack_stem(Path("deck.kindle-anki.json")), "deck")
        self.assertEqual(pack_stem(Path("deck.folo-kindle.json")), "deck")
        self.assertEqual(pack_stem(Path("deck.apkg")), "deck")

    def test_imported_cards_do_not_carry_device_srs_state(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-state-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            package = import_apkg(apkg)
        for card in package["cards"]:
            self.assertNotIn("state", card)

    def test_img_card_imports_and_cloze_skips(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-markup-") as temp:
            apkg = Path(temp) / "demo.apkg"
            basic = _model(1, "Basic", ["Front", "Back"])
            deck_id = 1_700_000_000_001
            decks = {str(deck_id): {"id": deck_id, "name": "Kindle::Demo"}}
            models = {"1": basic}
            db_path = Path(temp) / "collection.anki2"
            connection = sqlite3.connect(db_path)
            connection.executescript(
                """
                CREATE TABLE col (id INTEGER PRIMARY KEY, models TEXT NOT NULL, decks TEXT NOT NULL);
                CREATE TABLE notes (id INTEGER PRIMARY KEY, mid INTEGER NOT NULL, tags TEXT, flds TEXT);
                CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER NOT NULL, did INTEGER NOT NULL, ord INTEGER NOT NULL);
                """
            )
            connection.execute(
                "INSERT INTO col (id, models, decks) VALUES (1, ?, ?)",
                (json.dumps(models), json.dumps(decks)),
            )
            connection.executemany(
                "INSERT INTO notes (id, mid, tags, flds) VALUES (?, ?, ?, ?)",
                [
                    (100, 1, "", 'See the figure<br><img src="question.jpg">\x1fThe figure'),
                    (101, 1, "", "The capital is {{c1::Paris}}\x1fParis"),
                ],
            )
            connection.executemany(
                "INSERT INTO cards (id, nid, did, ord) VALUES (?, ?, ?, 0)",
                [(200, 100, deck_id), (201, 101, deck_id)],
            )
            connection.commit()
            connection.close()
            with zipfile.ZipFile(apkg, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.write(db_path, "collection.anki2")
                archive.writestr("media", json.dumps({"0": "question.jpg"}))
                archive.writestr("0", b"test-image")
            package = import_apkg(apkg)
        self.assertEqual(package["report"]["imported_cards"], 1)
        self.assertEqual(package["report"]["skipped_cards"], 1)
        self.assertEqual(len(package["cards"]), 1)
        self.assertIn("See the figure", package["cards"][0]["front"])
        self.assertEqual(package["cards"][0]["front_images"][0]["name"], "question.jpg")
        self.assertNotIn("Paris", package["cards"][0]["front"])


class SafeStemTests(unittest.TestCase):
    def test_replaces_windows_forbidden_characters(self) -> None:
        self.assertEqual(safe_stem("Kindle::Demo"), "Kindle Demo")
        self.assertEqual(safe_stem("A/B\\C:D*E"), "A B C D E")

    def test_strips_trailing_dots_and_spaces(self) -> None:
        self.assertEqual(safe_stem("Deck. "), "Deck")
        self.assertEqual(safe_stem(". hidden ."), "hidden")

    def test_reserved_device_names_get_prefixed(self) -> None:
        self.assertEqual(safe_stem("CON"), "_CON")
        self.assertEqual(safe_stem("com1"), "_com1")

    def test_blank_falls_back(self) -> None:
        self.assertEqual(safe_stem("   "), "kindle-anki")
        self.assertEqual(safe_stem("..", fallback="deck"), "deck")

    def test_truncates_to_a_safe_length(self) -> None:
        self.assertEqual(len(safe_stem("很长的名字" * 100)), 80)


if __name__ == "__main__":
    unittest.main()
