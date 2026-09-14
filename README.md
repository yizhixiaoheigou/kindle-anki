<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Kindle Anki

Kindle Anki is a KOReader plugin that studies Anki `.apkg` decks (short-answer
and choice, with images) on a jailbroken Kindle. Conversion happens on a
computer. Progress stays on the Kindle.

**Not official Anki. Not AnkiWeb-compatible. Not an Amazon product. Not an
official KOReader plugin.**

## Screenshots

<p align="center">
  <img src="screenshots/converter-idle.jpg" width="24%" alt="Converter, idle">
  <img src="screenshots/converter-mapping.jpg" width="24%" alt="Converter, field mapping">
  <img src="screenshots/converter-converting.jpg" width="24%" alt="Converter, converting">
  <img src="screenshots/converter-success.jpg" width="24%" alt="Converter, done and sharing over Wi-Fi">
</p>

## Who this is for

- A jailbroken Kindle with KOReader.
- Anki decks you already have as `.apkg` (choice cards and images included).

Not for stock Kindle ebooks. Not ESP32 hardware. Not AnkiWeb sync.

## Requirements

- Jailbroken Kindle with KOReader.
- A computer for conversion.
- Same **home** Wi-Fi for import.

Prebuilt converter apps are unsigned local builds (a macOS universal2 `.app`
and a Windows onedir) — see [packaging/README.md](packaging/README.md). Without
one, install Python 3 with Tcl/Tk from python.org and use
`desktop/Kindle-Anki-Import.command` (macOS) or `desktop/Kindle-Anki-Import.bat`
(Windows).

## Install the plugin

Unzip so `kindleanki.koplugin/` is a folder. Copy it to
`/mnt/us/koreader/plugins/kindleanki.koplugin/`. If upgrading from
`foloanki.koplugin`, delete the old folder. Eject. **Fully quit KOReader and
reopen.**

Details: [docs/USER_GUIDE.md](docs/USER_GUIDE.md). Old paths:
[docs/MIGRATION.md](docs/MIGRATION.md).

## Convert a deck

macOS: `desktop/Kindle-Anki-Import.command` (needs python3 + Tk) or
`dist/Kindle Anki Import.app` if present. Windows: `desktop/Kindle-Anki-Import.bat`,
or the `Kindle-Anki-Import` onedir if present.

Pick `.apkg`, name the pack (defaults to the deck name), map front/back
fields, Convert. Output: `name.kindle-anki.zip`.

## Import over Wi-Fi

Keep the converter open. **Tools → More tools → Kindle Anki → Import from computer** and
type the printed IP. The LAN server on port 8766 has **no password** and is
home-Wi-Fi only. USB **Import pack** is the fallback.

## Study

Start studying / starred / retry missed / Browse. Daily new-card count is asked
on first open of a pack (1–999). Again = 10 minutes. Hard/Good/Easy use day
SM-2. No reverse cards, no tag filter, no AnkiWeb.

## Optional AI

**Tools → More tools → Kindle Anki → AI settings.** Endpoint, model, and API key stay **on
the Kindle**. Direct HTTPS POST `/v1/chat/completions`. Card images are sent along as
base64 when a card has them. Thinking tags are
hidden, not disabled. Pack JSON does not carry keys. Plain `http://` endpoints send the
key unencrypted — prefer `https://`.

## What is not synced

No AnkiWeb. No desktop Anki. No hardware progress sync.

## Versus KAnki / anki.koplugin

This tool **converts existing `.apkg`** (choice + images) on a computer and
reviews them in KOReader with an independent scheduler. It does not speak
AnkiConnect and does not sync.

## Development

```bash
python3 -m unittest discover -s tests -p 'test_kindle_*.py'
```

See [CONTRIBUTING.md](CONTRIBUTING.md). Pack format: [docs/PACK_FORMAT.md](docs/PACK_FORMAT.md).

## License

MIT. Copyright (c) 2026 yizhixiaoheigou. The KOReader plugin
(`plugin/kindleanki.koplugin/`) is licensed AGPL-3.0-or-later, like KOReader
itself. Third-party code and trademark notes:
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
