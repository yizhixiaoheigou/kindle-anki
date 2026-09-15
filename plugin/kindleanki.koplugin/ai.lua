local JSON = require("json")
local _ = require("i18n").t
local ltn12 = require("ltn12")
local mime = require("mime")
local socket = require("socket")
local http = require("socket.http")
local https = require("ssl.https")
local socketutil = require("socketutil")
local util = require("util")
local ffiutil = require("ffi/util")

local AI = {}
AI.MAX_HISTORY_MESSAGES = 12
AI.MAX_RESPONSE_CHARS = 8000
AI.MAX_IMAGE_BYTES = 4 * 1024 * 1024
AI.MAX_IMAGE_TOTAL_BYTES = 12 * 1024 * 1024
local SKIP_CONTENT_TYPES = {
    reasoning = true,
    thinking = true,
    thought = true,
    reasoning_content = true,
}

local function option_letter(index)
    local label = ""
    while index > 0 do
        local remainder = (index - 1) % 26
        label = string.char(65 + remainder) .. label
        index = math.floor((index - 1) / 26)
    end
    return label
end

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function endpoint_for(value)
    local endpoint = trim(value):gsub("/+$", "")
    if endpoint == "" then return nil end
    if not endpoint:match("^https?://") then return nil end
    if endpoint:match("/chat/completions$") then return endpoint end
    if endpoint:match("/v1$") then return endpoint .. "/chat/completions" end
    return endpoint .. "/v1/chat/completions"
end

-- KOReader has good CJK fallback fonts, but no emoji font. Keep common
-- educational symbols readable on the Kindle and replace emoji with a clear
-- text marker instead of letting the renderer fall back to "?".
local DISPLAY_REPLACEMENTS = {
    ["×"] = " x ", ["÷"] = " / ", ["−"] = "-", ["–"] = "-", ["—"] = "-",
    ["≤"] = "<=", ["≥"] = ">=", ["≠"] = "!=", ["≈"] = "约等于",
    ["±"] = "+/-", ["→"] = "->", ["←"] = "<-", ["↔"] = "<->",
    ["√"] = "根号", ["∞"] = "无穷", ["∑"] = "求和", ["∫"] = "积分",
    ["∂"] = "偏导", ["∈"] = "属于", ["∉"] = "不属于", ["∴"] = "因此",
    ["∵"] = "因为", ["•"] = "*", ["★"] = "*", ["✓"] = "[正确]", ["✗"] = "[错误]",
    ["…"] = "...",
}

local function kindle_safe_text(value)
    local output = {}
    for _, char in ipairs(util.splitToChars(tostring(value or ""))) do
        local replacement = DISPLAY_REPLACEMENTS[char]
        if replacement == nil then
            local codepoint = ffiutil.utf8charcode(char)
            if codepoint == 0xFE0E or codepoint == 0xFE0F or codepoint == 0x200D
                    or (codepoint >= 0x1F3FB and codepoint <= 0x1F3FF) then
                replacement = ""
            elseif codepoint and ((codepoint >= 0x1F000 and codepoint <= 0x1FAFF)
                    or (codepoint >= 0x1FC00 and codepoint <= 0x1FFFF)) then
                replacement = "[图标]"
            else
                replacement = char
            end
        end
        table.insert(output, replacement)
    end
    return table.concat(output)
end

