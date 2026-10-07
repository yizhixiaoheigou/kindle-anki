#!/usr/bin/env python3
"""Run the Lua pack-validation harness against store.lua.

Packs reach the Kindle over unauthenticated LAN pages, so malformed cards
must be refused at load time instead of crashing KOReader during review.
Skips when no Lua interpreter is available.
"""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tests" / "lua_harness" / "run_pack_validation.lua"

LUA = shutil.which("lua") or shutil.which("luajit")


@unittest.skipIf(LUA is None, "lua is not available")
class StoreLuaTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
