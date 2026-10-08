<p align="right">
  <strong>简体中文</strong> · <a href="CLAUDE.md">English</a>
</p>

# CLAUDE.md

本文件为 Claude Code（claude.ai/code）在本仓库工作提供指引。

产品边界、红线与文档规则在 [`AGENTS.md`](./AGENTS.md) / [`AGENTS.zh_CN.md`](./AGENTS.zh_CN.md)，请先读。本文件只补充命令与架构。

## 当前状态

- `main` 包含 2026-10-07 审计修复，领先 `origin/main`，尚未 push。
- `feature/ui-redesign` 包含界面重设计和无线部署脚本，维护者正在 Kindle 上测试，测完再合并。
- 详情与下一步见 [`docs/HANDOFF.md`](docs/HANDOFF.md)（英文），历程见 [`docs/PROJECT_HISTORY.md`](docs/PROJECT_HISTORY.md)。

## 命令

```bash
# 全部主机测试（与 CI 相同，CI 跑 Python 3.11–3.13）
python3 -m unittest discover -s tests -p 'test_kindle_*.py'

# 单个文件 / 单个测试
python3 -m unittest tests.test_kindle_schedule
python3 -m unittest tests.test_kindle_cards.KindlePackTests.test_round_trip_and_rebuild_deck_card_ids

# 桌面转换器（只用标准库 + Tk，无需安装）
python3 tools/kindle_import_app.py
python3 tools/kindle_anki_importer.py --help   # 命令行转换器

# 通过 Wi-Fi 把插件装到 Kindle（走 KOReader 自带的 SSH 服务，密钥登录）
scripts/kindle-deploy.sh <kindle-ip>              # 装完在 KOReader 里 退出 → 重启 KOReader
scripts/kindle-deploy.sh <kindle-ip> --crash-log  # 查看 koreader/crash.log 末尾
scripts/kindle-deploy.sh <kindle-ip> --rollback   # 恢复上一次安装的版本
scripts/kindle-deploy.sh <kindle-ip> --enable-restart  # 每台 Kindle 执行一次：之后每次安装都会自动重启 KOReader
```

- 部署脚本要求 Kindle 的 `koreader/settings/SSH/authorized_keys` 里有你的公钥，并且 KOReader 的 SSH 服务器在运行（工具 → 更多工具 → SSH 服务器，勾选「随 KOReader 启动 SSH 服务器」）。替换后会逐个文件核对 MD5。远程重启只在有 `/mnt/us/kindle-anki/dev-remote-restart` 标记文件的 Kindle 上生效（`--enable-restart` 创建）；脚本创建 `/tmp/kindle-anki-restart` 后，插件走 KOReader 菜单自己的重启流程，会先保存设置和学习进度。
- UI 测试在模块顶层 import `tkinter`，要用带 Tcl/Tk 的 Python。
- `test_kindle_web_converter.py` 需要 `node`，各个 `test_kindle_*_lua.py` 需要 `lua`/`luajit`（Web 服务那个还需要 luasocket）。缺少对应工具时会**静默跳过**，所以没有这些工具时全绿，并不代表浏览器转换器和插件的 Lua 代码已被覆盖。设置 `KINDLE_ANKI_REQUIRE_TOOLS=1` 可让缺工具直接失败；CI 已设置该变量，并安装 Lua 5.4、luasocket 和 node。
- 维护者的 Linux VM 没有 `tkinter` 和 `lua`。全量测试请在 Mac 上跑：`mac-run python3 -m unittest discover -s tests -p 'test_kindle_*.py'`。Mac 上有 Tk、`lua`、`node`，不会有跳过。
- 如果存在 `tools/anki_importer.py` 或 `tools/folo_*.py`，CI 会直接失败。
- `requirements-dev.txt`（PyInstaller、Pillow）只用于打包，构建步骤见 `packaging/README.md`。`.venv`/`.venv-x86_64` 是 macOS 构建用的虚拟环境。

## 架构

项目分三部分，共用同一份契约——**包格式**（`docs/PACK_FORMAT.md`）：`name.kindle-anki.json` 加同名 `name.kindle-anki.media/`，打包成 `name.kindle-anki.zip`。

1. **桌面转换器（`tools/`，Python 标准库）。** `kindle_apkg.py` 读取 `.apkg` 里的 SQLite 集合。`kindle_anki_importer.py` 把笔记映射成卡片：Basic 类笔记变成 `short_answer`，带 `||` 选项字段的笔记变成 `choice`；它还提供驱动字段映射的 `inspect_apkg`。`kindle_cards.py` 定义标准包结构（`FORMAT_NAME = "kindle-anki"`）。`kindle_bundle.py` 写出 JSON、媒体目录和 zip，并去掉 `ai.api_key`。`kindle_import_app.py` 是 Tk 窗口，视觉常量在 `kindle_import_ui.py`；它还运行 `kindle_pack_server.py`（插件拉取用的 `:8766` 局域网服务），并负责 4 位配对码的 AI 设置配对。测试模块把 `tools/` 加进 `sys.path`，直接按模块名导入。

2. **浏览器转换器（`plugin/kindleanki.koplugin/web/*.js`）。** 这是 Python 流水线的 JS 移植，由插件提供页面，在手机或电脑浏览器里运行，然后上传成品包。`test_kindle_web_converter.py` 用同一个合成 `.apkg` 同时跑两套转换器，要求包字段、zip 布局和 inspect 报告完全一致。**改转换逻辑时，Python 和 JS 必须同步修改。**

3. **KOReader 插件（`plugin/kindleanki.koplugin/`，Lua，AGPL）。**
   - `main.lua`：菜单（工具 → Kindle Anki）、两类卡片的复习界面、三种导入方式（USB、从 `:8766` 拉取、浏览器页面）和 AI 设置。
   - `store.lua`：包和学习进度存放在 `/mnt/us/kindle-anki/{packs,ai}`，同时兼容读取旧的 `/mnt/us/folo-anki/`。
   - `schedule.lua`：按天计算的 SM-2，Again = 10 分钟。
   - `ai.lua`：直接 POST 到 `/v1/chat/completions`，历史条数有上限，卡片图片以 base64 发送。
   - `webserver.lua`：无认证的 `:8767` 服务，提供 `web/` 静态页面以及 `/api/info`、`/api/packs`（GET/POST/DELETE）、`/api/ai-settings`。
   - `i18n.lua`：内置的 zh_CN 翻译表。

   插件从不解析 `.apkg`，只接收成品包。

插件测试大多是**静态契约检查**：`test_kindle_plugin.py` 断言 Lua 源码里出现特定字符串和写法。改 UI 文案、i18n 键或代码写法时，要有意识地同步更新这些断言。Lua 运行时覆盖来自 `tests/lua_harness/` 下的测试脚本（Web 服务、卡片界面与导航、卡包校验与统计、zip 防护、学习日），它们打桩 KOReader 模块，由各个 `test_kindle_*_lua.py` 驱动。
