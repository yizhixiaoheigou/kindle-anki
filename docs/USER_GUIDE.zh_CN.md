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
5. 打开 **工具 → Kindle Anki**。

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

## 3. 在 Kindle 上导入

### 最省事：手机/电脑浏览器里转换（不需要装任何东西）

1. Kindle 和手机/电脑连同一个 Wi-Fi。
2. **工具 → Kindle Anki → 导入卡包 → 用手机或电脑浏览器导入**。弹窗里会显示地址，例如
   `http://192.168.1.20:8767/`，旁边是同一地址的二维码。
3. 用手机相机扫二维码，或在浏览器里输入这个地址。如果用微信（或 QQ、钉钉、支付宝等）
   扫码，页面会在 App 里打开，并提示你：点右上角「···」，选「在浏览器打开」（iPhone
   选「在 Safari 中打开」），在浏览器里选文件更顺手。
4. 在网页里选 Anki `.apkg`（导出时勾选「支持旧版本 Anki」）。网页会列出每种笔记
   类型的**全部字段**，每个字段下面有「例如 …」真实内容示例；在字段右边点「正面」或
   「背面」——不会有任何预勾选。每种笔记下面有一台 Kindle 模样的预览，用第一条笔记
   显示卡片在 Kindle 上的样子，选错字段一眼就能看出来。
5. 点「转换并发送到 Kindle」。转换在浏览器里完成，卡片内容不离开你的设备；随后
   Kindle 弹出「已导入 …」，卡包立即可用。某种笔记没选齐正/背面时不会转换，并会把
   它标成红色。「只转换，下载 .zip」可把同一份卡包存成文件。

「卡包」标签页列出 Kindle 上已有的卡包。点「删除」后再确认一次，会连同学习进度和
AI 对话一起清掉——效果和插件里的「管理卡包」一样。「AI」标签页可以把 AI 设置保存到
Kindle（见下文）。

网页里还有「AI 设置（可选）」区块：把接口、模型名和 API key 连同 Kindle 弹窗里
显示的 4 位配对码一起粘贴进去，就直达 Kindle 的插件设置——再也不用在 Kindle 键盘上
敲长密钥。网页只能写入密钥，永远读不回。配对码输错 5 次后网页不再接受 AI 设置，
在 Kindle 上点「立即停止」再重新打开导入页即可拿到新配对码。

弹窗选「停止」即可关掉这个服务（端口 8767 上的小服务器随它关闭）。30 分钟无人访问时它也会自动关闭。它没有密码，
和电脑转换器的 8766 一样只用于家里 Wi-Fi。Kindle 自己从不解包 Anki 文件，只接收
转换好的卡包。

### 从电脑转换器导入（Wi-Fi，不用 USB）

转换窗口保持打开。右侧会用大号字体显示局域网 IP（例如 `192.168.1.10`）。可点
「复制 IP」。端口 **8766** 没有密码。只用家里 Wi-Fi。

1. Kindle 和电脑连同一个 Wi-Fi。
2. **工具 → Kindle Anki → 导入卡包 → 从电脑转换器导入**。
3. 填这个 IP（下次会记住）。
4. 选卡包，插件自己下载。

若 Mac 弹出「是否允许 Python 接受传入连接」，在家里网络上选允许。

USB 只当备用：把 zip 拷进 Kindle，再用「导入卡包」。

删除卡包：**工具 → Kindle Anki → 管理卡包**，或在「我的卡包」左上角菜单里选「管理卡包」。
该卡包的进度和 AI 对话会一起清掉。

导入的卡包如果文件名或标题与 Kindle 上已有的相同，会保留旧卡包并提示「没有覆盖」。要更新
卡包，请先删除旧的（其进度会一起清掉）。

每天学多少张在 Kindle 上第一次打开卡包时设置，不在电脑转换时写入。学习日（以及每日额度和
到期日）按 Kindle 本地时间零点翻页。

插件默认简体中文。切换语言：**工具 → Kindle Anki → Language / 语言**。

## 4. 刷题和可选 AI

「我的卡包」列出所有卡包和今天还剩多少张。点一个卡包，会看到今天的安排（复习几张、
新卡几张）和「开始学习」；错题、收藏、浏览全部也在同一屏，带着数量。只有一个牌组的
卡包会直接打开这个牌组。

卡片上点「显示答案」，答案出现在问题下方；四个评分按钮排成一行，每个都标着下次出现的
时间。重来等 10 分钟，困难 / 良好 / 简单用天粒度 SM-2。一轮学完会显示这轮的评分情况，
并可以直接重做答错的。进度只留在 Kindle，不同步 AnkiWeb。

可选 AI 只用 Kindle 上保存的一份设置，卡包里自带的 AI 字段一律不用。
**工具 → Kindle Anki → AI 设置** 里有三种设置方式，和导入卡包的三种方式一一对应：

- **用手机或电脑浏览器（推荐）**：Kindle 显示二维码（扫开直接进入网页的「AI」页）和 4 位
  配对码。在网页里填好接口、模型和 API key，填配对码保存。网页只能写入密钥，读不回来。
  Kindle 还没设置 AI 时，网页会预填 DeepSeek（`https://api.deepseek.com`，模型 `deepseek-flash`），
  只需粘贴 key；用别家就改这两项。已经设置过 AI 时，留空的项保持 Kindle 上原来的值。
- **从电脑转换器（同一 Wi-Fi）**：先在转换器「AI 设置」里粘贴好配置，再在 Kindle 上填电脑 IP
  和转换器窗口里的配对码。配对码输错 5 次后转换器不再提供 AI 设置，在转换器「AI 设置」里
  再点一次保存即可换新码。
- **在 Kindle 上直接填写**。

还没设置 AI 时点「AI 解析」，会提示你去设置。请求会把卡片文本和图片（base64）发给接口；
明文 `http://` 传输 key 不加密。

不是官方 Anki。不兼容 AnkiWeb。
