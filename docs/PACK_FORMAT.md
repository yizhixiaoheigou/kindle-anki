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

Images sit under the matching side's text and scale to the smaller of 90%
width or 50% height.

Do not put API keys in pack JSON. The converter strips `ai.api_key` on save.
Old packs that already contain a key still load; the plugin prefers the
Kindle-local AI settings.
