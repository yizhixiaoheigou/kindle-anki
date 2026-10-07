# Changelog

Notable changes to Kindle Anki. Format follows Keep a Changelog.

## Unreleased

- Fixed: the plugin now refuses packs whose choice cards have non-integer,
  out-of-range, or duplicate `correct_indices`, non-text options, or non-text
  `expected_answers`, matching the converter's own rules. Such a pack used
  to load and then crash KOReader when the card's answer was shown.
- Security: the converter's `/ai-settings` endpoint (`:8766`) now locks after
  5 wrong pairing codes; saving the AI settings again issues a new code. The
  code comes from `secrets` instead of `random`. Before this, the 4-digit code
  could be brute-forced from the LAN in about a second, leaking the API key.
- Security: **Remember on this computer** now writes
  `~/.kindle-anki/ai-settings.json` as 0600 and tightens an existing file.
  Note that 0.1.0 said the key is stored only on the Kindle; with this option
  on, it is also stored in plain text on the computer.
- Fixed cards showing raw HTML (`<div style=…>`, `&#39;`) on KOReader older than
  v2026.07, whose TextViewer cannot render HTML. Those builds now get plain
  text, and card images open from a **View images** button. The AI chat
  "Previous page"/"Next page" buttons no longer crash on those builds.
- Added **Import via browser**: the plugin now opens a small LAN page
  (`http://<kindle-ip>:8767`) where a phone or computer browser converts an
  `.apkg` entirely in the browser and uploads the finished pack straight onto
  the Kindle. No desktop converter or USB needed; the Kindle still never
  unpacks Anki files — only finished kindle-anki zips are accepted. The
  browser converter is a byte-compatible port of the Python pipeline
  (`plugin/.../web/`), pinned by Node↔Python conformance tests. The page can
  also push AI settings (endpoint/model/API key) onto the Kindle with the
  4-digit pairing code shown in the same dialog — write-only, never readable
  back through the page, JSON-only, and locked after 5 wrong codes. The page also lists existing packs and can delete
  them (progress and AI chats included) through the plugin's own guards.
- Added "Setup with an AI" (`docs/SETUP_WITH_AI.md`): hand the page to any AI
  assistant, plug the Kindle in over USB, and the AI installs the plugin,
  converts, and imports packs. When KOReader is missing, the guide walks
  through installing MRPI and KOReader (jailbreak is only pointed to, never
  taught).

## 0.1.0 — 2026-09-15

Initial public release.

- KOReader plugin `kindleanki.koplugin`: study `*.kindle-anki.zip` packs with
  short-answer and choice cards (images included), a day-granularity SM-2
  scheduler, starred and retry-missed queues, USB and LAN (port 8766) pack
  import, a daily new-card limit, and optional direct-to-AI explanations with
  the API key stored only on the Kindle.
- Desktop converter: `.apkg` to Kindle pack with front/back field mapping
  (Tkinter app, web page fallback, USB share). Runtime is stdlib-only. Packs
  are named after the deck by default, with an optional pack-name field before
  converting; the name labels the pack on the Kindle and the output files.
- AI setup without typing: paste endpoint/model/key into the converter's
  AI settings and pull them onto the Kindle with a 4-digit pairing code.
  Keys still never touch pack JSON.
- Unsigned prebuilt apps via PyInstaller: macOS universal2 `.app` and a Windows
  onedir, assembled locally (see packaging/README.md).
- Docs: user guide, pack format, migration from `foloanki`; English and
  Simplified Chinese throughout.
