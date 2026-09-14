<p align="right">
  <a href="SECURITY.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Security

- Do not put API keys in pack JSON. Converter `save_package` strips `ai.api_key`.
  Store keys only in KOReader plugin settings.
- The LAN pack server binds `0.0.0.0:8766` with no authentication. Use home
  Wi-Fi only. Anyone on that LAN can download converted decks.
- Pack JSON and zips are plaintext study material.

Report issues privately to the repository owner. Do not file packs or keys in
public issues.
