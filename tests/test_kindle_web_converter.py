#!/usr/bin/env python3
"""Conformance tests: the browser converter must agree with the desktop one.

The web importer (plugin/kindleanki.koplugin/web/*.js) is a port of the
Python pipeline in tools/. These tests run both on the same synthetic
.apkg files through Node and require field-identical packs, identical zip
layouts, and identical inspect reports, so the two paths cannot drift.
"""

from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tests"))

from test_kindle_cards import _make_apkg  # noqa: E402

from kindle_anki_importer import import_apkg, inspect_apkg  # noqa: E402
from kindle_bundle import write_kindle_bundle  # noqa: E402

NODE = shutil.which("node")
# CI sets KINDLE_ANKI_REQUIRE_TOOLS=1 so a missing interpreter fails the run
# instead of skipping these tests silently.
REQUIRE_TOOLS = os.environ.get("KINDLE_ANKI_REQUIRE_TOOLS") == "1"

RUNNER = ROOT / "tests" / "node" / "run_converter.js"
WEB_DIR = ROOT / "plugin" / "kindleanki.koplugin" / "web"

AI = {
    "endpoint": "https://api.example/v1",
    "model": "demo-model",
    "api_key": "pack-test-key",
}


def _run_node(*args: object) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [NODE, *map(str, args)],
        capture_output=True,
        text=True,
        timeout=180,
    )
    if result.returncode != 0:
        raise AssertionError("node converter failed:\n" + result.stderr)
    return result


def _convert_both(apkg: Path, temp: Path, *, title: str | None = None):
    """Return (python_package, python_zip_path, js_package, js_zip_path)."""

    python_package = import_apkg(apkg, AI, title=title)
    python_dir = temp / "python-out"
    python_zip = write_kindle_bundle(copy.deepcopy(python_package), apkg, python_dir)["zip"]

    js_package_path = temp / "js-package.json"
    js_zip_path = temp / "js-bundle.zip"
    args = [RUNNER, apkg, js_package_path, js_zip_path]
    if title is not None:
        args = [RUNNER, "--title", title, apkg, js_package_path, js_zip_path]
    _run_node(*args)
    js_package = json.loads(js_package_path.read_text(encoding="utf-8"))
    return python_package, python_zip, js_package, js_zip_path


def _model(model_id: int, name: str, fields: list[str]) -> dict:
    return {
        "id": model_id,
        "name": name,
        "flds": [{"name": field, "ord": index} for index, field in enumerate(fields)],
        "tmpls": [{"name": "Card 1", "ord": 0, "qfmt": "{{Question}}", "afmt": "{{Answer}}"}],
    }


def _write_apkg(path: Path, models: dict, decks: dict, notes: list[tuple], cards: list[tuple],
                media: dict | None = None) -> None:
    with tempfile.TemporaryDirectory(prefix="kindle-web-fixture-") as temp:
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
            "INSERT INTO notes (id, mid, tags, flds) VALUES (?, ?, ?, ?)", notes)
        connection.executemany(
            "INSERT INTO cards (id, nid, did, ord) VALUES (?, ?, ?, 0)", cards)
        connection.commit()
        connection.close()
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.write(db_path, "collection.anki2")
            for entry_name, payload in (media or {}).items():
                archive.writestr(entry_name, payload)


