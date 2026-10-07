#!/usr/bin/env python3
"""Run the Lua card-view harness against new and old KOReader TextViewer.

KOReader v2026.07 added HTML rendering to TextViewer; older builds print the
markup verbatim. Skips when no Lua interpreter is available.
"""

import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tests" / "lua_harness" / "run_card_view.lua"

LUA = shutil.which("lua") or shutil.which("luajit")
# CI sets KINDLE_ANKI_REQUIRE_TOOLS=1 so a missing interpreter fails the run
# instead of skipping these tests silently.
REQUIRE_TOOLS = os.environ.get("KINDLE_ANKI_REQUIRE_TOOLS") == "1"



@unittest.skipIf(LUA is None and not REQUIRE_TOOLS, "lua is not available")
class CardViewLuaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertIsNotNone(LUA, "lua is required when KINDLE_ANKI_REQUIRE_TOOLS=1")

    def test_card_views_on_new_and_old_koreader(self) -> None:
        result = subprocess.run(
            [LUA, str(HARNESS)],
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
