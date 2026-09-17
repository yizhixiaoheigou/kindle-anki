<p align="right">
  <strong>简体中文</strong> · <a href="SETUP_WITH_AI.md">English</a>
</p>

# 让 AI 帮你装——把这一页发给任意 AI 助手

**用法**：把本页链接发给 AI 助手(ZCode、Claude、ChatGPT、WorkBuddy、豆包办公 等)，附一句话：
「请严格按照这个文档，帮我把 Kindle Anki 装到我的 Kindle 上」。
你要做的只有一件事：**用 USB 线把 Kindle 连上电脑**。

---

## 以下是指令，写给执行的 AI

你的任务：帮用户把 KOReader 插件 **Kindle Anki** 装进(或升级)他的 Kindle,并按需转换和导入 Anki 卡包。用户已把 Kindle 用 USB 连到电脑。**全程只操作 Kindle 的用户分区(U 盘部分)，永远不碰系统分区、不删用户数据。**

### 第 0 步：环境确认

1. 探测操作系统(macOS / Windows)。
2. 找到 Kindle 挂载点:
   - macOS:`/Volumes/Kindle`(用 `ls /Volumes` 确认)
   - Windows:一个新盘符(如 `E:`),可让用户在资源管理器里确认
3. 确认 `<挂载点>/koreader/` 目录存在(即设备已装 KOReader)。**存在 → 跳到第 1 步。**
   不存在 → 按下面的分支处理,不要直接放弃:

   **分支 A:设备还没越狱。**
   如实告诉用户:KOReader 只能装在越狱后的 Kindle 上;越狱有失去保修等风险,
   是否越狱由用户自行决定、自担风险。指路(不要代替用户执行,也不要提供越狱步骤):

   - 越狱方法汇总:KOReader 官方 wiki 的 Kindle 安装页
     (https://github.com/koreader/koreader/wiki) → 前置条件一节,按用户固件版本找对应方法
   - 越狱完成后回来,从分支 B 继续

   **分支 B:已越狱,但没装 KOReader。你来装:**
   1. 打开 https://github.com/koreader/koreader/wiki 的 Kindle 安装页,按用户固件版本
      读最新官方步骤(以下为概要,以官方页为准):
   2. 装 MRPI(MobileRead Package Installer):把它的 zip 拷到 `<挂载点>/mrpackages/`,
      在 Kindle 顶部搜索框输入 `;mrpi` 回车触发安装(这一步**由用户在设备上操作**,
      你把 zip 放好并告诉用户确切要输入的内容)。
   3. 装 KOReader:从 https://github.com/koreader/koreader/releases 下载
      `koreader-kindle-*.zip`,同样拷进 `<挂载点>/mrpackages/`,再次搜索框输入 `;mrpi`。
   4. 装启动器 KUAL(Kindle Unified Application Launcher,同一 wiki 页有链接),
      之后从 KUAL 菜单启动 KOReader。
   5. 启动成功后回到本流程第 1 步。
4. 若 `<挂载点>/koreader/plugins/foloanki.koplugin/` 存在(旧版前身):**不要删除**,
   提醒用户按 https://github.com/yizhixiaoheigou/kindle-anki/blob/main/docs/MIGRATION.zh_CN.md 处理。

### 第 1 步:下载

从 https://github.com/yizhixiaoheigou/kindle-anki/releases/latest 下载:

- `kindleanki.koplugin-v*.zip` —— 必需(插件本体)
- `Kindle-Anki-converter-v*.zip` —— 仅当需要转换 `.apkg` 卡包(纯 Python 标准库,免安装)

### 第 2 步:安装/升级插件

1. 解压插件 zip,得到文件夹 `kindleanki.koplugin/`。
2. 复制到 `<挂载点>/koreader/plugins/kindleanki.koplugin/`,已有旧版则整体覆盖。
3. 校验:`<挂载点>/koreader/plugins/kindleanki.koplugin/_meta.lua` 存在且含 `version`。

### 第 3 步:转换卡包(用户提供 `.apkg` 时)

在解压出的 converter 目录里运行(纯标准库,任何 Python 3 ≥ 3.11 都行):

```bash
python3 tools/kindle_anki_importer.py "/path/to/卡包.apkg" -o "/path/to/out/名字.kindle-anki.json"
```

Windows 用 `py -3` 代替 `python3`。产物:`名字.kindle-anki.json` + `名字.kindle-anki.media/` + `名字.kindle-anki.zip`。
若报告大量 `Skipped`,提示用户可能需要字段映射(交互式 GUI 更合适,见第 6 步备注)。

### 第 4 步:把卡包放进设备

把 **json 和 media 目录**(不是 zip)复制到:

```
<挂载点>/kindle-anki/packs/名字.kindle-anki.json
<挂载点>/kindle-anki/packs/名字.kindle-anki.media/
```

目录不存在就创建。备选:只拷 zip 到设备任意位置,让用户用菜单「导入卡包」选它。

### 第 5 步:收尾(必须逐条告诉用户)

1. 安全弹出 Kindle,拔线。
2. 在 Kindle 上**完全退出 KOReader 再重新打开**(插件才会加载)。
3. 菜单:**工具 → 更多工具 → Kindle Anki**。
4. 第一次打开卡包会问每天新卡数(1–999,默认 20)。
5. 可选 AI 功能:电脑上打开转换器(双击 `Kindle-Anki-Import.command`/`.bat`,或 release 里的免安装 app),
   点「AI 设置」粘贴密钥;Kindle 上选「从电脑导入 AI 设置」,输电脑 IP 和窗口里的 4 位配对码。
   前提:两边在同一 Wi-Fi。

### 故障排查

| 症状 | 处置 |
|---|---|
| 找不到 Kindle 挂载点 | 换线/换口;Kindle 锁屏时拔插一次;Windows 看磁盘管理 |
| 没有 `koreader/` 目录 | 未装 KOReader,回第 0 步 |
| 电脑没有 Python | 装 https://www.python.org/downloads/ (勾 Tcl/Tk);或直接用 release 里的免安装转换器 |
| macOS app 打不开 | 未签名:右键 → 打开 |
| Windows SmartScreen 拦截 | 更多信息 → 仍要运行 |
| 菜单里没有 Kindle Anki | 没有完全退出 KOReader;或插件目录层级拷错 |

### 红线(任何情况下不得违反)

- 不删除、不改写用户 Kindle 上的任何已有数据(尤其 `/mnt/us/folo-anki/` 旧目录)。
- 不把 API 密钥写进卡包 JSON;密钥只属于 KOReader 插件设置。
- 不执行越狱,不提供越狱指导。
- 完成后不主动改动设备其他内容。