@unittest.skipIf(NODE is None and not REQUIRE_TOOLS, "node is not available")
class WebConverterConformance(unittest.TestCase):
    def setUp(self) -> None:
        self.assertIsNotNone(NODE, "node is required when KINDLE_ANKI_REQUIRE_TOOLS=1")

    def test_package_matches_python(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-web-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            python_package, _, js_package, _ = _convert_both(apkg, Path(temp))
        self.assertEqual(js_package, python_package)

    def test_zip_layout_and_content_match_python(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-web-zip-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            _, python_zip, _, js_zip = _convert_both(apkg, Path(temp))
            with zipfile.ZipFile(js_zip) as js_archive, zipfile.ZipFile(python_zip) as py_archive:
                self.assertEqual(set(js_archive.namelist()), set(py_archive.namelist()))
                js_json = json.loads(js_archive.read("Kindle Demo.kindle-anki.json"))
                py_json = json.loads(py_archive.read("Kindle Demo.kindle-anki.json"))
                self.assertEqual(js_json, py_json)
                self.assertEqual(
                    js_archive.read("Kindle Demo.kindle-anki.media/question.jpg"),
                    py_archive.read("Kindle Demo.kindle-anki.media/question.jpg"),
                )
        self.assertEqual(js_json["format"], "kindle-anki")
        self.assertNotIn("api_key", js_json.get("ai") or {})
        self.assertNotIn("report", js_json)

    def test_inspect_matches_python(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-web-inspect-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            out = Path(temp) / "inspect.json"
            _run_node(RUNNER, "--inspect", apkg, out)
            js_inspect = json.loads(out.read_text(encoding="utf-8"))
        py_inspect = None
        with tempfile.TemporaryDirectory(prefix="kindle-web-inspect-py-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            py_inspect = inspect_apkg(apkg)
        self.assertEqual(js_inspect, py_inspect)

    def test_title_override_and_chinese_zip_name(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-web-title-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            python_package, python_zip, js_package, js_zip = _convert_both(
                apkg, Path(temp), title="我的错题本")
            self.assertEqual(js_package, python_package)
            with zipfile.ZipFile(js_zip) as js_archive, zipfile.ZipFile(python_zip) as py_archive:
                self.assertEqual(set(js_archive.namelist()), set(py_archive.namelist()))
                self.assertIn("我的错题本.kindle-anki.json", js_archive.namelist())

    def test_large_field_uses_overflow_pages(self) -> None:
        big_back = "很长的解析。" + "补充说明内容。" * 8000
        with tempfile.TemporaryDirectory(prefix="kindle-web-overflow-") as temp:
            apkg = Path(temp) / "big.apkg"
            deck_id = 1_700_000_000_002
            _write_apkg(
                apkg,
                {"1": _model(1, "Basic", ["Front", "Back"])},
                {str(deck_id): {"id": deck_id, "name": "Overflow::Deck"}},
                [(100, 1, "", ("short question\x1f" + big_back))],
                [(200, 100, deck_id)],
            )
            python_package, _, js_package, _ = _convert_both(apkg, Path(temp))
        self.assertEqual(len(js_package["cards"]), 1)
        self.assertEqual(js_package, python_package)
        self.assertGreater(len(js_package["cards"][0]["back"]), 50000)

    def test_answer_parsing_variants_match(self) -> None:
        deck_id = 1_700_000_000_003
        models = {
            "1": _model(1, "Single Choice", ["Question", "Option A", "Option B", "Option C", "Answer"]),
            "2": _model(2, "Embedded", ["Front", "Back"]),
        }
        notes = [
            (100, 1, "", "数字题\x1f甲\x1f乙\x1f丙\x1f2"),
            (101, 1, "", "字母题\x1f甲\x1f乙\x1f丙\x1fA、C"),
            (102, 1, "", "文本题\x1f甲\x1f乙\x1f丙\x1f乙"),
            (103, 2, "", "下列哪些是对的？\nA. 一\nB. 二\nC. 三\x1fA、C\n解析"),
        ]
        with tempfile.TemporaryDirectory(prefix="kindle-web-answers-") as temp:
            apkg = Path(temp) / "answers.apkg"
            _write_apkg(apkg, models, {str(deck_id): {"id": deck_id, "name": "Answers"}},
                        notes, [(200, 100, deck_id), (201, 101, deck_id), (202, 102, deck_id), (203, 103, deck_id)])
            python_package, _, js_package, _ = _convert_both(apkg, Path(temp))
        self.assertEqual(js_package, python_package)
        self.assertEqual(js_package["cards"][0]["correct_indices"], [1])
        self.assertEqual(js_package["cards"][1]["correct_indices"], [0, 2])
        self.assertEqual(js_package["cards"][2]["correct_indices"], [1])
        self.assertEqual(js_package["cards"][3]["type"], "choice")

    def test_media_name_dedup_matches(self) -> None:
        deck_id = 1_700_000_000_004
        models = {"1": _model(1, "Basic", ["Front", "Back"])}
        notes = [
            (100, 1, "", '题目一<br><img src="dup.jpg">\x1f答案一'),
            (101, 1, "", '题目二<br><img src="dup.jpg">\x1f答案二'),
        ]
        with tempfile.TemporaryDirectory(prefix="kindle-web-media-") as temp:
            apkg = Path(temp) / "media.apkg"
            _write_apkg(
                apkg, models, {str(deck_id): {"id": deck_id, "name": "Media::Deck"}},
                notes, [(200, 100, deck_id), (201, 101, deck_id)],
                media={"media": json.dumps({"0": "dup.jpg", "1": "dup.jpg"}),
                       "0": b"image-one-bytes", "1": b"image-two-bytes"},
            )
            python_package, python_zip, js_package, js_zip = _convert_both(apkg, Path(temp))
            self.assertEqual(js_package, python_package)
            with zipfile.ZipFile(js_zip) as js_archive, zipfile.ZipFile(python_zip) as py_archive:
                self.assertEqual(set(js_archive.namelist()), set(py_archive.namelist()))

    def test_field_mapping_matches_python(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-web-map-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            mapping = {"1": {"front": [0], "back": [0, 1]}, "5": {"front": [0], "back": [0, 2, 3]}}
            map_path = Path(temp) / "mapping.json"
            map_path.write_text(json.dumps(mapping), encoding="utf-8")
            js_package_path = Path(temp) / "js.json"
            _run_node(RUNNER, "--map", map_path, apkg, js_package_path)
            js_package = json.loads(js_package_path.read_text(encoding="utf-8"))
            python_package = import_apkg(apkg, AI, field_mapping=mapping)
        self.assertEqual(js_package, python_package)

    def test_no_ai_leaves_empty_profile(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-web-noai-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            js_package_path = Path(temp) / "js.json"
            _run_node(RUNNER, "--no-ai", apkg, js_package_path)
            js_package = json.loads(js_package_path.read_text(encoding="utf-8"))
            python_package = import_apkg(apkg, None)
        self.assertEqual(js_package, python_package)

    def test_anki_style_ordinal_comments_schema(self) -> None:
        """Real Anki exports annotate columns with /* n */ ordinal comments;
        the browser's SQLite reader must parse them like the real engine."""
        deck_id = 1_700_000_000_009
        models = {
            "1": _model(1, "Basic", ["Front", "Back"]),
            "2": _model(2, "Single Choice",
                        ["Question", "Option A", "Option B", "Answer"]),
        }
        with tempfile.TemporaryDirectory(prefix="kindle-web-annot-") as temp:
            apkg = Path(temp) / "annotated.apkg"
            with tempfile.TemporaryDirectory() as db_temp:
                db_path = Path(db_temp) / "collection.anki2"
                connection = sqlite3.connect(db_path)
                connection.executescript(
                    """
                    CREATE TABLE col (
                        /* 0 */ id INTEGER PRIMARY KEY,
                        /* 1 */ crt INTEGER NOT NULL,
                        /* 2 */ mod INTEGER NOT NULL,
                        /* 3 */ scm INTEGER NOT NULL,
                        /* 4 */ ver INTEGER NOT NULL,
                        /* 5 */ tmz TEXT NOT NULL,
                        /* 6 */ models TEXT NOT NULL,
                        /* 7 */ decks TEXT NOT NULL
                    );
                    CREATE TABLE notes (
                        /* 0 */ id INTEGER PRIMARY KEY,
                        /* 1 */ guid TEXT NOT NULL,
                        /* 2 */ mid INTEGER NOT NULL,
                        /* 3 */ mod INTEGER INTEGER NOT NULL,
                        /* 4 */ usn INTEGER NOT NULL,
                        /* 5 */ tags TEXT NOT NULL,
                        /* 6 */ flds TEXT NOT NULL,
                        /* 7 */ sfld INTEGER NOT NULL,
                        /* 8 */ csum INTEGER NOT NULL,
                        /* 9 */ flags INTEGER NOT NULL,
                        /* 10 */ data TEXT NOT NULL
                    );
                    CREATE TABLE cards (
                        /* 0 */ id INTEGER PRIMARY KEY,
                        /* 1 */ nid INTEGER NOT NULL,
                        /* 2 */ did INTEGER NOT NULL,
                        /* 3 */ ord INTEGER NOT NULL,
                        /* 4 */ usn INTEGER NOT NULL,
                        /* 5 */ type INTEGER NOT NULL
                    );
                    """
                )
                connection.execute(
                    "INSERT INTO col (id, crt, mod, scm, ver, tmz, models, decks)"
                    " VALUES (1, 0, 0, 0, 11, 'UTC', ?, ?)",
                    (json.dumps(models), json.dumps({str(deck_id): {"id": deck_id, "name": "Annotated::Deck"}})),
                )
                connection.executemany(
                    "INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data)"
                    " VALUES (?, ?, ?, 0, 0, ?, ?, 0, 0, 0, '')",
                    [
                        (100, "g1", 1, "", "注释卡正面\x1f注释卡背面"),
                        (101, "g2", 2, "", "注释选择题\x1f甲\x1f乙\x1fA"),
                    ],
                )
                connection.executemany(
                    "INSERT INTO cards (id, nid, did, ord, usn, type) VALUES (?, ?, ?, 0, 0, 0)",
                    [(200, 100, deck_id), (201, 101, deck_id)],
                )
                connection.commit()
                connection.close()
                with zipfile.ZipFile(apkg, "w", zipfile.ZIP_DEFLATED) as archive:
                    archive.write(db_path, "collection.anki2")
            js_package_path = Path(temp) / "js.json"
            _run_node(RUNNER, "--no-ai", apkg, js_package_path)
            js_package = json.loads(js_package_path.read_text(encoding="utf-8"))
            python_package = import_apkg(apkg, None)
        self.assertEqual(js_package, python_package)
        self.assertEqual(len(python_package["cards"]), 2)
        self.assertEqual(python_package["cards"][0]["front"], "注释卡正面")

    def test_rejects_non_apkg_name(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-web-reject-") as temp:
            apkg = Path(temp) / "demo.apkg"
            _make_apkg(apkg)
            renamed = Path(temp) / "demo.colpkg"
            shutil.copyfile(apkg, renamed)
            result = subprocess.run(
                [NODE, str(RUNNER), renamed, Path(temp) / "out.json"],
                capture_output=True, text=True, timeout=60,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("the Kindle importer accepts an .apkg file", result.stderr)


@unittest.skipIf(NODE is None and not REQUIRE_TOOLS, "node is not available")
class WebConverterUnit(unittest.TestCase):
    """Direct checks of the JS-side pieces the conformance fixtures miss."""

    def setUp(self) -> None:
        self.assertIsNotNone(NODE, "node is required when KINDLE_ANKI_REQUIRE_TOOLS=1")

    def test_safe_stem_matches_python(self) -> None:
        from kindle_bundle import safe_stem as python_safe_stem

        runner = ROOT / "tests" / "node" / "run_safe_stem.js"
        cases = ["Kindle::Demo", "A/B\\C:D*E", "Deck. ", ". hidden .", "CON",
                 "com1", "   ", "..", "很长的名字" * 100, ""]
        results = json.loads(subprocess.run(
            [NODE, str(runner), json.dumps(cases)],
            capture_output=True, text=True, timeout=60, check=True,
        ).stdout)
        for case, js_result in zip(cases, results):
            self.assertEqual(js_result, python_safe_stem(case, fallback="kindle-anki"), repr(case))


if __name__ == "__main__":
    unittest.main()
