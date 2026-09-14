#!/usr/bin/env python3
"""Host coverage for the LAN pack server used by Wi-Fi import."""

from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from kindle_pack_server import is_lan_ip, list_packs, safe_zip_name, start_pack_server  # noqa: E402


class KindlePackServerTests(unittest.TestCase):
    def test_lan_ip_skips_vpn_and_loopback(self) -> None:
        self.assertTrue(is_lan_ip("192.168.5.35"))
        self.assertFalse(is_lan_ip("198.18.0.1"))
        self.assertFalse(is_lan_ip("127.0.0.1"))

    def test_safe_zip_name_rejects_path_escape(self) -> None:
        self.assertEqual(safe_zip_name("demo.folo-kindle.zip"), "demo.folo-kindle.zip")
        self.assertEqual(safe_zip_name("demo.kindle-anki.zip"), "demo.kindle-anki.zip")
        self.assertIsNone(safe_zip_name("../demo.folo-kindle.zip"))
        self.assertIsNone(safe_zip_name("demo.json"))

    def test_lists_and_serves_zip(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kindle-share-") as temp:
            root = Path(temp)
            payload = b"kindle-zip-bytes"
            (root / "一建管理专题聚焦.folo-kindle.zip").write_bytes(payload)
            (root / "alpha.kindle-anki.zip").write_bytes(b"new-zip")
            (root / "ignore.txt").write_text("no", encoding="utf-8")
            listed = list_packs(root)
            names = [item["name"] for item in listed]
            self.assertEqual(names, ["alpha.kindle-anki.zip", "一建管理专题聚焦.folo-kindle.zip"])
            self.assertEqual([item["id"] for item in listed], [0, 1])
            server, _holder = start_pack_server(root, 0)
            port = int(server.server_address[1])
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with urlopen(f"http://127.0.0.1:{port}/packs", timeout=3) as response:
                    body = json.loads(response.read().decode("utf-8"))
                self.assertTrue(body["ok"])
                self.assertEqual(body["packs"][0]["name"], "alpha.kindle-anki.zip")
                self.assertEqual(body["packs"][0]["id"], 0)
                self.assertEqual(body["packs"][1]["id"], 1)
                with urlopen(f"http://127.0.0.1:{port}/packs/1", timeout=3) as response:
                    self.assertEqual(response.read(), payload)
            finally:
                server.shutdown()
                server.server_close()


if __name__ == "__main__":
    unittest.main()
