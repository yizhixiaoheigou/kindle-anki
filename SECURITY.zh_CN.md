<p align="right">
  <strong>简体中文</strong> · <a href="SECURITY.md">English</a>
</p>

# 安全

- 不要把 API key 写进卡包 JSON。转换器 `save_package` 会去掉 `ai.api_key`。密钥只
  放 KOReader 插件设置。
- 局域网卡包服务器绑在 `0.0.0.0:8766`，没有认证。只用家里 Wi-Fi。同一局域网的人
  都能下载转换好的卡包。
- Kindle 端的浏览器导入页绑在 `0.0.0.0:8767`，同样没有认证。同样的家里 Wi-Fi
  前提；同一局域网的人可以往 Kindle 上传卡包或读取卡包列表。它拒绝直接上传
  `.apkg`（必须先在浏览器里转换）。通过 `POST /api/ai-settings` 写入 AI 设置需要
  Kindle 屏幕上显示的 4 位配对码，并且必须以 `application/json` 提交（其他网站无法跨站
  提交）；输错 5 次后该接口锁定，需在 Kindle 上停止再重开导入页换新码。写入只可写入：网页能替换配置，但永远读不回已存的
  密钥、进度或设置。`DELETE /api/packs` 同样无认证：局域网内的人可以删除卡包（连带
  进度与 AI 对话）。删除名必须能对上插件自己列出的卡包，路径穿越不会触达存储层。
- 卡包 JSON 和 zip 是明文学习材料。

私下向仓库所有者报告问题。不要在公开 issue 里贴卡包或密钥。
