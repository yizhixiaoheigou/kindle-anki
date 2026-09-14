<p align="right">
  <strong>简体中文</strong> · <a href="SECURITY.md">English</a>
</p>

# 安全

- 不要把 API key 写进卡包 JSON。转换器 `save_package` 会去掉 `ai.api_key`。密钥只
  放 KOReader 插件设置。
- 局域网卡包服务器绑在 `0.0.0.0:8766`，没有认证。只用家里 Wi-Fi。同一局域网的人
  都能下载转换好的卡包。
- 卡包 JSON 和 zip 是明文学习材料。

私下向仓库所有者报告问题。不要在公开 issue 里贴卡包或密钥。
