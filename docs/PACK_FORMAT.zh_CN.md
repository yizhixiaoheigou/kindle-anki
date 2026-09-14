<p align="right">
  <strong>简体中文</strong> · <a href="PACK_FORMAT.md">English</a>
</p>

# Kindle Anki 卡包格式

写入端发出 `"format": "kindle-anki"` 版本 `1`，文件是 `*.kindle-anki.json`，旁边是
`*.kindle-anki.media/` 和 `*.kindle-anki.zip`。

读取端还接受版本 1 的 `"format": "folo-kindle-anki"` 和 `*.folo-kindle.*`。
文件名后缀和 JSON 的 `format` 互相独立。插件不回写已有卡包 JSON。

`correct_indices` 从 0 起。Anki 打包的选项字段用 `||`；那种字段里的答案从 1 起。

图片放在对应面文字下方，按 90% 宽和 50% 高里更紧的那个缩放。

不要把 API key 写进卡包 JSON。转换器保存时会去掉 `ai.api_key`。已经带密钥的旧包
仍能加载；插件优先用 Kindle 本机 AI 设置。
