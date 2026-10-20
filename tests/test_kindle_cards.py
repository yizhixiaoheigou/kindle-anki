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
from kindle_apkg import NewFormatExportError, NoImportableCardsError  # noqa: E402
from kindle_bundle import safe_stem, write_kindle_bundle  # noqa: E402
from kindle_cards import KindlePackageError, load_package, save_package, validate_package  # noqa: E402


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


def _cloze_model(model_id: int, name: str, fields: list[str], qfmt: str) -> dict:
    model = _model(model_id, name, fields)
    model["type"] = 1
    model["tmpls"] = [{"name": "Cloze", "ord": 0, "qfmt": qfmt, "afmt": qfmt + "<br>{{Back Extra}}"}]
    return model


def _write_collection(path: Path, models: dict, notes: list[tuple], cards: list[tuple],
                      media: dict[str, bytes] | None = None,
                      decks: dict[int, str] | None = None) -> None:
    """cards are (id, note_id, ord) in the one "Shapes" deck, or
    (id, note_id, ord, deck_id) with ``decks`` naming each deck."""

    deck_id = 1_700_000_000_005
    deck_table = {str(key): {"id": key, "name": name} for key, name in (decks or {deck_id: "Shapes"}).items()}
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
            (json.dumps(models), json.dumps(deck_table)),
        )
        connection.executemany("INSERT INTO notes (id, mid, tags, flds) VALUES (?, ?, '', ?)", notes)
        connection.executemany(
            "INSERT INTO cards (id, nid, did, ord) VALUES (?, ?, ?, ?)",
            [(card[0], card[1], card[3] if len(card) > 3 else deck_id, card[2]) for card in cards],
        )
        connection.commit()
        connection.close()
        names = sorted(media or {})
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.write(db_path, "collection.anki2")
            archive.writestr("media", json.dumps({str(index): name for index, name in enumerate(names)}))
            for index, name in enumerate(names):
                archive.writestr(str(index), (media or {})[name])


def _make_shapes_apkg(path: Path) -> None:
    """Cloze (with an empty Back Extra), nested cloze, image-only sides,
    an audio-only back, and an image occlusion note."""

    models = {
        "1": _cloze_model(1, "Cloze", ["Text", "Back Extra"], "{{cloze:Text}}"),
        "2": _model(2, "Basic", ["Front", "Back"]),
        "3": _cloze_model(
            3, "Image Occlusion", ["Occlusion", "Image", "Header", "Back Extra", "Comments"],
            "{{#Header}}<div>{{Header}}</div>{{/Header}}{{cloze:Occlusion}}<div>{{Image}}</div>",
        ),
    }
    notes = [
        (100, 1, "The {{c1::sun::star}} rises in the {{c2::<b>east</b>}}\x1f"),
        (101, 1, "{{c1::Paris is in {{c2::France}}}}\x1fGeography"),
        (102, 2, '<img src="q.png">\x1fa cat'),
        (103, 2, 'What is this?\x1f<img src="a.png">'),
        (104, 2, "word\x1f[sound:w.mp3]"),
        (105, 3, "{{c1::image-occlusion:rect:left=.1:top=.2:width=.3:height=.4}}"
                 '\x1f<img src="io.png">\x1f\x1f\x1f'),
    ]
    cards = [(200, 100, 0), (201, 100, 1), (202, 101, 0), (203, 101, 1),
             (204, 102, 0), (205, 103, 0), (206, 104, 0), (207, 105, 0)]
    media = {"q.png": b"q-image", "a.png": b"a-image", "io.png": b"io-image", "w.mp3": b"audio"}
    _write_collection(path, models, notes, cards, media)


def _png(width: int, height: int) -> bytes:
    return (b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR" + width.to_bytes(4, "big")
            + height.to_bytes(4, "big") + b"\x08\x02\x00\x00\x00")


