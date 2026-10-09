---
knowledge-role: handoff
---
# Kindle Anki — handoff

The one current hand-off. Rewrite it in place; history goes to
[PROJECT_HISTORY.md](PROJECT_HISTORY.md). Updated 2026-10-09.

## Where things stand

- `main` equals `origin/main` (pushed 2026-10-09). CI passed on Python
  3.11–3.13 with Lua, luasocket, and node installed and
  `KINDLE_ANKI_REQUIRE_TOOLS=1`, so no test was skipped.
- The maintainer's Kindle (KOReader v2026.07.1) runs `aa75187`: it lacks the DeepSeek defaults (`8232f84`) and the `#ai`
  hashchange fix (`aa69f6c`). It was reset to a first-run state on
  2026-10-08; the old packs, progress, and AI settings are in
  `~/kindle-anki-backups/kindle-data-before-reset-20261008.tar` on the Mac.
  Its KOReader SSH server autostarts (key only) and remote restart is on.

## Next

1. When the Kindle is awake, run `scripts/kindle-deploy.sh <kindle-ip>` to
   bring it to `main` (it installs, verifies, and restarts KOReader). Do not
   ask for USB; use `--crash-log` for crashes.
2. The owner is walking the first-run flows (import a pack, set up AI). Fix
   what they report.
3. A friend on old KOReader needs the new plugin; confirm the plain-text cards
   and the View images button there.

## Open, not scheduled

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
