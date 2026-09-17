<p align="right">
  <a href="SETUP_WITH_AI.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Setup with an AI — give this page to any AI assistant

**How to use**: send this page's link to an AI assistant (ZCode, Claude,
ChatGPT, WorkBuddy, Doubao, …) with the message "Follow this document exactly
and install Kindle Anki on my Kindle." The only thing you do: **connect the
Kindle to the computer with a USB cable.** If the AI says it cannot find the
device, just follow the steps it gives you.

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

   **No mount point? Don't just tell the user to swap cables — first work out which
   kind of "not found" this is:**
   - Use the OS tools to see what identity the Kindle shows up as over USB:
     - macOS: `ioreg -p IOUSB -l -w 0 | grep -E '"USB Product Name"'`
       - **`RNDIS/Ethernet Gadget`** → case 1 below
       - **`Internal Storage`** → case 2 below
     - Windows: find it in Device Manager; an `RNDIS` / `NDIS` / network-adapter
       entry means case 1, a disk-drive / portable-device entry means case 2.
     (A vendor string containing `lab126`, or vendor ID `0x1949`, only tells you it
     is an Amazon device — it does **not** distinguish the two modes.)
   - **Case 1: the product name is `RNDIS/Ethernet Gadget` (USB ethernet mode).**
     That mode does not expose mass storage, so swapping cables or ports will never
     help. You must tell the user how to turn it off:
     1. On the Kindle, quit KOReader → **KUAL → USBNetwork → Toggle USBNetwork**
        (pick Disable if offered).
     2. **Unplug the USB cable, wait 3–5 seconds, then plug it back in** — the
        device is not re-enumerated without a replug; this step cannot be skipped.
     3. Re-check for the mount point.
     If the user's KUAL has no USBNetwork entry, ask them to describe or photograph
     the menus they see and judge from that. **Do not invent commands.**
   - **Case 2: the product name is `Internal Storage` (mass-storage mode) but there
     is still no drive.** The device is fine; the volume just is not attached —
     most often because it was "safely ejected" without the cable being unplugged.
     Do **not** send the user to toggle usbnet (it is not active in this mode). Have
     them **unplug, wait 3–5 seconds, and plug back in**; the drive should appear.
     Only if it still does not, suspect a damaged filesystem.
   - **The device is not visible at all** → only then is it cable/port/screen-lock:
     have the user try another cable or port, unlock the screen and replug once.

