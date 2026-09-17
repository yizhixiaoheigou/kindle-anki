<p align="right">
  <strong>简体中文</strong> · <a href="SETUP_WITH_AI.md">English</a>
</p>

# 让 AI 帮你装——把这一页发给任意 AI 助手

**用法**：把本页链接发给 AI 助手(ZCode、Claude、ChatGPT、WorkBuddy、豆包办公 等)，附一句话：
「请严格按照这个文档，帮我把 Kindle Anki 装到我的 Kindle 上」。
你要做的只有一件事:**用 USB 线把 Kindle 连上电脑**。如果 AI 说找不到设备,照它给的提示操作即可。

---

## 以下是指令，写给执行的 AI

你的任务：帮用户把 KOReader 插件 **Kindle Anki** 装进(或升级)他的 Kindle,并按需转换和导入 Anki 卡包。用户已把 Kindle 用 USB 连到电脑。**全程只操作 Kindle 的用户分区(U 盘部分)，永远不碰系统分区、不删用户数据。**

### 第 0 步：环境确认

1. 探测操作系统(macOS / Windows)。
2. 找到 Kindle 挂载点:
   - macOS:`/Volumes/Kindle`(用 `ls /Volumes` 确认)
   - Windows:一个新盘符(如 `E:`),可让用户在资源管理器里确认

   **找不到挂载点?别急着让用户换线,先分清是哪种"找不到":**
   - 用系统工具看这个 Kindle 在 USB 上以什么身份出现:
     - macOS:`ioreg -p IOUSB -l -w 0 | grep -E '"USB Product Name"'`
       - 看到 **`RNDIS/Ethernet Gadget`** → 第 1 种
       - 看到 **`Internal Storage`** → 第 2 种
     - Windows:设备管理器里找它;`RNDIS` / `NDIS` / 网络适配器类 = 第 1 种,
       磁盘驱动器 / 便携设备类 = 第 2 种。
     (厂商串里含 `lab126` 或厂商号 `0x1949` 只能说明"这是台亚马逊设备",
     **不能**用来区分这两种模式。)
   - **第 1 种:产品名是 `RNDIS/Ethernet Gadget`(USB 网卡模式)。**
     该模式不暴露 U 盘,换线换口都没用。此时你必须主动告诉用户怎么关掉它:
     1. 在 Kindle 上退出 KOReader → **KUAL → USBNetwork → Toggle USBNetwork**
        (有 Disable 就选 Disable)。
     2. **拔掉 USB 线,等 3~5 秒,再插回去** —— 不拔插不会重新枚举,这一步不能省。
     3. 插回后重新确认挂载点出现。
     若用户的 KUAL 里没有 USBNetwork 这一项,让他在设备上描述或拍下看到的菜单再判断,
     **不要凭空猜命令**。
   - **第 2 种:产品名是 `Internal Storage`(大容量存储模式)却没有盘符。**
     设备本身没问题,只是卷没挂上 —— 最常见的原因是上一次"安全弹出"之后线没拔。
     **不要**让用户去关 usbnet(这个模式下它根本没启用)。让他**拔线、等 3~5 秒、再插回**,
     盘符就应该出现;如果插回后仍然没有,再怀疑文件系统损坏。
   - **完全看不到这个设备** → 才轮到线材/端口/锁屏:让用户换线换口、解锁屏幕后拔插一次。

