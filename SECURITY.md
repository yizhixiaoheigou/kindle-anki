<p align="right">
  <a href="SECURITY.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Security

- Do not put API keys in pack JSON. Converter `save_package` strips `ai.api_key`.
  Store keys only in KOReader plugin settings.
- The LAN pack server binds `0.0.0.0:8766` with no authentication. Use home
  Wi-Fi only. Anyone on that LAN can download converted decks.
- `GET /ai-settings` on `:8766` hands the converter's AI settings, API key
  included, to whoever sends the 4-digit pairing code shown in the converter
  window. After 5 wrong codes it refuses every request until the AI settings
  are saved again, which issues a new code. **Remember on this computer**
  stores the settings, key included, in plain text at
  `~/.kindle-anki/ai-settings.json`, readable by your user only (0600).
- The Kindle-side browser-import page binds `0.0.0.0:8767` with no
  authentication. Same home-Wi-Fi rule; anyone on that LAN can upload a pack
  onto the Kindle or read its pack list. It rejects raw `.apkg` uploads —
  the browser must convert first. Uploads must be sent as `application/zip`,
  so other websites cannot push packs cross-site. Requests whose `Host` is a
  public name (DNS rebinding) and writes whose `Origin` is another site are
  refused; open the page by the Kindle's IP, a single-label name, or a
  `.local`/`.lan`/`.home` name. AI-settings writes via
  `POST /api/ai-settings` require the 4-digit pairing code shown on the
  Kindle screen, sent as `application/json` (so other websites cannot
  submit it cross-site); after 5 wrong codes the endpoint locks until the
  page is stopped and reopened with a new code. Writes are write-only: the page can replace the profile but can
  never read the stored key, progress, or settings back. `DELETE /api/packs`
  shares the unauthenticated posture: anyone on the LAN can delete a pack
  (with its progress and AI chats). Names must resolve to a pack the store
  lists; path traversal never reaches the store.
- AI requests to an `https://` endpoint are encrypted, but the server
  certificate is not verified: KOReader's TLS library defaults to no
  verification and ships no CA bundle. On a network you do not trust, a
  man-in-the-middle could read the API key. Use AI on trusted Wi-Fi, and use
  a key you can revoke.
- Pack JSON and zips are plaintext study material.

Report issues privately to the repository owner. Do not file packs or keys in
public issues.
