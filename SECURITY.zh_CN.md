<p align="right">
  <strong>简体中文</strong> · <a href="SECURITY.md">English</a>
</p>

# 安全

- 不要把 API key 写进卡包 JSON。转换器 `save_package` 会去掉 `ai.api_key`。密钥只
  放 KOReader 插件设置。
- 局域网卡包服务器绑在 `0.0.0.0:8766`，没有认证。只用家里 Wi-Fi。同一局域网的人
  都能下载转换好的卡包。
- `:8766` 上的 `GET /ai-settings` 会把转换器里的 AI 设置（含 API key）交给带着转换器
  窗口所示 4 位配对码的请求。输错 5 次后拒绝所有请求，直到在转换器里重新保存 AI 设置
  换新码。勾选「在本机记住」会把设置（含密钥）明文存到 `~/.kindle-anki/ai-settings.json`，
  仅当前用户可读（0600）。
- Kindle 端的浏览器导入页绑在 `0.0.0.0:8767`，同样没有认证。同样的家里 Wi-Fi
  前提；同一局域网的人可以往 Kindle 上传卡包或读取卡包列表。它拒绝直接上传
  `.apkg`（必须先在浏览器里转换）。上传必须以 `application/zip` 提交，其他网站无法跨站
  塞卡包。`Host` 为公网域名的请求（DNS 重绑定）和 `Origin` 来自其他网站的写操作都会被
  拒绝；请用 Kindle 的 IP、单段主机名或 `.local`/`.lan`/`.home` 域名打开页面。通过 `POST /api/ai-settings` 写入 AI 设置需要
  Kindle 屏幕上显示的 4 位配对码，并且必须以 `application/json` 提交（其他网站无法跨站
  提交）；输错 5 次后该接口锁定，需在 Kindle 上停止再重开导入页换新码。写入只可写入：网页能替换配置，但永远读不回已存的
  密钥、进度或设置。`DELETE /api/packs` 同样无认证：局域网内的人可以删除卡包（连带
  进度与 AI 对话）。删除名必须能对上插件自己列出的卡包，路径穿越不会触达存储层。
- 卡包 JSON 和 zip 是明文学习材料。

私下向仓库所有者报告问题。不要在公开 issue 里贴卡包或密钥。
