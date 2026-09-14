<p align="right">
  <a href="CONTRIBUTING.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Contributing

This repository is a KOReader plugin and a desktop Python converter. There is
no ESP-IDF, no `idf.py`, no firmware `validate.sh`, no BSP, and no BLE.

## Checks

```bash
python3 -m unittest discover -s tests -p 'test_kindle_*.py'
```

Do not add `tools/anki_importer.py` or `tools/folo_*.py`.

## Pull requests

Title: `<type>(<scope>): …` with scopes `plugin`, `converter`, `docs`, `ci`.

Docs: English `.md` plus Simplified Chinese `.zh_CN.md`.

Never commit API keys, `.apkg` decks, or personal pack JSON.
