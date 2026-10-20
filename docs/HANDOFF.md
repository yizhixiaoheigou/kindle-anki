---
knowledge-role: handoff
---
# Kindle Anki — handoff

The one current hand-off. Rewrite it in place; history goes to
[PROJECT_HISTORY.md](PROJECT_HISTORY.md). Updated 2026-10-20.

## Where things stand

- `main` equals `origin/main` (pushed 2026-10-09). CI passed on Python
  3.11–3.13 with Lua, luasocket, and node installed and
  `KINDLE_ANKI_REQUIRE_TOOLS=1`, so no test was skipped.
- The maintainer's Kindle (KOReader v2026.07.1) runs `aa75187`: it lacks the DeepSeek defaults (`8232f84`) and the `#ai`
  hashchange fix (`aa69f6c`). It was reset to a first-run state on
  2026-10-08; the old packs, progress, and AI settings are in
  `~/kindle-anki-backups/kindle-data-before-reset-20261008.tar` on the Mac.
  Its KOReader SSH server autostarts (key only) and remote restart is on.
- Branch `feat/converter-skip-reasons-cloze-images` (2 commits on `main`,
  not merged or pushed) answers a user report of "no importable cards". The
  user's `.apkg` was a default Anki export: real cards in the zstd-compressed
  `collection.anki21b`, plus a placeholder `collection.anki2` with one
  "please update Anki" note. The converters now refuse such files with
  re-export steps. The branch also adds Cloze cards, image-only sides, skip
  reasons in the error, and better default back fields. See CHANGELOG
  "Unreleased". The full suite passes on the Mac with
  `KINDLE_ANKI_REQUIRE_TOOLS=1`, and the browser page was checked in
  headless Chrome.

## Next

1. Owner: review and merge the branch, push, rebuild the Windows package
   (`packaging/README.md`) for the reporter, and deploy the plugin so the
   browser page on the Kindle has the fix. Tell the reporter to re-export
   with "Support older Anki versions" checked.
2. When the Kindle is awake, run `scripts/kindle-deploy.sh <kindle-ip>` to
   bring it to `main` (it installs, verifies, and restarts KOReader). Do not
   ask for USB; use `--crash-log` for crashes.
3. The owner is walking the first-run flows (import a pack, set up AI). Fix
   what they report.
4. A friend on old KOReader needs the new plugin; confirm the plain-text cards
   and the View images button there.

## Open, not scheduled

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
- The browser page and desktop converter are Chinese only; the plugin has
  zh_CN/en via `i18n.lua`. Offered, not requested.

## Key paths

- Plugin: `plugin/kindleanki.koplugin/` (UI in `main.lua`, data in `store.lua`,
  `:8767` server in `webserver.lua`, QR screen in `importdialog.lua`, page in
  `web/`).
- Lua harnesses: `tests/lua_harness/`; run the suite on the Mac (CLAUDE.md).
- Deploy: `scripts/kindle-deploy.sh`. Pushing to GitHub is done by the owner
  from the Mac's Terminal.