3. 确认 `<挂载点>/koreader/` 目录存在(即设备已装 KOReader)。**存在 → 跳到第 1 步。**
   不存在 → 按下面的分支处理,不要直接放弃:
   判定依据:设备上存在越狱痕迹(任一即可)——`LanguageBreakRan`、`libkh/`、`mkk/`、
   `rp/`、`patchedUks.sqsh`。有 → 走分支 B;完全没有 → 走分支 A。

   **分支 A:设备还没越狱。**
   如实告诉用户:KOReader 只能装在越狱后的 Kindle 上;越狱有失去保修等风险,
   是否越狱由用户自行决定、自担风险。指路(不要代替用户执行,也不要提供越狱步骤):

   - 越狱方法汇总:KOReader 官方 wiki 的 Kindle 安装页
     (https://github.com/koreader/koreader/wiki) → 前置条件一节,按用户固件版本找对应方法
   - 越狱完成后回来,从分支 B 继续

   **分支 B:已越狱,但没装 KOReader。你来装:**
   1. 打开 https://github.com/koreader/koreader/wiki 的 Kindle 安装页
      (Installation on Kindle devices),按**固件版本**确定装法(以官方页为准):
      - 固件 ≥ 5.16.3 → KUALA 方式:先装 https://github.com/kasparcode/kuala/releases
      - 固件 < 5.16.3 且已有 KUAL → 把包**解压到 U 盘根目录**,再从 KUAL 启动
      - 越狱是 WinterBreak(2026-06 起)/ SpringBreak / Sanctuary / Véra 等新方法 →
        让用户在 Kindle 搜索框依次输入 `;kpm update`、`;kpm upgrade`、
        `;kpm install koreader`
      - 只有更老的越狱方式才需要 Booklet/KOL(那条路 `mrpackages/` 里放的是 KOL 的
        **bin 文件**,不是 koreader 包)
      KUAL / MRPI 若已经装好就跳过,不要重复装。
   2. **选对包 —— 这一步最容易错。** 下载页有四个 Kindle 资产,按固件选:

      | 资产 | 适用 |
      |---|---|
      | `koreader-kindlehf-*.zip` | 固件 **≥ 5.16.3** |
      | `koreader-kindlepw2-*.zip` | 固件 **≤ 5.16.2** 的触屏机 |
      | `koreader-kindle-*.zip`(无后缀) | K4 / Kindle Touch / PW1 |
      | `koreader-kindle-legacy-*.zip` | 带物理键盘的 K2 / K3 / DX |

      注意 `koreader-kindle-*` 这个通配**能匹配全部四个**,别随手取"最新"那个。
   3. 从 https://github.com/koreader/koreader/releases 下载最新 Kindle 包,按第 1 条
      选定的方式安装。若选的是"解压到根目录":解压后 `<挂载点>/koreader/` 与
      `<挂载点>/extensions/koreader/` 必须落在 U 盘根目录(约 98M / 2200+ 个文件,
      建议后台执行)。
   4. 安全弹出后,让用户在 **KUAL → KOReader → Start KOReader** 启动(首次会走初始化)。
      用户若还没有 KUAL,按同一 wiki 页的链接先装。
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
   (macOS 往 FAT 卷写文件会留下一堆 `._*` AppleDouble 文件,属噪声,校验时忽略。)

### 第 3 步:转换卡包(用户提供 `.apkg` 时)

在解压出的 converter 目录里运行(纯标准库,任何 Python 3 ≥ 3.11 都行):

```bash
python3 tools/kindle_anki_importer.py "/path/to/卡包.apkg" -o "/path/to/out/名字.kindle-anki.json"
```

Windows 用 `py -3` 代替 `python3`。产物:`名字.kindle-anki.json` + `名字.kindle-anki.media/` + `名字.kindle-anki.zip`。
若牌组里没有图片/音频,则**不会**生成 `.media/` 目录,属正常,不要去设备上找它。
若报告大量 `Skipped`,提示用户可能需要字段映射 —— 这种情况交互式 GUI 更合适
(release 里的 `Kindle-Anki-Import.command` / `.bat`,或免安装转换器)。

### 第 4 步:把卡包放进设备

把 **json 和 media 目录**(不是 zip)复制到:

```
<挂载点>/kindle-anki/packs/名字.kindle-anki.json
<挂载点>/kindle-anki/packs/名字.kindle-anki.media/
```

目录不存在就创建。备选:只拷 zip 到设备任意位置,让用户用菜单「导入卡包」选它。

### 第 5 步:收尾(必须逐条告诉用户)

1. 安全弹出 Kindle,拔线。
2. 让插件加载:
   - 设备上原本已经装过 KOReader → 在 Kindle 上**完全退出 KOReader 再重新打开**。
   - 这是本次刚装好的 KOReader(走的是分支 B)→ 从
     **KUAL → KOReader → Start KOReader** 启动。
3. 菜单:**工具 → 更多工具 → Kindle Anki**。
4. 第一次打开卡包会问每天新卡数(1–999,默认 20)。
5. 可选 AI 功能:电脑上打开转换器(双击 `Kindle-Anki-Import.command`/`.bat`,或 release 里的免安装 app),
   点「AI 设置」粘贴密钥;Kindle 上选「从电脑导入 AI 设置」,输电脑 IP 和窗口里的 4 位配对码。
   前提:两边在同一 Wi-Fi。

### 故障排查

| 症状 | 处置 |
|---|---|
| 找不到 Kindle 挂载点 | 先按第 0 步分清:USB 到底有没有枚举到设备?**枚举到却没有盘符 = USBNetwork 模式**,让用户关掉 usbnet 后**拔插一次**;确认没枚举到,才换线/换口、解锁屏幕后拔插 |
| 没有 `koreader/` 目录 | 未装 KOReader,回第 0 步 |
| 电脑没有 Python | 装 https://www.python.org/downloads/ (勾 Tcl/Tk);或直接用 release 里的免安装转换器 |
| macOS app 打不开 | 未签名:右键 → 打开 |
| Windows SmartScreen 拦截 | 更多信息 → 仍要运行 |
| 菜单里没有 Kindle Anki | 没有完全退出 KOReader;或插件目录层级拷错 |

### 红线(任何情况下不得违反)

- 不改写、不删除用户的**数据文件**(卡包、学习进度、`/mnt/us/folo-anki/` 旧目录等)。
  按第 2 步覆盖升级插件本体是允许的。
- 不把 API 密钥写进卡包 JSON;密钥只属于 KOReader 插件设置。
- 不执行越狱,不提供越狱指导。
- 完成后不主动改动设备其他内容。
- **KOReader 正在运行时,不要让用户插电脑切到 U 盘/大容量存储模式** —— 官方明确不支持,
  可能把 KOReader 甚至 Kindle 系统弄崩。要充电请用充电器,或先退出 KOReader。
