<p align="right">
  <a href="PACK_FORMAT.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Kindle Anki pack format

Writer emits `"format": "kindle-anki"` version `1` and files
`*.kindle-anki.json` plus sibling `*.kindle-anki.media/` and
`*.kindle-anki.zip`.

The reader also accepts `"format": "folo-kindle-anki"` and `*.folo-kindle.*`
at version 1. Filename suffix and JSON `format` are independent. The plugin
never rewrites existing pack JSON.

`correct_indices` are zero-based. Packed Anki option fields use `||`; answers
in those fields are 1-based.

`front` and `back` are plain text. A side's text may be empty only when that
side has images (`front_images` or `back_images`); the plugin only checks
that both are strings, so older plugins load such cards too.

Cloze notes become `short_answer` cards, one per cloze number. The front
shows the active deletion as `[...]` (or `[hint]`) and the others as plain
text; the back shows it as `[answer]`, then the Back Extra field. When the
active deletion has one answer, it is also stored in `expected_answers`,
which **Type answer** compares against.

Images sit under the matching side's text and scale to the smaller of 90%
width or 50% height.

Do not put API keys in pack JSON. The converter strips `ai.api_key` on save.
The optional `ai` block (endpoint, model, system prompt) is kept for other
tools, but the Kindle plugin ignores it: AI uses only the settings saved on
the Kindle. Old packs that carry an `ai` block, even with a key, still load.
