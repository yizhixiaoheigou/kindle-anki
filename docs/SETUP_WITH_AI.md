<p align="right">
  <a href="SETUP_WITH_AI.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Setup with an AI — give this page to any AI assistant

**How to use**: send this page's link to an AI assistant (ZCode, Claude,
ChatGPT, …) with the message "Follow this document exactly and install Kindle
Anki on my Kindle." The only thing you do: **connect the Kindle to the
computer with a USB cable.**

---

## Instructions for the executing AI

Your task: install (or upgrade) the KOReader plugin **Kindle Anki** on the
user's Kindle, and convert/import Anki decks when asked. The user has already
connected the Kindle over USB. **Only touch the user partition (the mass-storage
part). Never touch the system partition; never delete user data.**

### Step 0: environment

1. Detect the OS (macOS / Windows).
2. Find the Kindle mount point:
   - macOS: `/Volumes/Kindle` (check with `ls /Volumes`)
   - Windows: a new drive letter (e.g. `E:`); ask the user in Explorer if unsure
3. Verify `<mount>/koreader/` exists (KOReader installed).
   **If missing, stop**: tell the user to install KOReader first
   (https://github.com/koreader/koreader/wiki). This tool does not provide
   jailbreaks or KOReader installation.
4. If `<mount>/koreader/plugins/foloanki.koplugin/` exists (the old
   predecessor): **do not delete it**; point the user to
   https://github.com/yizhixiaoheigou/kindle-anki/blob/main/docs/MIGRATION.md.

### Step 1: download

From https://github.com/yizhixiaoheigou/kindle-anki/releases/latest:

- `kindleanki.koplugin-v*.zip` — required (the plugin)
- `Kindle-Anki-converter-v*.zip` — only when converting `.apkg` decks
  (pure-stdlib Python, nothing to install)

### Step 2: install/upgrade the plugin

1. Unzip the plugin zip; you get a `kindleanki.koplugin/` folder.
2. Copy it to `<mount>/koreader/plugins/kindleanki.koplugin/`, replacing any
   older copy as a whole.
3. Verify `<mount>/koreader/plugins/kindleanki.koplugin/_meta.lua` exists and
   contains `version`.

### Step 3: convert a deck (when the user provides an `.apkg`)

Inside the unzipped converter directory run (stdlib only, any Python 3 ≥ 3.11):

```bash
python3 tools/kindle_anki_importer.py "/path/to/deck.apkg" -o "/path/to/out/name.kindle-anki.json"
```

Use `py -3` on Windows. Output: `name.kindle-anki.json` +
`name.kindle-anki.media/` + `name.kindle-anki.zip`. If the report shows many
`Skipped` cards, the deck may need field mapping — the GUI converter is
better for that (see Step 5 note).

### Step 4: put the pack on the device

Copy **the json and the media folder** (not the zip) to:

```
<mount>/kindle-anki/packs/name.kindle-anki.json
<mount>/kindle-anki/packs/name.kindle-anki.media/
```

Create the directory if needed. Alternative: copy just the zip anywhere onto
the device and let the user pick it via the plugin's "Import pack" menu.

### Step 5: finish (tell the user each item)

1. Safely eject the Kindle and unplug.
2. On the Kindle, **fully quit KOReader and reopen it** so the plugin loads.
3. Menu: **Tools → More tools → Kindle Anki**.
4. The first open of a pack asks for the daily new-card count (1–999, default 20).
5. Optional AI: open the converter on the computer (double-click
   `Kindle-Anki-Import.command` / `.bat`, or the packaged app from the
   release), click **AI settings**, paste the key; on the Kindle choose
   **Import AI settings from computer** and enter the computer IP plus the
   4-digit pairing code shown in the converter window. Both devices must be
   on the same Wi-Fi.

### Troubleshooting

| Symptom | Fix |
|---|---|
| Kindle mount point not found | different cable/port; replug while unlocked; Windows Disk Management |
| no `koreader/` directory | KOReader not installed — back to Step 0 |
| computer has no Python | install from https://www.python.org/downloads/ (with Tcl/Tk), or use the packaged converter from the release |
| macOS app won't open | unsigned: right-click → Open |
| Windows SmartScreen block | More info → Run anyway |
| Kindle Anki missing from the menu | KOReader was not fully restarted, or the plugin folder nesting is wrong |

### Red lines (never violate)

- Never delete or rewrite any existing data on the user's Kindle (especially
  the legacy `/mnt/us/folo-anki/` directory).
- Never write API keys into pack JSON; keys belong only to KOReader plugin
  settings.
- Never perform or guide jailbreaking.
- Do not touch anything else on the device after finishing.
