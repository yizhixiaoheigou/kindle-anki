local AI = require("ai")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Store = require("store")
local Screen = require("device").screen
local WebServer = require("webserver")
local TextViewer = require("ui/widget/textviewer")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local I18N = require("i18n")
local util = require("util")
local _ = I18N.t

local function open_settings()
    local new_path = DataStorage:getSettingsDir() .. "/kindle_anki.lua"
    local old_path = DataStorage:getSettingsDir() .. "/folo_anki.lua"
    local settings = LuaSettings:open(new_path)
    if settings and settings.data and next(settings.data) ~= nil then
        return settings
    end
    local legacy = LuaSettings:open(old_path)
    if legacy and legacy.data and next(legacy.data) ~= nil then
        legacy.file = new_path
        return legacy
    end
    return settings
end

local KindleAnki = WidgetContainer:extend{
    name = "kindleanki",
    is_doc_only = false,
    settings_file = DataStorage:getSettingsDir() .. "/kindle_anki.lua",
}

local function close_widget(widget)
    if widget then
        UIManager:close(widget)
    end
end

-- TextViewer renders HTML only from KOReader v2026.07 (koreader#15588).
-- Older builds ignore text_format and print the markup verbatim, so cards
-- fall back to plain text there and images open from a button instead.
local function textviewer_renders_html()
    local formats = TextViewer.html_text_formats
    return type(formats) == "table" and formats.html == true
end

-- Before v2026.07 the scroll widget was `scroll_text_w`, there was no
-- `box_widget`, and `onScrollOrNavigate` did not exist.
local function viewer_scroll_widget(viewer)
    return viewer and (viewer.scroll_widget or viewer.scroll_text_w)
end

local function viewer_text_box(viewer)
    if not viewer then return nil end
    if viewer.box_widget then return viewer.box_widget end
    local scroll = viewer_scroll_widget(viewer)
    return scroll and scroll.text_widget
end

local function scroll_viewer_page(viewer, direction)
    if viewer.onScrollOrNavigate then
        viewer:onScrollOrNavigate(direction)
        return
    end
    local scroll = viewer_scroll_widget(viewer)
    if scroll and scroll.scrollText then scroll:scrollText(direction) end
end

local function pack_directory(pack)
    local path = pack and pack._path
    return path and path:match("^(.*)/[^/]+$") or "/mnt/us/kindle-anki/packs"
end

local function display_deck_name(deck)
    local name = tostring(deck and deck.name or "")
    local leaf = name:match("::([^:]+)$") or name
    leaf = leaf:gsub("^%s+", ""):gsub("%s+$", "")
    return leaf:match("^(第%d+章)") or leaf
end

local function study_title(pack, deck)
    local pack_title = tostring(pack and pack.title or "")
    local deck_title = display_deck_name(deck)
    if pack_title ~= "" and deck_title ~= "" then
        return pack_title .. " · " .. deck_title
    end
    return pack_title ~= "" and pack_title or deck_title
end

local function option_letter(index)
    local label = ""
    while index > 0 do
        local remainder = (index - 1) % 26
        label = string.char(65 + remainder) .. label
        index = math.floor((index - 1) / 26)
    end
    return label
end

local function option_label(index, text, selected)
    return string.format("%s %s. %s", selected and "☑" or "☐", option_letter(index), text)
end

function KindleAnki:init()
    self.settings = open_settings()
    I18N.set_locale(self.settings:readSetting("locale", "zh_CN"))
    self.store = Store:new(self.settings)
    self.ui.menu:registerToMainMenu(self)
    -- KOReader builds a fresh plugin instance for the file browser and for
    -- every opened book, but the import page outlives them: hand a running
    -- server to the newest instance so its callbacks and settings are live.
    if WebServer.active and WebServer.active:is_running() then
        self:attach_webserver(WebServer.active)
    end
    self:watch_dev_restart()
end

-- KOReader broadcasts FlushSettings on suspend and exit. Progress is
-- batched in memory, so write it out then instead of losing it.
function KindleAnki:onFlushSettings()
    if self.store then self.store:flush_progress() end
end

-- Developer devices only: when DEV_RESTART_MARKER exists, the deploy script
-- (scripts/kindle-deploy.sh --restart) asks for a restart by creating
-- DEV_RESTART_REQUEST. KOReader then restarts through its own menu path,
-- which saves settings and progress first. Without the marker nothing runs.
local DEV_RESTART_MARKER = "/mnt/us/kindle-anki/dev-remote-restart"
local DEV_RESTART_REQUEST = "/tmp/kindle-anki-restart"
local DEV_RESTART_POLL_SECONDS = 2

function KindleAnki:watch_dev_restart()
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(DEV_RESTART_MARKER, "mode") ~= "file" then return end
    -- One watcher for all plugin instances; it acts through the newest one,
    -- whose UI (file browser or reader) is the one on screen.
    KindleAnki.dev_restart_owner = self
    if KindleAnki.dev_restart_watching then return end
    KindleAnki.dev_restart_watching = true
    local function check()
        if lfs.attributes(DEV_RESTART_REQUEST, "mode") then
            os.remove(DEV_RESTART_REQUEST)
            KindleAnki.dev_restart_watching = false
            local owner = KindleAnki.dev_restart_owner
            if owner and owner.store then owner.store:flush_progress() end
            local menu = owner and owner.ui and owner.ui.menu
            if menu and menu.exitOrRestart then
                menu:exitOrRestart(function() UIManager:restartKOReader() end)
            else
                UIManager:flushSettings()
                UIManager:restartKOReader()
            end
            return
        end
        UIManager:scheduleIn(DEV_RESTART_POLL_SECONDS, check)
    end
    UIManager:scheduleIn(DEV_RESTART_POLL_SECONDS, check)
end

function KindleAnki:addToMainMenu(menu_items)
    menu_items.kindle_anki = {
        text = _("Kindle Anki"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Open packs"),
                callback = function() self:open_library() end,
            },
            {
                text = _("Import packs"),
                sub_item_table = {
                    { text = _("Phone or computer browser (recommended)"), callback = function() self:open_browser_import() end },
                    { text = _("Computer converter over Wi-Fi"), callback = function() self:import_from_computer() end },
                    { text = _("A file already on this Kindle"), callback = function() self:import_pack() end },
                },
            },
            {
                text = _("Manage packs"),
                callback = function() self:open_pack_manager() end,
            },
            {
                text = _("AI settings"),
                sub_item_table = {
                    { text = _("Phone or computer browser (recommended)"), callback = function() self:open_browser_import("ai") end },
                    { text = _("Computer converter over Wi-Fi"), callback = function() self:open_ai_share_import() end },
                    { text = _("Type it on the Kindle"), callback = function() self:open_ai_settings() end },
                    { text = _("Clean AI storage"), callback = function() self:clean_ai_storage() end },
                },
            },
            {
                -- Bilingual on purpose: a reader who cannot read the
                -- current language still has to find the switch.
                text = "Language / 语言",
                sub_item_table = {
                    self:language_menu_item("zh_CN", "简体中文"),
                    self:language_menu_item("en", "English"),
                },
            },
        },
    }
end

