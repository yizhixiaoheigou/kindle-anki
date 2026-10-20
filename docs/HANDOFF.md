---
knowledge-role: handoff
---
# Kindle Anki — handoff

The one current hand-off. Rewrite it in place; history goes to
[PROJECT_HISTORY.md](PROJECT_HISTORY.md). Updated 2026-10-20.

## Where things stand

- `origin/main` was last pushed 2026-10-09. CI passed on Python
  3.11–3.13 with Lua, luasocket, and node installed and
  `KINDLE_ANKI_REQUIRE_TOOLS=1`, so no test was skipped.
- The maintainer's Kindle (KOReader v2026.07.1) runs `aa75187`: it lacks the DeepSeek defaults (`8232f84`) and the `#ai`
  hashchange fix (`aa69f6c`). It was reset to a first-run state on
  2026-10-08; the old packs, progress, and AI settings are in
  `~/kindle-anki-backups/kindle-data-before-reset-20261008.tar` on the Mac.
  Its KOReader SSH server autostarts (key only) and remote restart is on.
- Local `main` holds 0.2.0 (annotated tag `v0.2.0`), not pushed yet. The
  suite passed on the Mac with `KINDLE_ANKI_REQUIRE_TOOLS=1`, and the browser
  page was checked in headless Chrome, served and as the offline file.
- The computer converter is now the browser page as one offline HTML file
  (`packaging/build_standalone_html.py`). The release ships only the plugin
  zip and that HTML; the PyInstaller `.app`/Windows builds and the Python
  fallback zip are no longer released, so no Windows machine is needed.

## Next

1. Publish 0.2.0 from the Mac Terminal: `./packaging/make_release_zips.sh
   0.2.0`, push `main` and `v0.2.0`, then `gh release create` with
   `kindleanki.koplugin-v0.2.0.zip` and `Kindle-Anki-converter-v0.2.0.html`
   and `RELEASE_NOTES-v0.2.0.md`. Tell the reporter to re-export with
   "Support older Anki versions" checked.
2. When the Kindle is awake, run `scripts/kindle-deploy.sh <kindle-ip>` to
   bring it to `main` (it installs, verifies, and restarts KOReader). Do not
   ask for USB; use `--crash-log` for crashes.
3. The owner is walking the first-run flows (import a pack, set up AI). Fix
   what they report.
4. A friend on old KOReader needs the new plugin; confirm the plain-text cards
   and the View images button there.
5. Decide whether to retire the Tk app: the plugin's **Computer converter over
   Wi-Fi** import and AI pairing (`:8766`) only work with the Python app run
   from source now. Removing them would drop `kindle_import_app.py`,
   `kindle_import_ui.py`, `kindle_pack_server.py`, the PyInstaller files, and
   their tests; the Python converter itself stays as the parity reference
   and CLI.

## Open, not scheduled

- Left from the 0.2.0 review. Converter:
  - default fields from the card templates (front = question side);
  - MathJax/LaTeX and furigana shown raw;
  - `{{edit:cloze:…}}` not seen as a cloze field;
  - a `<style>`/`<script>` field dropped whole as "empty";
  - Image Occlusion Enhanced add-on notes not detected;
  - new cards ordered by id, not Anki's due order.

  Plugin:
  - untouched card defaults stored in settings, so the file grows with each
    pack;
  - delete from the web page during an open session brings progress back;
  - the `unzip` fallback has no symlink or unpacked-size guard;
  - JSON is copied before media, and write errors are ignored;
  - `DELETE /api/packs` needs no pairing code;
  - an endpoint-only AI settings save keeps the old key;
  - "Fetching…" screens never paint;
  - store and server errors are shown in English.

- Reading new-format exports (`collection.anki21b`) directly would remove
  the re-export step that most users hit. It needs a zstd decoder in both
  Python (stdlib has none before 3.14) and JS, a schema-18 reader
  (`notetypes`/`fields`/`templates`/`decks` tables with protobuf configs),
  and the zstd media map, all kept field-identical across both converters.
- On KOReader before v2026.07, an image-only front is a blank page with only
  the View images button.

- README's two Kindle photos show the pre-redesign screens (captioned so).
  Replacing them needs KOReader screenshots taken on the device; the owner
  declined for now.
- `deepseek-flash` is the owner's chosen default model name; not checked
  against DeepSeek's model list.
- Zip import through `ffi/archiver` (KOReader 2025.08+) and the `unzip`
  fallback on busybox are tested only in harnesses, not on a device.
- Audit N4: `tests/test_kindle_schedule.py` tests a Python copy of
  `schedule.lua`; replace it with a Lua harness.
- AI HTTPS certificate verification needs a CA bundle decision.
- The browser page (and so the offline converter) and the Tk app are Chinese only; the plugin has
  zh_CN/en via `i18n.lua`. Offered, not requested.

## Key paths

- Plugin: `plugin/kindleanki.koplugin/` (UI in `main.lua`, data in `store.lua`,
  `:8767` server in `webserver.lua`, QR screen in `importdialog.lua`, page in
  `web/`).
- Lua harnesses: `tests/lua_harness/`; run the suite on the Mac (CLAUDE.md).
- Deploy: `scripts/kindle-deploy.sh`. Pushing to GitHub is done by the owner
  from the Mac's Terminal.
