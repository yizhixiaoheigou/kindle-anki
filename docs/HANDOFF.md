---
knowledge-role: handoff
---
# Kindle Anki — handoff

The one current hand-off. Rewrite it in place; history goes to
[PROJECT_HISTORY.md](PROJECT_HISTORY.md). Updated 2026-10-08.

## Where things stand

- `main` holds everything: the 2026-10-07 audit fixes, the old-KOReader
  plain-text fallback, the plugin and browser-page redesign, the QR code on
  the import screen, one global AI setting with the same three setup routes
  as importing packs, and DeepSeek as the suggested AI provider.
- The maintainer's Kindle (KOReader v2026.07.1) was reset on 2026-10-08:
  plugin, packs, progress, and AI settings removed, then a fresh plugin
  installed so the owner can walk the first-run flows. A backup of the old
  data is on the maintainer's computer. Its KOReader SSH server autostarts
  with key-only login, and remote restart is enabled.
- Full suite on the Mac passes with `KINDLE_ANKI_REQUIRE_TOOLS=1`.

## Next

1. The owner is walking the first-run flows (import a pack, set up AI) on
   the Kindle. Fix what they report, deploy with
   `scripts/kindle-deploy.sh <kindle-ip>` (installs, verifies, restarts
   KOReader), and use `--crash-log` for crashes. Do not ask for USB.
2. Watch the first CI run after a push: it is the first one that installs
   Lua (`.github/workflows/ci.yml`).
3. A friend on old KOReader needs the new plugin; confirm the plain-text
   cards and the View images button there.
4. `deepseek-flash` is the owner's chosen default model name; it was not
   checked against DeepSeek's model list.

## Not verified on a device

- Zip import through `ffi/archiver` (KOReader 2025.08+) and the `unzip`
  fallback on busybox.
- The plain-text fallback on KOReader older than v2026.07.

## Open, not scheduled

- Audit N4: `tests/test_kindle_schedule.py` tests a Python copy of
  `schedule.lua`; replace it with a Lua harness.
- AI HTTPS certificate verification needs a CA bundle decision.

## Key paths

- Plugin: `plugin/kindleanki.koplugin/` (UI in `main.lua`, data in `store.lua`,
  `:8767` server in `webserver.lua`, page in `web/`).
- Lua harnesses: `tests/lua_harness/`; run the suite on the Mac (CLAUDE.md).
- Deploy: `scripts/kindle-deploy.sh`.
