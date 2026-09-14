#!/usr/bin/env python3
"""Local web UI that wraps kindle_anki_importer.py for Mac/desktop use.

Run on the computer that holds the .apkg files (not on the Kindle):

    python3 tools/kindle_import_server.py
    open http://127.0.0.1:8765

Then copy the generated *.kindle-anki.json and *.media/ folder to the Kindle
under /mnt/us/kindle-anki/packs/. The legacy folder /mnt/us/folo-anki/ still works.
"""

from __future__ import annotations

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import tempfile
import traceback
from urllib.parse import parse_qs

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from kindle_anki_importer import import_apkg, inspect_apkg  # noqa: E402
from kindle_bundle import write_kindle_bundle  # noqa: E402

HTML = """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8"/>
  <title>Kindle Anki 导入</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 760px; margin: 2rem auto; padding: 0 1rem; }
    .card { border: 1px solid #ddd; border-radius: 12px; padding: 1.25rem; }
    label { display:block; margin-top: 0.75rem; font-weight: 600; }
    input, button { font-size: 1rem; margin-top: 0.35rem; }
    button { padding: 0.55rem 1rem; }
    pre { background: #111; color: #eee; padding: 1rem; overflow:auto; border-radius: 8px; }
    .hint { color: #555; font-size: 0.95rem; }
    .model { border-top: 1px solid #eee; margin-top: 1rem; padding-top: 0.75rem; }
    .fields { display:flex; gap: 1.5rem; flex-wrap: wrap; }
    .fields label { font-weight: 400; margin-top: 0.25rem; }
    .sample { color:#666; font-size: 0.85rem; }
  </style>
</head>
<body>
  <h1>Kindle Anki 导入</h1>
  <p class="hint">把 Anki <code>.apkg</code> 转成 Kindle 插件用的卡包（json + zip）。每种笔记类型可勾选正面/背面字段。给别人用请双击 <code>desktop/Kindle-Anki-Import.command</code>。</p>
  <div class="card">
    <form id="form">
      <label>APKG 文件 <input type="file" name="apkg" accept=".apkg" required></label>
      <label>卡包名称（可选，默认用牌组名） <input name="title" style="width:100%"></label>
      <label>输出目录（本机绝对路径） <input name="outdir" style="width:100%" placeholder="/path/to/output" required></label>
      <label>API endpoint（可选） <input name="endpoint" style="width:100%" placeholder="https://api.example.com/v1"></label>
      <label>Model（可选） <input name="model" style="width:100%"></label>
      <div id="mapping"></div>
      <p><button type="submit">转换</button></p>
    </form>
    <pre id="out">选择 .apkg 后会列出字段，再勾选正面和背面。</pre>
  </div>
<script>
const form = document.getElementById('form');
const out = document.getElementById('out');
const mappingHost = document.getElementById('mapping');
const fileInput = form.apkg;
let inspectData = null;

function fieldLabel(name, index, sample) {
  const text = (sample && sample[index] || '').replace(/\\s+/g, ' ').trim().slice(0, 24);
  return text ? `${name || ('字段 ' + (index+1))}（例如 ${text}）` : (name || ('字段 ' + (index+1)));
}

function renderMapping(data) {
  mappingHost.innerHTML = '';
  inspectData = data;
  (data.models || []).forEach(model => {
    const box = document.createElement('div');
    box.className = 'model';
    box.dataset.modelId = model.id;
    const title = document.createElement('p');
    title.textContent = `${model.name} · ${model.kind === 'choice' ? '选择题' : model.kind === 'short_answer' ? '简答题' : '未识别，按简答题导入'}`;
    box.appendChild(title);
    const cols = document.createElement('div');
    cols.className = 'fields';
    ['front', 'back'].forEach(side => {
      const col = document.createElement('div');
      const head = document.createElement('strong');
      head.textContent = side === 'front' ? '正面字段' : '背面字段';
      col.appendChild(head);
      const selected = new Set(side === 'front' ? model.suggested_front : model.suggested_back);
      (model.fields || []).forEach((name, index) => {
        const row = document.createElement('label');
        const boxEl = document.createElement('input');
        boxEl.type = 'checkbox';
        boxEl.dataset.side = side;
        boxEl.value = String(index);
        boxEl.checked = selected.has(index);
        row.append(boxEl, document.createTextNode(' ' + fieldLabel(name, index, model.sample)));
        col.appendChild(row);
      });
      cols.appendChild(col);
    });
    box.appendChild(cols);
    mappingHost.appendChild(box);
  });
}

function collectMapping() {
  const mapping = {};
  mappingHost.querySelectorAll('.model').forEach(box => {
    const id = box.dataset.modelId;
    const front = [];
    const back = [];
    box.querySelectorAll('input[type=checkbox]').forEach(input => {
      if (!input.checked) return;
      (input.dataset.side === 'front' ? front : back).push(Number(input.value));
    });
    mapping[id] = { front, back };
  });
  return mapping;
}

fileInput.addEventListener('change', async () => {
  if (!fileInput.files[0]) return;
  out.textContent = '正在解析字段…';
  const data = new FormData();
  data.append('apkg', fileInput.files[0]);
  const res = await fetch('/inspect', { method: 'POST', body: data });
  const text = await res.text();
  if (!res.ok) { out.textContent = text; return; }
  const parsed = JSON.parse(text);
  renderMapping(parsed);
  out.textContent = '已列出字段。背面不要勾正面内容，翻面就不会再看到题目。';
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  out.textContent = '转换中…';
  const data = new FormData(form);
  data.set('mapping', JSON.stringify(collectMapping()));
  const res = await fetch('/convert', { method: 'POST', body: data });
  out.textContent = await res.text();
});
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def do_GET(self):
        if self.path not in ("/", "/index.html"):
            self.send_error(404)
            return
        body = HTML.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path not in ("/convert", "/inspect"):
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            content_type = self.headers.get("Content-Type", "")
            if "multipart/form-data" not in content_type:
                raise ValueError("expected multipart form upload")
            boundary = content_type.split("boundary=")[-1].encode()
            fields, files = _parse_multipart(raw, boundary)
            if "apkg" not in files:
                raise ValueError("apkg file is required")
            filename, blob = files["apkg"]
            with tempfile.TemporaryDirectory() as tmp:
                apkg_path = Path(tmp) / (filename or "deck.apkg")
                apkg_path.write_bytes(blob)
                if self.path == "/inspect":
                    report = inspect_apkg(apkg_path)
                    body = json.dumps(report, ensure_ascii=False, indent=2).encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json; charset=utf-8")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                outdir = Path(fields.get("outdir", "").strip()).expanduser()
                if not fields.get("outdir"):
                    raise ValueError("outdir is required")
                outdir.mkdir(parents=True, exist_ok=True)
                ai = {}
                if fields.get("endpoint"):
                    ai["endpoint"] = fields["endpoint"].strip()
                if fields.get("model"):
                    ai["model"] = fields["model"].strip()
                field_mapping = None
                if fields.get("mapping"):
                    field_mapping = json.loads(fields["mapping"])
                    if not isinstance(field_mapping, dict):
                        raise ValueError("mapping must be a JSON object")
                package = import_apkg(
                    apkg_path, ai or None, field_mapping,
                    title=(fields.get("title") or "").strip() or None,
                )
                bundle = write_kindle_bundle(package, apkg_path, outdir)
            report = {
                "ok": True,
                "output": str(bundle["json"]),
                "zip": str(bundle["zip"]),
                "media_dir": str(bundle["media_dir"]),
                "cards": len(package.get("cards", [])),
                "images": bundle["extracted"],
                "next": "Copy the .kindle-anki.zip onto the Kindle, then Kindle Anki → Import pack.",
            }
            body = json.dumps(report, ensure_ascii=False, indent=2).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as exc:  # noqa: BLE001 - show to local user
            body = ("ERROR: %s\n\n%s" % (exc, traceback.format_exc())).encode("utf-8")
            self.send_response(500)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)


def _parse_multipart(raw: bytes, boundary: bytes):
    fields = {}
    files = {}
    parts = raw.split(b"--" + boundary)
    for part in parts:
        if part in (b"", b"--", b"--\r\n", b"\r\n"):
            continue
        if part.startswith(b"--"):
            continue
        if part.startswith(b"\r\n"):
            part = part[2:]
        if part.endswith(b"\r\n"):
            part = part[:-2]
        header_blob, _, body = part.partition(b"\r\n\r\n")
        headers = header_blob.decode("utf-8", "replace")
        disposition = ""
        for line in headers.split("\r\n"):
            if line.lower().startswith("content-disposition:"):
                disposition = line
        name = None
        filename = None
        for item in disposition.split(";"):
            item = item.strip()
            if item.startswith("name="):
                name = item.split("=", 1)[1].strip().strip('"')
            if item.startswith("filename="):
                filename = item.split("=", 1)[1].strip().strip('"')
        if not name:
            continue
        if filename is not None:
            files[name] = (filename, body)
        else:
            fields[name] = body.decode("utf-8", "replace")
    return fields, files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Kindle import UI on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
