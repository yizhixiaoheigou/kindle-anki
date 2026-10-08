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
local scheduled = {}
local restarts = 0
package.preload["ui/uimanager"] = function()
    return {
        show = function(_, widget) table.insert(shown, widget) end,
        close = function() end,
        scheduleIn = function(_, _, fn) table.insert(scheduled, fn) end,
        flushSettings = function() end,
        restartKOReader = function() restarts = restarts + 1 end,
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

local classes = {}
for _, name in ipairs({
    "ui/widget/buttondialog", "ui/widget/confirmbox", "ui/widget/infomessage",
    "ui/widget/inputdialog", "ui/widget/multiinputdialog", "ui/widget/menu",
}) do
    local class = widget_class()
    classes[name] = class
    package.preload[name] = function() return class end
end
local Menu = classes["ui/widget/menu"]
local ButtonDialog = classes["ui/widget/buttondialog"]
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
            getSize = function() return { w = 1072, h = 1448 } end,
            scaleBySize = function(_, value) return value end,
        },
        hasKeys = function() return false end,
        input = { group = { Back = {} } },
    }
end

-- Widgets the import QR dialog is built from.
local qr_widgets = {}
for _, name in ipairs({
    "ui/widget/buttontable", "ui/widget/container/centercontainer", "ui/widget/container/framecontainer",
    "ui/widget/textboxwidget", "ui/widget/verticalgroup", "ui/widget/verticalspan",
}) do
    package.preload[name] = function() return widget_class() end
end
local QRWidgetStub = widget_class()
function QRWidgetStub:new(args) args._class = QRWidgetStub table.insert(qr_widgets, args) return args end
package.preload["ui/widget/qrwidget"] = function() return QRWidgetStub end
package.preload["ffi/blitbuffer"] = function() return { COLOR_WHITE = 0 } end
package.preload["ui/font"] = function() return { getFace = function(_, name, size) return name .. size end } end
package.preload["ui/size"] = function()
    return { padding = { large = 10 }, radius = { window = 7 }, border = { window = 1 } }
