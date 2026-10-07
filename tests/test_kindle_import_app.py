#!/usr/bin/env python3
"""Converter app helpers that need the Tk-importing module (no live window)."""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

try:
    import tkinter  # noqa: F401
except ImportError:  # pragma: no cover - host without Tk
    tkinter = None


@unittest.skipIf(tkinter is None, "tkinter is not available")
class KindleImportAppTests(unittest.TestCase):
    @unittest.skipIf(os.name != "posix", "POSIX file modes only")
    def test_remembered_ai_settings_are_owner_only(self) -> None:
        from kindle_import_app import write_private_json

        with tempfile.TemporaryDirectory(prefix="kindle-ai-file-") as temp:
            path = Path(temp) / ".kindle-anki" / "ai-settings.json"
            path.parent.mkdir()
            path.write_text("{}", encoding="utf-8")
            path.chmod(0o644)  # a file left by an older converter
            write_private_json(path, {"api_key": "sk-secret"})
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(json.loads(path.read_text(encoding="utf-8"))["api_key"], "sk-secret")

            fresh = Path(temp) / "new" / "ai-settings.json"
            write_private_json(fresh, {"api_key": "sk-other"})
            self.assertEqual(stat.S_IMODE(fresh.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(fresh.parent.stat().st_mode), 0o700)


if __name__ == "__main__":
    unittest.main()
