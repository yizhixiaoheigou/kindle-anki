<p align="right">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

# 打包

只在本机做。没有另行批准不要上传 Release zip。

## 主机测试

```bash
python3 -m unittest discover -s tests -p 'test_kindle_*.py'
```

## 构建环境

`tools/` 里的转换器和网页服务运行时只用标准库；下面的 venv 只为 PyInstaller
构建而设。

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
```

universal2 构建还需要一个 x86_64 CPython 的 venv（任意 x86_64 Python 3.12，
比如在 `arch -x86_64` 下建，或用 uv 装）：

```bash
python3 -m venv .venv-x86_64 && .venv-x86_64/bin/pip install -r requirements-dev.txt
```

## macOS .app 和 Windows onedir（不再发布）

从 0.2.0 起 Release 改发离线转换网页（见下）。下面这两种 Python Tk 应用的构建仍可本地使用。

### macOS .app（universal2）

未签名。门禁：右键 → 打开。Apple Silicon 和 Intel 都能用。

```bash
.venv/bin/pyinstaller --noconfirm --clean --distpath dist/arm64 --workpath build/arm64 packaging/kindleanki.spec
arch -x86_64 .venv-x86_64/bin/pyinstaller --noconfirm --clean --distpath dist/x86_64 --workpath build/x86_64 packaging/kindleanki.spec
.venv/bin/python packaging/merge_universal_app.py \
  "dist/arm64/Kindle Anki Import.app" \
  "dist/x86_64/Kindle Anki Import.app" \
  "dist/Kindle Anki Import.app"
```

产物：`dist/Kindle Anki Import.app`（不弹终端）。图标：`python3
packaging/make_dock_icon.py`（需要 Pillow）重写
`packaging/Kindle-Anki-Import.icns` 和 Windows 用的
`packaging/Kindle-Anki-Import.ico`。

### Windows onedir

在一台装好 Python 3（带 Tcl/Tk）的 Windows 电脑上，把本项目拷过去，运行：

```bat
packaging\build_windows.bat
```

脚本会建 `.venv-windows`、装 PyInstaller，产出
`dist\Kindle-Anki-Import\Kindle-Anki-Import.exe`（窗口程序，不弹控制台）。
未签名：SmartScreen 可能要点「更多信息 → 仍要运行」。
`desktop/Kindle-Anki-Import.bat` 会优先找 `dist\Kindle-Anki-Import`。

## Release 文件

```bash
./packaging/make_release_zips.sh 0.2.0
```

写到 `dist/release/`：

- `kindleanki.koplugin-v<版本>.zip`：插件，包含 Lua 文件和 `web/`（浏览器导入页）；缺了 `web/`
  脚本会报错退出。
- `Kindle-Anki-converter-v<版本>.html`：电脑转换器，由 `packaging/build_standalone_html.py`
  生成。它就是 `web/index.html` 把三个脚本内联进去、再设上 `KINDLE_ANKI_STANDALONE`，所以只转换
  和下载，不调用任何 Kindle 接口。在新版 Chrome、Edge、Safari、Firefox 里用 `file://` 打开即可
  （需要 `DecompressionStream`）。
