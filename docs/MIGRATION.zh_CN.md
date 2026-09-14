<p align="right">
  <strong>简体中文</strong> · <a href="MIGRATION.md">English</a>
</p>

# 从固件树插件迁过来

本工具最初是 FoloToy AI Passport 固件树里的 KOReader 插件。磁盘名曾是
`foloanki.koplugin`、`/mnt/us/folo-anki/`、`*.folo-kindle.json`。

## 新插件会做什么

- 安装目录：`kindleanki.koplugin`。
- 新卡包：`/mnt/us/kindle-anki/packs/` 和 `*.kindle-anki.json`。
- 设置：`kindle_anki.lua`。若为空，第一次打开会从 `folo_anki.lua` 拷一份，旧文件保留。
- **双读：** `/mnt/us/folo-anki/packs/` 里已有卡包仍会列出（只读扫描）。进度键是
  完整 JSON 路径，所以**不会搬文件**。注意：**「管理卡包」也能删除旧包**——删除
  是显式的用户操作且有确认框，旧包与新包在此一视同仁。
- 插件**不回写**已有卡包的 `format` 或文件名。这样还能回退：把
  `foloanki.koplugin` 拷回去即可。

## 盖在旧安装上

1. 把 `kindleanki.koplugin` 拷到 `/mnt/us/koreader/plugins/`。
2. 删除 `foloanki.koplugin`，避免两个插件都注册 `name = "kindleanki"`。
3. 完全退出 KOReader 再打开。
4. **不要**从文件选择器再导入已经在库里的卡包（例如 `2026`）。已列出则导入是
   no-op。zip 标题和已有卡包相同也是 no-op。

不要 `mv /mnt/us/folo-anki /mnt/us/kindle-anki`。不改进度键会丢 SRS。以后才会有
「确认后拷贝」的可选动作。

zip 解压临时目录（`.import-tmp`、`.download.*`）不算库内成员。新 zip 在匹配失败后
才拷到 `/mnt/us/kindle-anki/packs/`。
