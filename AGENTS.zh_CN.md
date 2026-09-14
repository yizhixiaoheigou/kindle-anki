<p align="right">
  <strong>简体中文</strong> · <a href="AGENTS.md">English</a>
</p>

# Kindle Anki — agent 说明

独立的 KOReader 插件加桌面转换器。不是 ESP32 固件。不是 AnkiWeb。

## 产品边界

- 电脑转 `.apkg`。插件不解包 Anki 文件。
- 进度只留在 Kindle。不同步 AnkiWeb、桌面 Anki 或硬件。
- 不要把 API key 写进卡包 JSON。密钥只放 KOReader 插件设置。
- 局域网卡包服务器（`:8766`）无认证，只建议家里 Wi-Fi。
- 双读旧路径 `/mnt/us/folo-anki/` 和 `foloanki.koplugin`。不要自动删除。不要回写已有卡包 JSON。

## 验证

```bash
python3 -m unittest discover -s tests -p 'test_kindle_*.py'
```

不要加入 `tools/anki_importer.py` 或 `tools/folo_*.py`。

## 文档

英文 `.md` 配简体中文 `.zh_CN.md`，两边对齐。

## 红线

未经仓库所有者批准，不要 `git push`、不要新建公开 GitHub 仓、不要发布 Release、不要删用户数据。