function KindleAnki:language_menu_item(locale, label)
    return {
        text = label,
        radio = true,
        checked_func = function()
            return self.settings:readSetting("locale", "zh_CN") == locale
        end,
        callback = function()
            self.settings:saveSetting("locale", locale):flush()
            I18N.set_locale(locale)
            UIManager:show(InfoMessage:new{
                text = _("Language changed. Menus already open update after you reopen them."),
            })
        end,
    }
end

function KindleAnki:open_ai_share_import()
    close_widget(self.library_dialog)
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Import AI settings from computer"),
        fields = {
            { text = self.store:computer_host(), hint = "192.168.x.x", description = _("Computer IP (converter open)") },
            { text = "", hint = "1234", description = _("Pairing code shown in the converter") },
        },
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() close_widget(dialog) end },
            { text = _("Import"), is_enter_default = true, callback = function()
                local fields = dialog:getFields()
                local host = fields[1] or ""
                local code = fields[2] or ""
                close_widget(dialog)
                self.store:set_computer_host(host)
                self:fetch_ai_settings(host, code)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function KindleAnki:fetch_ai_settings(host, code)
    UIManager:show(InfoMessage:new{text = _("Fetching AI settings…"), timeout = 2})
    local payload, err = self.store:fetch_ai_settings(host, code)
    if not payload then
        UIManager:show(InfoMessage:new{
            text = string.format(_("Could not import AI settings: %s"), tostring(err)),
        })
        return
    end
    local key = tostring(payload.api_key or "")
    local masked = key ~= "" and (string.rep("•", math.max(#key - 4, 0)) .. key:sub(-4)) or _("(empty)")
    local summary = string.format(
        "%s\n%s\n%s",
        "endpoint: " .. tostring(payload.endpoint or ""),
        "model: " .. tostring(payload.model or ""),
        "key: " .. masked
    )
    UIManager:show(ConfirmBox:new{
        text = summary,
        ok_text = _("Save"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            local saved = self.settings:readSetting("ai", {})
            if type(saved) ~= "table" then saved = {} end
            -- Only overwrite fields the computer actually filled in.
            for field, value in pairs{endpoint = payload.endpoint, model = payload.model,
                api_key = payload.api_key, system_prompt = payload.system_prompt} do
                if type(value) == "string" and value ~= "" then saved[field] = value end
            end
            self.settings:saveSetting("ai", saved):flush()
            self.ai_history = {}
            UIManager:show(InfoMessage:new{text = _("AI settings saved locally")})
        end,
    })
end

-- Right-hand label for a pack or deck row: what studying it now would hold.
local function today_label(summary)
    if summary.daily_new == nil then
        return string.format(_("%d cards"), summary.total)
    end
    if summary.today > 0 then
        return string.format(_("%d to study"), summary.today)
    end
    return _("Done today")
end

-- Full-screen list in KOReader's own file-browser style. `back` puts a
-- back arrow in the title bar; `actions` puts the menu icon there instead.
function KindleAnki:show_list(key, options)
    close_widget(self[key])
    local menu
    menu = Menu:new{
        title = options.title,
        subtitle = options.subtitle,
        item_table = options.items,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        title_bar_fm_style = true,
        title_bar_left_icon = options.back and "chevron.left" or (options.actions and "appbar.menu") or nil,
        onLeftButtonTap = function()
            if options.back then
                close_widget(menu)
                options.back()
            elseif options.actions then
                options.actions()
            end
        end,
        -- Menu calls this after every selection as well as on close.
        close_callback = function() close_widget(menu) end,
    }
    self[key] = menu
    UIManager:show(menu)
end

function KindleAnki:open_library()
    self.packs = self.store:list()
    local items = {}
    for _, pack in ipairs(self.packs) do
        local current_pack = pack
        local summary = self.store:pack_summary(current_pack)
        table.insert(items, {
            text = current_pack.title,
            mandatory = today_label(summary),
            dim = summary.daily_new ~= nil and summary.today == 0,
            callback = function() self:open_decks(current_pack) end,
        })
    end
    if #items == 0 then
        table.insert(items, {
            text = _("No packs yet. Tap here to import one."),
            callback = function() self:open_import_hub() end,
        })
    end
    self:show_list("library_dialog", {
        title = _("Kindle Anki"),
        subtitle = #self.packs > 0 and _("Tap a pack to study. The menu icon has import, manage, and AI.") or nil,
        items = items,
        actions = function() self:open_library_actions() end,
    })
end

function KindleAnki:open_library_actions()
    local dialog
    local function run(action)
        return function()
            close_widget(dialog)
            close_widget(self.library_dialog)
            action()
        end
    end
    dialog = ButtonDialog:new{
        buttons = {
            {{ text = _("Import packs"), align = "left", callback = run(function() self:open_import_hub() end) }},
            {{ text = _("Manage packs"), align = "left", callback = run(function() self:open_pack_manager() end) }},
            {{ text = _("AI settings"), align = "left", callback = run(function() self:open_ai_hub() end) }},
            {{ text = _("Clean AI storage"), align = "left", callback = function()
                close_widget(dialog)
                self:clean_ai_storage()
            end }},
        },
        shrink_unneeded_width = true,
    }
    UIManager:show(dialog)
end

function KindleAnki:open_import_hub()
    local dialog
    local function run(action)
        return function()
            close_widget(dialog)
            action()
        end
    end
    dialog = ButtonDialog:new{
        title = _("Import packs"),
        buttons = {
            {{ text = _("Phone or computer browser (recommended)"), align = "left",
               callback = run(function() self:open_browser_import() end) }},
            {{ text = _("Computer converter over Wi-Fi"), align = "left",
               callback = run(function() self:import_from_computer() end) }},
            {{ text = _("A file already on this Kindle"), align = "left",
               callback = run(function() self:import_pack() end) }},
            {{ text = _("Cancel"), callback = function() close_widget(dialog) end }},
        },
    }
    UIManager:show(dialog)
end

function KindleAnki:open_ai_hub()
    local dialog
    local function run(action)
        return function()
            close_widget(dialog)
            action()
        end
    end
    dialog = ButtonDialog:new{
        title = _("AI settings"),
        buttons = {
            {{ text = _("Phone or computer browser (recommended)"), align = "left",
               callback = run(function() self:open_browser_import("ai") end) }},
            {{ text = _("Computer converter over Wi-Fi"), align = "left",
               callback = run(function() self:open_ai_share_import() end) }},
            {{ text = _("Type it on the Kindle"), align = "left",
               callback = run(function() self:open_ai_settings() end) }},
            {{ text = _("Cancel"), callback = function() close_widget(dialog) end }},
        },
    }
    UIManager:show(dialog)
end

function KindleAnki:clean_ai_storage()
    local removed, total = self.store:cleanup_ai_space()
    UIManager:show(InfoMessage:new{
        text = string.format(_("Removed %d old AI chats. About %d KB remain."),
            removed, math.floor(total / 1024))
    })
end

function KindleAnki:open_pack_manager()
    self.packs = self.store:list()
    if #self.packs == 0 then
        UIManager:show(InfoMessage:new{text = _("No packs to manage.")})
        self:open_library()
        return
    end
    local items = {}
    -- Not `for _, pack`: that would shadow the translation function `_`.
    for _index, pack in ipairs(self.packs) do
        local current_pack = pack
        table.insert(items, {
            text = current_pack.title,
            mandatory = _("Delete"),
            callback = function()
                self:confirm_delete_pack(current_pack, function() self:open_pack_manager() end)
            end,
        })
    end
    self:show_list("manage_dialog", {
        title = _("Manage packs"),
        subtitle = _("Tap a pack to delete it with its progress and AI chats."),
        items = items,
        back = function() self:open_library() end,
    })
end

function KindleAnki:confirm_delete_pack(pack, after)
    UIManager:show(ConfirmBox:new{
        text = string.format(
            _("Delete %s? Study progress and AI chats for this pack will be removed."),
            pack.title or _("this pack")
        ),
        ok_text = _("Delete"),
        ok_callback = function()
            local ok, err = self.store:delete_pack(pack)
            if not ok then
                UIManager:show(InfoMessage:new{
                    text = string.format(_("Could not delete pack: %s"), tostring(err)),
                })
            else
                UIManager:show(InfoMessage:new{
                    text = string.format(_("Deleted %s"), pack.title or _("this pack")),
                })
            end
            if after then after() end
        end,
        cancel_callback = function()
            if after then after() end
        end,
    })
end

local function generate_pairing_code()
    -- Four digits are only safe because the server locks after a few wrong
    -- tries (WebServer.MAX_AI_ATTEMPTS); the code itself must not be
    -- predictable, so prefer the kernel RNG over a clock seed.
    local urandom = io.open("/dev/urandom", "rb")
    if urandom then
        local bytes = urandom:read(4)
        urandom:close()
        if bytes and #bytes == 4 then
            local b1, b2, b3, b4 = bytes:byte(1, 4)
            return string.format("%04d", (((b1 * 256 + b2) * 256 + b3) * 256 + b4) % 10000)
        end
    end
    math.randomseed(os.time() * 1000 + math.floor((os.clock() % 1) * 1000))
    return string.format("%04d", math.random(0, 9999))
end

function KindleAnki:attach_webserver(server)
    server.store = self.store
    server.on_result = function(result) self:on_web_import_result(result) end
    server.on_ai_settings = function(payload) return self:on_web_ai_settings(payload) end
    server.ai_configured = function()
        local config = self:ai_config()
        return config.endpoint ~= "" or config.api_key ~= ""
    end
    server.on_delete_pack = function(pack) return self:on_web_delete_pack(pack) end
    server.on_idle_stop = function()
        if WebServer.active == server then WebServer.active = nil end
        UIManager:show(InfoMessage:new{text = _("Import page closed after 30 minutes without visits.")})
    end
end

-- `focus` is "ai" when opened from AI settings: same page, its AI tab.
function KindleAnki:open_browser_import(focus)
    close_widget(self.library_dialog)
    if WebServer.active and WebServer.active:is_running() then
        self:attach_webserver(WebServer.active)
        self:show_browser_import_dialog(focus)
        return
    end
    local function work()
        local server = WebServer:new{
            store = self.store,
            port = tonumber(self.settings:readSetting("web_port", WebServer.DEFAULT_PORT)) or WebServer.DEFAULT_PORT,
            upload_path = self.store:pack_dir() .. "/.upload.kindle-anki.zip",
            ai_code = generate_pairing_code(),
        }
        self:attach_webserver(server)
        local ok, err = server:start()
        if not ok then
            UIManager:show(InfoMessage:new{
                text = string.format(_("Could not open the import page: %s"), tostring(err)),
            })
            return
        end
        WebServer.active = server
        self:show_browser_import_dialog(focus)
    end
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if ok and NetworkMgr and NetworkMgr.runWhenOnline then
        NetworkMgr:runWhenOnline(work)
    else
        work()
    end
end

function KindleAnki:show_browser_import_dialog(focus)
    local url = WebServer.active:url()
    local code = WebServer.active.ai_code or ""
    local has_ip = not url:find("<kindle-ip>", 1, true)
    local for_ai = focus == "ai"
    local function stop()
        if WebServer.active then
            WebServer.active:stop()
            WebServer.active = nil
        end
        UIManager:show(InfoMessage:new{text = _("Import page closed.")})
    end
    local wifi_note = has_ip and _("Phone and Kindle must be on the same Wi-Fi. If you scan with WeChat, tap ··· at the top right and open the page in your browser; choosing files works better there.")
        or _("No Wi-Fi address found. Check that the Kindle is connected to Wi-Fi, then open this page again.")
    local code_note = string.format(_("Pairing code (for AI settings): %s"), code)
    local notes
    if for_ai then
        notes = { code_note, _("Fill in the page's AI tab and enter this code. The key is saved on this Kindle only."), wifi_note }
    else
        notes = { wifi_note, code_note }
    end
    table.insert(notes, _("The page keeps working until you tap Stop here, quit KOReader, or nobody visits it for 30 minutes. You can leave this screen and come back later."))
    local title = for_ai and _("Set up AI from a phone or computer") or _("Import via browser")
    local ok, dialog = pcall(function()
        local ImportDialog = require("importdialog")
        return ImportDialog:new{
            title = title,
            lead = _("Scan with your phone camera, or type this address in a browser:"),
            url = url,
            -- The page opens its AI tab for #ai.
            qr_text = for_ai and (url .. "#ai") or url,
            show_qr = has_ip,
            notes = notes,
            keep_text = _("Keep it running"),
            stop_text = _("Stop now"),
            on_stop = stop,
        }
    end)
    if ok and dialog then
        UIManager:show(dialog)
        return
    end
    -- Some KOReader build lacks a widget the QR screen uses: plain text.
    UIManager:show(ConfirmBox:new{
        title = title,
        text = _("Open this address in your phone or computer browser (same Wi-Fi):")
            .. "\n\n" .. url .. "\n\n"
            .. (for_ai and "" or (_("Pick the .apkg in the page, convert it there, and it lands on this Kindle.") .. "\n\n"))
            .. table.concat(notes, "\n\n"),
        ok_text = _("Keep it running"),
        cancel_text = _("Stop now"),
        ok_callback = function() end,
        cancel_callback = stop,
    })
end

function KindleAnki:on_web_ai_settings(payload)
    if type(payload) ~= "table" then
        return { ok = false, error = "missing settings" }
    end
    local incoming = {}
    for _, field in ipairs({ "endpoint", "model", "api_key", "system_prompt" }) do
        local value = payload[field]
        if type(value) == "string" and value ~= "" then incoming[field] = value end
    end
    if incoming.endpoint and not incoming.endpoint:match("^https?://") then
        return { ok = false, error = _("AI endpoint must be an http:// or https:// URL") }
    end
    if next(incoming) == nil then
        return { ok = false, error = "nothing to save; fill at least one field" }
    end
    local saved = self.settings:readSetting("ai", {})
    if type(saved) ~= "table" then saved = {} end
    -- Same merge rule as the computer flow: only fields the sender actually
    -- filled in are overwritten; the key is stored on the Kindle only.
    for field, value in pairs(incoming) do saved[field] = value end
    self.settings:saveSetting("ai", saved):flush()
    local key = incoming.api_key or ""
    local masked = key ~= ""
        and (string.rep("•", math.max(#key - 4, 0)) .. key:sub(-4)) or ""
    UIManager:show(InfoMessage:new{text = _("AI settings saved locally")})
    return {
        ok = true,
        endpoint = incoming.endpoint or "",
        model = incoming.model or "",
        key_masked = masked,
    }
end

function KindleAnki:on_web_delete_pack(pack)
    -- Deletion itself is the store's job; its guards only ever touch packs
    -- inside the library folders and clean progress and AI chats with them.
    local ok, err = self.store:delete_pack(pack)
    if not ok then
        UIManager:show(InfoMessage:new{
            text = string.format(_("Could not delete pack: %s"), tostring(err)),
        })
        return { ok = false, error = tostring(err or "could not delete pack") }
    end
    UIManager:show(InfoMessage:new{
        text = string.format(_("Deleted %s"), pack.title or _("this pack")),
    })
    return { ok = true, title = tostring(pack.title or "") }
end

local function imported_message(title, existing)
    if existing then
        return string.format(_("%s is already on this Kindle and was not replaced. Delete it first to import a new version."), title)
    end
    return string.format(_("Imported %s"), title)
end

function KindleAnki:on_web_import_result(result)
    if result.ok and result.existing then
        UIManager:show(InfoMessage:new{text = imported_message(tostring(result.title or ""), true)})
    elseif result.ok then
        UIManager:show(InfoMessage:new{
            text = string.format(_("Imported %s"), tostring(result.title or "")),
        })
    else
        UIManager:show(InfoMessage:new{
            text = string.format(_("Could not import pack: %s"), tostring(result.error or "")),
        })
    end
end

function KindleAnki:import_from_computer()
    close_widget(self.library_dialog)
    local dialog
    dialog = InputDialog:new{
        title = _("Computer IP"),
        description = _("Open the converter on your computer first. Enter the IP shown in that window. Same Wi-Fi, no USB."),
        input = self.store:computer_host(),
        input_hint = "192.168.x.x",
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function()
                close_widget(dialog)
                self:open_library()
            end },
            { text = _("Look up packs"), is_enter_default = true, callback = function()
                local host = dialog:getInputText()
                close_widget(dialog)
                self.store:set_computer_host(host)
                self:fetch_computer_packs(host)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function KindleAnki:fetch_computer_packs(host)
    local function work()
        local packs, err = self.store:list_computer_packs(host)
        if not packs then
            UIManager:show(InfoMessage:new{
                text = string.format(_("Could not reach computer: %s"), tostring(err)),
            })
            self:open_library()
            return
        end
        if #packs == 0 then
            UIManager:show(InfoMessage:new{text = _("No packs on the computer. Convert a deck first.")})
            self:open_library()
            return
        end
        local buttons = {}
        for index, item in ipairs(packs) do
            local name = item.name or tostring(index)
            local pack_id = tonumber(item.id)
            if pack_id == nil then pack_id = index - 1 end
            local display = name:gsub("%.kindle%-anki%.zip$", "")
            table.insert(buttons, {{
                text = display,
                align = "left",
                callback = function()
                    close_widget(self.computer_dialog)
                    self:download_computer_pack(host, name, pack_id)
                end,
            }})
        end
        table.insert(buttons, {{
            text = _("Back"),
            callback = function()
                close_widget(self.computer_dialog)
                self:open_library()
            end,
        }})
        self.computer_dialog = ButtonDialog:new{
            title = _("Import from computer"),
            buttons = buttons,
            rows_per_page = 8,
        }
        UIManager:show(self.computer_dialog)
    end
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if ok and NetworkMgr and NetworkMgr.runWhenOnline then
        NetworkMgr:runWhenOnline(work)
    else
        work()
    end
end

function KindleAnki:download_computer_pack(host, name, pack_id)
    UIManager:show(InfoMessage:new{text = _("Downloading pack…"), timeout = 2})
    local pack, err, existing = self.store:import_from_computer(host, name, nil, pack_id)
    if not pack then
        UIManager:show(InfoMessage:new{
            text = string.format(_("Could not import pack: %s"), tostring(err)),
        })
        self:open_library()
        return
    end
    UIManager:show(InfoMessage:new{
        text = imported_message(pack.title or name, existing),
    })
    self:open_library()
end

function KindleAnki:import_pack()
    close_widget(self.library_dialog)
    local ok, PathChooser = pcall(require, "ui/widget/pathchooser")
    if not ok then
        UIManager:show(InfoMessage:new{
            text = _("This KOReader build has no file picker. Copy the pack to /mnt/us/kindle-anki/packs/. The legacy folder /mnt/us/folo-anki/ still works."),
        })
        return
    end
    UIManager:show(PathChooser:new{
        title = _("Import pack"),
        path = "/mnt/us",
        select_file = true,
        select_directory = false,
        file_filter = function(filename)
            filename = tostring(filename or ""):lower()
            return filename:match("%.kindle%-anki%.json$")
                or filename:match("%.folo%-kindle%.json$")
                or filename:match("%.kindle%-anki%.zip$")
                or filename:match("%.folo%-kindle%.zip$")
                or filename:match("%.zip$")
        end,
        onConfirm = function(file_path)
            local pack, err, existing = self.store:import_from_path(file_path)
            if not pack then
                UIManager:show(InfoMessage:new{
                    text = string.format(_("Could not import pack: %s"), tostring(err)),
                })
                self:open_library()
                return
            end
            UIManager:show(InfoMessage:new{
                text = imported_message(pack.title or file_path, existing),
            })
            self:open_library()
        end,
    })
end

function KindleAnki:open_decks(pack)
    self.pack = pack
    -- One deck: its pack screen would be a list of one, so skip it.
    if #pack.decks == 1 then
        self.single_deck = true
        self:open_deck_actions(pack.decks[1])
        return
    end
    self.single_deck = false
    local items = {}
    for _, deck in ipairs(pack.decks) do
        local current_deck = deck
        local summary = self.store:deck_summary(pack, current_deck)
        table.insert(items, {
            text = display_deck_name(current_deck),
            mandatory = today_label(summary),
            dim = summary.daily_new ~= nil and summary.today == 0,
            callback = function() self:open_deck_actions(current_deck) end,
        })
    end
    local summary = self.store:pack_summary(pack)
    self:show_list("deck_dialog", {
        title = pack.title,
        subtitle = summary.daily_new and string.format(_("Today: %d reviews, %d new"), summary.due, summary.new_today)
            or string.format(_("%d cards, not started"), summary.total),
        items = items,
        back = function() self:open_library() end,
    })
end

function KindleAnki:open_deck_actions(deck)
    self.deck = deck
    close_widget(self.deck_action_dialog)
    if not self.store:daily_new_for(self.pack) then
        self:ask_daily_new(deck, false)
        return
    end
    local summary = self.store:deck_summary(self.pack, deck)
    local function go(action)
        return function()
            close_widget(self.deck_action_dialog)
            action()
        end
    end
    local study_button
    if summary.today > 0 then
        study_button = { text = string.format("%s (%d)", _("Start studying"), summary.today),
            callback = go(function() self:begin_session(deck, "study") end) }
    else
        study_button = { text = _("Done for today. Study more"),
            callback = go(function() self:ask_extra_count(deck) end) }
    end
    local buttons = {
        { study_button },
        {
            { text = string.format("%s (%d)", _("Retry missed"), summary.missed), enabled = summary.missed > 0,
              callback = go(function() self:begin_session(deck, "errors") end) },
            { text = string.format("%s (%d)", _("Starred cards"), summary.starred), enabled = summary.starred > 0,
              callback = go(function() self:begin_session(deck, "starred") end) },
        },
        {
            { text = string.format("%s (%d)", _("Browse cards"), summary.total),
              callback = go(function() self:begin_session(deck, "browse") end) },
            { text = string.format(_("Cards per day (%d)"), summary.daily_new),
              callback = go(function() self:ask_daily_new(deck, true) end) },
        },
        {
            { text = _("Back"), callback = go(function() self:leave_deck() end) },
        },
    }
    self.deck_action_dialog = ButtonDialog:new{
        title = display_deck_name(deck) .. "\n"
            .. string.format(_("Today: %d reviews, %d new"), summary.due, summary.new_today) .. "\n"
            .. string.format(_("%d cards, %d not started yet"), summary.total, summary.new),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.deck_action_dialog)
end

-- Where "back" from a deck goes: the pack's deck list, or the library when
-- the pack has a single deck and its list was skipped.
function KindleAnki:leave_deck()
    self.store:flush_progress()
    if self.single_deck or not self.pack then
        self:open_library()
    else
        self:open_decks(self.pack)
    end
end

function KindleAnki:ask_count(title, description, default_value, confirm_label, on_ok, on_cancel)
    local dialog
    dialog = InputDialog:new{
        title = title,
        description = description,
        input = tostring(default_value or Store.DEFAULT_DAILY_NEW),
        input_hint = "1-999",
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function()
                close_widget(dialog)
                if on_cancel then on_cancel() end
            end },
            { text = confirm_label or _("Save"), is_enter_default = true, callback = function()
                local count = Store.clamp_count(dialog:getInputText())
                if not count then
                    UIManager:show(InfoMessage:new{text = _("Enter a number from 1 to 999.")})
                    return
                end
                close_widget(dialog)
                on_ok(count)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function KindleAnki:ask_daily_new(deck, changing)
    local current = self.store:daily_new_for(self.pack) or Store.DEFAULT_DAILY_NEW
    self:ask_count(
        _("How many cards per day?"),
        _("This number applies every day until you change it."),
        current,
        _("Save"),
        function(count)
            self.store:set_daily_new(self.pack, count)
            self:open_deck_actions(deck)
        end,
        function()
            if changing or self.store:daily_new_for(self.pack) then
                self:open_deck_actions(deck)
            else
                self:leave_deck()
            end
        end
    )
end

function KindleAnki:ask_extra_count(deck)
    self:ask_count(
        _("How many more cards today?"),
        _("Only for today. Tomorrow still uses your daily number."),
        10,
        _("Start studying"),
        function(count)
            self:begin_session(deck, "extra", count)
        end,
        function()
            self:open_deck_actions(deck)
        end
    )
end

function KindleAnki:start_studying(deck)
    local cards = self.store:build_session(self.pack, deck, "study")
    if #cards > 0 then
        self:begin_session(deck, "study")
        return
    end
    self:ask_extra_count(deck)
end

function KindleAnki:begin_session(deck, mode, extra_count)
    self.deck = deck
    self.session_mode = mode or "study"
    self.cards, self.session_meta = self.store:build_session(self.pack, deck, self.session_mode, extra_count)
    self.card_position = 1
    self.selected = {}
    self.ai_history = {}
    self.session_tally = { again = 0, hard = 0, good = 0, easy = 0 }
    if #self.cards == 0 then
        local message = self.session_mode == "extra" and _("No more cards left to study.")
            or self.session_mode == "starred" and _("No starred cards in this deck.")
            or self.session_mode == "errors" and _("No missed cards to retry.")
            or _("No cards available for this mode.")
        UIManager:show(InfoMessage:new{text = message})
        self:open_deck_actions(deck)
        return
    end
    self:show_card()
end

function KindleAnki:begin_deck(deck)
    self:start_studying(deck)
end

function KindleAnki:card_progress()
    return string.format(_("Card %d / %d"), self.card_position, #self.cards)
end

-- Title bar of the card screens: where you are, and how far along.
function KindleAnki:card_title()
    return string.format("%s    %d / %d", study_title(self.pack, self.deck), self.card_position, #self.cards)
end

function KindleAnki:exit_session()
    close_widget(self.card_view)
    self.store:flush_progress()
    self:open_deck_actions(self.deck)
end

local IMAGE_MAX_WIDTH_RATIO = 0.90
local IMAGE_MAX_HEIGHT_RATIO = 0.50

local function html_escape(value)
    return util.htmlEscape(tostring(value or "")):gsub("\n", "<br/>")
end

local function html_attribute(value)
    -- util.htmlEscape also encodes '/', which KOReader's MuPDF resource
    -- loader may keep literally when it resolves an image src. Only encode
    -- characters that are meaningful inside a quoted HTML attribute here.
    return tostring(value or "")
        :gsub("&", "&amp;")
        :gsub('"', "&quot;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
end

local function image_reference_size(reference)
    if type(reference) ~= "table" then return 600, 400 end
    return tonumber(reference.width) or 600, tonumber(reference.height) or 400
end

local function image_display_size(width, height)
    width = math.max(1, tonumber(width) or 1)
    height = math.max(1, tonumber(height) or 1)
    local page_width = math.max(1, Screen:getWidth() - Screen:scaleBySize(48))
    local page_height = math.max(1, Screen:getHeight() - Screen:scaleBySize(120))
    local max_width = math.max(1, math.floor(page_width * IMAGE_MAX_WIDTH_RATIO))
    local max_height = math.max(1, math.floor(page_height * IMAGE_MAX_HEIGHT_RATIO))
    -- Fit inside both caps and keep the smaller result so a tall image is
    -- limited by height and a wide image is limited by width.
    local scale = math.min(max_width / width, max_height / height)
    return math.max(1, math.floor(width * scale)), math.max(1, math.floor(height * scale))
end

function KindleAnki:card_image_html(card, fields)
    local images = {}
    local media_dir = self.pack and self.pack.media_dir
    if type(media_dir) ~= "string" then return "" end
    for _, field in ipairs(fields or { "front_images" }) do
        for _, reference in ipairs(card[field] or {}) do
            local name = type(reference) == "table" and reference.name or reference
            local width, height = image_reference_size(reference)
            if type(name) == "string" and name ~= "" then
                local display_width, display_height = image_display_size(width, height)
                -- TextViewer gives MuPDF the pack directory as its resource
                -- root through `file`; use the same relative form as
                -- KOReader's own HTML image pages.
                local source = media_dir .. "/" .. name
                table.insert(images, string.format(
                    '<div style="text-align:center;margin-top:8px;margin-bottom:12px">'
                        .. '<img src="%s" width="%d" height="%d" '
                        .. 'style="display:block;margin-left:auto;margin-right:auto;width:%dpx;height:%dpx" alt="%s"/></div>',
                    html_attribute(source), display_width, display_height,
                    display_width, display_height, html_attribute(name)
                ))
            end
        end
    end
    return table.concat(images, "\n")
end

local function html_wants_field(fields, name)
    if not fields then return false end
    for _, field in ipairs(fields) do
        if field == name then return true end
    end
    return false
end

-- Text blocks shared by the HTML card body and the plain-text fallback.
-- The card body as role-tagged blocks, shared by the HTML view and the
-- plain-text fallback. Roles: "status" (how the answer went), "muted" (the
-- question, repeated above the answer), "main" (what to read now),
-- "options", and "rule" (the line between question and answer).
function KindleAnki:card_text_blocks(card, prefix, include_back)
    local blocks = {}
    if prefix and prefix ~= "" then table.insert(blocks, { role = "status", text = prefix }) end
    local options
    if card.type == "choice" then
        local lines = {}
        for index, option in ipairs(card.options) do
            table.insert(lines, string.format("%s. %s", option_letter(index), option))
        end
        options = table.concat(lines, "\n")
    end
    if include_back then
        table.insert(blocks, { role = "muted", text = tostring(card.front or "") })
        if options then table.insert(blocks, { role = "muted", text = options }) end
        table.insert(blocks, { role = "rule", text = "" })
        table.insert(blocks, { role = "main", text = tostring(card.back or "") })
        return blocks
    end
    table.insert(blocks, { role = "main", text = tostring(card.front or "") })
    if options then table.insert(blocks, { role = "options", text = options }) end
    return blocks
end

local BLOCK_STYLES = {
    status = "margin-bottom:0.9em;font-weight:bold",
    muted = "margin-bottom:0.6em;font-size:0.9em;color:#555555",
    main = "margin-bottom:0.8em;font-size:1.3em;line-height:1.45",
    options = "margin-bottom:0.8em;line-height:1.6",
}

local function plain_card_text(blocks)
    local parts = {}
    for _, block in ipairs(blocks) do
        table.insert(parts, block.role == "rule" and "────────" or block.text)
    end
    return table.concat(parts, "\n\n")
end

function KindleAnki:card_html(card, fields, prefix, include_back)
    local blocks = {}
    for _, block in ipairs(self:card_text_blocks(card, prefix, include_back)) do
        if block.role == "rule" then
            table.insert(blocks, '<div style="border-top:1px solid #888888;margin:0.4em 0 0.9em 0"></div>')
        else
            table.insert(blocks, string.format('<div style="%s">%s</div>',
                BLOCK_STYLES[block.role], html_escape(block.text)))
        end
    end
    if include_back then
        if html_wants_field(fields, "back_images") then
            local back_images = self:card_image_html(card, { "back_images" })
            if back_images ~= "" then table.insert(blocks, back_images) end
        end
        return table.concat(blocks, "\n")
    end
    if html_wants_field(fields, "front_images") then
        local front_images = self:card_image_html(card, { "front_images" })
        if front_images ~= "" then table.insert(blocks, front_images) end
    end
    return table.concat(blocks, "\n")
end

function KindleAnki:card_html_viewer_options(card, fields, prefix, include_back)
    if not textviewer_renders_html() then
        return { text = plain_card_text(self:card_text_blocks(card, prefix, include_back)) }
    end
    return {
        text_format = "html",
        file = self.pack._path .. ".kindle-card.html",
        text = self:card_html(card, fields, prefix, include_back),
    }
end

-- Old KOReader cannot place images inside the card text, so offer them
-- in ImageViewer from a button. Returns nil when there is nothing to add.
function KindleAnki:card_images_button(card, field)
    if textviewer_renders_html() then return nil end
    local paths = self:card_image_paths(card, { field })
    if #paths == 0 then return nil end
    return {{
        text = string.format(_("View images (%d)"), #paths),
        callback = function() self:show_card_images(paths) end,
    }}
end

function KindleAnki:show_card_images(paths)
    local lfs = require("libs/libkoreader-lfs")
    local existing = {}
    for _, path in ipairs(paths) do
        if lfs.attributes(path, "mode") == "file" then table.insert(existing, path) end
    end
    if #existing == 0 then
        UIManager:show(InfoMessage:new{text = _("Image files are missing from this pack.")})
        return
    end
    local ImageViewer = require("ui/widget/imageviewer")
    if #existing == 1 then
        UIManager:show(ImageViewer:new{ file = existing[1], fullscreen = true })
        return
    end
    local RenderImage = require("ui/renderimage")
    local images = { image_disposable = true }
    for index, path in ipairs(existing) do
        images[index] = function() return RenderImage:renderImageFile(path, false) end
    end
    UIManager:show(ImageViewer:new{ image = images, fullscreen = true })
end

function KindleAnki:card_image_paths(card, fields)
    local paths = {}
    local seen = {}
    local media_dir = self.pack and self.pack.media_dir
    if type(media_dir) ~= "string" then return paths end
    local base = pack_directory(self.pack) .. "/" .. media_dir
    for _, field in ipairs(fields or { "front_images", "back_images" }) do
        for _, reference in ipairs(card[field] or {}) do
            local name = type(reference) == "table" and reference.name or reference
            if type(name) == "string" and name ~= "" and name ~= "." and name ~= ".."
                    and not name:match("[/\\\\]") then
                local path = base .. "/" .. name
                if not seen[path] then
                    seen[path] = true
                    table.insert(paths, path)
                end
            end
        end
    end
    return paths
end

function KindleAnki:show_card()
    close_widget(self.card_view)
    local card = self.cards[self.card_position]
    if not card then
        UIManager:show(InfoMessage:new{text = _("Deck complete")})
        return
    end
    self.selected = self.selected or {}
    local buttons = {}
    -- Secondary actions share one row under the main one.
    local secondary = {
        { text = _("AI explain"), callback = function() self:open_ai_question(card, false) end },
        { text = _("Exit deck"), callback = function() self:exit_session() end },
    }
    if card.type == "choice" then
        for index, option in ipairs(card.options) do
            local option_index = index
            table.insert(buttons, {{
                text = option_label(option_index, option, self.selected[option_index]),
                align = "left",
                callback = function()
                    if card.mode == "single" then
                        self:show_answer({ [option_index] = true })
                    else
                        self.selected[option_index] = not self.selected[option_index] or nil
                        self:show_card()
                    end
                end,
            }})
        end
        if card.mode == "multiple" then
            table.insert(buttons, {{
                text = _("Check my choices"),
                callback = function() self:show_answer(self.selected) end,
            }})
        end
    elseif card.type == "short_answer" then
        table.insert(buttons, {{
            text = _("Show back"),
            callback = function() self:show_answer(nil, nil) end,
        }})
        table.insert(secondary, 1, {
            text = _("Type answer"),
            callback = function() self:open_typing_dialog(card) end,
        })
    end
    local images_button = self:card_images_button(card, "front_images")
    if images_button then table.insert(secondary, 1, images_button[1]) end
    table.insert(buttons, secondary)
    local viewer_options = self:card_html_viewer_options(card, { "front_images", "back_images" })
    self.card_view = TextViewer:new{
        title = self:card_title(),
        text = viewer_options.text,
        text_format = viewer_options.text_format,
        file = viewer_options.file,
        show_menu = false,
        buttons_table = buttons,
        text_type = "general",
    }
    UIManager:show(self.card_view)
end

function KindleAnki:open_typing_dialog(card)
    local dialog
    dialog = InputDialog:new{
        title = _("Type your answer"),
        description = card.front,
        input = "",
        allow_newline = true,
        fullscreen = true,
        condensed = true,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() close_widget(dialog) end },
            { text = _("Show back"), is_enter_default = true, callback = function()
                local typed = dialog:getInputText()
                close_widget(dialog)
                self:show_answer(nil, typed)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function selected_labels(selected)
    local labels = {}
    if type(selected) ~= "table" then
        return _("none")
    end
    -- Option buttons are 1-based (1=A). A list like {2} means B; a set like
    -- { [2]=true } also means B. Do not treat the list key 1 as option A.
    local is_index_list = selected[1] ~= nil and selected[1] ~= true
    if is_index_list then
        for _, index in ipairs(selected) do
            local number = tonumber(index)
            if number and number >= 1 then table.insert(labels, option_letter(number)) end
        end
    else
        for index, is_selected in pairs(selected) do
            if is_selected then table.insert(labels, option_letter(index)) end
        end
    end
    table.sort(labels)
    return #labels > 0 and table.concat(labels, ", ") or _("none")
end

local function normalized_answer(value)
    return tostring(value or ""):lower():gsub("%s+", "")
end

function KindleAnki:show_answer(selected, typed)
    close_widget(self.card_view)
    local card = self.cards[self.card_position]
    if not card then return end
    local prefix = ""
    if typed ~= nil then
        local answer_status = ""
        if card.type == "short_answer" and card.expected_answers and #card.expected_answers > 0 then
            local matches = false
            for _, expected in ipairs(card.expected_answers) do
                if normalized_answer(expected) == normalized_answer(typed) then matches = true end
            end
            answer_status = matches and "\n" .. _("Match: correct")
                or "\n" .. _("Match: check the back")
        end
        prefix = _("Your answer:") .. "\n" .. typed .. answer_status
    end
    if card.type == "choice" then
        local chosen = selected_labels(selected)
        local correct = {}
        for _, index in ipairs(card.correct_indices) do table.insert(correct, option_letter(index + 1)) end
        table.sort(correct)
        local correct_text = table.concat(correct, ", ")
        prefix = (chosen == correct_text and _("Correct") or _("Not quite")) .. "\n"
            .. _("Your choice: ") .. chosen .. "\n" .. _("Correct: ") .. correct_text
    end
    local state = self.store:card_state(self.pack, card)
    local Schedule = self.store.Schedule
    local function rating_label(name, rating)
        if self.session_mode == "browse" then return _(name) end
        if rating == "again" then
            return string.format("%s · %s", _(name), _("10 min"))
        end
        local days = Schedule.preview_days(state.interval, rating)
        if days == 0 then
            return string.format("%s · %s", _(name), _("today"))
        end
        return string.format("%s · %s", _(name), string.format(_("%d days"), days))
    end
    local function rate(rating)
        return function() self:rate_and_next(rating) end
    end
    local starred = self.store:is_starred(self.pack, card)
    local tools = {
        { text = _("AI explain"), callback = function() self:open_ai_question(card, true) end },
        { text = starred and _("Unstar") or _("Star"), callback = function()
            self.store:toggle_star(self.pack, card)
            self:show_answer(selected, typed)
        end },
    }
    local images_button = self:card_images_button(card, "back_images")
    if images_button then table.insert(tools, images_button[1]) end
    local ratings = {
        { text = rating_label("Again", "again"), callback = rate("again") },
        { text = rating_label("Hard", "hard"), callback = rate("hard") },
        { text = rating_label("Good", "good"), callback = rate("good") },
        { text = rating_label("Easy", "easy"), callback = rate("easy") },
    }
    local buttons
    if self.session_mode == "browse" and not self._browse_rate_unlocked then
        -- Browsing does not touch the schedule unless asked to.
        table.insert(tools, { text = _("Rate anyway"), callback = function()
            UIManager:show(InfoMessage:new{text = _("Rating in browse mode updates the study schedule.")})
            self._browse_rate_unlocked = true
            self:show_answer(selected, typed)
        end })
        table.insert(tools, { text = _("Exit deck"), callback = function() self:exit_session() end })
        buttons = {
            {{ text = _("Next"), callback = rate("skipped") }},
            tools,
        }
    else
        table.insert(tools, { text = _("Skip"), callback = rate("skipped") })
        table.insert(tools, { text = _("Exit deck"), callback = function() self:exit_session() end })
        buttons = { ratings, tools }
    end
    local viewer_options = self:card_html_viewer_options(
        card, { "front_images", "back_images" }, prefix, true
    )
    self.card_view = TextViewer:new{
        title = self:card_title(),
        text = viewer_options.text,
        text_format = viewer_options.text_format,
        file = viewer_options.file,
        show_menu = false,
        buttons_table = buttons,
        text_type = "general",
    }
    UIManager:show(self.card_view)
end

function KindleAnki:rate_and_next(rating)
    local card = self.cards[self.card_position]
    if not card then return end
    if rating ~= "skipped" then
        local as_extra = self.session_mode == "extra"
            or (self.session_meta and self.session_meta.as_extra)
        self.store:record_review(self.pack, card, rating, { as_extra = as_extra })
        self.session_tally = self.session_tally or {}
        self.session_tally[rating] = (self.session_tally[rating] or 0) + 1
    end
    close_widget(self.card_view)
    self.card_position = self.card_position + 1
    self.store:set_next_index(self.pack, self.deck.id, self.card_position)
    self.selected = {}
    self._browse_rate_unlocked = false
    self.ai_history = {}
    if self.card_position > #self.cards then
        self:show_round_done()
        return
    end
    self:show_card()
end

-- End of a round: what was done, and the sensible next steps.
function KindleAnki:show_round_done()
    self.store:flush_progress()
    local title = self.session_mode == "browse" and _("Browse complete")
        or self.session_mode == "extra" and _("Extra study complete")
        or _("Today's goal reached")
    local tally = self.session_tally or {}
    local rated = (tally.again or 0) + (tally.hard or 0) + (tally.good or 0) + (tally.easy or 0)
    if rated > 0 then
        title = title .. "\n" .. string.format(_("%d cards rated: Again %d, Hard %d, Good %d, Easy %d"),
            rated, tally.again or 0, tally.hard or 0, tally.good or 0, tally.easy or 0)
    end
    local function go(action)
        return function()
            close_widget(self.done_dialog)
            action()
        end
    end
    local buttons = {}
    local summary = self.store:deck_summary(self.pack, self.deck)
    if self.session_mode ~= "errors" and summary.missed > 0 then
        table.insert(buttons, {{ text = string.format("%s (%d)", _("Retry missed"), summary.missed),
            callback = go(function() self:begin_session(self.deck, "errors") end) }})
    end
    if summary.today > 0 then
        table.insert(buttons, {{ text = string.format("%s (%d)", _("Start studying"), summary.today),
            callback = go(function() self:begin_session(self.deck, "study") end) }})
    else
        table.insert(buttons, {{ text = _("Study more"),
            callback = go(function() self:ask_extra_count(self.deck) end) }})
    end
    table.insert(buttons, {{ text = _("Back to deck"),
        callback = go(function() self:open_deck_actions(self.deck) end) }})
    self.done_dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.done_dialog)
end

-- The Kindle's own AI settings are the only source. Packs may still carry
-- an `ai` block from older converters; it is ignored, so a key never goes
-- to a server a pack names.
function KindleAnki:ai_config()
    local saved = self.settings:readSetting("ai", {})
    if type(saved) ~= "table" then saved = {} end
    local function text(value) return type(value) == "string" and value or "" end
    return {
        endpoint = text(saved.endpoint),
        model = text(saved.model),
        api_key = text(saved.api_key),
        system_prompt = text(saved.system_prompt),
    }
end

-- Suggested provider, filled in until the user sets their own. The browser
-- page uses the same pair (web/app.js AI_DEFAULTS).
local AI_DEFAULT_ENDPOINT = "https://api.deepseek.com"
local AI_DEFAULT_MODEL = "deepseek-flash"

function KindleAnki:open_ai_settings()
    local config = self:ai_config()
    if config.endpoint == "" and config.api_key == "" then
        config.endpoint = AI_DEFAULT_ENDPOINT
        if config.model == "" then config.model = AI_DEFAULT_MODEL end
    end
    local dialog
    dialog = MultiInputDialog:new{
        title = _("AI settings"),
        fields = {
            { text = config.endpoint, hint = "https://api.example.com/v1", description = _("OpenAI-compatible endpoint") },
            { text = config.model, hint = "model-name", description = _("Model name") },
            { text = config.api_key, hint = "sk-…", text_type = "password", description = _("API key. Plain http:// sends it unencrypted") },
            { text = config.system_prompt, hint = _("Explain clearly"), description = _("System prompt") },
        },
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() close_widget(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local fields = dialog:getFields()
                self.settings:saveSetting("ai", {
                    endpoint = fields[1], model = fields[2], api_key = fields[3], system_prompt = fields[4],
                }):flush()
                close_widget(dialog)
                UIManager:show(InfoMessage:new{text = _("AI settings saved locally")})
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function KindleAnki:ai_transcript()
    local history = self.ai_history or {}
    local lines = {}
    local latest_user_index
    for message_index = #history, 1, -1 do
        if history[message_index].role == "user" then
            latest_user_index = message_index
            break
        end
    end

    local charpos = 1
    self.ai_latest_question_charpos = nil
    for message_index, message in ipairs(history) do
        local speaker = message.role == "user" and _("You: ") or _("AI: ")
        local line = speaker .. tostring(message.content or "")
        if message_index == latest_user_index then
            self.ai_latest_question_charpos = charpos
        end
        table.insert(lines, line)
        charpos = charpos + #util.splitToChars(line)
        if message_index < #history then
            charpos = charpos + 2 -- the two newlines inserted by table.concat
        end
    end
    return table.concat(lines, "\n\n")
end

function KindleAnki:scroll_ai_viewer_to_latest(viewer)
    local charpos = self.ai_latest_question_charpos
    local box = viewer_text_box(viewer)
    if not charpos or not box or not box.lines_per_page or box.lines_per_page < 1 then return end
    if not box.getCharPageTopLineNumber or not box.vertical_string_list then return end

    local top_line = box:getCharPageTopLineNumber(charpos)
    if not top_line or top_line < 1 then return end
    local page_count = math.max(1, 1 + math.floor((#box.vertical_string_list - 1) / box.lines_per_page))
    local page_number = 1 + math.floor((top_line - 1) / box.lines_per_page)
    if page_number < 1 then return end
    local ratio = page_count > 1 and (page_number - 1) / (page_count - 1) or 0
    if ratio < 0 or ratio > 1 then return end
    viewer_scroll_widget(viewer):scrollToRatio(ratio, true)
end

function KindleAnki:show_ai_conversation(card, revealed)
    local viewer
    viewer = TextViewer:new{
        title = _("AI explanation"),
        text = self:ai_transcript(),
        show_menu = false,
        buttons_table = {
            {
                { text = _("Previous page"), callback = function() scroll_viewer_page(viewer, -1) end },
                { text = _("Next page"), callback = function() scroll_viewer_page(viewer, 1) end },
            },
            {
                { text = _("Ask again"), callback = function() close_widget(viewer); self:open_ai_input(card, revealed) end },
                { text = _("Restart chat"), callback = function()
                    self.store:clear_ai_history(self.pack, card)
                    self.ai_history = {}
                    close_widget(viewer)
                    UIManager:show(InfoMessage:new{text = _("AI chat cleared for this card")})
                    self:open_ai_input(card, revealed)
                end },
            },
            {
                { text = _("Close"), callback = function() close_widget(viewer) end },
            },
        },
        text_type = "general",
    }
    UIManager:show(viewer)
    self:scroll_ai_viewer_to_latest(viewer)
end

function KindleAnki:load_ai_history(card)
    self.ai_history = self.store:load_ai_history(self.pack, card) or {}
end

function KindleAnki:open_ai_question(card, revealed)
    self:load_ai_history(card)
    if #(self.ai_history or {}) > 0 then
        self:show_ai_conversation(card, revealed)
        return
    end
    self:open_ai_input(card, revealed)
end

function KindleAnki:open_ai_input(card, revealed)
    local config = self:ai_config()
    if config.api_key == "" then
        UIManager:show(ConfirmBox:new{
            text = _("AI is not set up yet. Set it up from your phone or computer now?"),
            ok_text = _("Set up AI"),
            cancel_text = _("Cancel"),
            ok_callback = function() self:open_ai_hub() end,
        })
        return
    end
    -- KOReader ships a Simplified Chinese Pinyin IME. Prefer it for this
    -- Chinese-first plugin; the keyboard's globe key still allows switching
    -- to another enabled layout for an English question.
    G_reader_settings:saveSetting("keyboard_layout", "zh_CN")
    local dialog
    dialog = InputDialog:new{
        title = _("Ask AI about this card"),
        description = _("The previous AI conversation will appear after you send."),
        input_hint = _("Type what you do not understand"),
        input = "",
        allow_newline = true,
        fullscreen = false,
        condensed = true,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() close_widget(dialog) end },
            { text = _("Send"), is_enter_default = true, callback = function()
                local question = dialog:getInputText()
                close_widget(dialog)
                self:send_ai(card, config, question, revealed)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function KindleAnki:send_ai(card, config, question, revealed)
    local waiting = InfoMessage:new{text = _("Asking AI…")}
    UIManager:show(waiting)
    local image_paths = self:card_image_paths(card)

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            return AI:request(config, card, self.ai_history, question, revealed, image_paths)
        end, waiting)
        close_widget(waiting)
        if not completed or type(result) ~= "table" then
            UIManager:show(InfoMessage:new{text = _("AI request was interrupted")})
            return
        end
        if not result.ok then
            UIManager:show(InfoMessage:new{text = result.error})
            return
        end
        local answer = result.text
        table.insert(self.ai_history, { role = "user", content = question })
        table.insert(self.ai_history, { role = "assistant", content = answer })
        if #self.ai_history > AI.MAX_HISTORY_MESSAGES then
            table.remove(self.ai_history, 1)
            table.remove(self.ai_history, 1)
        end
        self.store:save_ai_history(self.pack, card, self.ai_history)
        self.store:cleanup_ai_space()
        self:show_ai_conversation(card, revealed)
    end)
end

return KindleAnki