local function strip_tagged_block(text, open_tag, close_tag)
    while true do
        local start_at = text:find(open_tag, 1, true)
        if not start_at then return text end
        local close_at = text:find(close_tag, start_at + #open_tag, true)
        if not close_at then
            return trim(text:sub(1, start_at - 1))
        end
        text = text:sub(1, start_at - 1) .. text:sub(close_at + #close_tag)
    end
end

local function strip_thinking(text)
    text = tostring(text or "")
    text = strip_tagged_block(text, "<think>", "</think>")
    text = strip_tagged_block(text, "<thinking>", "</thinking>")
    text = strip_tagged_block(text, "<reasoning>", "</reasoning>")
    text = strip_tagged_block(text, "<thought>", "</thought>")
    return trim(text)
end

local function content_text(value)
    if type(value) == "string" then return value end
    if type(value) == "table" then
        local part_type = tostring(value.type or value.kind or "")
        if SKIP_CONTENT_TYPES[part_type] then return "" end
        if type(value.text) == "string" then return value.text end
        if value.content ~= nil then
            local nested = content_text(value.content)
            if nested ~= "" then return nested end
        end
        if type(value.output_text) == "string" then return value.output_text end
        local parts = {}
        for _, item in ipairs(value) do
            if type(item) == "string" then
                table.insert(parts, item)
            elseif type(item) == "table" then
                local item_text = content_text(item)
                if item_text ~= "" then
                    table.insert(parts, item_text)
                end
            end
        end
        return table.concat(parts)
    end
    return ""
end

local function response_text(payload)
    if type(payload) ~= "table" then return nil end
    if type(payload.choices) == "table" and type(payload.choices[1]) == "table" then
        local choice = payload.choices[1]
        local message = choice.message or choice.delta
        if type(message) == "table" then
            -- Keep server-side reasoning; never put it in the visible answer.
            local text = strip_thinking(content_text(message.content))
            if text ~= "" then return text end
            text = strip_thinking(content_text(message.text))
            if text ~= "" then return text end
        end
        local text = strip_thinking(content_text(choice.text))
        if text ~= "" then return text end
    end
    if type(payload.output_text) == "string" then
        local text = strip_thinking(payload.output_text)
        if text ~= "" then return text end
    end
    if type(payload.response) == "string" then
        local text = strip_thinking(payload.response)
        if text ~= "" then return text end
    end
    if type(payload.answer) == "string" then
        local text = strip_thinking(payload.answer)
        if text ~= "" then return text end
    end
    if type(payload.output) == "table" then
        local text = strip_thinking(content_text(payload.output))
        if text ~= "" then return text end
    end
    return nil
end

local function card_context(card, revealed)
    local lines = { _("Card front:"), card.front }
    if card.type == "choice" then
        table.insert(lines, _("Options:"))
        for index, option in ipairs(card.options) do
            table.insert(lines, string.format("%s. %s", option_letter(index), option))
        end
    end
    -- The UI may keep the back hidden, but AI must always receive the complete
    -- card so it explains the supplied answer instead of guessing one.
    table.insert(lines, _("Card back:"))
    table.insert(lines, card.back)
    if card.type == "choice" then
        local correct = {}
        for _, index in ipairs(card.correct_indices or {}) do
            table.insert(correct, option_letter(index + 1))
        end
        table.insert(lines, _("Correct option labels: ") .. table.concat(correct, ", "))
    end
    return table.concat(lines, "\n")
end

local function image_mime_type(path, data)
    if data:sub(1, 8) == "\137PNG\r\n\026\n" then return "image/png" end
    if data:sub(1, 4) == "GIF8" then return "image/gif" end
    if data:sub(1, 2) == "\255\216" then return "image/jpeg" end
    if data:sub(1, 12):sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then
        return "image/webp"
    end
    local extension = path:lower():match("%.([a-z0-9]+)$")
    local extensions = {
        jpg = "image/jpeg", jpeg = "image/jpeg", png = "image/png",
        gif = "image/gif", webp = "image/webp",
    }
    return extensions[extension]
end

local function image_part(path)
    local file = io.open(path, "rb")
    if not file then return nil, _("Card image could not be read") end
    local data = file:read("*a")
    file:close()
    if type(data) ~= "string" or data == "" then
        return nil, _("Card image could not be read")
    end
    if #data > AI.MAX_IMAGE_BYTES then
        return nil, _("Card image is too large")
    end
    local content_type = image_mime_type(path, data)
    if not content_type then return nil, _("Card image format is unsupported") end
    local encoded = mime.b64(data)
    if type(encoded) ~= "string" or encoded == "" then
        return nil, _("Card image encoding failed")
    end
    return {
        type = "image_url",
        image_url = { url = "data:" .. content_type .. ";base64," .. encoded:gsub("%s", "") },
    }, #data
end

function AI.build_messages(config, card, history, question, revealed, image_paths)
    -- Formal order for prompt-prefix caching:
    -- system -> fixed card context (+ images) -> prior Q&A -> new question only.
    local configured_prompt = trim(config.system_prompt)
    local system_prompt = configured_prompt ~= "" and configured_prompt
        or _("You are a patient study assistant. Explain the learner's question clearly and concisely.")
    system_prompt = system_prompt .. "\n\n" .. _(
        "For Kindle e-ink output, use plain text. Do not use emoji, decorative symbols, or LaTeX. "
        .. "Use ASCII forms such as +, -, *, /, =, <=, and >= for formulas, and explain other symbols in words."
    )
    local messages = {
        {
            role = "system",
            content = system_prompt,
        },
    }

    local context = card_context(card, true)
    local context_content = { { type = "text", text = context } }
    local total_image_bytes = 0
    for _, path in ipairs(image_paths or {}) do
        local image, size_or_error = image_part(path)
        if not image then return nil, size_or_error end
        total_image_bytes = total_image_bytes + size_or_error
        if total_image_bytes > AI.MAX_IMAGE_TOTAL_BYTES then
            return nil, _("Card images are too large for one AI request")
        end
        table.insert(context_content, image)
    end
    table.insert(messages, {
        role = "user",
        content = #context_content == 1 and context or context_content,
    })
    table.insert(messages, {
        role = "assistant",
        content = _("I have the full card. Ask your question."),
    })

    local start = math.max(1, #(history or {}) - AI.MAX_HISTORY_MESSAGES + 1)
    for index = start, #(history or {}) do
        local message = history[index]
        if type(message) == "table" and (message.role == "user" or message.role == "assistant") then
            table.insert(messages, { role = message.role, content = trim(message.content) })
        end
    end
    table.insert(messages, {
        role = "user",
        content = trim(question),
    })
    return messages
end

local function request_sync(request, body)
    local response_body = {}
    request.source = ltn12.source.string(body)
    request.sink = ltn12.sink.table(response_body)

    -- Chat completions regularly take longer than 20s to generate; a short
    -- limit here surfaces as "no HTTP response" to the user.
    socketutil:set_timeout(60, 360)
    local requester = request.url:match("^https://") and https.request or http.request
    local ok, code, headers, status = pcall(function()
        return socket.skip(1, requester(request))
    end)
    socketutil:reset_timeout()

    if not ok then
        return { error = tostring(code) }
    end
    return {
        code = code,
        headers = headers,
        status = status,
        body = table.concat(response_body),
    }
end

function AI:request(config, card, history, question, revealed, image_paths)
    local url = endpoint_for(config.endpoint)
    if not url then return { ok = false, error = _("AI endpoint must be an http:// or https:// URL") } end
    if trim(config.model) == "" then return { ok = false, error = _("AI model is not configured") } end
    if trim(config.api_key) == "" then return { ok = false, error = _("AI API key is not configured in the pack or Kindle settings") } end
    if trim(question) == "" then return { ok = false, error = _("Question is empty") } end

    local messages, message_error = self.build_messages(
        config, card, history, question, revealed, image_paths
    )
    if not messages then return { ok = false, error = message_error } end
    local payload = {
        model = trim(config.model),
        messages = messages,
        stream = false,
        temperature = 0.2,
        max_tokens = 4096,
    }
    local body = JSON.encode(payload)
    local response = request_sync({
        url = url,
        method = "POST",
        headers = {
            ["Authorization"] = "Bearer " .. trim(config.api_key),
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
            ["Content-Length"] = tostring(#body),
        },
    }, body)
    if response.error then return { ok = false, error = _("AI request failed") } end

    local code = tonumber(response.code)
    if not code then return { ok = false, error = _("AI request failed without an HTTP response") } end
    if code < 200 or code >= 300 then
        return { ok = false, error = string.format(_("AI request failed (HTTP %d)"), code) }
    end

    local ok, decoded = pcall(JSON.decode, response.body or "")
    if not ok then return { ok = false, error = _("AI returned invalid JSON") } end
    local text = kindle_safe_text(trim(response_text(decoded) or ""))
    if text == "" then
        return { ok = false, error = _("AI returned only internal reasoning. Ask again.") }
    end
    local chars = util.splitToChars(text)
    if #chars > AI.MAX_RESPONSE_CHARS then
        text = table.concat(chars, "", 1, AI.MAX_RESPONSE_CHARS) .. "\n[…]"
    end
    return { ok = true, text = text }
end

return AI
