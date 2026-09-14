<p align="right">
  <strong>简体中文</strong> · <a href="USER_GUIDE.md">English</a>
</p>

# Kindle Anki — 安装和导入

给已经越狱、装着 KOReader 的 Kindle 用。不是官方 Anki，不兼容 AnkiWeb，也不是
亚马逊或 KOReader 官方插件。

## 1. 安装插件（做一次）

1. Kindle 上先装好 [KOReader](https://koreader.rocks/)。
2. 把文件夹 `kindleanki.koplugin` 拷到 KOReader 的 `plugins` 目录：
   `/mnt/us/koreader/plugins/kindleanki.koplugin/`
   USB 连上电脑时，路径是 `Kindle/koreader/plugins/kindleanki.koplugin/`。
3. 如果以前装过 `foloanki.koplugin`，删掉旧文件夹，避免两个插件抢同一个菜单。
4. 弹出 Kindle，**完全退出 KOReader** 再打开。只热重启可能还在用旧插件。
5. 打开 **工具 → 更多工具 → Kindle Anki**。

已经在 `/mnt/us/folo-anki/` 里的卡包仍会列出。新导入写到
`/mnt/us/kindle-anki/packs/`。见 [MIGRATION.zh_CN.md](MIGRATION.zh_CN.md)。

## 2. 在电脑上转换 Anki 卡包

Mac：双击 `desktop/Kindle-Anki-Import.command`；若已打包，用
`dist/Kindle Anki Import.app`。

Windows：免安装的 `Kindle-Anki-Import` onedir（若有），或
`desktop/Kindle-Anki-Import.bat` 配 [python.org](https://www.python.org/downloads/)
的 Python 3（带 Tcl/Tk）。

窗口里：

1. 选择 Anki 的 `.apkg`。
2. 需要的话填**卡包名称**。默认已预填文件里解析出的牌组名；这个名字就是
   Kindle 卡包列表里的名字，也是输出文件名。不改就沿用牌组名。
3. 勾选正面、背面字段。背面不要勾题目，翻面就不会再显示正面。
4. 选择保存位置（桌面即可）。
5. 点 **转换**。

会生成同名的三样：

- `名字.kindle-anki.zip` —— 把这一个文件拷到 Kindle 即可
- `名字.kindle-anki.json` 和 `名字.kindle-anki.media/` —— 同样内容的未打包版

转换全程在本机，不会上传卡包，也不会把 API key 写进卡包。

## 3. 在 Kindle 上导入（Wi-Fi，不用 USB）

转换窗口保持打开。右侧会用大号字体显示局域网 IP（例如 `192.168.1.10`）。可点
「复制 IP」。端口 **8766** 没有密码。只用家里 Wi-Fi。

1. Kindle 和电脑连同一个 Wi-Fi。
2. **工具 → 更多工具 → Kindle Anki → 从电脑导入**。
3. 填这个 IP（下次会记住）。
4. 选卡包，插件自己下载。

若 Mac 弹出「是否允许 Python 接受传入连接」，在家里网络上选允许。

USB 只当备用：把 zip 拷进 Kindle，再用「导入卡包」。

删除卡包：**工具 → 更多工具 → Kindle Anki → 管理卡包**，或打开某个卡包后点「删除此卡包」。
该卡包的进度和 AI 对话会一起清掉。

每天学多少张在 Kindle 上第一次打开卡包时设置，不在电脑转换时写入。

## 4. 刷题和可选 AI

开始学习 / 收藏 / 错题再练 / 浏览。Again 等 10 分钟。Hard / Good / Easy 用天粒度
SM-2。进度只留在 Kindle，不同步 AnkiWeb。

可选 AI：**工具 → 更多工具 → Kindle Anki → AI 设置**。在 Kindle 上填 endpoint、模型和 API
key。转换器不会把密钥写进卡包 JSON。请求会把卡片文本和图片（base64）发给 endpoint；
明文 `http://` 传输 key 不加密。不想在 Kindle 上打字：先点转换器的 **AI 设置** 粘贴好
配置，再在 Kindle 用「从电脑导入 AI 设置」+ 转换器窗口显示的配对码一键导入。

不是官方 Anki。不兼容 AnkiWeb。
