# 更新日志

Kindle Anki 的显著变化记录。格式参照 Keep a Changelog。

## 0.1.0 — 未发布

首次公开发布。

- KOReader 插件 `kindleanki.koplugin`：刷 `*.kindle-anki.zip` 卡包，支持简答题和
  选择题（含图片），天粒度 SM-2 调度，收藏与错题再练队列，USB 和局域网（8766
  端口）导入卡包，每日新卡上限，可选直连 AI 解析且 API key 只存 Kindle。
- 桌面转换器：`.apkg` 转 Kindle 卡包，可勾选正面/背面字段（Tkinter 应用、网页
  后备、USB 分享）。运行时只依赖标准库。卡包默认以牌组命名，转换前可填写卡包
  名称；这个名字用于 Kindle 卡包列表和输出文件。
- AI 免打字配置：在转换器「AI 设置」里粘贴 endpoint/模型/密钥，Kindle 通过 4 位
  配对码一键导入。密钥依旧不写入卡包 JSON。
- PyInstaller 产出的未签名预编译应用：macOS universal2 `.app` 和 Windows
  onedir，均在本机汇出（见 packaging/README.zh_CN.md）。
- 文档：用户指南、卡包格式、foloanki 迁移；全程英文加简体中文。
