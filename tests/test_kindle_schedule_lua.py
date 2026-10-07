#!/usr/bin/env python3
"""Run schedule.lua's day boundary under several time zones.

Skips when no Lua interpreter is available.
"""

import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tests" / "lua_harness" / "run_schedule.lua"

LUA = shutil.which("lua") or shutil.which("luajit")
# CI sets KINDLE_ANKI_REQUIRE_TOOLS=1 so a missing interpreter fails the run
# instead of skipping these tests silently.
REQUIRE_TOOLS = os.environ.get("KINDLE_ANKI_REQUIRE_TOOLS") == "1"



@unittest.skipIf(LUA is None and not REQUIRE_TOOLS, "lua is not available")
class ScheduleLuaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertIsNotNone(LUA, "lua is required when KINDLE_ANKI_REQUIRE_TOOLS=1")

    def test_study_day_follows_local_midnight(self) -> None:
        for zone in ("UTC", "Asia/Shanghai", "America/New_York"):
            with self.subTest(zone=zone):
                result = subprocess.run(
                    [LUA, str(HARNESS), zone],
                    capture_output=True,
                    text=True,
                    timeout=60,
                    cwd=str(ROOT),
                    env={**os.environ, "TZ": zone},
                )
                self.assertEqual(
                    result.returncode, 0,
                    "lua harness failed:\n" + result.stdout + "\n" + result.stderr,
                )
                self.assertIn("ALL OK", result.stdout)
                self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
