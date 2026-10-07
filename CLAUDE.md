<p align="right">
  <a href="CLAUDE.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Product boundaries, red lines, and doc rules live in [`AGENTS.md`](./AGENTS.md) — read it first. This file adds commands and architecture only.

## Commands

```bash
# All host tests (same as CI, which runs Python 3.11–3.13)
python3 -m unittest discover -s tests -p 'test_kindle_*.py'

# One file / one test
python3 -m unittest tests.test_kindle_schedule
python3 -m unittest tests.test_kindle_cards.KindlePackTests.test_round_trip_and_rebuild_deck_card_ids

# Desktop converter (stdlib + Tk only, no install needed)
python3 tools/kindle_import_app.py
python3 tools/kindle_anki_importer.py --help   # CLI converter
```

- The UI tests import `tkinter` at module level, so use a Python that has Tcl/Tk.
- `test_kindle_web_converter.py` needs `node`. The `test_kindle_*_lua.py` files need `lua`/`luajit` (the web server one also needs luasocket). Each **skips silently** when its tool is missing, so a green run without them has not covered the browser converter or the plugin's Lua. Set `KINDLE_ANKI_REQUIRE_TOOLS=1` to make a missing tool fail instead; CI sets it and installs Lua 5.4, luasocket, and node.
- The maintainer's Linux VM has no `tkinter` or `lua`. Run the full suite on the Mac with `mac-run python3 -m unittest discover -s tests -p 'test_kindle_*.py'`, which has Tk, `lua`, and `node`, so nothing skips.
- CI fails if `tools/anki_importer.py` or `tools/folo_*.py` exists.
- `requirements-dev.txt` (PyInstaller, Pillow) is for packaging only. Build steps are in `packaging/README.md`. `.venv`/`.venv-x86_64` are macOS build venvs.

## Architecture

There are three parts. They share one contract, the **pack format** (`docs/PACK_FORMAT.md`): `name.kindle-anki.json` + sibling `name.kindle-anki.media/`, zipped as `name.kindle-anki.zip`.

1. **Desktop converter (`tools/`, Python stdlib).** `kindle_apkg.py` reads the `.apkg` SQLite collection. `kindle_anki_importer.py` maps notes to cards: Basic-style notes become `short_answer`, notes with `||` option fields become `choice`. It also has `inspect_apkg`, which drives field mapping. `kindle_cards.py` defines the canonical pack schema (`FORMAT_NAME = "kindle-anki"`). `kindle_bundle.py` writes the JSON, media, and zip, and strips `ai.api_key`. `kindle_import_app.py` is the Tk window, with visual tokens in `kindle_import_ui.py`. It also runs `kindle_pack_server.py`, the LAN server on `:8766` that the plugin pulls from, and handles AI-settings pairing with a 4-digit code. Test modules add `tools/` to `sys.path` and import modules by bare name.

2. **Browser converter (`plugin/kindleanki.koplugin/web/*.js`).** This is a JS port of the Python pipeline. It is served by the plugin, runs in the phone or computer browser, and uploads a finished pack. `test_kindle_web_converter.py` runs both converters on the same synthetic `.apkg` and requires field-identical packs, zip layouts, and inspect reports. **Any change to the conversion logic must be made in both Python and JS.**

3. **KOReader plugin (`plugin/kindleanki.koplugin/`, Lua, AGPL).**
   - `main.lua` holds the menu (Tools → More tools → Kindle Anki), the review UI for both card families, the imports (USB, `:8766` pull, browser page), and AI settings.
   - `store.lua` handles pack and progress persistence under `/mnt/us/kindle-anki/{packs,ai}`, and dual-reads legacy `/mnt/us/folo-anki/`.
   - `schedule.lua` is day-based SM-2. Again = 10 min.
   - `ai.lua` makes a direct POST to `/v1/chat/completions` with bounded history, and sends card images as base64.
   - `webserver.lua` is the unauthenticated `:8767` server. It serves `web/` plus `/api/info`, `/api/packs` (GET/POST/DELETE), and `/api/ai-settings`.
   - `i18n.lua` is the bundled zh_CN catalog.

   The plugin never parses `.apkg`. It only accepts finished packs.

Plugin tests are mostly **static contract checks**: `test_kindle_plugin.py` asserts that specific strings and tokens appear in the Lua sources. When you rename a UI string, i18n key, or code idiom, update those assertions on purpose. The only runtime Lua coverage is `tests/lua_harness/run_webserver.lua`, which stubs KOReader modules.
