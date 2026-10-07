#!/usr/bin/env python3
"""Run the Lua pack-validation harness against store.lua.

Packs reach the Kindle over unauthenticated LAN pages, so malformed cards
must be refused at load time instead of crashing KOReader during review.
Skips when no Lua interpreter is available.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tests" / "lua_harness" / "run_pack_validation.lua"
ZIP_HARNESS = ROOT / "tests" / "lua_harness" / "run_zip_extract.lua"

LUA = shutil.which("lua") or shutil.which("luajit")
# CI sets KINDLE_ANKI_REQUIRE_TOOLS=1 so a missing interpreter fails the run
# instead of skipping these tests silently.
REQUIRE_TOOLS = os.environ.get("KINDLE_ANKI_REQUIRE_TOOLS") == "1"



@unittest.skipIf(LUA is None and not REQUIRE_TOOLS, "lua is not available")
class StoreLuaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertIsNotNone(LUA, "lua is required when KINDLE_ANKI_REQUIRE_TOOLS=1")

    def test_pack_validation_refuses_crashing_cards(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-store-lua-") as temp:
            result = subprocess.run(
                [LUA, str(HARNESS), temp],
                capture_output=True,
                text=True,
                timeout=60,
                cwd=str(ROOT),
            )
        self.assertEqual(
            result.returncode, 0,
            "lua harness failed:\n" + result.stdout + "\n" + result.stderr,
        )
        self.assertIn("ALL OK", result.stdout)
        self.assertNotIn("FAIL", result.stdout)

    @unittest.skipIf(shutil.which("unzip") is None and not REQUIRE_TOOLS, "unzip is not available")
    def test_zip_extraction_refuses_unsafe_entries(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-zip-lua-") as temp:
            scratch = Path(temp)
            with zipfile.ZipFile(scratch / "good.zip", "w") as archive:
                archive.writestr("demo.kindle-anki.json", "{}")
                archive.writestr("demo.kindle-anki.media/a.png", b"png")
            with zipfile.ZipFile(scratch / "slip.zip", "w") as archive:
                archive.writestr("ok.txt", "fine")
                archive.writestr("../escape.txt", "escaped")
            with zipfile.ZipFile(scratch / "backslash.zip", "w") as archive:
                archive.writestr(zipfile.ZipInfo("..\\escape.txt"), "escaped")
            result = subprocess.run(
                [LUA, str(ZIP_HARNESS), temp],
                capture_output=True,
                text=True,
                timeout=60,
                cwd=str(ROOT),
            )
        self.assertEqual(
            result.returncode, 0,
            "lua harness failed:\n" + result.stdout + "\n" + result.stderr,
        )
        self.assertIn("ALL OK", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
