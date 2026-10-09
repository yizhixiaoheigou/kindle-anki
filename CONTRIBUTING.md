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

Use a Python with Tcl/Tk — the UI tests import `tkinter` at module level.
The plugin tests need `lua` with luasocket and the browser-converter tests
need `node`; without them those tests skip silently. Run with
`KINDLE_ANKI_REQUIRE_TOOLS=1` to make a missing tool fail instead, as CI does.

To try a change on a Kindle, `scripts/kindle-deploy.sh <kindle-ip>` installs
the plugin over KOReader's SSH server and restarts KOReader; `--crash-log`
prints the end of KOReader's crash log. One-time setup is described at the top
of the script.

Do not add `tools/anki_importer.py` or `tools/folo_*.py`.

## Pull requests

Title: `<type>(<scope>): …` with scopes `plugin`, `converter`, `docs`, `ci`.

Docs: English `.md` plus Simplified Chinese `.zh_CN.md`.

Never commit API keys, `.apkg` decks, or personal pack JSON.