def _make_quirks_apkg(path: Path) -> None:
    """Real-deck quirks: chapter subdecks, option images, text answers,
    URL-encoded image names, reverse and type-in templates, options on one
    line, tables, too many images, and a cloze with no matching number."""

    reversed_model = _model(3, "Basic (and reversed card)", ["Front", "Back"])
    reversed_model["tmpls"] = [
        {"name": "Card 1", "ord": 0, "qfmt": "{{Front}}", "afmt": "{{Back}}"},
        {"name": "Card 2", "ord": 1, "qfmt": "{{Back}}", "afmt": "{{Front}}"},
    ]
    typed_model = _model(4, "Basic (type in the answer)", ["Front", "Back"])
    typed_model["tmpls"] = [
        {"name": "Card 1", "ord": 0, "qfmt": "{{Front}}\n\n{{type:Back}}", "afmt": "{{Back}}"},
    ]
    models = {
        "1": _model(1, "Single Choice", ["Question", "Option A", "Option B", "Option C", "Answer"]),
        "2": _model(2, "Basic", ["Front", "Back"]),
        "3": reversed_model,
        "4": typed_model,
        "5": _cloze_model(5, "Cloze", ["Text", "Back Extra"], "{{cloze:Text}}"),
    }
    many = "".join(f'<img src="p{index}.png">' for index in range(9))
    notes = [
        (100, 1, '看图选择<img src="q.png">\x1f（见图）<img src="a.png">\x1f<img src="b.png">'
                 '\x1f（见图）<img src="q.png">\x1fB'),
        (101, 1, "Cell part?\x1fThe mitochondria\x1fRibosome\x1fNucleus\x1fThe mitochondria"),
        (102, 2, "Rate it\nA: excellent\nB: good\x1fa grade scale"),
        (103, 2, '<img src="my%20pic.png">\x1fa picture'),
        (104, 3, "chien\x1fdog"),
        (105, 4, "capital of France\x1fParis"),
        (106, 2, "资本金比例是（）。<br>A. 30% B. 20%<br>C. 40% D. 50%\x1fB"),
        (107, 2, "<table><tr><th>合同</th><th>金额</th></tr><tr><td>A</td><td>100</td></tr></table>"
                 "\x1f<ol><li>一</li><li>二</li></ol>"),
        (108, 2, many + "\x1f九张图"),
        (109, 5, "only {{c2::two}}\x1f"),
    ]
    decks = {1: "高项::10 收尾", 2: "高项::2 中段", 3: "高项::01 开篇"}
    cards = [(200, 100, 0, 3), (201, 101, 0, 3), (202, 102, 0, 2), (203, 103, 0, 2),
             (204, 104, 0, 1), (205, 104, 1, 1), (206, 105, 0, 1), (207, 106, 0, 1),
             (208, 107, 0, 1), (209, 108, 0, 1), (210, 109, 0, 1)]
    media = {"q.png": _png(123, 45), "a.png": b"a", "b.png": b"b", "my pic.png": _png(7, 9)}
    media.update({f"p{index}.png": b"p" for index in range(9)})
    _write_collection(path, models, notes, cards, media, decks)


def _make_new_format_apkg(path: Path) -> None:
    """Like Anki's default export: the cards sit in collection.anki21b and
    collection.anki2 holds only a placeholder note with an empty back."""

    _write_collection(
        path,
        {"1": _model(1, "Basic", ["Front", "Back"])},
        [(100, 1, "请更新至 Anki 的最新版本，然后再次导入 .colpkg/.apkg 文件。\x1f")],
        [(200, 100, 0)],
    )
    with zipfile.ZipFile(path, "a") as archive:
        archive.writestr("collection.anki21b", b"(\xb5/\xfd compressed collection")
        archive.writestr("meta", b"\x08\x03")


