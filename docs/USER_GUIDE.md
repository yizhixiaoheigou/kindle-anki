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
5. Open **Tools → Kindle Anki**.

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

## 3. Import on the Kindle

### Easiest: convert in a phone/computer browser (no converter needed)

1. Kindle and phone/computer on the same Wi-Fi.
2. **Tools → Kindle Anki → Import packs → Import via browser**. A dialog shows
   the address, for example `http://192.168.1.20:8767/`, and the same address
   as a QR code.
3. Scan the QR code with the phone camera, or type the address in a browser.
   If you scan with WeChat (or QQ, DingTalk, Alipay…), the page opens inside
   that app and says so: tap **···** at the top right and choose to open it
   in the browser (Safari on iPhone), where picking the file works better.
4. Pick the Anki `.apkg` in the page (export it with *Support older Anki
   versions* checked). The page lists every note type with **all** its
   fields; each field shows an "例如 …" snippet of its real content. Tap
   **正面** (front) or **背面** (back) on each field you want — nothing is
   pre-selected. A Kindle-shaped preview under each note type shows the
   first note as it will appear, so a wrong field is easy to spot.
5. Tap **转换并发送到 Kindle** (Convert and send to Kindle). The conversion
   runs inside the browser and card content stays on your device; the
   Kindle then shows "Imported …" and the pack is ready. It refuses, and
   marks the note type in red, until every note type has at least one front
   and one back field. **只转换，下载 .zip** gives you the same pack as a file
   instead.

The **卡包** (Packs) tab lists what is already on the Kindle. **删除**
(Delete) asks once more, then removes the pack together with its study
progress and AI chats — the same as the plugin's own Manage packs. The
**AI** tab saves AI settings onto the Kindle (see below).

The page also has an **AI settings** box: paste your endpoint, model, and
API key plus the 4-digit pairing code shown in the same Kindle dialog, and
they are saved straight into the Kindle's plugin settings — no typing the
long key on the Kindle keyboard. The page can write the key but can never
read it back. After 5 wrong pairing codes the page stops accepting AI
settings; tap **Stop now** on the Kindle and open the page again for a new
code.

Leave the dialog's **Stop** for when you are done; the small server on port
8767 closes with it. It also closes by itself after 30 minutes with no
visits. It has no password — home Wi-Fi only, like the computer
converter's port 8766. The Kindle never unpacks Anki files itself; it only
receives the finished pack.

### From the computer converter (Wi-Fi, no USB)

Keep the converter window open. The dock on the right shows the LAN IP in large
type (for example `192.168.1.10`). Use **Copy IP** if you want to paste it.
Port **8766** has no password. Home Wi-Fi only.

1. Kindle and computer on the same Wi-Fi.
2. **Tools → Kindle Anki → Import packs → Import from computer**.
3. Type that IP (it is remembered next time).
4. Pick the pack. The plugin downloads it itself.

If macOS asks to allow Python incoming connections, allow it on a home network.

USB is only a fallback: copy the zip onto the Kindle and use **Import pack**.

To remove a pack: **Tools → Kindle Anki → Manage packs**, or the menu icon
at the top left of **Open packs**. Progress and AI chats for that pack go with it.

Importing a pack whose file name or title is already on the Kindle keeps the
existing one and says so. To update a pack, delete the old one first; its
progress goes with it.

Daily new-card count is set on the Kindle the first time you open the pack, not
during conversion. The study day, and with it the daily count and due dates,
turns over at the Kindle's local midnight.

The plugin starts in Simplified Chinese. Switch with **Tools → Kindle Anki →
Language / 语言**.

## 4. Study and optional AI

**Open packs** lists your packs with what is left to study today. Tap one to
see today's plan (reviews and new cards) and **Start studying**; missed,
starred, and browse-all are one tap away with their counts. A pack with a
single deck opens that deck directly.

On a card, **Show back** reveals the answer under the question; the four
ratings sit in one row with the next interval on each. Again waits 10
minutes. Hard / Good / Easy use a day-granularity SM-2 variant. At the end of
a round you see how you rated the cards and can retry the missed ones.
Progress stays on the Kindle. There is no AnkiWeb sync.

Optional AI: **Tools → Kindle Anki → AI settings → Edit AI settings**. Enter endpoint, model, and
API key **on the Kindle**. The converter does not embed keys in pack JSON. Requests POST
the card text and images (base64) to the endpoint; plain `http://` sends the key
unencrypted. To skip typing on the Kindle: click **AI settings** in the converter, paste
your config, then use **Import AI settings from computer** on the Kindle with the
4-digit pairing code shown in the converter window — or paste the same fields
into the **browser import page** (section 3) together with the pairing code
shown in the Kindle dialog. After 5 wrong codes the converter stops handing
out the settings; click **Save** in its AI settings again for a new code.

Not official Anki. Not AnkiWeb-compatible.
