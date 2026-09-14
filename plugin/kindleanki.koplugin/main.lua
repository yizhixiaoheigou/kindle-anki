local AI = require("ai")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Store = require("store")
local Screen = require("device").screen
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
end

function KindleAnki:addToMainMenu(menu_items)
    menu_items.kindle_anki = {
        text = _("Kindle Anki"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Import from computer"),
                callback = function() self:import_from_computer() end,
            },
            {
                text = _("Open packs"),
                callback = function() self:open_library() end,
            },
            {
                text = _("Manage packs"),
                callback = function() self:open_pack_manager() end,
            },
        },
    }
end

function KindleAnki:open_library()
    self.packs = self.store:list()
    local buttons = {
        {{
            text = _("Import from computer"),
            align = "left",
            callback = function() self:import_from_computer() end,
        }},
        {{
            text = _("Import pack"),
            align = "left",
            callback = function() self:import_pack() end,
        }},
        {{
            text = _("Manage packs"),
            align = "left",
            callback = function()
                close_widget(self.library_dialog)
                self:open_pack_manager()
            end,
        }},
    }
    for _, pack in ipairs(self.packs) do
        local current_pack = pack
        table.insert(buttons, {{
            text = current_pack.title,
            align = "left",
            callback = function()
                close_widget(self.library_dialog)
                self:open_decks(current_pack)
            end,
        }})
    end
    table.insert(buttons, {{
        text = _("AI settings"),
        align = "left",
        callback = function() self:open_ai_settings() end,
    }})
    table.insert(buttons, {{
        text = _("Clean AI storage"),
        align = "left",
        callback = function()
            local removed, total = self.store:cleanup_ai_space()
            UIManager:show(InfoMessage:new{
                text = string.format(_("Removed %d old AI chats. About %d KB remain."),
                    removed, math.floor(total / 1024))
            })
        end,
    }})
    table.insert(buttons, {{
        text = _("Close"),
        callback = function() close_widget(self.library_dialog) end,
    }})
    self.library_dialog = ButtonDialog:new{
        title = #self.packs > 0 and _("Choose a Kindle Anki pack")
            or _("No packs yet. Keep the computer converter open, then use Import from computer."),
        buttons = buttons,
        rows_per_page = 12,
    }
    UIManager:show(self.library_dialog)
end

function KindleAnki:open_pack_manager()
    close_widget(self.library_dialog)
    close_widget(self.manage_dialog)
    self.packs = self.store:list()
    local buttons = {}
    if #self.packs == 0 then
        UIManager:show(InfoMessage:new{text = _("No packs to manage.")})
        self:open_library()
        return
    end
    for _, pack in ipairs(self.packs) do
        local current_pack = pack
        table.insert(buttons, {{
            text = string.format(_("Delete: %s"), current_pack.title),
            align = "left",
            callback = function()
                close_widget(self.manage_dialog)
                self:confirm_delete_pack(current_pack, function()
                    self:open_pack_manager()
                end)
            end,
        }})
    end
    table.insert(buttons, {{
        text = _("Back"),
        callback = function()
            close_widget(self.manage_dialog)
            self:open_library()
        end,
    }})
    self.manage_dialog = ButtonDialog:new{
        title = _("Manage packs"),
        buttons = buttons,
        rows_per_page = 12,
    }
    UIManager:show(self.manage_dialog)
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
    local pack, err = self.store:import_from_computer(host, name, nil, pack_id)
    if not pack then
        UIManager:show(InfoMessage:new{
            text = string.format(_("Could not import pack: %s"), tostring(err)),
        })
        self:open_library()
        return
    end
    UIManager:show(InfoMessage:new{
        text = string.format(_("Imported %s"), pack.title or name),
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
            local pack, err = self.store:import_from_path(file_path)
            if not pack then
                UIManager:show(InfoMessage:new{
                    text = string.format(_("Could not import pack: %s"), tostring(err)),
                })
                self:open_library()
                return
            end
            UIManager:show(InfoMessage:new{
                text = string.format(_("Imported %s"), pack.title or file_path),
            })
            self:open_library()
        end,
    })
end