def _make_unrecognised_apkg(path: Path) -> None:
    """Note types the importer cannot recognise, for back-field suggestions."""

    _write_collection(
        path,
        {
            "1": _model(1, "红宝书", ["单词", "音标", "解释", "Audio"]),
            "2": _model(2, "Vocab", ["Word", "Notes", "Gloss", "Audio"]),
            "3": _model(3, "Sounds", ["Word", "Audio"]),
        },
        [
            (100, 1, "abandon\x1f[ə'bændən]\x1fv./n.放弃\x1f[sound:abandon.mp3]"),
            (101, 2, "lush\x1f<br>\x1f茂盛的\x1f[sound:lush.mp3]"),
            (102, 3, "word\x1f[sound:word.mp3]"),
        ],
        [(200, 100, 0), (201, 101, 0), (202, 102, 0)],
    )


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
            self.assertIn("unsupported_model=1", str(ctx.exception))
            self.assertIsInstance(ctx.exception, NoImportableCardsError)
            self.assertEqual(ctx.exception.report["skipped_reasons"], {"unsupported_model": 1})
            self.assertEqual(ctx.exception.report["total_cards"], 1)

    def test_cloze_notes_become_one_card_per_cloze(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-cloze-") as temp:
            apkg = Path(temp) / "shapes.apkg"
            _make_shapes_apkg(apkg)
            package = import_apkg(apkg)
        by_source = {card["source_card_id"]: card for card in package["cards"]}
        first = by_source[200]
        self.assertEqual(first["type"], "short_answer")
        self.assertEqual(first["front"], "The [star] rises in the east")
        self.assertEqual(first["back"], "The [sun] rises in the east")
        self.assertEqual(first["expected_answers"], ["sun"])
        second = by_source[201]
        self.assertEqual(second["front"], "The sun rises in the [...]")
        self.assertEqual(second["back"], "The sun rises in the [east]")
        self.assertEqual(second["expected_answers"], ["east"])
        # Nested clozes resolve from the inside out.
        self.assertEqual(by_source[202]["front"], "[...]")
        self.assertEqual(by_source[202]["back"], "[Paris is in France]\nGeography")
        self.assertEqual(by_source[203]["front"], "Paris is in [...]")
        self.assertEqual(by_source[203]["back"], "Paris is in [France]\nGeography")

    def test_image_only_sides_import_and_audio_only_back_skips(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-image-only-") as temp:
            apkg = Path(temp) / "shapes.apkg"
            _make_shapes_apkg(apkg)
            package = import_apkg(apkg)
            result = write_kindle_bundle(package, apkg, Path(temp) / "out")
            loaded = load_package(result["json"])
        by_source = {card["source_card_id"]: card for card in loaded["cards"]}
        self.assertEqual(by_source[204]["front"], "")
        self.assertEqual(by_source[204]["front_images"][0]["name"], "q.png")
        self.assertEqual(by_source[204]["back"], "a cat")
        self.assertEqual(by_source[205]["back"], "")
        self.assertEqual(by_source[205]["back_images"][0]["name"], "a.png")
        self.assertNotIn(206, by_source)
        self.assertNotIn(207, by_source)
        self.assertEqual(package["report"]["imported_cards"], 6)
        self.assertEqual(
            package["report"]["skipped_reasons"], {"empty_back": 1, "image_occlusion": 1}
        )

    def test_empty_text_needs_an_image_on_that_side(self) -> None:
        package = self._package()
        package["cards"][0]["front"] = ""
        with self.assertRaises(KindlePackageError):
            validate_package(package)
        package["cards"][0]["front_images"] = ["q.png"]
        self.assertEqual(validate_package(package)["cards"][0]["front"], "")
        package["cards"][0]["back"] = ""
        with self.assertRaises(KindlePackageError):
            validate_package(package)

    def test_inspect_reports_cloze_kind_and_fields(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-cloze-inspect-") as temp:
            apkg = Path(temp) / "shapes.apkg"
            _make_shapes_apkg(apkg)
            info = inspect_apkg(apkg)
        cloze = next(model for model in info["models"] if model["name"] == "Cloze")
        self.assertEqual(cloze["kind"], "cloze")
        self.assertEqual(cloze["suggested_front"], [0])
        self.assertEqual(cloze["suggested_back"], [1])
        occlusion = next(model for model in info["models"] if model["name"] == "Image Occlusion")
        self.assertEqual(occlusion["suggested_front"], [0])
        self.assertEqual(occlusion["suggested_back"], [3])

    def test_cloze_mapping_keeps_cloze_rendering(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-cloze-map-") as temp:
            apkg = Path(temp) / "shapes.apkg"
            _make_shapes_apkg(apkg)
            package = import_apkg(apkg, field_mapping={"1": {"front": [0], "back": []}})
        card = next(card for card in package["cards"] if card["source_card_id"] == 202)
        self.assertEqual(card["front"], "[...]")
        self.assertEqual(card["back"], "[Paris is in France]")

    def test_new_format_export_is_named_not_read_as_a_placeholder(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-new-format-") as temp:
            apkg = Path(temp) / "10.apkg"
            _make_new_format_apkg(apkg)
            with self.assertRaises(NewFormatExportError) as inspect_error:
                inspect_apkg(apkg)
            with self.assertRaises(NewFormatExportError):
                import_apkg(apkg)
        self.assertIn("Support older Anki versions", str(inspect_error.exception))

    def test_unrecognised_note_types_suggest_a_back_with_text(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-suggest-") as temp:
            apkg = Path(temp) / "vocab.apkg"
            _make_unrecognised_apkg(apkg)
            info = inspect_apkg(apkg)
            mapping = {
                str(model["id"]): {"front": model["suggested_front"], "back": model["suggested_back"]}
                for model in info["models"]
            }
            package = import_apkg(apkg, field_mapping=mapping)
        backs = {model["name"]: model["suggested_back"] for model in info["models"]}
        # A field named like an answer, else the first one with text, else the last.
        self.assertEqual(backs, {"红宝书": [2], "Vocab": [2], "Sounds": [1]})
        self.assertEqual([card["back"] for card in package["cards"]], ["v./n.放弃", "茂盛的"])

    def test_real_deck_quirks(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-quirks-") as temp:
            apkg = Path(temp) / "quirks.apkg"
            _make_quirks_apkg(apkg)
            package = import_apkg(apkg)
            info = inspect_apkg(apkg)
            result = write_kindle_bundle(package, apkg, Path(temp) / "out")
            load_package(result["json"])
        cards = {card["source_card_id"]: card for card in package["cards"]}
        # Subdecks under one parent name the pack after the parent; chapters
        # sort by number.
        self.assertEqual(package["title"], "高项")
        self.assertEqual(info["suggested_title"], "高项")
        self.assertEqual([deck["name"] for deck in package["decks"]],
                         ["高项::01 开篇", "高项::2 中段", "高项::10 收尾"])
        # Option images join the question images and are numbered.
        self.assertEqual(cards[200]["options"], ["（见图） （图2）", "（图3）", "（见图） （图1）"])
        self.assertEqual([image["name"] for image in cards[200]["front_images"]], ["q.png", "a.png", "b.png"])
        self.assertEqual(cards[200]["front_images"][0]["width"], 123)
        # An answer that is an option's text is that option, not its letters.
        self.assertEqual(cards[201]["correct_indices"], [0])
        self.assertEqual(cards[201]["mode"], "single")
        # A back starting with an English word is not an answer label.
        self.assertEqual(cards[202]["type"], "short_answer")
        # URL-encoded image names find their file.
        self.assertEqual(cards[203]["front_images"], [{"name": "my_pic.png", "width": 7, "height": 9}])
        # The reverse template imports with front and back swapped.
        self.assertEqual((cards[204]["front"], cards[204]["back"]), ("chien", "dog"))
        self.assertEqual((cards[205]["front"], cards[205]["back"]), ("dog", "chien"))
        # {{type:Back}} becomes the expected answer.
        self.assertEqual(cards[206]["expected_answers"], ["Paris"])
        self.assertNotIn("expected_answers", cards[204])
        # Options on one line become a choice card.
        self.assertEqual(cards[207]["type"], "choice")
        self.assertEqual(cards[207]["options"], ["30%", "20%", "40%", "50%"])
        # Tables keep rows on lines; ordered lists keep their numbers.
        self.assertEqual(cards[208]["front"], "合同 | 金额\nA | 100")
        self.assertEqual(cards[208]["back"], "1. 一\n2. 二")
        # More than 8 images on a side are cut to 8, not a failed pack.
        self.assertEqual(len(cards[209]["front_images"]), 8)
        self.assertEqual(package["report"]["skipped_reasons"], {"cloze_not_found": 1})

    def test_all_image_occlusion_reports_why(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-io-") as temp:
            apkg = Path(temp) / "io.apkg"
            models = {"3": _cloze_model(3, "Image Occlusion", ["Occlusion", "Image"], "{{cloze:Occlusion}}")}
            _write_collection(
                apkg, models,
                [(100, 3, "{{c1::image-occlusion:rect:left=.1}}\x1f<img src=\"io.png\">")],
                [(200, 100, 0)],
            )
            with self.assertRaises(NoImportableCardsError) as ctx:
                import_apkg(apkg)
        self.assertEqual(ctx.exception.report["skipped_reasons"], {"image_occlusion": 1})
        self.assertIn("image_occlusion=1", str(ctx.exception))

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
