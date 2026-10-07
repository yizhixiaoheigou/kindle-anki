#!/usr/bin/env lua
-- Card review views on new and old KOReader, with KOReader modules stubbed.
--   lua run_card_view.lua
-- KOReader v2026.07 added HTML rendering to TextViewer (koreader#15588).
-- Older builds print the markup verbatim, so main.lua must send plain text
-- there. Exits 0 and prints ALL OK when every scenario passes.

io.stdout:setvbuf("line")

local root = (arg and arg[0] or ""):match("^(.*)/tests/lua_harness/[^/]+$") or "."
local plugin_dir = root .. "/plugin/kindleanki.koplugin"
package.path = plugin_dir .. "/?.lua;" .. package.path

local failures = 0
local function check(name, ok)
    print((ok and "ok   " or "FAIL ") .. name)
    if not ok then failures = failures + 1 end
end

-- ------------------------------------------------------------------
-- KOReader stubs
-- ------------------------------------------------------------------

local shown = {}
package.preload["ui/uimanager"] = function()
    return {
        show = function(_, widget) table.insert(shown, widget) end,
        close = function() end,
        scheduleIn = function() end,
    }
end

local function widget_class()
    local class = {}
    function class:new(args)
        args = args or {}
        args._class = class
        return args
    end
    return class
end

local TextViewer = widget_class()
local NEW_TEXTVIEWER_FORMATS = { html = true, htm = true, md = true }
local text_viewers = {}
function TextViewer:new(args)
    args._class = TextViewer
    if self.html_text_formats then
        -- v2026.07+: scroll_widget, box_widget and onScrollOrNavigate.
        args.scroll_widget = {
            pages = {},
            onScrollDown = function(widget) table.insert(widget.pages, 1) return true end,
            onScrollUp = function(widget) table.insert(widget.pages, -1) return true end,
        }
        args.onScrollOrNavigate = function(viewer, direction)
            if direction > 0 then return viewer.scroll_widget:onScrollDown() end
            return viewer.scroll_widget:onScrollUp()
        end
    else
        -- Before v2026.07: only scroll_text_w, which pages with scrollText.
        args.scroll_text_w = {
            pages = {},
            scrollText = function(widget, direction) table.insert(widget.pages, direction) end,
        }
    end
    table.insert(text_viewers, args)
    return args
end
package.preload["ui/widget/textviewer"] = function() return TextViewer end

local ImageViewer = widget_class()
package.preload["ui/widget/imageviewer"] = function() return ImageViewer end
package.preload["ui/renderimage"] = function()
    return { renderImageFile = function(_, path) return { path = path } end }
end
local missing_files = {}
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path, key)
            if key == "mode" and not missing_files[path] then return "file" end
            return nil
        end,
    }
end

for _, name in ipairs({
    "ui/widget/buttondialog", "ui/widget/confirmbox", "ui/widget/infomessage",
    "ui/widget/inputdialog", "ui/widget/multiinputdialog",
}) do
    local class = widget_class()
    package.preload[name] = function() return class end
end
package.preload["datastorage"] = function()
    return { getSettingsDir = function() return "/tmp/kindle-anki-harness" end }
end
package.preload["luasettings"] = function()
    return { open = function() return { data = {}, readSetting = function(_, _, default) return default end } end }
end
package.preload["device"] = function()
    return {
        screen = {
            getWidth = function() return 1072 end,
            getHeight = function() return 1448 end,
            scaleBySize = function(_, value) return value end,
        },
    }
end
package.preload["ui/trapper"] = function() return {} end
package.preload["ui/widget/container/widgetcontainer"] = function()
    return { extend = function(_, class) class.__index = class return class end }
end
package.preload["util"] = function()
    -- Same entities as KOReader's util.htmlEscape, including '/'.
    local entities = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;",
        ['"'] = "&quot;", ["'"] = "&#39;", ["/"] = "&#47;" }
    return {
        htmlEscape = function(text) return (text:gsub("[&<>\"'/]", entities)) end,
        splitToChars = function(text)
            local chars = {}
            for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do table.insert(chars, char) end
            return chars
        end,
    }