function KindleAnki:open_decks(pack)
    self.pack = pack
    local buttons = {}
    for _, deck in ipairs(pack.decks) do
        local current_deck = deck
        local card_count = 0
        for _, card in ipairs(pack.cards) do
            if card.deck_id == current_deck.id then card_count = card_count + 1 end
        end
        table.insert(buttons, {{
            text = string.format("%s (%d)", display_deck_name(current_deck), card_count),
            align = "left",
            callback = function()
                close_widget(self.deck_dialog)
                self:open_deck_actions(current_deck)
            end,
        }})
    end
    table.insert(buttons, {{
        text = _("Delete this pack"),
        callback = function()
            close_widget(self.deck_dialog)
            self:confirm_delete_pack(pack, function() self:open_library() end)
        end,
    }})
    table.insert(buttons, {{
        text = _("Back"),
        callback = function()
            close_widget(self.deck_dialog)
            self:open_library()
        end,
    }})
    self.deck_dialog = ButtonDialog:new{
        title = pack.title,
        buttons = buttons,
        rows_per_page = 8,
    }
    UIManager:show(self.deck_dialog)
end

function KindleAnki:open_deck_actions(deck)
    self.deck = deck
    if not self.store:daily_new_for(self.pack) then
        self:ask_daily_new(deck, false)
        return
    end
    local daily_new = self.store:daily_new_for(self.pack)
    local buttons = {
        {{ text = _("Start studying"), align = "left", callback = function()
            close_widget(self.deck_action_dialog)
            self:start_studying(deck)
        end }},
        {{ text = _("Starred cards"), align = "left", callback = function()
            close_widget(self.deck_action_dialog)
            self:begin_session(deck, "starred")
        end }},
        {{ text = _("Retry missed"), align = "left", callback = function()
            close_widget(self.deck_action_dialog)
            self:begin_session(deck, "errors")
        end }},
        {{ text = _("Browse cards"), align = "left", callback = function()
            close_widget(self.deck_action_dialog)
            self:begin_session(deck, "browse")
        end }},
        {{ text = string.format(_("Cards per day (%d)"), daily_new), align = "left", callback = function()
            close_widget(self.deck_action_dialog)
            self:ask_daily_new(deck, true)
        end }},
        {{ text = _("Back"), callback = function()
            close_widget(self.deck_action_dialog)
            self:open_decks(self.pack)
        end }},
    }
    self.deck_action_dialog = ButtonDialog:new{
        title = string.format(_("%s · %d cards/day"), display_deck_name(deck), daily_new),
        buttons = buttons,
        rows_per_page = 12,
    }
    UIManager:show(self.deck_action_dialog)
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
                self:open_decks(self.pack)
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
    return string.format("第 %d / %d 张", self.card_position, #self.cards)
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

function KindleAnki:card_html(card, fields, prefix, include_back)
    local blocks = {
        string.format('<div style="margin-bottom:12px">%s</div>', html_escape(self:card_progress())),
    }
    if prefix and prefix ~= "" then table.insert(blocks, 1, prefix) end
    if include_back then
        table.insert(blocks, string.format('<div style="margin-bottom:12px">%s</div>', html_escape(_("Card back:"))))
        table.insert(blocks, string.format('<div style="margin-bottom:12px">%s</div>', html_escape(card.back)))
        if html_wants_field(fields, "back_images") then
            local back_images = self:card_image_html(card, { "back_images" })
            if back_images ~= "" then table.insert(blocks, back_images) end
        end
        return table.concat(blocks, "\n")
    end
    table.insert(blocks, string.format('<div style="margin-bottom:12px">%s</div>', html_escape(_("Card front:"))))
    table.insert(blocks, string.format('<div style="margin-bottom:12px">%s</div>', html_escape(card.front)))
    if card.type == "choice" then
        local options = { _("Options:") }
        for index, option in ipairs(card.options) do
            table.insert(options, string.format("%s. %s", option_letter(index), option))
        end
        table.insert(blocks, string.format('<div style="margin-bottom:12px">%s</div>',
            html_escape(table.concat(options, "\n"))))
    end
    if html_wants_field(fields, "front_images") then
        local front_images = self:card_image_html(card, { "front_images" })
        if front_images ~= "" then table.insert(blocks, front_images) end
    end
    return table.concat(blocks, "\n")
end

function KindleAnki:card_html_viewer_options(card, fields, prefix, include_back)
    return {
        text_format = "html",
        file = self.pack._path .. ".kindle-card.html",
        text = self:card_html(card, fields, prefix, include_back),
    }
end

function KindleAnki:card_image_paths(card)
    local paths = {}
    local seen = {}
    local media_dir = self.pack and self.pack.media_dir
    if type(media_dir) ~= "string" then return paths end
    local base = pack_directory(self.pack) .. "/" .. media_dir
    for _, field in ipairs({ "front_images", "back_images" }) do
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
                text = _("Show back"),
                callback = function() self:show_answer(self.selected) end,
            }})
        end
    elseif card.type == "short_answer" then
        table.insert(buttons, {{
            text = _("Type answer"),
            callback = function() self:open_typing_dialog(card) end,
        }})
        table.insert(buttons, {{
            text = _("Show back"),
            callback = function() self:show_answer(nil, nil) end,
        }})
    end
    table.insert(buttons, {{
        text = _("AI explain"),
        callback = function() self:open_ai_question(card, false) end,
    }})
    table.insert(buttons, {{
        text = _("Exit deck"),
        callback = function()
            close_widget(self.card_view)
            self:open_decks(self.pack)
        end,
    }})
    local viewer_options = self:card_html_viewer_options(card, { "front_images", "back_images" })
    self.card_view = TextViewer:new{
        title = study_title(self.pack, self.deck),
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
            answer_status = matches and "\n" .. _("Match: correct") .. "\n"
                or "\n" .. _("Match: check the back") .. "\n"
        end
        prefix = string.format('<div style="margin-bottom:12px">%s</div>', html_escape(
            _("Your answer:") .. "\n" .. typed .. answer_status))
    end
    if card.type == "choice" then
        local chosen = selected_labels(selected)
        local correct = {}
        for _, index in ipairs(card.correct_indices) do table.insert(correct, option_letter(index + 1)) end
        prefix = string.format('<div style="margin-bottom:12px">%s</div>', html_escape(
            _("Your choice: ") .. chosen .. "\n" .. _("Correct: ")
                .. table.concat(correct, ", ")))
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
    local starred = self.store:is_starred(self.pack, card)
    local star_text = starred and _("Unstar") or _("Star")
    local buttons
    if self.session_mode == "browse" then
        buttons = {
            {{ text = _("Rate anyway"), callback = function()
                UIManager:show(InfoMessage:new{text = _("Rating in browse mode updates the study schedule.")})
                self._browse_rate_unlocked = true
                self:show_answer(selected, typed)
            end },
             { text = _("Next"), callback = function() self:rate_and_next("skipped") end }},
            {{ text = _("AI explain"), callback = function() self:open_ai_question(card, true) end },
             { text = _("Exit deck"), callback = function() close_widget(self.card_view); self:open_deck_actions(self.deck) end }},
        }
        if self._browse_rate_unlocked then
            buttons = {
                {{ text = rating_label("Again", "again"), callback = function() self:rate_and_next("again") end },
                 { text = rating_label("Hard", "hard"), callback = function() self:rate_and_next("hard") end }},
                {{ text = rating_label("Good", "good"), callback = function() self:rate_and_next("good") end },
                 { text = rating_label("Easy", "easy"), callback = function() self:rate_and_next("easy") end }},
                {{ text = _("AI explain"), callback = function() self:open_ai_question(card, true) end },
                 { text = _("Next"), callback = function() self:rate_and_next("skipped") end }},
            }
        end
    else
        buttons = {
            {{ text = rating_label("Again", "again"), callback = function() self:rate_and_next("again") end },
             { text = rating_label("Hard", "hard"), callback = function() self:rate_and_next("hard") end }},
            {{ text = rating_label("Good", "good"), callback = function() self:rate_and_next("good") end },
             { text = rating_label("Easy", "easy"), callback = function() self:rate_and_next("easy") end }},
            {{ text = _("AI explain"), callback = function() self:open_ai_question(card, true) end },
             { text = star_text, callback = function()
                self.store:toggle_star(self.pack, card)
                self:show_answer(selected, typed)
             end }},
            {{ text = _("Next"), callback = function() self:rate_and_next("skipped") end }},
        }
    end
    local viewer_options = self:card_html_viewer_options(
        card, { "front_images", "back_images" }, prefix, true
    )
    self.card_view = TextViewer:new{
        title = study_title(self.pack, self.deck),
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
    end
    close_widget(self.card_view)
    self.card_position = self.card_position + 1
    self.store:set_next_index(self.pack, self.deck.id, self.card_position)
    self.selected = {}
    self._browse_rate_unlocked = false
    self.ai_history = {}
    if self.card_position > #self.cards then
        local title = self.session_mode == "browse" and _("Browse complete")
            or self.session_mode == "extra" and _("Extra study complete")
            or _("Today's goal reached")
        local buttons = {}
        local missed = self.store:build_session(self.pack, self.deck, "errors")
        if self.session_mode ~= "errors" and #missed > 0 then
            table.insert(buttons, {{ text = _("Retry missed"), callback = function()
                close_widget(self.done_dialog)
                self:begin_session(self.deck, "errors")
            end }})
        end
        table.insert(buttons, {{ text = _("Start studying"), callback = function()
            close_widget(self.done_dialog)
            self:start_studying(self.deck)
        end }})
        table.insert(buttons, {{ text = _("Browse cards"), callback = function()
            close_widget(self.done_dialog)
            self:begin_session(self.deck, "browse")
        end }})
        table.insert(buttons, {{ text = _("Back"), callback = function()
            close_widget(self.done_dialog)
            self:open_deck_actions(self.deck)
        end }})
        self.done_dialog = ButtonDialog:new{
            title = title,
            buttons = buttons,
            rows_per_page = 8,
        }
        UIManager:show(self.done_dialog)
        return
    end
    self:show_card()
end

function KindleAnki:ai_config()
    local saved = self.settings:readSetting("ai", {})
    if type(saved) ~= "table" then saved = {} end
    local pack_ai = self.pack and self.pack.ai or {}
    if type(pack_ai) ~= "table" then pack_ai = {} end
    local function present(v) return v ~= nil and v ~= "" end
    -- Pair credentials with their source: a local API key must never travel to
    -- a pack-supplied endpoint (or a pack key to a local endpoint) without an
    -- explicit confirmation at request time.
    local endpoint, api_key, cross_source = "", "", false
    if present(saved.endpoint) and present(saved.api_key) then
        endpoint, api_key = saved.endpoint, saved.api_key
    elseif present(pack_ai.endpoint) and present(pack_ai.api_key) then
        endpoint, api_key = pack_ai.endpoint, pack_ai.api_key
    elseif present(saved.api_key) and present(pack_ai.endpoint) then
        endpoint, api_key, cross_source = pack_ai.endpoint, saved.api_key, true
    elseif present(pack_ai.api_key) and present(saved.endpoint) then
        endpoint, api_key, cross_source = saved.endpoint, pack_ai.api_key, true
    elseif present(saved.endpoint) then
        endpoint = saved.endpoint
    elseif present(pack_ai.endpoint) then
        endpoint = pack_ai.endpoint
    end
    local model = present(saved.model) and saved.model or pack_ai.model or ""
    local system_prompt = present(saved.system_prompt) and saved.system_prompt
        or pack_ai.system_prompt or ""
    return {
        endpoint = endpoint,
        model = model,
        api_key = api_key,
        system_prompt = system_prompt,
        cross_source = cross_source,
    }
end

function KindleAnki:open_ai_settings()
    local config = self:ai_config()
    local dialog
    dialog = MultiInputDialog:new{
        title = _("AI settings (local values override pack)"),
        fields = {
            { text = config.endpoint, hint = "https://api.example.com/v1", description = _("OpenAI-compatible endpoint") },
            { text = config.model, hint = "model-name", description = _("Model name") },
            { text = config.api_key, hint = "sk-…", text_type = "password", description = _("API key; local value overrides the pack. Plain http:// sends it unencrypted") },
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
    local box = viewer and viewer.box_widget
    if not charpos or not box or not box.lines_per_page or box.lines_per_page < 1 then return end
    if not box.getCharPageTopLineNumber or not box.vertical_string_list then return end

    local top_line = box:getCharPageTopLineNumber(charpos)
    if not top_line or top_line < 1 then return end
    local page_count = math.max(1, 1 + math.floor((#box.vertical_string_list - 1) / box.lines_per_page))
    local page_number = 1 + math.floor((top_line - 1) / box.lines_per_page)
    if page_number < 1 then return end
    local ratio = page_count > 1 and (page_number - 1) / (page_count - 1) or 0
    if ratio < 0 or ratio > 1 then return end
    viewer.scroll_widget:scrollToRatio(ratio, true)
end

function KindleAnki:show_ai_conversation(card, revealed)
    local viewer
    viewer = TextViewer:new{
        title = _("AI explanation"),
        text = self:ai_transcript(),
        show_menu = false,
        buttons_table = {
            {
                { text = _("Previous page"), callback = function() viewer:onScrollOrNavigate(-1) end },
                { text = _("Next page"), callback = function() viewer:onScrollOrNavigate(1) end },
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
        UIManager:show(InfoMessage:new{text = _("Configure an API key in the pack or Kindle Anki → AI settings first.")})
        return
    end
    if config.cross_source and not self._ai_cross_consent then
        UIManager:show(ConfirmBox:new{
            text = _("This pack defines its own AI endpoint. Your local API key will be sent to that server. Continue?"),
            ok_text = _("Continue"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                self._ai_cross_consent = true
                self:open_ai_input(card, revealed)
            end,
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
