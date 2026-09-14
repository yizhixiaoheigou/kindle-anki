#!/usr/bin/env python3
"""Pure-function tests for converter UI helpers. No live Tk window."""

from __future__ import annotations

import sys
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from kindle_import_ui import (  # noqa: E402
    COPY,
    choose_family,
    field_name_text,
    field_sample_text,
    initial_pack_name,
    kind_label,
    mapping_fronts_complete,
    share_keep_line,
    wheel_steps,
)


class _Event:
    def __init__(self, *, delta=0, num=None) -> None:
        self.delta = delta
        self.num = num


class KindleImportUiTests(unittest.TestCase):
    def test_initial_pack_name_from_inspect(self) -> None:
        self.assertEqual(initial_pack_name({"suggested_title": "驾照"}), "驾照")
        self.assertEqual(initial_pack_name({"suggested_title": "  重点  "}), "重点")
        self.assertEqual(initial_pack_name({}), "")
        self.assertEqual(initial_pack_name({"suggested_title": ""}), "")
        self.assertEqual(initial_pack_name(None), "")

    def test_choose_family_prefers_first_available(self) -> None:
        self.assertEqual(
            choose_family({"Hiragino Sans GB", "Menlo"}, ("PingFang SC", "Hiragino Sans GB"), "TkDefaultFont"),
            "Hiragino Sans GB",
        )
        self.assertEqual(choose_family(set(), ("PingFang SC",), "TkDefaultFont"), "TkDefaultFont")

    def test_field_name_and_sample(self) -> None:
        self.assertEqual(field_name_text("正面", 0), "正面")
        self.assertEqual(field_name_text("", 2), COPY["field_unnamed"].format(n=3))
        self.assertEqual(field_sample_text("2 + 2"), COPY["sample"].format(text="2 + 2"))
        self.assertEqual(field_sample_text(""), "")
        long = "a" * 40
        self.assertIn("例如", field_sample_text(long, limit=24))
        self.assertLessEqual(len(field_sample_text(long, limit=24)), len(COPY["sample"].format(text="a" * 24)))

    def test_kind_label_and_fronts(self) -> None:
        self.assertEqual(kind_label("choice"), COPY["kind_choice"])
        self.assertEqual(kind_label("mystery"), COPY["kind_unknown"])
        self.assertFalse(mapping_fronts_complete({}))
        self.assertFalse(mapping_fronts_complete({"1": {"front": [], "back": [1]}}))
        self.assertFalse(mapping_fronts_complete({"1": {"front": [0], "back": []}, "2": {"front": [], "back": [1]}}))
        self.assertTrue(mapping_fronts_complete({"1": {"front": [0], "back": []}, "2": {"front": [1], "back": [2]}}))

    def test_share_keep_line_and_wheel(self) -> None:
        self.assertEqual(share_keep_line(8766), COPY["share_keep_line"].format(port=8766))
        self.assertEqual(wheel_steps(_Event(num=4)), -1)
        self.assertEqual(wheel_steps(_Event(num=5)), 1)
        self.assertEqual(wheel_steps(_Event(delta=120)), -1)
        self.assertEqual(wheel_steps(_Event(delta=-120)), 1)
        self.assertEqual(wheel_steps(_Event(delta=1)), -1)


if __name__ == "__main__":
    unittest.main()