end
package.preload["ui/widget/container/inputcontainer"] = function()
    local Base = {}
    function Base:extend(class) class = class or {} setmetatable(class, { __index = self }) class.__index = class return class end
    function Base:new(object)
        object = setmetatable(object or {}, self)
        object.key_events = {}
        if object.init then object:init() end
        return object
    end
    return Base
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
    plugin.reviews = {}
    plugin.flushes = 0
    plugin.summary = { total = 1, due = 0, new = 1, new_today = 1, today = 1, starred = 0, missed = 0, daily_new = 20 }
    plugin.store = {
        card_state = function() return { interval = 0 } end,
        is_starred = function() return false end,
        Schedule = { preview_days = function() return 1 end },
        daily_new_for = function() return plugin.summary.daily_new end,
        deck_summary = function() return plugin.summary end,
        pack_summary = function() return plugin.summary end,
        flush_progress = function() plugin.flushes = plugin.flushes + 1 end,
        record_review = function(_, _, card, rating) table.insert(plugin.reviews, rating) end,
        set_next_index = function() end,
        list = function() return plugin.library or {} end,
        build_session = function() return plugin.cards, {} end,
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
check("old: progress sits in the title", viewer.title:find("1 / 1", 1, true) ~= nil)
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
check("old: Exit stays the last button", texts[#texts] == "退出")
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
        check("buttons follow the language", find_button(last_viewer(), "Show back") ~= nil)
        language.sub_item_table[1].callback()
        plugin:show_card()
        check("switching back restores Chinese", find_button(last_viewer(), "显示答案") ~= nil)
    end
    I18N.set_locale("zh_CN")
end

-- ------------------------------------------------------------------
-- Import via browser: QR dialog
-- ------------------------------------------------------------------

do
    local WebServerStub = require("webserver")
    local stopped = 0
    WebServerStub.active = {
        ai_code = "4821",
        url = function() return "http://192.168.5.36:8767/" end,
        stop = function() stopped = stopped + 1 end,
    }
    plugin = new_plugin(short_card)
    shown, qr_widgets = {}, {}
    plugin:show_browser_import_dialog()
    local dialog = shown[#shown]
    check("import dialog has a QR code of the page address", #qr_widgets == 1
        and qr_widgets[1].text == "http://192.168.5.36:8767/")
    check("import dialog shows the pairing code", dialog and dialog.notes
        and table.concat(dialog.notes, "\n"):find("4821", 1, true) ~= nil)
    check("import dialog explains WeChat", dialog and dialog.notes[1]:find("微信", 1, true) ~= nil)
    shown = {}
    dialog.on_stop()
    check("stop closes the server", stopped == 1 and WebServerStub.active == nil)

    -- Opened from AI settings: same page, AI tab, pairing code first.
    WebServerStub.active = {
        ai_code = "4821",
        url = function() return "http://192.168.5.36:8767/" end,
        stop = function() end,
    }
    shown, qr_widgets = {}, {}
    plugin:show_browser_import_dialog("ai")
    local ai_dialog = shown[#shown]
    check("AI entry QR opens the AI tab", #qr_widgets == 1 and qr_widgets[1].text == "http://192.168.5.36:8767/#ai")
    check("AI entry shows the plain address", ai_dialog.url == "http://192.168.5.36:8767/")
    check("AI entry leads with the pairing code", ai_dialog.notes[1]:find("4821", 1, true) ~= nil
        and ai_dialog.title == "用手机或电脑浏览器设置 AI")

    -- No Wi-Fi address: no QR code, a hint instead.
    WebServerStub.active = { ai_code = "1", url = function() return "http://<kindle-ip>:8767/" end, stop = function() end }
    shown, qr_widgets = {}, {}
    plugin:show_browser_import_dialog()
    check("no address means no QR code", #qr_widgets == 0
        and shown[#shown].notes[1]:find("没找到", 1, true) ~= nil)

    -- A KOReader build where the dialog cannot be built falls back to text.
    local real = package.loaded["importdialog"]
    package.loaded["importdialog"] = { new = function() error("no QRWidget here") end }
    shown = {}
    plugin:show_browser_import_dialog()
    check("dialog failure falls back to a text box", shown[#shown] and shown[#shown]._class == classes["ui/widget/confirmbox"]
        and shown[#shown].text:find("http://<kindle-ip>:8767/", 1, true) ~= nil)
    package.loaded["importdialog"] = real
    WebServerStub.active = nil
end

-- ------------------------------------------------------------------
-- Navigation screens
-- ------------------------------------------------------------------

do
    -- AI settings come only from the Kindle, never from the pack.
    plugin = new_plugin(short_card)
    local saved = { ai = { endpoint = "https://kindle.example/v1", model = "m", api_key = "sk-kindle" } }
    plugin.settings = { readSetting = function(_, key, default) return saved[key] or default end }
    plugin.pack.ai = { endpoint = "https://pack.example/v1", api_key = "sk-pack", model = "pack-model" }
    local config = plugin:ai_config()
    check("AI config ignores the pack", config.endpoint == "https://kindle.example/v1"
        and config.api_key == "sk-kindle" and config.model == "m")
    saved.ai = nil
    config = plugin:ai_config()
    check("no Kindle AI settings means no AI, even if the pack has some", config.endpoint == ""
        and config.api_key == "")
    shown = {}
    plugin:open_ai_input(short_card, false)
    check("missing AI offers to set it up", shown[#shown] and shown[#shown]._class == classes["ui/widget/confirmbox"]
        and shown[#shown].text:find("AI 还没设置", 1, true) ~= nil)

    -- The AI submenu mirrors the import submenu.
    local menu = {}
    plugin:addToMainMenu(menu)
    local function submenu(title)
        for _, item in ipairs(menu.kindle_anki.sub_item_table) do
            if item.text == title then return item.sub_item_table end
        end
    end
    local ai_menu, import_menu = submenu("AI 设置"), submenu("导入卡包")
    check("AI submenu offers the browser first", ai_menu and ai_menu[1].text == "用手机或电脑浏览器（推荐）"
        and ai_menu[2].text == "从电脑转换器（同一 Wi-Fi）" and ai_menu[3].text == "在 Kindle 上直接填写")
    check("import submenu uses the same wording", import_menu and import_menu[1].text == ai_menu[1].text
        and import_menu[2].text == ai_menu[2].text)
end

do
    -- Manage packs used to crash: its loop shadowed the `_` translator.
    TextViewer.html_text_formats = NEW_TEXTVIEWER_FORMATS
    plugin = new_plugin(short_card)
    plugin.library = { plugin.pack }
    shown = {}
    local ok, err = pcall(function() plugin:open_pack_manager() end)
    check("manage packs opens", ok or print("  " .. tostring(err)))
    local manager
    for index = #shown, 1, -1 do
        if shown[index]._class == Menu then manager = shown[index] break end
    end
    check("manage packs lists packs with a delete label", manager ~= nil
        and manager.item_table[1].mandatory == "删除" and manager.title_bar_left_icon == "chevron.left")
end

local function last_of(class)
    for index = #shown, 1, -1 do
        if shown[index]._class == class then return shown[index] end
    end
end

local function dialog_button(dialog, text)
    for _, row in ipairs(dialog.buttons or {}) do
        for _, button in ipairs(row) do
            if button.text == text then return button end
        end
    end
end

do
    TextViewer.html_text_formats = NEW_TEXTVIEWER_FORMATS
    local two_decks = { title = "Two", decks = { { id = 1, name = "A" }, { id = 2, name = "B" } }, cards = {} }
    plugin = new_plugin(short_card)
    plugin.library = { plugin.pack, two_decks }
    plugin.summary = { total = 30, due = 5, new = 20, new_today = 12, today = 17, starred = 2, missed = 0, daily_new = 20 }
    shown = {}
    plugin:open_library()
    local library = last_of(Menu)
    check("library is a full-screen list", library ~= nil and library.covers_fullscreen == true)
    check("library rows show today's count", library and library.item_table[1].mandatory == "待学 17")
    check("library has the actions icon", library and library.title_bar_left_icon == "appbar.menu")

    -- A single-deck pack goes straight to its deck screen.
    plugin.pack.decks = { { id = 1, name = "Only" } }
    shown = {}
    library.item_table[1].callback()
    local home = last_of(ButtonDialog)
    check("single deck skips the deck list", home ~= nil and last_of(Menu) == nil)
    check("deck title shows today's plan", home and home.title:find("今天：复习 5 张，新卡 12 张", 1, true) ~= nil)
    check("study button carries the count", home and dialog_button(home, "开始学习 (17)") ~= nil)
    local missed = home and dialog_button(home, "错题再练 (0)")
    check("empty missed list is disabled", missed ~= nil and missed.enabled == false)
    shown = {}
    dialog_button(home, "返回").callback()
    check("back from a single deck returns to the library", last_of(Menu) ~= nil
        and last_of(Menu).title == "Kindle Anki")

    -- Several decks get a list with their own counts.
    shown = {}
    plugin:open_decks(two_decks)
    local decks = last_of(Menu)
    check("multi-deck pack lists its decks", decks ~= nil and #decks.item_table == 2
        and decks.title_bar_left_icon == "chevron.left")

    -- Nothing left today: the main button offers more instead.
    plugin.summary = { total = 30, due = 0, new = 0, new_today = 0, today = 0, starred = 0, missed = 0, daily_new = 20 }
    shown = {}
    plugin:open_deck_actions(two_decks.decks[1])
    check("finished deck offers to study more", dialog_button(last_of(ButtonDialog), "今天学完了，再学几张") ~= nil)
end

do
    -- A round: rate every card, then the summary counts the ratings.
    TextViewer.html_text_formats = NEW_TEXTVIEWER_FORMATS
    local second = { id = 9, deck_id = 1, type = "short_answer", front = "Q2", back = "A2" }
    plugin = new_plugin(short_card)
    plugin.cards = { short_card, second }
    plugin.summary = { total = 2, due = 0, new = 0, new_today = 0, today = 0, starred = 0, missed = 1, daily_new = 20 }
    plugin:begin_session(plugin.deck, "study")
    check("session opens on the first card", last_viewer().title:find("1 / 2", 1, true) ~= nil)
    plugin:show_answer(nil, nil)
    check("answer shows the question above the back", last_viewer().text:find("lush", 1, true) ~= nil
        and last_viewer().text:find("茂盛的", 1, true) ~= nil)
    check("ratings share one row", #last_viewer().buttons_table[1] == 4)
    find_button(last_viewer(), "重来 · 10 分钟").callback()
    plugin:show_answer(nil, nil)
    shown = {}
    find_button(last_viewer(), "良好 · 1 天后").callback()
    local done = last_of(ButtonDialog)
    check("round summary counts ratings", done and done.title:find("本轮评分 2 张：重来 1，困难 0，良好 1，简单 0", 1, true) ~= nil)
    check("round summary offers missed cards", done and dialog_button(done, "错题再练 (1)") ~= nil)
    check("ratings were recorded", plugin.reviews[1] == "again" and plugin.reviews[2] == "good")
    check("progress is flushed at the end of a round", plugin.flushes >= 1)
end

do
    -- A choice card says whether the pick was right.
    TextViewer.html_text_formats = NEW_TEXTVIEWER_FORMATS
    plugin = new_plugin(choice_card)
    plugin:show_answer({ [2] = true })
    check("right choice is marked correct", last_viewer().text:find("回答正确", 1, true) ~= nil)
    plugin:show_answer({ [1] = true })
    check("wrong choice is marked", last_viewer().text:find("回答有误", 1, true) ~= nil)
end

-- ------------------------------------------------------------------
-- Developer remote restart
-- ------------------------------------------------------------------

do
    local MARKER = "/mnt/us/kindle-anki/dev-remote-restart"
    local REQUEST = "/tmp/kindle-anki-restart"
    KindleAnki.dev_restart_watching = nil
    plugin = new_plugin(short_card)
    local exits = 0
    plugin.ui = { menu = { exitOrRestart = function(_, callback) exits = exits + 1 callback() end } }

    missing_files[MARKER] = true
    scheduled = {}
    plugin:watch_dev_restart()
    check("no marker, no watcher", #scheduled == 0)

    missing_files[MARKER] = nil
    missing_files[REQUEST] = true
    plugin:watch_dev_restart()
    plugin:watch_dev_restart()
    check("marker starts one watcher", #scheduled == 1)
    local tick = table.remove(scheduled)
    tick()
    check("no request keeps polling", restarts == 0 and #scheduled == 1)

    missing_files[REQUEST] = nil
    plugin.flushes = 0
    tick = table.remove(scheduled)
    tick()
    check("request restarts through the menu", exits == 1 and restarts == 1)
    check("progress is flushed before restart", plugin.flushes == 1)
    check("watcher stops after restarting", #scheduled == 0)
    missing_files[MARKER] = true
end

if failures > 0 then
    print(failures .. " FAILED")
    os.exit(1)
end
print("ALL OK")
