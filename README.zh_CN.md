<p align="right">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

[![Host tests](https://github.com/yizhixiaoheigou/kindle-anki/actions/workflows/ci.yml/badge.svg)](https://github.com/yizhixiaoheigou/kindle-anki/actions/workflows/ci.yml)

# Kindle Anki

在越狱 Kindle 的 KOReader 里刷 Anki `.apkg`（简答、选择、填空，含图片）。用手机扫 Kindle 上的
二维码，在打开的网页里选 `.apkg`，转换好的卡包直接落到 Kindle。进度只留在 Kindle。

**不是官方 Anki。不兼容 AnkiWeb。不是亚马逊产品。不是 KOReader 官方插件。**

## 截图

Kindle 在手机上打开的网页：选字段、看 Kindle 预览、发送。「AI」页默认填好 DeepSeek。

<p align="center">
  <img src="screenshots/web-import.jpg" width="32%" alt="网页：选正面和背面字段，下方是 Kindle 预览">
  <img src="screenshots/web-ai.jpg" width="32%" alt="网页：AI 设置，已预填 DeepSeek">
</p>

Kindle 上的效果（照片是旧版学习界面）：

<p align="center">
  <img src="screenshots/kindle-study.jpg" width="32%" alt="在 Kindle 上刷古诗卡">
  <img src="screenshots/kindle-ai.jpg" width="32%" alt="Kindle 上的 AI 解析">
</p>

## 给谁用

- 已越狱、装着 [KOReader](https://github.com/koreader/koreader)（开源的 Kindle 阅读系统）的 Kindle。
- 手里已有 `.apkg` 卡包——用电脑版 [Anki](https://apps.ankiweb.net/) 的「导出」功能生成（含选择题、填空题和图片）。

本工具不包含、也不提供任何越狱方法；是否越狱由你自行决定并自担风险。

## 需要什么

- 越狱 Kindle + KOReader。v2026.07 及以上版本在卡片里直接显示图片；更早的版本
  以纯文本显示卡片，图片用「查看图片」按钮打开。
- 一部带浏览器的手机或电脑，不用装任何东西。
- Kindle 和手机连同一个**家里的** Wi-Fi。

## 安装插件

> 看不懂教程?把 [SETUP_WITH_AI.zh_CN.md](docs/SETUP_WITH_AI.zh_CN.md) 发给任意 AI 助手,
> 再用 USB 线把 Kindle 连上电脑,它带你装完。

解压后应有文件夹 `kindleanki.koplugin/`。拷到
`/mnt/us/koreader/plugins/kindleanki.koplugin/`。若从 `foloanki.koplugin` 升级，
删掉旧文件夹。弹出 Kindle。**完全退出 KOReader 再打开。** 插件在 **工具 → Kindle Anki**。

细节：[docs/USER_GUIDE.zh_CN.md](docs/USER_GUIDE.zh_CN.md)。旧路径：
[docs/MIGRATION.zh_CN.md](docs/MIGRATION.zh_CN.md)。

## 导入卡包

**工具 → Kindle Anki → 导入卡包** 里有三种方式：

- **用手机或电脑浏览器（推荐）。** Kindle 显示二维码和地址（`http://<Kindle IP>:8767`）。
  用手机相机扫码，选 `.apkg`，在字段右边点「正面 / 背面」，下方的 Kindle 预览会显示第一条
  笔记的效果，然后点「转换并发送到 Kindle」。转换在浏览器里完成，Kindle 自己从不解包 Anki
  文件。用微信等 App 扫码时，网页会提示怎么换到手机浏览器。网页的「卡包」页可以查看和
  删除 Kindle 上的卡包。
- **从电脑转换器（同一 Wi-Fi）。** 给从源码运行的 Python 转换器用（见下）：窗口不要关，
  在 Kindle 上填窗口里显示的 IP。8766 端口**没有密码**，只建议家里 Wi-Fi。
- **Kindle 里已有的卡包文件。** 用 USB 把 `.kindle-anki.zip` 拷进 Kindle 再选它。没有 Wi-Fi
  时用下面的离线转换器生成 zip。

导入网页 30 分钟无人访问会自动关闭。

### 电脑转换器（可选）

Release 里的 `Kindle-Anki-converter-v<版本>.html` 就是同一个导入网页的离线版。Mac、Windows、
Linux 上双击就在浏览器里打开，不用安装，也不往任何地方发数据。选 `.apkg`、勾字段、点
「转换并下载 .zip」，再用 USB 把 zip 拷进 Kindle。电脑和 Kindle 连同一个 Wi-Fi 时，更省事的
是用电脑浏览器打开 Kindle 上显示的地址，转换完直接发到 Kindle。

开发者仍可从源码运行 Python 转换器：`python3 tools/kindle_import_app.py`（需要带 Tcl/Tk 的
Python 3），或 `desktop/Kindle-Anki-Import.command` / `.bat`。它另外提供 8766 端口给
「从电脑转换器（同一 Wi-Fi）」用。

## 刷题

**工具 → Kindle Anki → 我的卡包** 列出所有卡包和今天还剩多少张。牌组页显示今天要复习和
要学的新卡，「开始学习」「错题再练」「收藏的卡片」「浏览全部」都带数量。第一次打开时问
每天新卡数（1–999）。卡片上点「显示答案」，答案出现在问题下方；四个评分按钮排成一行，
每个都标着下次出现的时间。重来 = 10 分钟，困难/良好/简单用天粒度 SM-2。一轮学完显示
评分小结，并可以直接重做答错的。菜单里有「Language / 语言」（简体中文 / English）。

## 可选 AI

AI 解析只用 Kindle 上保存的一份设置，卡包里自带的 AI 字段一律不用。在
**工具 → Kindle Anki → AI 设置** 里任选一种方式设置：

- **用手机或电脑浏览器（推荐）。** Kindle 显示二维码和 4 位配对码。扫码打开网页，在「AI」
  页填好接口、模型和 API key，再填配对码保存。接口和模型默认预填 DeepSeek，用 DeepSeek 只需
  粘贴 key。
- **从电脑转换器（同一 Wi-Fi）。** 用从源码运行的 Python 转换器时：先在它的「AI 设置」里
  粘贴好配置，再在 Kindle 上填电脑 IP 和它窗口里的配对码。
- **在 Kindle 上直接填写。**

请求直连 `/v1/chat/completions`；卡片带图时，图片会以 base64 一并发出。思考过程会藏起来，
但不会关掉模型思考。卡包 JSON 从不带密钥。明文 `http://` 的接口会不加密传输 key，建议用
`https://`。

## 和 KAnki / anki.koplugin 的差别

本工具在**手机或电脑浏览器里（或用离线转换网页）转换已有的 `.apkg`**（选择题、填空题 + 图），在 KOReader
里用独立调度刷。

## 开发

```bash
python3 -m unittest discover -s tests -p 'test_kindle_*.py'
```

插件测试需要带 luasocket 的 `lua`，浏览器转换器测试需要 `node`，缺了会跳过。设置
`KINDLE_ANKI_REQUIRE_TOOLS=1` 则改为直接失败（CI 已设置）。`scripts/kindle-deploy.sh <Kindle IP>`
通过 KOReader 的 SSH 服务把插件装到 Kindle，不用插 USB。
见 [CONTRIBUTING.zh_CN.md](CONTRIBUTING.zh_CN.md)。卡包格式：
[docs/PACK_FORMAT.zh_CN.md](docs/PACK_FORMAT.zh_CN.md)。

## 许可证

MIT。Copyright (c) 2026 yizhixiaoheigou。KOReader 插件
（`plugin/kindleanki.koplugin/`）与 KOReader 本体一致，采用 AGPL-3.0-or-later。
第三方代码与商标说明：[THIRD_PARTY_NOTICES.zh_CN.md](THIRD_PARTY_NOTICES.zh_CN.md)。
