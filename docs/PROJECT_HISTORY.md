---
knowledge-role: project-history
---
# Kindle Anki — project history

One milestone chain from the first release to now. What is current and what
to do next lives in [HANDOFF.md](HANDOFF.md); commit-level detail lives in git
and [CHANGELOG.md](../CHANGELOG.md). Single-language by design (see AGENTS.md).

## 2026-09-15 — 0.1.0: plugin and desktop converter (`d058987`, tag `v0.1.0` at `97b7cd7`)

- Shipped the KOReader plugin (short-answer and choice cards, day-based SM-2,
  AI explain) and the Tk desktop converter with its `:8766` LAN pack server.
- First audit (`docs/AUDIT.md`, local only, git-ignored) found H1–H2 and
  M1–M9; all were fixed the same day (`5a5d9f2`, `fe73f0e`).
- An independent review (`docs/AUDIT-2026-09-15-independent-review.md`, local
  only) added N1–N6. They stayed open until 2026-10-07 (below).
- Type-free AI setup: keys pasted in the converter, pulled to the Kindle with a
  4-digit pairing code (`97b7cd7`).
- The converter window redesign ([converter-ui-redesign.md](converter-ui-redesign.md),
  historical) landed in the same release.

## 2026-09-17 — AI-assisted setup guide

- [SETUP_WITH_AI.md](SETUP_WITH_AI.md): hand the page to any AI assistant and
  plug in USB; it installs the plugin and imports packs, and points to (never
  teaches) jailbreaking.

## 2026-09-29 — browser import on the Kindle (`59c709e`)

- The plugin serves `:8767`: a phone or computer browser converts the `.apkg`
  with a JS port of the Python pipeline and uploads the finished pack. Node vs
  Python conformance tests pin the two converters together.

## 2026-10-07 — old-KOReader fix and a full audit

- A user on KOReader older than v2026.07 saw raw HTML on cards: `TextViewer`
  only renders HTML since koreader#15588. The plugin now detects
  `TextViewer.html_text_formats` and falls back to plain text, with images in
  `ImageViewer` (`3a086f7`). Verified in a Lua harness only.
- Audit of the whole project; fixes on `main`:
  - N1/N2: converter pairing locks after 5 wrong codes, `secrets` codes, key
    file 0600 (`65cd60c`).
  - N3: plugin rejects packs whose cards would crash the review UI (`b37091a`).
  - `:8767` refuses cross-site uploads and DNS rebinding (`b807d78`).
  - Zip extraction moved to KOReader's `ffi/archiver` (the old code required a
    non-existent `ffi/archive`); the `unzip` fallback fails closed (`089eb9a`).
  - Import page idles at 0.5 s polling and stops after 30 minutes (`bf35365`).
  - N5/N6: study day follows local midnight; Language menu (`95407b2`).
  - Duplicate imports are reported, downloads capped (`6eaeaab`, `668b9d1`).
  - AI HTTPS does not verify certificates: documented in SECURITY.md, not
    fixed (`822d476`).
  - CI installs Lua and node and fails instead of skipping (`4fb65d7`).
- Left open: N4 (the Python schedule mirror can drift from `schedule.lua`;
  a Lua schedule harness now covers the day boundary only).
- Pitfall: `for _, x in ...` rebinds the `_` translator; calling `_()` inside
  the loop crashes KOReader. A static test now rejects it.

## 2026-10-07/08 — UI redesign and wireless deploy (branch `feature/ui-redesign`)

- Plugin: full-screen pack list with today's counts, deck screen with today's
  plan and counted actions, single-deck packs skip the deck list, answer
  screen with the question above the answer and ratings in one row, round
  summary; menu moved from Tools → More tools to Tools (`42400fa`, `70b31b5`).
- Browser page: Import / Packs / AI tabs, front/back toggles with a live
  Kindle preview of the first note, one convert-and-send button (`42400fa`).
- The redesign introduced the `_` shadowing crash in Manage packs; found from
  `crash.log` and fixed (`8847327`).
- `scripts/kindle-deploy.sh` installs over KOReader's SSH server (key only,
  port 2222), verifies MD5s, keeps a rollback copy, and restarts KOReader
  through the plugin's developer hook, which only runs on a Kindle with the
  `/mnt/us/kindle-anki/dev-remote-restart` marker (`79417eb`, `8cfd6ea`).
  Never kill KOReader instead: it drops unsaved settings and progress.
- The plugin now flushes batched progress on KOReader's FlushSettings
  (`8cfd6ea`).
