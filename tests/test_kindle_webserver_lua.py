#!/usr/bin/env python3
"""Run the Lua end-to-end smoke test for the Kindle-side web importer.

Drives webserver.lua through a real luasocket server with KOReader modules
stubbed out. Skips when no Lua interpreter is available.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tests" / "lua_harness" / "run_webserver.lua"

LUA = shutil.which("lua") or shutil.which("luajit")
# CI sets KINDLE_ANKI_REQUIRE_TOOLS=1 so a missing interpreter fails the run
# instead of skipping these tests silently.
REQUIRE_TOOLS = os.environ.get("KINDLE_ANKI_REQUIRE_TOOLS") == "1"



@unittest.skipIf(LUA is None and not REQUIRE_TOOLS, "lua is not available")
class WebServerLuaSmokeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertIsNotNone(LUA, "lua is required when KINDLE_ANKI_REQUIRE_TOOLS=1")

    def test_webserver_end_to_end(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-web-lua-") as temp:
            blob = Path(temp) / "blob.bin"
            blob.write_bytes(bytes(range(256)) * 4096)  # 1 MB pattern
            result = subprocess.run(
                [LUA, str(HARNESS), str(blob)],
                capture_output=True,
                text=True,
                timeout=180,
                cwd=str(ROOT),
            )
        self.assertEqual(
            result.returncode, 0,
            "lua harness failed:\n" + result.stdout + "\n" + result.stderr,
        )
        self.assertIn("ALL OK", result.stdout)
        self.assertNotIn("FAIL", result.stdout)

    def test_plugin_lua_sources_still_parse(self) -> None:
        plugin = ROOT / "plugin" / "kindleanki.koplugin"
        luac = shutil.which("luac")
        for source in ("webserver.lua", "main.lua", "store.lua", "i18n.lua"):
            if luac:
                result = subprocess.run(
                    [luac, "-p", str(plugin / source)],
                    capture_output=True, text=True, timeout=60,
                )
                self.assertEqual(result.returncode, 0, source + ": " + result.stderr)
            else:
                # No luac: loadfile at least parses the chunk.
                result = subprocess.run(
                    [LUA, "-e",
                     'assert(loadfile("' + str(plugin / source) + '"))'],
                    capture_output=True, text=True, timeout=60,
                )
                self.assertEqual(result.returncode, 0, source + ": " + result.stderr)


if __name__ == "__main__":
    unittest.main()
