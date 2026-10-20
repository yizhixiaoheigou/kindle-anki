#!/usr/bin/env python3
"""Build the computer converter: the plugin's browser import page as one
offline HTML file. It converts .apkg files and downloads the pack; it never
talks to a Kindle (app.js reads KINDLE_ANKI_STANDALONE).

    python3 packaging/build_standalone_html.py dist/release/Kindle-Anki-converter.html
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


WEB = Path(__file__).resolve().parent.parent / "plugin" / "kindleanki.koplugin" / "web"
SCRIPTS = ("apkg.js", "convert.js", "app.js")
TITLE = "Kindle Anki 转换器"


def build() -> str:
    page = (WEB / "index.html").read_text(encoding="utf-8")
    page, count = re.subn(r"<title>[^<]*</title>", f"<title>{TITLE}</title>", page)
    if count != 1:
        raise SystemExit("index.html: expected one <title>")
    page = page.replace("正在连接 Kindle…", "", 1)
    tags = "\n".join(f'<script src="{name}"></script>' for name in SCRIPTS)
    if page.count(tags) != 1:
        raise SystemExit("index.html: expected the three script tags together")
    inline = ["<script>window.KINDLE_ANKI_STANDALONE = true;</script>"]
    for name in SCRIPTS:
        source = (WEB / name).read_text(encoding="utf-8")
        # A script tag inside the source would end or confuse the inline block.
        if re.search(r"</?script", source, re.IGNORECASE):
            raise SystemExit(f"{name} contains a script tag; it cannot be inlined")
        inline.append(f"<script>\n{source}\n</script>")
    page = page.replace(tags, "\n".join(inline), 1)
    if re.search(r"<script[^>]*\ssrc=", page) or "<link" in page:
        raise SystemExit("standalone page still loads an external file")
    return page


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    out = Path(argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(build(), encoding="utf-8")
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
