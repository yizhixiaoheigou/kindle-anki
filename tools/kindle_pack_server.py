#!/usr/bin/env python3
"""LAN pack server so a Kindle can import without USB.

The desktop converter keeps this running. The KOReader plugin fetches
http://<computer>:8766/packs and downloads a .kindle-anki.zip.
"""

from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hmac
import json
from pathlib import Path
import secrets
import socket
import subprocess
import threading
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse

PACK_PORT = 8766
# Wrong pairing codes allowed per code. The code is 4 digits, so an
# unlimited /ai-settings falls to a LAN brute force in about a second and
# hands out the API key; once locked, saving the AI settings again in the
# converter issues a fresh code.
MAX_AI_ATTEMPTS = 5


def new_pairing_code() -> str:
    return f"{secrets.randbelow(10000):04d}"


def set_pairing_code(holder: dict[str, Any], code: str) -> None:
    """Install a new pairing code and clear the wrong-code counter."""
    with holder["ai_lock"]:
        holder["ai_code"] = code
        holder["ai_failures"] = 0


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


def make_handler(root_holder: dict[str, Any]):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: Any) -> None:
            return

        def _root(self) -> Path:
            return Path(root_holder["root"])

        def _send(self, code: int, body: bytes, content_type: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
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
            if path == "/ai-settings":
                query = parse_qs(parsed.query)
                code = (query.get("code") or [""])[0]
                with root_holder["ai_lock"]:
                    expected = str(root_holder.get("ai_code") or "")
                    config = root_holder.get("ai_config")
                    if not expected or not config:
                        self._send(403, b"invalid pairing code", "text/plain")
                        return
                    if root_holder.get("ai_failures", 0) >= MAX_AI_ATTEMPTS:
                        self._send(429, b"too many wrong pairing codes; save the AI settings "
                                   b"in the converter again for a new code", "text/plain")
                        return
                    if not hmac.compare_digest(code.encode("utf-8"), expected.encode("utf-8")):
                        root_holder["ai_failures"] = root_holder.get("ai_failures", 0) + 1
                        self._send(403, b"invalid pairing code", "text/plain")
                        return
                body = json.dumps(config, ensure_ascii=False).encode("utf-8")
                self._send(200, body, "application/json; charset=utf-8")
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
                size = zip_path.stat().st_size
                self.send_response(200)
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Length", str(size))
                self.end_headers()
                with zip_path.open("rb") as handle:
                    while True:
                        chunk = handle.read(1024 * 1024)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                return
            self._send(404, b"not found", "text/plain")

    return Handler


def start_pack_server(root: Path, port: int = PACK_PORT) -> tuple[ThreadingHTTPServer, dict[str, Any]]:
    holder: dict[str, Any] = {"root": Path(root), "ai_lock": threading.Lock(), "ai_failures": 0}
    server = ThreadingHTTPServer(("0.0.0.0", port), make_handler(holder))
    server.daemon_threads = True
    return server, holder
