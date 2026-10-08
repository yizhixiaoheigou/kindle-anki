---
knowledge-role: handoff
---
# Kindle Anki — handoff

The one current hand-off. Rewrite it in place; history goes to
[PROJECT_HISTORY.md](PROJECT_HISTORY.md). Updated 2026-10-08.

## Where things stand

- `main` (`4fb65d7`) holds the 2026-10-07 audit fixes and the old-KOReader
  plain-text fallback. It is 14 commits ahead of `origin/main` and not pushed;
  pushing is the owner's call (AGENTS.md red line).
- `feature/ui-redesign` (`8cfd6ea`, 5 commits on top of `main`) holds the
  plugin and browser-page redesign, the Tools menu move, the Manage packs
  crash fix, and the wireless deploy script with remote restart. Not merged.
- The maintainer's Kindle (KOReader v2026.07.1) runs `feature/ui-redesign`.
  Its KOReader SSH server autostarts with key-only login, and remote restart
  is enabled on it.
- Full suite on the Mac: 83 tests pass with `KINDLE_ANKI_REQUIRE_TOOLS=1`.

## Next

1. The owner is testing the redesign on the Kindle. Fix what they report,
   deploy with `scripts/kindle-deploy.sh <kindle-ip>` (it installs, verifies,
   and restarts KOReader), and use `--crash-log` for crashes. Do not ask for
   USB.
2. When the owner approves, merge `feature/ui-redesign` into `main`.
3. If the owner pushes: watch the first CI run, which is the first one that
   installs Lua (`.github/workflows/ci.yml`).
4. The friend on old KOReader needs the new plugin; confirm the plain-text
   cards and the View images button there.

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