end
package.preload["ai"] = function() return {} end
package.preload["store"] = function() return {} end
package.preload["webserver"] = function() return {} end

local KindleAnki = dofile(plugin_dir .. "/main.lua")
require("i18n").set_locale("zh_CN")

-- ------------------------------------------------------------------
-- Fixtures
-- ------------------------------------------------------------------

local short_card = {
    id = "c1",
    type = "short_answer",
    front = "lush\nThe island's surface is covered with a lush forest.",
    back = "茂盛的 a/b",
    front_images = { { name = "front.png", width = 300, height = 200 } },
    back_images = { "back-1.png", "back-2.png" },
}
local choice_card = {
    id = "c2",
    type = "choice",
    mode = "single",
    front = "Pick one",
    options = { "first", "second" },
    correct_indices = { 1 },
}

local function new_plugin(card)
    local plugin = setmetatable({}, KindleAnki)
    plugin.pack = { _path = "/mnt/us/kindle-anki/packs/p.kindle-anki.json", media_dir = "p.kindle-anki.media", title = "P" }
    plugin.deck = { id = "d", name = "D" }
    plugin.cards = { card }
    plugin.card_position = 1
    plugin.session_mode = "study"
    plugin.store = {
        card_state = function() return { interval = 0 } end,
        is_starred = function() return false end,
        Schedule = { preview_days = function() return 1 end },
    }
    return plugin
end

local function button_texts(viewer)
    local texts = {}
    for _, row in ipairs(viewer.buttons_table or {}) do
        for _, button in ipairs(row) do table.insert(texts, button.text) end
    end
    return texts
end

local function find_button(viewer, text)
    for _, row in ipairs(viewer.buttons_table or {}) do
        for _, button in ipairs(row) do
            if button.text == text then return button end
        end
    end
end

local function has_markup(text)
    return text:find("<", 1, true) ~= nil or text:find("&#", 1, true) ~= nil
        or text:find("&amp;", 1, true) ~= nil
end

