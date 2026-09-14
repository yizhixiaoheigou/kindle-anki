<p align="right">
  <strong>简体中文</strong> · <a href="converter-ui-redesign.md">English</a>
</p>

# Kindle Anki 转换窗口重绘

实现以英文稿 [converter-ui-redesign.md](converter-ui-redesign.md) 为准。本文对齐关键决策。

状态：已审阅。范围：`tools/kindle_import_app.py` 与 `tools/kindle_import_ui.py`。不改卡包格式、导入语义、局域网无认证、Kindle 插件。

## 方案

仍用 Tkinter/ttk，强制 **clam**。窗口是纸色 Kindle 边框（校对台）：三栏始终在——顶栏（使用说明）、字段井、底部转换 + 大号 IP。检查语义不变。检查/转换在后台线程，只通过队列回 UI。成功不再弹模态框。没有 API key 输入。

## 关键决策

- 不改 Electron / SwiftUI / 网页。
- 启用的「转换」是唯一朱砂色；IP 用 Menlo 22，从启动就在右侧。
- 每个笔记类型至少勾一个正面；否则点转换会提示，不静默走自动检测。
- `再转一个` 只清空井，主按钮始终叫「转换」。
- 网页版 `kindle_import_server.py` 不在本轮。
- Release 上传需单独批准。

## 色板

`paper` `#E8E6DF`，`well` `#F3F2EC`，`ink` `#1A1916`，`mute` `#4A4944`，`rule` `#B8B6AE`，`seal` `#8C2A1E`。

## 待决（不挡落地）

1. 是否在 Info.plist 强制浅色文件对话框。
2. 转换前是否显示笔记条数（要改 importer，默认不做）。
3. 已定：主按钮保持「转换」。
4. Windows 观感不在本轮截图。
5. Dock 图标已做：纸色墨水屏加朱砂印，`packaging/Kindle-Anki-Import.icns`。

情绪稿（布局以英文 ASCII 为准，不要按图实现 Entry / IP:端口 / 底部使用说明）：

- `../screenshots/converter-idle.jpg`
- `../screenshots/converter-mapping.jpg`
- `../screenshots/converter-converting.jpg`
- `../screenshots/converter-success.jpg`
