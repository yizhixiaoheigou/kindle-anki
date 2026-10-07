-- Small catalog for this standalone KOReader plugin.
-- KOReader's gettext catalog only covers the core application; keeping the
-- plugin catalog here makes the installed plugin self-contained.

local I18N = {}

local catalogs = {
    en = {},
    zh_CN = {
        ["Kindle Anki"] = "Kindle Anki",
        ["Review Kindle card packs with short-answer and choice cards, plus direct text AI explanations. Not official Anki."] =
            "复习 Kindle 卡包，支持简答题、选择题和直接文本 AI 解析。非官方 Anki。",
        ["AI settings"] = "AI 设置",
        ["Close"] = "关闭",
        ["Import pack"] = "Kindle 里已有的卡包文件",
        ["Import packs"] = "导入卡包",
        ["Import from computer"] = "从电脑转换器导入",
        ["Import via browser"] = "用手机或电脑浏览器导入",
        ["Open this address in your phone or computer browser (same Wi-Fi):"] =
            "在手机或电脑浏览器（同一 Wi-Fi）里打开这个地址：",
        ["Pick the .apkg in the page, convert it there, and it lands on this Kindle."] =
            "在网页里选择 .apkg 文件，转换会直接在浏览器完成，卡包随即导入这台 Kindle。",
        ["Import page closed."] = "导入网页已关闭。",
        ["Could not open the import page: %s"] = "无法打开导入网页：%s",
        ["Pairing code (for AI settings): %s"] = "配对码（网页里保存 AI 设置用）：%s",
        ["The page keeps working until you tap Stop here, quit KOReader, or nobody visits it for 30 minutes. You can leave this screen and come back later."] =
            "导入页会一直开着：你可以退出这个界面，手机随时能连；用完回到这里点「立即停止」。退出 KOReader 或 30 分钟无人访问时也会自动关闭。",
        ["Import page closed after 30 minutes without visits."] = "导入网页 30 分钟无人访问，已自动关闭。",
        ["Keep it running"] = "保持开启（用完再停）",
        ["Stop now"] = "立即停止",
        ["Open packs"] = "我的卡包",
        ["Tap a pack to study. The menu icon has import, manage, and AI."] =
            "点卡包开始学习。左上角菜单里可以导入、管理卡包和设置 AI。",
        ["No packs yet. Tap here to import one."] = "还没有卡包。点这里导入一个。",
        ["Phone or computer browser (recommended)"] = "用手机或电脑浏览器（推荐）",
        ["Computer converter over Wi-Fi"] = "从电脑转换器（同一 Wi-Fi）",
        ["A file already on this Kindle"] = "Kindle 里已有的卡包文件",
        ["Tap a pack to delete it with its progress and AI chats."] = "点卡包即可删除，学习进度和 AI 对话会一起删除。",
        ["%d cards"] = "%d 张",
        ["%d to study"] = "待学 %d",
        ["Done today"] = "今日已完成",
        ["Today: %d reviews, %d new"] = "今天：复习 %d 张，新卡 %d 张",
        ["%d cards, not started"] = "共 %d 张，还没开始学",
        ["%d cards, %d not started yet"] = "共 %d 张，其中 %d 张还没学过",
        ["Done for today. Study more"] = "今天学完了，再学几张",
        ["Manage packs"] = "管理卡包",
        ["Delete %s? Study progress and AI chats for this pack will be removed."] =
            "删除 %s？该卡包的学习进度和 AI 对话也会清掉。",
        ["Delete"] = "删除",
        ["this pack"] = "此卡包",
        ["Deleted %s"] = "已删除 %s",
        ["Could not delete pack: %s"] = "无法删除卡包：%s",
        ["No packs to manage."] = "没有可管理的卡包。",
        ["Computer IP"] = "电脑 IP",
        ["Open the converter on your computer first. Enter the IP shown in that window. Same Wi-Fi, no USB."] =
            "先在电脑上打开转换工具，把窗口里显示的 IP 填到这里。同一 Wi-Fi 即可，不用插 USB。",
        ["Look up packs"] = "查找卡包",
        ["Could not reach computer: %s"] = "连不上电脑：%s",
        ["No packs on the computer. Convert a deck first."] = "电脑上还没有卡包。请先转换一个牌组。",
        ["Downloading pack…"] = "正在下载卡包…",
        ["Imported %s"] = "已导入 %s",
        ["%s is already on this Kindle and was not replaced. Delete it first to import a new version."] =
            "Kindle 上已有「%s」，没有覆盖。要更新，请先删除旧卡包再导入。",
        ["Could not import pack: %s"] = "无法导入卡包：%s",
        ["This KOReader build has no file picker. Copy the pack to /mnt/us/kindle-anki/packs/. The legacy folder /mnt/us/folo-anki/ still works."] =
            "当前 KOReader 没有文件选择器。请把卡包拷到 /mnt/us/kindle-anki/packs/。旧目录 /mnt/us/folo-anki/ 仍然可用。",
        ["Back"] = "返回",
        ["Deck complete"] = "牌组完成",
        ["Show back"] = "显示答案",
        ["Check my choices"] = "提交选择",
        ["Type answer"] = "输入答案",
        ["AI explain"] = "AI 解析",
        ["Exit deck"] = "退出",
        ["Card %d / %d"] = "第 %d / %d 张",
        ["Language changed. Menus already open update after you reopen them."] =
            "语言已切换。已经打开的菜单需要重新打开才会更新。",
        ["View images (%d)"] = "查看图片（%d）",
        ["Image files are missing from this pack."] = "卡包里缺少图片文件。",
        ["Type your answer"] = "输入你的答案",
        ["Cancel"] = "取消",
        ["none"] = "未选择",
        ["Match: correct"] = "匹配正确",
        ["Match: check the back"] = "请对照背面检查",
        ["Your answer:"] = "你的答案：",
        ["Your choice: "] = "你的选择：",
        ["Correct"] = "回答正确",
        ["Not quite"] = "回答有误",
        ["Correct: "] = "正确答案：",
        ["Again"] = "重来",
        ["Hard"] = "困难",
        ["Good"] = "良好",
        ["Easy"] = "简单",
        ["Next"] = "下一张",
        ["Skip"] = "跳过",
        ["Rate anyway"] = "仍要评分",
        ["Edit AI settings"] = "填写 AI 设置",
        ["AI settings (local values override pack)"] = "AI 设置（本机设置优先于卡包）",
        ["OpenAI-compatible endpoint"] = "OpenAI 兼容接口",
        ["Model name"] = "模型名称",
        ["API key; local value overrides the pack. Plain http:// sends it unencrypted"] =
            "API 密钥；本机设置优先于卡包。明文 http:// 会不加密传输密钥",
        ["This pack defines its own AI endpoint. Your local API key will be sent to that server. Continue?"] =
            "此卡包自带 AI 接口。你的本机 API 密钥将被发送到该服务器。是否继续？",
        ["Continue"] = "继续",
        ["System prompt"] = "系统提示词",
        ["Explain clearly"] = "请清晰解释",
        ["Save"] = "保存",
        ["AI settings saved locally"] = "AI 设置已保存到本机",
        ["Import AI settings from computer"] = "从电脑导入 AI 设置",
        ["Computer IP (converter open)"] = "电脑 IP（转换器需开着）",
        ["Pairing code shown in the converter"] = "转换器窗口里显示的配对码",
        ["Import"] = "导入",
        ["(empty)"] = "（空）",
        ["Fetching AI settings…"] = "正在获取 AI 设置…",
        ["Could not import AI settings: %s"] = "导入 AI 设置失败：%s",
        ["Configure an API key in the pack or Kindle Anki → AI settings first."] =
            "请先在卡包中配置 API 密钥，或进入 Kindle Anki → AI 设置。",
        ["Ask AI about this card"] = "询问 AI",
        ["The previous AI conversation will appear after you send."] = "发送后会显示之前的 AI 对话，可继续追问。",
        ["Type what you do not understand"] = "输入你不懂的地方",
        ["Send"] = "发送",
        ["Asking AI…"] = "正在请求 AI…",
        ["AI explanation"] = "AI 解析",
        ["Previous page"] = "上一页",
        ["Next page"] = "下一页",
        ["Ask again"] = "再问一次",
        ["Card front:"] = "卡片正面：",
        ["Options:"] = "选项：",
        ["Card back:"] = "卡片背面：",
        ["Correct option labels: "] = "正确选项：",
        ["The learner has not revealed the answer. Do not give away the answer unless necessary to explain the question."] =
            "学习者尚未查看答案。除非为了解释题目确有必要，否则不要直接透露答案。",
        ["You: "] = "你：",
        ["AI: "] = "AI：",
        ["You are a patient study assistant. Explain the learner's question clearly and concisely."] =
            "你是一名耐心的学习助手，请清晰、简洁地解释学习者的问题。",
        ["For Kindle e-ink output, use plain text. Do not use emoji, decorative symbols, or LaTeX. Use ASCII forms such as +, -, *, /, =, <=, and >= for formulas, and explain other symbols in words."] =
            "这是 Kindle 墨水屏，请使用纯文本输出，不要使用表情、装饰性符号或 LaTeX。公式请优先使用 +、-、*、/、=、<=、>= 等 ASCII 写法，其他符号请用文字说明。",
        ["Learner's question:"] = "学习者的问题：",
        ["AI endpoint must be an http:// or https:// URL"] = "AI 接口必须是 http:// 或 https:// URL",
        ["AI model is not configured"] = "尚未配置 AI 模型",
        ["AI API key is not configured in the pack or Kindle settings"] =
            "卡包或 Kindle 设置中尚未配置 AI API 密钥",
        ["Question is empty"] = "问题不能为空",
        ["AI request failed without an HTTP response"] = "AI 请求失败：没有收到 HTTP 响应",
        ["AI request failed"] = "AI 请求失败",
        ["AI request failed (HTTP %d)"] = "AI 请求失败（HTTP %d）",
        ["AI request was interrupted"] = "AI 请求已中断",
        ["AI returned invalid JSON"] = "AI 返回了无效的 JSON",
        ["AI returned no text"] = "AI 没有返回文本",
        ["AI returned only internal reasoning. Ask again."] =
            "模型只返回了内部思考，没有解析正文。请再问一次。",
        ["Card image could not be read"] = "无法读取卡片图片",
        ["Card image is too large"] = "卡片图片过大",
        ["Card image format is unsupported"] = "卡片图片格式不支持",
        ["Card image encoding failed"] = "卡片图片编码失败",
        ["Card images are too large for one AI request"] = "卡片图片总量超过单次 AI 请求限制",

        ["Start studying"] = "开始学习",
        ["Starred cards"] = "收藏的卡片",
        ["Retry missed"] = "错题再练",
        ["No starred cards in this deck."] = "这个牌组没有收藏的卡片。",
        ["No missed cards to retry."] = "没有可再练的错题。",
        ["Star"] = "收藏",
        ["Unstar"] = "取消收藏",
        ["10 min"] = "10 分钟",
        ["Browse cards"] = "浏览全部",
        ["Cards per day (%d)"] = "每天新卡 %d 张",
        ["How many cards per day?"] = "一天打算学多少张？",
        ["This number applies every day until you change it."] =
            "这个数字之后每天都有效，可随时改。",
        ["How many more cards today?"] = "今天再学多少张？",
        ["Only for today. Tomorrow still uses your daily number."] =
            "只加在今天。明天仍按每天张数。",
        ["Enter a number from 1 to 999."] = "请输入 1 到 999 的整数。",
        ["No more cards left to study."] = "没有更多可学的卡片。",
        ["No cards available for this mode."] = "当前模式没有可用卡片。",
        ["today"] = "今天",
        ["%d days"] = "%d 天后",
        ["Rating in browse mode updates the study schedule."] =
            "在浏览模式下评分会改动学习进度。",
        ["Today's goal reached"] = "今日目标达成",
        ["Extra study complete"] = "加练完成",
        ["Browse complete"] = "浏览完成",
        ["%d cards rated: Again %d, Hard %d, Good %d, Easy %d"] =
            "本轮评分 %d 张：重来 %d，困难 %d，良好 %d，简单 %d",
        ["Study more"] = "再学几张",
        ["Back to deck"] = "返回牌组",
        ["Restart chat"] = "清空重聊",
        ["AI chat cleared for this card"] = "已清空本卡 AI 对话",
        ["Clean AI storage"] = "清理 AI 占用",
        ["Removed %d old AI chats. About %d KB remain."] =
            "已删除 %d 段旧 AI 对话，大约还剩 %d KB。",
        ["I have the full card. Ask your question."] =
            "我已拿到完整卡片内容，请提出你的问题。",
    },
}

local locale = "zh_CN"

function I18N.set_locale(requested)
    if type(requested) == "string" and requested:match("^en") then
        locale = "en"
    else
        locale = "zh_CN"
    end
end

function I18N.t(source)
    local catalog = catalogs[locale] or catalogs.zh_CN
    return catalog[source] or source
end

return I18N
