<p align="right">
  <a href="USER_GUIDE.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Kindle Anki — install and import

For people who already have a jailbroken Kindle running KOReader. This is not
an official Anki product, not AnkiWeb-compatible, and not an Amazon or KOReader
official plugin.

## 1. Install the plugin (once)

1. Install [KOReader](https://koreader.rocks/) if it is not already on the Kindle.
2. Copy the folder `kindleanki.koplugin` into KOReader's `plugins` directory:
   `/mnt/us/koreader/plugins/kindleanki.koplugin/`
   On USB this is `Kindle/koreader/plugins/kindleanki.koplugin/`.
3. If you previously installed `foloanki.koplugin`, delete that old folder so
   two plugins do not register the same menu.
4. Eject the Kindle and **fully quit KOReader**, then reopen it. A partial
   restart can keep the old plugin in memory.
5. Open **Tools → More tools → Kindle Anki**.

Packs already under `/mnt/us/folo-anki/` still list. New imports go to
`/mnt/us/kindle-anki/packs/`. See [MIGRATION.md](MIGRATION.md).

## 2. Convert an Anki deck on a computer

macOS: double-click `dist/Kindle Anki Import.app`. The `.command` launcher
opens that app if it is present.

Windows: the packaged `Kindle-Anki-Import` onedir if you have it, or
`desktop/Kindle-Anki-Import.bat` with Python 3 (Tcl/Tk) from
[python.org](https://www.python.org/downloads/).

In the window:

1. Choose an Anki `.apkg`.
2. Type a **pack name** if you want one. It starts as the deck name read from
   the file; this name labels the pack on the Kindle and names the output
   files. Leave it as is and you get the deck name.
3. Tick **front** and **back** fields. Leave the question unchecked on the back
   if the flipped card should not repeat the front.
4. Choose a save folder (Desktop is fine).
5. Click **Convert**.

You get three things with the same name:

- `name.kindle-anki.zip` — copy this one file onto the Kindle
- `name.kindle-anki.json` and `name.kindle-anki.media/` — same content, unpacked

The converter never uploads your deck. It does not write API keys into the pack.

## 3. Import on the Kindle (Wi-Fi, no USB)

Keep the converter window open. The dock on the right shows the LAN IP in large
type (for example `192.168.1.10`). Use **Copy IP** if you want to paste it.
Port **8766** has no password. Home Wi-Fi only.

1. Kindle and computer on the same Wi-Fi.
2. **Tools → More tools → Kindle Anki → Import from computer**.
3. Type that IP (it is remembered next time).
4. Pick the pack. The plugin downloads it itself.

If macOS asks to allow Python incoming connections, allow it on a home network.

USB is only a fallback: copy the zip onto the Kindle and use **Import pack**.

To remove a pack: **Tools → More tools → Kindle Anki → Manage packs**, or open a pack and
choose **Delete this pack**. Progress and AI chats for that pack go with it.

Daily new-card count is set on the Kindle the first time you open the pack, not
during conversion.

## 4. Study and optional AI

Start studying / starred / retry missed / Browse. Again waits 10 minutes.
Hard / Good / Easy use a day-granularity SM-2 variant. Progress stays on the
Kindle. There is no AnkiWeb sync.

Optional AI: **Tools → More tools → Kindle Anki → AI settings**. Enter endpoint, model, and
API key **on the Kindle**. The converter does not embed keys in pack JSON. Requests POST
the card text and images (base64) to the endpoint; plain `http://` sends the key
unencrypted. To skip typing on the Kindle: click **AI settings** in the converter, paste
your config, then use **Import AI settings from computer** on the Kindle with the
4-digit pairing code shown in the converter window.

Not official Anki. Not AnkiWeb-compatible.
