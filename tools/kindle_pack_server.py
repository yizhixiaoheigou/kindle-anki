#!/usr/bin/env python3
"""LAN pack server so a Kindle can import without USB.

The desktop converter keeps this running. The KOReader plugin fetches
http://<computer>:8766/packs and downloads a .kindle-anki.zip.
"""

from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import socket
import subprocess
from typing import Any
from urllib.parse import unquote, urlparse

PACK_PORT = 8766


def is_lan_ip(ip: str) -> bool:
    if not ip or ip.startswith(("127.", "169.254.", "198.18.", "198.19.")):
        return False
    return ip.startswith(("10.", "192.168.")) or (
        ip.startswith("172.") and 16 <= _second_octet(ip) <= 31
    )


def _second_octet(ip: str) -> int:
    parts = ip.split(".")
    try:
        return int(parts[1])
    except (IndexError, ValueError):
        return -1


def lan_ip() -> str:
    for command in (
        ["ipconfig", "getifaddr", "en0"],
        ["ipconfig", "getifaddr", "en1"],
    ):
        try:
            value = subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL).strip()
        except (OSError, subprocess.CalledProcessError):
            continue
        if is_lan_ip(value):
            return value
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if is_lan_ip(ip):
                return ip
    except OSError:
        pass
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        if is_lan_ip(ip):
            return ip
    except OSError:
        pass
    finally:
        sock.close()
    return "127.0.0.1"


def list_packs(root: Path) -> list[dict[str, Any]]:
    packs = []
    if not root.is_dir():
        return packs
    paths = list(root.glob("*.kindle-anki.zip")) + list(root.glob("*.folo-kindle.zip"))
    for index, path in enumerate(sorted({item.resolve(): item for item in paths if item.is_file()}.values(), key=lambda item: item.name)):
        packs.append({
            "id": index,
            "name": path.name,
            "bytes": path.stat().st_size,
        })
    return packs


def safe_zip_name(name: str) -> str | None:
    raw = unquote(name)
    if "/" in raw or "\\" in raw or ".." in raw:
        return None
    if raw == Path(raw).name and (
        raw.endswith(".kindle-anki.zip") or raw.endswith(".folo-kindle.zip")
    ):
        return raw
    return None


def make_handler(root_holder: dict[str, Path]):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: Any) -> None:
            return

        def _root(self) -> Path:
            return Path(root_holder["root"])

        def _send(self, code: int, body: bytes, content_type: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            parsed = urlparse(self.path)
            path = parsed.path.rstrip("/") or "/"
            root = self._root()
            if path == "/" or path == "/packs":
                payload = {
                    "ok": True,
                    "ip": lan_ip(),
                    "port": PACK_PORT,
                    "packs": list_packs(root),
                }
                self._send(200, json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                           "application/json; charset=utf-8")
                return
            if path.startswith("/packs/"):
                rest = path[len("/packs/"):]
                zip_path = None
                if rest.isdigit():
                    packs = list_packs(root)
                    index = int(rest)
                    if 0 <= index < len(packs):
                        zip_path = root / packs[index]["name"]
                else:
                    try:
                        rest = rest.encode("latin-1").decode("utf-8")
                    except UnicodeError:
                        rest = unquote(rest)
                    name = safe_zip_name(rest)
                    if name:
                        zip_path = root / name
                    else:
                        self._send(400, b"invalid pack name", "text/plain")
                        return
                if zip_path is None or not zip_path.is_file():
                    self._send(404, b"pack not found", "text/plain")
                    return
                data = zip_path.read_bytes()
                self._send(200, data, "application/zip")
                return
            self._send(404, b"not found", "text/plain")

    return Handler


def start_pack_server(root: Path, port: int = PACK_PORT) -> tuple[ThreadingHTTPServer, dict[str, Path]]:
    holder = {"root": Path(root)}
    server = ThreadingHTTPServer(("0.0.0.0", port), make_handler(holder))
    server.daemon_threads = True
    return server, holder
