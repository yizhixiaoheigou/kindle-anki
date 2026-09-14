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
        ["Choose a Kindle Anki pack"] = "选择 Kindle Anki 卡包",
        ["Import pack"] = "导入卡包",
        ["Import from computer"] = "从电脑导入",
        ["Open packs"] = "打开卡包",
        ["Manage packs"] = "管理卡包",
        ["Delete this pack"] = "删除此卡包",
        ["Delete: %s"] = "删除：%s",
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
        ["Could not import pack: %s"] = "无法导入卡包：%s",
        ["No packs yet. Keep the computer converter open, then use Import from computer."] =
            "还没有卡包。请先打开电脑上的转换工具，再用「从电脑导入」。",
        ["This KOReader build has no file picker. Copy the pack to /mnt/us/kindle-anki/packs/. The legacy folder /mnt/us/folo-anki/ still works."] =
            "当前 KOReader 没有文件选择器。请把卡包拷到 /mnt/us/kindle-anki/packs/。旧目录 /mnt/us/folo-anki/ 仍然可用。",
        ["Back"] = "返回",
        ["Deck complete"] = "牌组完成",
        ["Show back"] = "显示背面",
        ["Type answer"] = "输入答案",
        ["AI explain"] = "AI 解析",
        ["Exit deck"] = "退出牌组",
        ["Type your answer"] = "输入你的答案",
        ["Cancel"] = "取消",
        ["none"] = "未选择",
        ["Match: correct"] = "匹配正确",
        ["Match: check the back"] = "请对照背面检查",
        ["Your answer:"] = "你的答案：",
        ["Your choice: "] = "你的选择：",
        ["Correct: "] = "正确答案：",
        ["Again"] = "重来",
        ["Hard"] = "困难",
        ["Good"] = "良好",
        ["Easy"] = "简单",
        ["Next"] = "下一张",
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
        ["Browse cards"] = "浏览卡片",
        ["Cards per day (%d)"] = "每天学多少张（%d）",
        ["%s · %d cards/day"] = "%s · 每天 %d 张",
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
