<p align="right">
  <strong>简体中文</strong> · <a href="CONTRIBUTING.md">English</a>
</p>

# 贡献

本仓库是 KOReader 插件加桌面 Python 转换器。没有 ESP-IDF、没有 `idf.py`、没有
固件 `validate.sh`、没有 BSP、没有 BLE。

## 检查

```bash
python3 -m unittest discover -s tests -p 'test_kindle_*.py'
```

请用带 Tcl/Tk 的 Python——UI 测试在顶层 import `tkinter`。

不要加入 `tools/anki_importer.py` 或 `tools/folo_*.py`。

## Pull request

标题：`<type>(<scope>): …`，scope 用 `plugin`、`converter`、`docs`、`ci`。

文档：英文 `.md` 配简体中文 `.zh_CN.md`。

不要提交 API key、`.apkg` 卡包或私人卡包 JSON。