local function last_viewer() return text_viewers[#text_viewers] end

-- ------------------------------------------------------------------
-- New KOReader: HTML body with inline images
-- ------------------------------------------------------------------

TextViewer.html_text_formats = NEW_TEXTVIEWER_FORMATS
local plugin = new_plugin(short_card)
plugin:show_card()
local viewer = last_viewer()
check("new: front uses html", viewer.text_format == "html")
check("new: front sets resource file", viewer.file == plugin.pack._path .. ".kindle-card.html")
check("new: front embeds image", viewer.text:find('<img src="p.kindle-anki.media/front.png"', 1, true) ~= nil)
check("new: no image button", find_button(viewer, "查看图片（1）") == nil)

plugin:show_answer(nil, "it's")
viewer = last_viewer()
check("new: back uses html", viewer.text_format == "html")
check("new: typed answer is escaped once", viewer.text:find("it&#39;s", 1, true) ~= nil
    and viewer.text:find("&amp;#39;", 1, true) == nil)
check("new: back embeds images", viewer.text:find("back-2.png", 1, true) ~= nil)

-- ------------------------------------------------------------------
-- Old KOReader: plain text, images from a button
-- ------------------------------------------------------------------

TextViewer.html_text_formats = nil
plugin = new_plugin(short_card)
plugin:show_card()
viewer = last_viewer()
check("old: front has no text_format", viewer.text_format == nil)
check("old: front has no html file", viewer.file == nil)
check("old: front has no markup", not has_markup(viewer.text))
check("old: front shows progress", viewer.text:find("第 1 / 1 张", 1, true) ~= nil)
check("old: front shows raw apostrophe", viewer.text:find("The island's surface", 1, true) ~= nil)
check("old: front hides back", viewer.text:find("茂盛的", 1, true) == nil)
local images = find_button(viewer, "查看图片（1）")
check("old: front image button", images ~= nil)
if images then
    shown = {}
    images.callback()
    local image_viewer = shown[#shown]
    check("old: single image opens by file", image_viewer and image_viewer._class == ImageViewer
        and image_viewer.file == "/mnt/us/kindle-anki/packs/p.kindle-anki.media/front.png")
end

plugin:show_answer(nil, "it's")
viewer = last_viewer()
check("old: back has no markup", not has_markup(viewer.text))
check("old: back shows typed answer", viewer.text:find("你的答案：\nit's", 1, true) ~= nil)
check("old: back shows back text", viewer.text:find("茂盛的 a/b", 1, true) ~= nil)
images = find_button(viewer, "查看图片（2）")
check("old: back image button", images ~= nil)
local texts = button_texts(viewer)
check("old: Next stays the last button", texts[#texts] == "下一张" or texts[#texts] == "Next")
if images then
    shown = {}
    images.callback()
    local image_viewer = shown[#shown]
    local list = image_viewer and image_viewer.image
    check("old: several images open as a list", type(list) == "table" and #list == 2
        and list.image_disposable == true
        and list[2]().path == "/mnt/us/kindle-anki/packs/p.kindle-anki.media/back-2.png")

    missing_files["/mnt/us/kindle-anki/packs/p.kindle-anki.media/back-1.png"] = true
    missing_files["/mnt/us/kindle-anki/packs/p.kindle-anki.media/back-2.png"] = true
    shown = {}
    images.callback()
    check("old: missing images show a message", shown[#shown] and shown[#shown]._class ~= ImageViewer)
end

plugin = new_plugin(choice_card)
plugin:show_card()
viewer = last_viewer()
check("old: choice lists options", viewer.text:find("A. first\nB. second", 1, true) ~= nil)
check("old: choice has no image button", find_button(viewer, "查看图片（1）") == nil)
plugin:show_answer({ [2] = true })
viewer = last_viewer()
check("old: choice result without markup", not has_markup(viewer.text)
    and viewer.text:find("你的选择：B\n正确答案：B", 1, true) ~= nil)

-- ------------------------------------------------------------------
-- AI conversation paging on both builds
-- ------------------------------------------------------------------

for _, build in ipairs({ "new", "old" }) do
    TextViewer.html_text_formats = build == "new" and NEW_TEXTVIEWER_FORMATS or nil
    plugin = new_plugin(short_card)
    plugin.ai_history = { { role = "user", content = "q" }, { role = "assistant", content = "a" } }
    local ok, err = pcall(function() plugin:show_ai_conversation(short_card, false) end)
    check(build .. ": AI conversation opens", ok or print(err))
    viewer = last_viewer()
    local ok_next = pcall(function() find_button(viewer, "下一页").callback() end)
    local ok_prev = pcall(function() find_button(viewer, "上一页").callback() end)
    local pages = (viewer.scroll_widget or viewer.scroll_text_w).pages
    check(build .. ": AI paging works", ok_next and ok_prev and pages[1] == 1 and pages[2] == -1)
end

-- ------------------------------------------------------------------
-- Language switch
-- ------------------------------------------------------------------

do
    local I18N = require("i18n")
    local saved = {}
    plugin = new_plugin(short_card)
    plugin.settings = {
        readSetting = function(_, key, default) if saved[key] ~= nil then return saved[key] end return default end,
        saveSetting = function(settings, key, value) saved[key] = value return settings end,
        flush = function() end,
    }
    local menu = {}
    plugin:addToMainMenu(menu)
    local language
    for _, item in ipairs(menu.kindle_anki.sub_item_table) do
        if item.text == "Language / 语言" then language = item end
    end
    check("menu has a bilingual language entry", language ~= nil)
    if language then
        local english = language.sub_item_table[2]
        check("Chinese is checked by default", language.sub_item_table[1].checked_func() and not english.checked_func())
        english.callback()
        check("switching saves the locale", saved.locale == "en" and english.checked_func())
        TextViewer.html_text_formats = nil
        plugin:show_card()
        check("progress follows the language", last_viewer().text:find("Card 1 / 1", 1, true) ~= nil)
        language.sub_item_table[1].callback()
        plugin:show_card()
        check("switching back restores Chinese", last_viewer().text:find("第 1 / 1 张", 1, true) ~= nil)
    end
    I18N.set_locale("zh_CN")
end

if failures > 0 then
    print(failures .. " FAILED")
    os.exit(1)
end
print("ALL OK")
