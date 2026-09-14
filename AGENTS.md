<p align="right">
  <a href="AGENTS.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Kindle Anki — agent notes

Standalone KOReader plugin plus desktop converter. Not ESP32 firmware. Not AnkiWeb.

## Product boundary

- Computer converts `.apkg`. The plugin never unpacks Anki files.
- Progress stays on the Kindle. Do not sync to AnkiWeb, desktop Anki, or hardware.
- Never write API keys into pack JSON. Keys live in KOReader plugin settings.
- LAN pack server (`:8766`) is unauthenticated home-Wi-Fi only.
- Dual-read legacy `/mnt/us/folo-anki/` and `foloanki.koplugin`. Do not auto-delete them. Do not rewrite existing pack JSON.

## Validation

```bash
python3 -m unittest discover -s tests -p 'test_kindle_*.py'
```

Do not add `tools/anki_importer.py` or `tools/folo_*.py`.

## Docs

English `.md` plus Simplified Chinese `.zh_CN.md`. Keep both aligned.

## Red lines

Do not `git push`, create a new public GitHub repository, publish a Release, or delete user data without the repository owner's approval.
