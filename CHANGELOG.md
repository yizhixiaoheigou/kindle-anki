# Changelog

Notable changes to Kindle Anki. Format follows Keep a Changelog.

## 0.2.0 — 2026-10-20

- Converting real decks:
  - A deck exported with chapter subdecks takes the parent deck's name
    ("高项合并", not "高项合并::05 信息系统工程"), and chapters sort by number
    (第2章 before 第10章).
  - Images inside choice options are kept: they join the question's images
    and the option says which one ("（见图） （图2）"). An image-only option no
    longer disappears and shifts the letters.
  - "Basic (and reversed card)" and similar reverse templates import their
    reverse cards with front and back swapped, instead of skipping them.
  - Notes with a `{{type:Field}}` box fill **Type answer**'s expected answer.
  - Options written on one line ("A. 30% B. 20% C. 40% D. 50%") become a
    choice card.
  - Tables keep each row on one line with " | " between cells; list items
    keep "•" or their number.
  - An answer that is an option's own text picks that option; a word such as
    "The mitochondria" is no longer read as the letters A, C, D. A back that
    starts with an English word ("A good plan…") is no longer an answer label.
  - Image names with spaces or Chinese characters, which Anki stores
    URL-encoded, find their files.
  - A card side with more than 8 images keeps the first 8 instead of making
    the whole conversion fail.
  - The browser converter reads only the images cards use, one at a time,
    instead of unpacking every media file at once; a 31 MB deck with 7,500
    audio files went from about 800 MB of memory to about 200 MB.
  - A cloze card whose number is not in the note is reported as
    `cloze_not_found`, and an `.apkg` with no cards says so.
- Plugin:
  - Packs whose names contain ".." (such as "Ch 1..3" or "Words... part 2")
    now import, upload and delete normally; real path tricks are still
    refused.
  - Study progress is saved when you close a card with the title-bar X, when
    KOReader saves its settings or goes to sleep, and when the reader closes.
  - Cards whose question is only an image show that image above the answer
    too, including from **View images** on KOReader before v2026.07. The
    type-answer box says the question is an image.
  - **AI explain** skips card images it cannot send instead of failing. With
    text-only models such as DeepSeek it retries once without images, and a
    failure shows the provider's own error message.
  - Asking AI no longer switches KOReader's keyboard to Pinyin for good: the
    plugin uses Pinyin only while it is set to Chinese, then restores your
    layout.
- An `.apkg` exported without *Support older Anki versions* (Anki's default)
  is now refused with re-export steps in Chinese. The converters used to
  read the placeholder `collection.anki2` such exports carry and fail with
  "no importable cards". A file with only `collection.anki21b` used to leave
  the browser page stuck on 正在读取….
- For a note type the converter does not recognise, the desktop converter
  pre-ticks a back field named like an answer (解释, 释义, Answer…) or the
  first one with text, instead of the last field, which is often Audio.
- The browser page previews a Cloze note as its first card, shows an
  image-only field as （图片）, and says image occlusion notes will be
  skipped.
- The converters import Cloze notes: each cloze number becomes a card that
  hides that deletion as `[...]` (or its hint) and reveals it on the back,
  followed by Back Extra. **Type answer** checks a single-answer cloze.
  Anki's image occlusion notes are skipped with their own reason.
- A card side that is only an image now converts; before, an image-only
  front or back counted as empty and the card was skipped.
- When nothing in an `.apkg` converts, the desktop converter and the browser
  page now say how many cards were skipped for which reason and what to
  change, instead of only "no importable cards".
- AI setup suggests DeepSeek: on a Kindle without AI settings, the browser
  page and the Kindle's own AI dialog fill in `https://api.deepseek.com` and
  `deepseek-flash`, so only the key is left to enter. A Kindle that already
  has AI settings keeps them; the page learns only whether AI is set up.
- AI now uses only the settings saved on the Kindle; a pack's `ai` block is
  ignored. This removes the pack-endpoint confirmation, since a local key can
  no longer go to a server a pack names.
- **AI settings** offers the same three ways as **Import packs**: phone or
  computer browser (a QR code that opens the page's AI tab, with the pairing
  code first), the computer converter, or typing on the Kindle. **AI
  explain** without settings offers to set them up.
- The **Import via browser** screen on the Kindle now shows the page address
  as a QR code too. The page itself notices when it is opened inside WeChat,
  QQ, DingTalk, Alipay, Weibo, or Lark and explains how to open it in the
  phone's browser instead.
- The plugin menu now sits directly under **Tools** instead of **Tools →
  More tools**.
- Redesigned the plugin and the browser import page.
  - Plugin: **Open packs** is a full-screen list with what is left to study
    today; a deck screen shows today's plan with counted buttons; single-deck
    packs skip the deck list. Cards put progress in the title, show the
    question above the answer, and keep the four ratings in one row. A round
    ends with a rating summary. The plugin menu groups import and AI
    settings into submenus.
  - Browser page: three tabs (Import, Packs, AI); field mapping uses
    front/back toggles with a live Kindle preview of the first note; one
    button converts and sends; deleting a pack asks inline.
- **Import from computer** now stops a download past 512 MB and removes its
  temporary zip after importing or failing.
- Fixed: importing a pack whose file name or title is already on the Kindle
  said "Imported" although the existing pack was kept unchanged. The plugin
  and the browser page now say it was not replaced and how to update it.
- Fixed: the study day now turns over at the Kindle's local midnight. It used
  the UTC day, so in China the daily new-card count reset at 08:00 and late
  evening reviews counted toward the next morning.
- Added **Language / 语言** to the plugin menu (Simplified Chinese or
  English). The card progress line now follows it too.
- The Kindle import page now polls twice a second while nobody is connected
  (was 20 times a second around the clock) and closes itself after 30
  minutes without visits, so it no longer drains the battery or stays open
  on the LAN for days.
- Security: pack zips are now unpacked with KOReader's own libarchive reader
  (`ffi/archiver`, KOReader 2025.08+), which checks every name first, writes
  only regular files, and caps the unpacked size at 1 GB. Older KOReader
  still uses `unzip`, but a zip whose names cannot be listed is now refused
  instead of extracted blind. The old code asked for a module that does not
  exist (`ffi/archive`) and passed any zip when `unzip -Z1` was unsupported,
  as on busybox.
- Security: the Kindle import page (`:8767`) now requires uploads as
  `application/zip`, refuses requests whose `Host` is a public name, and
  refuses writes whose `Origin` is another site. Before this, any website
  the user had open could push packs onto the Kindle with a plain form POST,
  and a DNS-rebinding page could list and delete packs.
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
