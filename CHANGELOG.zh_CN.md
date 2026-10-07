# 更新日志

Kindle Anki 的显著变化记录。格式参照 Keep a Changelog。

## 未发布

- 修复:导入与 Kindle 上已有卡包同文件名或同标题的卡包时,旧卡包原样保留,却提示「已导入」。
  插件和浏览器页面现在会说明没有覆盖,以及如何更新。
- 修复:学习日改为按 Kindle 本地时间零点翻页。此前按 UTC 计算,在中国每日新卡额度在早上
  8 点才重置,深夜复习会被算进第二天。
- 插件菜单新增「Language / 语言」(简体中文 / English),卡片进度行也随之切换。
- Kindle 导入页在无人连接时改为每秒轮询 2 次(原来全天每秒 20 次),30 分钟无人访问
  自动关闭,不再持续耗电,也不会在局域网上一开好几天。
- 安全:卡包 zip 改用 KOReader 自带的 libarchive 读取器(`ffi/archiver`,KOReader 2025.08+)
  解压:先检查全部文件名,只写普通文件,解压后总大小上限 1 GB。更早的 KOReader 仍用
  `unzip`,但列不出文件名的 zip 会被拒绝,不再盲解。旧代码引用了不存在的模块(`ffi/archive`),
  且在 `unzip -Z1` 不受支持时(如 busybox)对任何 zip 一律放行。
- 安全:Kindle 导入页(`:8767`)上传必须是 `application/zip`,拒绝 `Host` 为公网域名的
  请求,拒绝 `Origin` 来自其他网站的写操作。此前用户浏览器里开着的任何网站都能用普通表单
  POST 往 Kindle 塞卡包,借助 DNS 重绑定还能列出和删除卡包。
- 修复:插件现在会拒收选择题 `correct_indices` 非整数、越界或重复,选项不是文本,
  或 `expected_answers` 不是文本的卡包,与转换器自身的规则一致。此前这类卡包能导入,
  翻到答案时会让 KOReader 崩溃。
- 安全:转换器的 `/ai-settings` 接口(`:8766`)配对码输错 5 次即锁定,在转换器里重新
  保存 AI 设置会换新码;配对码改用 `secrets` 生成。此前 4 位码可在局域网内约 1 秒穷举,
  导致 API key 泄露。
- 安全:勾选「在本机记住」时,`~/.kindle-anki/ai-settings.json` 改为 0600 权限写入,
  已有文件也会收紧。注意 0.1.0 说密钥只存在 Kindle 上;开启该选项后,电脑上也会明文保存一份。
- 修复 KOReader v2026.07 以前的版本上卡片显示 HTML 源码(`<div style=…>`、`&#39;`)
  的问题:这些版本的 TextViewer 不能渲染 HTML,现改为纯文本显示,卡片图片用
  「查看图片」按钮打开。AI 对话里的「上一页」「下一页」在这些版本上也不再报错。
- 新增「手机/电脑导入」:插件在局域网开一个小网页(`http://<Kindle IP>:8767`),
  手机或电脑浏览器在这个页面里**全程在浏览器内完成 `.apkg` 转换**,并把转换好的
  卡包直接上传进 Kindle。不再需要桌面转换器或 USB;Kindle 依旧从不解包 Anki
  文件——只接收转换完成的 kindle-anki zip。浏览器转换器是 Python 管线的字节级
  兼容移植(`plugin/.../web/`),由 Node↔Python 一致性测试锁定。网页还能用同一弹窗
  里显示的 4 位配对码把 AI 设置(接口/模型/API key)直接推送到 Kindle——只可写入,
  永远无法从网页读回,只接受 JSON 提交,输错 5 次即锁定。网页还会列出已有的卡包并可删除(连带学习进度与 AI 对话),
  删除走插件自身的安全护栏。
- 新增「让 AI 帮你装」文档(`docs/SETUP_WITH_AI.zh_CN.md`):把该页发给任意 AI 助手,
  插上 USB 线即可由 AI 完成插件安装、卡包转换与导入;设备未装 KOReader 时,
  文档指引 AI 带用户完成 MRPI/KOReader 安装(越狱只指路、不教学)。

## 0.1.0 — 2026-09-15

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