3. Verify `<mount>/koreader/` exists (KOReader installed). **If it does, skip to Step 1.**
   If not, follow the branches below instead of giving up.
   How to tell the two branches apart: look for jailbreak traces on the device (any
   one is enough) — `LanguageBreakRan`, `libkh/`, `mkk/`, `rp/`, `patchedUks.sqsh`.
   Present → Branch B; none at all → Branch A.

   **Branch A: the device is not jailbroken.**
   Tell the user plainly: KOReader requires a jailbroken Kindle; jailbreaking
   carries risks such as losing warranty and is the user's own decision. Point
   the way (do not perform it, do not provide jailbreak steps yourself):

   - Jailbreak index: the KOReader wiki's Installation on Kindle page
     (https://github.com/koreader/koreader/wiki) → prerequisites section,
     matching the device's firmware version
   - Once jailbroken, come back and continue with Branch B

   **Branch B: jailbroken, but no KOReader. You install it:**
   1. Open the Kindle install page at
      https://github.com/koreader/koreader/wiki (Installation on Kindle devices)
      and pick the method for the device's **firmware version** (the official page
      wins):
      - Firmware ≥ 5.16.3 → KUALA: install
        https://github.com/kasparcode/kuala/releases first
      - Firmware < 5.16.3 with KUAL already present → **unzip the package into the
        USB root**, then start it from KUAL
      - Jailbroken with WinterBreak (June 2026+), SpringBreak, Sanctuary, Véra or a
        similar newer method → have the user type `;kpm update`, `;kpm upgrade` and
        `;kpm install koreader` in the Kindle search bar, one after another
      - Only much older jailbreaks need Booklet/KOL (that route puts the KOL
        **bin files** — not the koreader package — into `mrpackages/`)
      If KUAL / MRPI are already installed, skip them; do not reinstall.
   2. **Pick the right package — this is the easiest step to get wrong.** The
      release page has four Kindle assets, chosen by firmware:

      | Asset | Applies to |
      |---|---|
      | `koreader-kindlehf-*.zip` | firmware **≥ 5.16.3** |
      | `koreader-kindlepw2-*.zip` | touch devices on firmware **≤ 5.16.2** |
      | `koreader-kindle-*.zip` (no suffix) | K4 / Kindle Touch / PW1 |
      | `koreader-kindle-legacy-*.zip` | keyboard Kindles: K2 / K3 / DX |

      Note that the glob `koreader-kindle-*` **matches all four** — do not just
      grab whichever one looks newest.
   3. Download the latest Kindle package from
      https://github.com/koreader/koreader/releases and install it the way chosen
      in item 1. If that is "unzip into the root": `<mount>/koreader/` and
      `<mount>/extensions/koreader/` must end up in the USB root (about 98M /
      2200+ files — run it in the background).
   4. Safely eject, then have the user start it via
      **KUAL → KOReader → Start KOReader** (the first run walks through setup).
      If the user has no KUAL yet, install it from the link on the same wiki page.
   5. Once KOReader starts, continue at Step 1 of this guide.

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
   contains `version`. (macOS leaves a crowd of `._*` AppleDouble files on FAT
   volumes — that is noise, ignore it when checking.)

### Step 3: convert a deck (when the user provides an `.apkg`)

Inside the unzipped converter directory run (stdlib only, any Python 3 ≥ 3.11):

```bash
python3 tools/kindle_anki_importer.py "/path/to/deck.apkg" -o "/path/to/out/name.kindle-anki.json"
```

Use `py -3` on Windows. Output: `name.kindle-anki.json` +
`name.kindle-anki.media/` + `name.kindle-anki.zip`. If the deck has no images or
audio, **no** `.media/` directory is produced — that is normal, do not go looking
for it on the device. If the report shows many `Skipped` cards the deck may need
field mapping; the GUI converter is better for that (the packaged
`Kindle-Anki-Import.command` / `.bat`, or the drop-in converter from the release).

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
2. So the plugin loads:
   - KOReader was already installed on the device → **fully quit and reopen it**.
   - KOReader was just installed by this run (Branch B) → start it via
     **KUAL → KOReader → Start KOReader**.
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
| Kindle mount point not found | work through Step 0 first: is the device enumerated over USB at all? **Enumerated but no drive = USBNetwork mode** — have the user turn usbnet off, then **replug once**; only after ruling that out try another cable/port, or replug with the screen unlocked |
| no `koreader/` directory | KOReader not installed — back to Step 0 |
| computer has no Python | install from https://www.python.org/downloads/ (with Tcl/Tk), or use the packaged converter from the release |
| macOS app won't open | unsigned: right-click → Open |
| Windows SmartScreen block | More info → Run anyway |
| Kindle Anki missing from the menu | KOReader was not fully restarted, or the plugin folder nesting is wrong |

### Red lines (never violate)

- Never rewrite or delete the user's **data files** (packs, study progress, the
  legacy `/mnt/us/folo-anki/` directory, …). Overwriting the plugin folder itself
  when upgrading, as Step 2 says, is allowed.
- Never write API keys into pack JSON; keys belong only to KOReader plugin
  settings.
- Never perform or guide jailbreaking.
- Do not touch anything else on the device after finishing.
- **While KOReader is running, do not have the user plug the device into a
  computer to switch it into mass-storage mode** — that is officially unsupported
  and can take down KOReader, or the Kindle itself. Charge with a charger, or quit
  KOReader first.
