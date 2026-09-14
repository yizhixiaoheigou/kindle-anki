# Changelog

Notable changes to Kindle Anki. Format follows Keep a Changelog.

## 0.1.0 — unreleased

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
