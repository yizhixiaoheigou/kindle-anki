<p align="right">
  <a href="MIGRATION.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Migrating from the firmware-tree plugin

This tool started as a KOReader plugin inside a FoloToy AI Passport firmware
tree. On-disk names used `foloanki.koplugin`, `/mnt/us/folo-anki/`, and
`*.folo-kindle.json`.

## What the new plugin does

- Install folder: `kindleanki.koplugin`.
- New packs: `/mnt/us/kindle-anki/packs/` and `*.kindle-anki.json`.
- Settings: `kindle_anki.lua`. If that file is empty, the plugin copies
  `folo_anki.lua` on first open and leaves the old file.
- **Dual-read:** existing packs under `/mnt/us/folo-anki/packs/` still list
  (read-only scan). Progress keys are the full JSON path, so those files are
  **not** moved. Note: **Manage packs can delete legacy packs too** — deletion
  is an explicit, confirmed user action, and legacy packs are treated like
  new ones there.
- The plugin **never rewrites** an existing pack's `format` field or filename.
  That keeps rollback possible: copy `foloanki.koplugin` back.

## Install over an old copy

1. Copy `kindleanki.koplugin` into `/mnt/us/koreader/plugins/`.
2. Delete `foloanki.koplugin` so both do not register `name = "kindleanki"`.
3. Fully quit KOReader and reopen.
4. Do **not** re-import pack `2026` (or any live pack) from PathChooser. If it
   already lists, importing it again is a no-op. A zip whose title matches a
   listed pack is also a no-op.

Do not `mv /mnt/us/folo-anki /mnt/us/kindle-anki`. That would break progress
keys unless they are rewritten. An optional confirmed copy action is later work.

Zip extract scratch (`.import-tmp`, `.download.*`) is not a library member.
New zips copy to `/mnt/us/kindle-anki/packs/` after a listed-pack match fails.
