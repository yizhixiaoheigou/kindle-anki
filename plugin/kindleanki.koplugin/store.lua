local JSON = require("json")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local Schedule = require("schedule")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")

local Store = {}
Store.__index = Store

local DATA_DIR = DataStorage:getDataDir()
local PACK_ROOTS = {
    "/mnt/us/kindle-anki/packs",
    DATA_DIR .. "/kindle-anki/packs",
    "/mnt/us/folo-anki/packs",
    DATA_DIR .. "/folo-anki/packs",
}
local AI_ROOTS = {
    "/mnt/us/kindle-anki/ai",
    DATA_DIR .. "/kindle-anki/ai",
    "/mnt/us/folo-anki/ai",
    DATA_DIR .. "/folo-anki/ai",
}
local PACK_DIR = PACK_ROOTS[1]
local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/kindle_anki.lua"
local SETTINGS_FILE_LEGACY = DataStorage:getSettingsDir() .. "/folo_anki.lua"
local FORMAT_NAMES = { ["kindle-anki"] = true, ["folo-kindle-anki"] = true }

local PROGRESS_FLUSH_EVERY = 10 -- flash-wear guard: batch progress writes
local DEFAULT_DAILY_NEW = 20
local MIN_DAILY_NEW = 1
local MAX_DAILY_NEW = 999
local AI_MAX_TOTAL_BYTES = 8 * 1024 * 1024

local function is_directory(path)
    return lfs.attributes(path, "mode") == "directory"
end

local function ensure_directory(path)
    if is_directory(path) then return true end
    local parent = path:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and not is_directory(parent) then
        ensure_directory(parent)
    end
    return lfs.mkdir(path)
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil, "cannot open " .. path end
    local contents = file:read("*a")
    file:close()
    return contents
end

local function write_file(path, contents)
    local parent = path:match("^(.*)/[^/]+$")
    if parent then ensure_directory(parent) end
    local file, err = io.open(path, "wb")
    if not file then return nil, err end
    file:write(contents)
    file:close()
    return true
end

local function basename(path)
    return path:match("([^/]+)$") or path
end

local function dirname(path)
    return path:match("^(.*)/[^/]+$") or "."
end

local function copy_file(src, dest)
    local contents, err = read_file(src)
    if not contents then return nil, err end
    return write_file(dest, contents)
end

local function under_directory(path, root)
    if type(path) ~= "string" or type(root) ~= "string" or root == "" then
        return false
    end
    if path == root then return false end
    return path:sub(1, #root + 1) == root .. "/"
end

local function remove_directory(path)
    if not is_directory(path) then return true end
    local ok, iterator, directory_object = pcall(lfs.dir, path)
    if not ok or not iterator then return nil, "cannot read " .. path end
    for name in iterator, directory_object do
        if name ~= "." and name ~= ".." then
            local child = path .. "/" .. name
            if is_directory(child) then
                local removed, err = remove_directory(child)
                if not removed then return nil, err end
            else
                os.remove(child)
            end
        end
    end
    local removed = lfs.rmdir(path)
    if not removed then return nil, "cannot remove " .. path end
    return true
end

local function copy_directory(src, dest)
    if not is_directory(src) then return true end
    ensure_directory(dest)
    local ok, iterator, directory_object = pcall(lfs.dir, src)
    if not ok or not iterator then return nil, "cannot read " .. src end
    for name in iterator, directory_object do
        if name ~= "." and name ~= ".." then
            local from = src .. "/" .. name
            local to = dest .. "/" .. name
            if is_directory(from) then
                local copied, copy_err = copy_directory(from, to)
                if not copied then return nil, copy_err end
            else
                local copied, copy_err = copy_file(from, to)
                if not copied then return nil, copy_err end
            end
        end
    end
    return true
end

local function find_pack_json(directory)
    local found
    local function walk(path)
        if found or not is_directory(path) then return end
        local ok, iterator, directory_object = pcall(lfs.dir, path)
        if not ok or not iterator then return end
        for name in iterator, directory_object do
            if name ~= "." and name ~= ".." then
                local child = path .. "/" .. name
                if name:match("%.kindle%-anki%.json$") or name:match("%.folo%-kindle%.json$") then
                    found = child
                    return
                elseif is_directory(child) then
                    walk(child)
                end
            end
        end
    end
    walk(directory)
    return found
end

local function zip_entry_names_safe(zip_path)
    -- Zip-slip guard: reject absolute paths, backslashes, and ".." segments
    -- before anything is extracted.
    local quoted_zip = zip_path:gsub('"', '\\"')
    local handle = io.popen('unzip -Z1 "' .. quoted_zip .. '" 2>/dev/null')
    if not handle then
        return true -- listing unavailable; the post-extract symlink scrub still applies
    end
    local safe = true
    for entry in handle:lines() do
        local clean = entry:gsub("[\r\n]", "")
        if clean ~= ""
            and (clean:sub(1, 1) == "/" or clean:find("\\", 1, true) or clean:find("%.%."))
        then
            safe = false
        end
    end
    handle:close()
    return safe
end

local function remove_symlinks(directory)
    for child in lfs.dir(directory) do
        if child ~= "." and child ~= ".." then
            local path = directory .. "/" .. child
            if lfs.symlinkattributes and lfs.symlinkattributes(path, "mode") == "link" then
                os.remove(path)
            elseif lfs.attributes(path, "mode") == "directory" then
                remove_symlinks(path)
            end
        end
    end
end

local function extract_zip(zip_path, dest)
    ensure_directory(dest)
    if not zip_entry_names_safe(zip_path) then
        return false
    end
    local ok_mod, archive = pcall(require, "ffi/archive")
    if ok_mod and type(archive) == "table" then
        if type(archive.unpack) == "function" then
            local ok = pcall(archive.unpack, archive, zip_path, dest)
            if ok then
                pcall(remove_symlinks, dest)
                return true
            end
        end
        if type(archive.extract) == "function" then
            local ok = pcall(archive.extract, archive, zip_path, dest)
            if ok then
                pcall(remove_symlinks, dest)
                return true
            end
        end
    end
    local quoted_zip = zip_path:gsub('"', '\\"')
    local quoted_dest = dest:gsub('"', '\\"')
    local status = os.execute('unzip -o "' .. quoted_zip .. '" -d "' .. quoted_dest .. '" >/dev/null 2>&1')
    if status == 0 or status == true then
        pcall(remove_symlinks, dest)
        return true
    end
    return false
end

local function validate_image_refs(card, field)
    local refs = card[field]
    if refs == nil then return true end
    if type(refs) ~= "table" or #refs > 8 then return false end
    for _, image in ipairs(refs) do
        if type(image) ~= "table" or type(image.name) ~= "string"
                or image.name == "" or image.name == "." or image.name == ".."
                or image.name:match("[/\\\\]")
                or type(image.width) ~= "number" or type(image.height) ~= "number"
                or image.width < 1 or image.height < 1 then
            return false
        end
    end
    return true
end

local function validate_pack(pack)
    if type(pack) ~= "table" or pack.version ~= 1 or not FORMAT_NAMES[pack.format] then
        return false, "unsupported pack format"
    end
    if type(pack.title) ~= "string" or type(pack.decks) ~= "table" or type(pack.cards) ~= "table" then
        return false, "pack is missing title, decks, or cards"
    end
    if pack.media_dir ~= nil then
        if type(pack.media_dir) ~= "string" or pack.media_dir == "" or pack.media_dir == "."
                or pack.media_dir == ".." or pack.media_dir:match("[/\\\\]") then
            return false, "invalid media directory"
        end
    end
    local deck_ids = {}
    for _, deck in ipairs(pack.decks) do
        if type(deck.id) ~= "number" or type(deck.name) ~= "string" then
            return false, "invalid deck entry"
        end
        deck_ids[deck.id] = true
    end
    local card_ids = {}
    for _, card in ipairs(pack.cards) do
        if type(card.id) ~= "number" or type(card.deck_id) ~= "number" or not deck_ids[card.deck_id] then
            return false, "invalid card deck reference"
        end
        if card_ids[card.id] then return false, "duplicate card id" end
        card_ids[card.id] = true
        if type(card.front) ~= "string" or type(card.back) ~= "string" then
            return false, "card is missing front or back"
        end
        if not validate_image_refs(card, "front_images")
                or not validate_image_refs(card, "back_images") then
            return false, "card has invalid image references"
        end
        if card.type == "short_answer" then
        elseif card.type == "choice" then
            if card.mode ~= "single" and card.mode ~= "multiple" then
                return false, "choice card has invalid mode"
            end
            if type(card.options) ~= "table" or #card.options < 2 or #card.options > 64 then
                return false, "choice card has an invalid option count"
            end
            if type(card.correct_indices) ~= "table" or #card.correct_indices < 1 then
                return false, "choice card is missing correct indices"
            end
        else
            return false, "unknown card type"
        end
    end
    if pack.ai ~= nil and type(pack.ai) ~= "table" then
        return false, "ai must be an object"
    end
    if type(pack.ai) == "table" then
        if pack.ai.key ~= nil or pack.ai["api-key"] ~= nil
                or pack.ai.token ~= nil or pack.ai.secret ~= nil then
            return false, "use the canonical pack.ai.api_key field"
        end
        if pack.ai.api_key ~= nil and type(pack.ai.api_key) ~= "string" then
            return false, "ai.api_key must be text"
        end
    end
    return true
end

local function list_json_files(directory)
    local files = {}
    if not is_directory(directory) then return files end
    local ok, iterator, directory_object = pcall(lfs.dir, directory)
    if not ok or not iterator then return files end
    for name in iterator, directory_object do
        if name:sub(1, 1) ~= "." and name:match("%.json$") then
            table.insert(files, directory .. "/" .. name)
        end
    end
    table.sort(files)
    return files
end

local function pack_key(pack)
    return pack._path or pack.title
end

local function sanitize_segment(value)
    value = tostring(value or "pack"):gsub("[^%w%._%-]+", "_")
    if value == "" then value = "pack" end
    return value
end

function Store:new(settings)
    if not settings then
        settings = LuaSettings:open(SETTINGS_FILE)
        if not (settings and settings.data and next(settings.data) ~= nil) then
            local legacy = LuaSettings:open(SETTINGS_FILE_LEGACY)
            if legacy and legacy.data and next(legacy.data) ~= nil then
                legacy.file = SETTINGS_FILE
                settings = legacy
            end
        end
    end
    local progress = settings:readSetting("progress", {})
    if type(progress) ~= "table" then progress = {} end
    return setmetatable({
        settings = settings,
        progress = progress,
    }, self)
end

function Store.clamp_count(value)
    if type(value) == "string" then
        value = value:match("^%s*(.-)%s*$")
    end
    local count = tonumber(value)
    if not count then return nil end
    count = math.floor(count)
    if count < MIN_DAILY_NEW or count > MAX_DAILY_NEW then return nil end
    return count
end

function Store:daily_new_for(pack)
    local progress = self:progress_for(pack)
    return Store.clamp_count(progress.daily_new)
end

function Store:set_daily_new(pack, value)
    local count = Store.clamp_count(value)
    if not count then return nil end
    local progress = self:progress_for(pack)
    progress.daily_new = count
    self:save_progress()
    return count
end

function Store:list()
    self:flush_progress()
    local result = {}
    local seen = {}
    for _, directory in ipairs(PACK_ROOTS) do
        for _, path in ipairs(list_json_files(directory)) do
            if not seen[path] then
                local pack = self:load(path)
                if pack then
                    pack._path = path
                    table.insert(result, pack)
                end
                seen[path] = true
            end
        end
    end
    table.sort(result, function(left, right) return left.title < right.title end)
    return result
end

local function listed_match(self, pack, source_json)
    local src_base = basename(source_json)
    for _, existing in ipairs(self:list()) do
        if existing._path == source_json then return existing end
        if basename(existing._path) == src_base then return existing end
        if pack and existing.title == pack.title then return existing end
    end
    return nil
end

function Store:load(path)
    local contents, read_error = read_file(path)
    if not contents then return nil, read_error end
    local ok, pack = pcall(JSON.decode, contents)
    if not ok then return nil, "invalid JSON" end
    local valid, error_text = validate_pack(pack)
    if not valid then return nil, error_text end
    return pack
end

local function copy_pack_into_library(pack, source_json)
    ensure_directory(PACK_DIR)
    local dest = PACK_DIR .. "/" .. basename(source_json)
    local copied, copy_err = copy_file(source_json, dest)
    if not copied then return nil, copy_err end
    if type(pack.media_dir) == "string" then
        local source_media = dirname(source_json) .. "/" .. pack.media_dir
        if is_directory(source_media) then
            local media_ok, media_err = copy_directory(source_media, PACK_DIR .. "/" .. pack.media_dir)
            if not media_ok then return nil, media_err end
        end
    end
    pack._path = dest
    return pack
end

function Store:import_from_path(path)
    if type(path) ~= "string" or path == "" then
        return nil, "missing path"
    end
    ensure_directory(PACK_DIR)
    local lower = path:lower()
    if lower:match("%.zip$") then
        local tmp = PACK_DIR .. "/.import-tmp"
        os.execute('rm -rf "' .. tmp:gsub('"', '\\"') .. '"')
        if not extract_zip(path, tmp) then
            return nil, "could not unzip pack"
        end
        local json_path = find_pack_json(tmp)
        if not json_path then
            os.execute('rm -rf "' .. tmp:gsub('"', '\\"') .. '"')
            return nil, "zip does not contain a Kindle pack JSON"
        end
        local pack, err = self:load(json_path)
        if not pack then
            os.execute('rm -rf "' .. tmp:gsub('"', '\\"') .. '"')
            return nil, err
        end
        local hit = listed_match(self, pack, json_path)
        if hit then
            os.execute('rm -rf "' .. tmp:gsub('"', '\\"') .. '"')
            return hit
        end
        pack, err = copy_pack_into_library(pack, json_path)
        os.execute('rm -rf "' .. tmp:gsub('"', '\\"') .. '"')
        return pack, err
    end
    if not lower:match("%.json$") then
        return nil, "choose a .kindle-anki.json, .folo-kindle.json, or zip pack"
    end
    local pack, err = self:load(path)
    if not pack then return nil, err end
    local hit = listed_match(self, pack, path)
    if hit then return hit end
    return copy_pack_into_library(pack, path)
end

function Store:delete_pack(pack)
    if type(pack) ~= "table" or type(pack._path) ~= "string" then
        return nil, "missing pack"
    end
    local path = pack._path
    local in_library = false
    for _, root in ipairs(PACK_ROOTS) do
        if under_directory(path, root) then
            in_library = true
            break
        end
    end
    if not in_library then
        return nil, "pack is not in the library folder"
    end
    if not path:lower():match("%.json$") then
        return nil, "pack path is not JSON"
    end
    os.remove(path)
    if type(pack.media_dir) == "string" and pack.media_dir ~= "" and not pack.media_dir:find("%.%.", 1, true) then
        local media = dirname(path) .. "/" .. pack.media_dir
        for _, root in ipairs(PACK_ROOTS) do
            if under_directory(media, root) then
                remove_directory(media)
                break
            end
        end
    end
    self.progress[pack_key(pack)] = nil
    if pack.title then self.progress[pack.title] = nil end
    self:save_progress()
    local pack_name = sanitize_segment(path:match("([^/]+)%.json$") or pack.title)
    if pack_name ~= "" and pack_name ~= "." and pack_name ~= ".." then
        for _, root in ipairs(self:ai_roots()) do
            remove_directory(root .. "/" .. pack_name)
        end
    end
    return true
end

function Store:computer_host()
    local host = self.settings:readSetting("computer_host", "")
    if type(host) == "string" then return host end
    return ""
end

function Store:set_computer_host(host)
    self.settings:saveSetting("computer_host", tostring(host or "")):flush()
end

function Store:list_computer_packs(host, port)
    host = tostring(host or ""):gsub("^%s+", ""):gsub("%s+$", "")
    port = tonumber(port) or 8766
    if host == "" then return nil, "missing computer IP" end
    local url = string.format("http://%s:%d/packs", host, port)
    local chunks = {}
    socketutil:set_timeout(8, 15)
    local ok, code = pcall(function()
        return socket.skip(1, http.request{
            url = url,
            sink = ltn12.sink.table(chunks),
        })
    end)
    socketutil:reset_timeout()
    if not ok then return nil, tostring(code) end
    if tonumber(code) ~= 200 then
        return nil, "computer returned " .. tostring(code)
    end
    local decoded_ok, payload = pcall(JSON.decode, table.concat(chunks))
    if not decoded_ok or type(payload) ~= "table" or type(payload.packs) ~= "table" then
        return nil, "computer did not return a pack list"
    end
    return payload.packs
end

function Store:fetch_ai_settings(host, code, port)
    host = tostring(host or ""):gsub("^%s+", ""):gsub("%s+$", "")
    code = tostring(code or ""):gsub("^%s+", ""):gsub("%s+$", "")
    port = tonumber(port) or 8766
    if host == "" then return nil, "missing computer IP" end
    if code == "" then return nil, "missing pairing code" end
    local url = string.format("http://%s:%d/ai-settings?code=%s", host, port, code)
    local chunks = {}
    socketutil:set_timeout(8, 15)
    local ok, response = pcall(function()
        return socket.skip(1, http.request{
            url = url,
            sink = ltn12.sink.table(chunks),
        })
    end)
    socketutil:reset_timeout()
    if not ok then return nil, tostring(response) end
    if tonumber(response) ~= 200 then
        return nil, "computer returned " .. tostring(response)
    end
    local decoded_ok, payload = pcall(JSON.decode, table.concat(chunks))
    if not decoded_ok or type(payload) ~= "table" or type(payload.api_key) ~= "string" then
        return nil, "computer did not return AI settings"
    end
    return payload
end

function Store:import_from_computer(host, name, port, pack_id)
    host = tostring(host or ""):gsub("^%s+", ""):gsub("%s+$", "")
    name = tostring(name or "")
    port = tonumber(port) or 8766
    pack_id = tonumber(pack_id)
    if host == "" then return nil, "missing computer IP" end
    if pack_id == nil and not name:match("%.kindle%-anki%.zip$") and not name:match("%.folo%-kindle%.zip$") then
        return nil, "choose a .kindle-anki.zip or .folo-kindle.zip pack"
    end
    ensure_directory(PACK_DIR)
    local url
    if pack_id ~= nil then
        url = string.format("http://%s:%d/packs/%d", host, port, pack_id)
    else
        url = string.format("http://%s:%d/packs/%s", host, port, name)
    end
    local dest = PACK_DIR .. "/.download.kindle-anki.zip"
    local file, err = io.open(dest, "wb")
    if not file then return nil, err end
    socketutil:set_timeout(20, 120)
    local ok, code = pcall(function()
        return socket.skip(1, http.request{
            url = url,
            sink = ltn12.sink.file(file),
        })
    end)
    socketutil:reset_timeout()
    if not ok then
        pcall(function() file:close() end)
        return nil, tostring(code)
    end
    if tonumber(code) ~= 200 then
        return nil, "download failed: " .. tostring(code)
    end
    return self:import_from_path(dest)
end

function Store:progress_for(pack)
    local key = pack_key(pack)
    if type(self.progress[key]) ~= "table" then
        self.progress[key] = { cards = {}, decks = {}, days = {} }
    end
    if type(self.progress[key].cards) ~= "table" then
        self.progress[key].cards = {}
    end
    if type(self.progress[key].decks) ~= "table" then
        self.progress[key].decks = {}
    end
    if type(self.progress[key].days) ~= "table" then
        self.progress[key].days = {}
    end
    return self.progress[key]
end

function Store:save_progress(force)
    -- Flash on Kindle is slow and wears out: batch progress writes and flush
    -- every PROGRESS_FLUSH_EVERY reviews, or immediately when forced.
    self._progress_pending = (self._progress_pending or 0) + 1
    if not force and self._progress_pending < PROGRESS_FLUSH_EVERY then
        return
    end
    self._progress_pending = 0
    self.settings:saveSetting("progress", self.progress):flush()
end

function Store:flush_progress()
    if (self._progress_pending or 0) > 0 then
        self:save_progress(true)
    end
end

function Store:card_state(pack, card)
    local progress = self:progress_for(pack)
    local key = tostring(card.id)
    local state = progress.cards[key]
    if type(state) ~= "table" then
        state = Schedule.default_state()
        progress.cards[key] = state
    end
    -- Migrate MVP records that only stored last_rating.
    if state.due == nil then
        local migrated = Schedule.default_state()
        migrated.last_rating = state.last_rating
        migrated.reviewed_at = state.reviewed_at
        if state.last_rating and state.last_rating ~= "skipped" then
            Schedule.apply(migrated, state.last_rating, Schedule.today(), false)
        end
        progress.cards[key] = migrated
        state = migrated
    end
    return state
end

function Store:day_stats(pack, today)
    today = today or Schedule.today()
    local progress = self:progress_for(pack)
    local key = tostring(today)
    if type(progress.days[key]) ~= "table" then
        progress.days[key] = { new_done = 0, review_done = 0, extra_done = 0 }
    end
    return progress.days[key]
end

function Store:record_review(pack, card, rating, options)
    options = options or {}
    if rating == "skipped" then
        return self:card_state(pack, card)
    end
    local state = self:card_state(pack, card)
    local was_new = Schedule.is_new(state)
    local as_extra = options.as_extra and true or false
    Schedule.apply(state, rating, options.today or Schedule.today(), as_extra)
    local stats = self:day_stats(pack, options.today)
    if as_extra then
        stats.extra_done = (stats.extra_done or 0) + 1
    elseif was_new then
        stats.new_done = (stats.new_done or 0) + 1
    else
        stats.review_done = (stats.review_done or 0) + 1
    end
    self:save_progress()
    return state
end

function Store:set_next_index(pack, deck_id, next_index)
    local progress = self:progress_for(pack)
    if type(progress.decks[tostring(deck_id)]) ~= "table" then
        progress.decks[tostring(deck_id)] = {}
    end
    progress.decks[tostring(deck_id)].next_index = next_index
    self:save_progress()
end

function Store:next_index(pack, deck_id)
    local progress = self:progress_for(pack)
    local deck_progress = progress.decks[tostring(deck_id)]
    return deck_progress and deck_progress.next_index or 1
end

function Store:is_starred(pack, card)
    return self:card_state(pack, card).starred == true
end

function Store:toggle_star(pack, card)
    local state = self:card_state(pack, card)
    state.starred = not state.starred
    self:save_progress()
    return state.starred
end

function Store:deck_cards(pack, deck_id)
    local cards = {}
    for _, card in ipairs(pack.cards) do
        if card.deck_id == deck_id then table.insert(cards, card) end
    end
    return cards
end

function Store:build_session(pack, deck, mode, extra_count)
    local today = Schedule.today()
    local cards = self:deck_cards(pack, deck.id)
    local stats = self:day_stats(pack, today)
    local daily_new = self:daily_new_for(pack) or 0
    local new_remaining = math.max(0, daily_new - (stats.new_done or 0))
    local due_list, new_list, later_list = {}, {}, {}
    for _, card in ipairs(cards) do
        local state = self:card_state(pack, card)
        if Schedule.is_new(state) then
            table.insert(new_list, card)
        elseif Schedule.is_due(state, today) then
            table.insert(due_list, card)
        else
            table.insert(later_list, card)
        end
    end
    local session = {}
    local meta = {
        mode = mode or "study",
        as_extra = false,
        today = today,
        daily_new = daily_new,
        new_remaining = new_remaining,
        due_count = #due_list,
    }

    if mode == "browse" then
        for _, card in ipairs(cards) do table.insert(session, card) end
        meta.mode = "browse"
        return session, meta
    end

    if mode == "starred" then
        for _, card in ipairs(cards) do
            if self:is_starred(pack, card) then table.insert(session, card) end
        end
        meta.mode = "starred"
        meta.as_extra = true
        return session, meta
    end

    if mode == "errors" then
        for _, card in ipairs(cards) do
            if self:card_state(pack, card).last_rating == "again" then
                table.insert(session, card)
            end
        end
        meta.mode = "errors"
        meta.as_extra = true
        return session, meta
    end

    if mode == "extra" then
        extra_count = Store.clamp_count(extra_count)
        local pool = {}
        for _, card in ipairs(later_list) do table.insert(pool, card) end
        for _, card in ipairs(new_list) do table.insert(pool, card) end
        if extra_count then
            for index = 1, math.min(extra_count, #pool) do
                table.insert(session, pool[index])
            end
        end
        meta.mode = "extra"
        meta.as_extra = true
        meta.extra_count = extra_count or 0
        meta.extra_available = #pool
        return session, meta
    end

    -- Default study: dues first, then remaining new-card quota for this pack.
    for _, card in ipairs(due_list) do table.insert(session, card) end
    for index = 1, math.min(new_remaining, #new_list) do
        table.insert(session, new_list[index])
    end
    meta.new_count = math.min(new_remaining, #new_list)
    return session, meta
end

function Store:ai_roots()
    return AI_ROOTS
end

function Store:ai_path(pack, card)
    local base = pack._path and pack._path:match("([^/]+)%.json$") or pack.title
    local pack_name = sanitize_segment(base)
    if pack_name == "." or pack_name == ".." then pack_name = "pack" end
    local card_name = sanitize_segment(card.id)
    if card_name == "." or card_name == ".." then card_name = "card" end
    for _, root in ipairs(self:ai_roots()) do
        local path = root .. "/" .. pack_name .. "/" .. card_name .. ".json"
        if lfs.attributes(path, "mode") == "file" then
            return path, root
        end
    end
    local preferred = self:ai_roots()[1]
    ensure_directory(preferred .. "/" .. pack_name)
    return preferred .. "/" .. pack_name .. "/" .. card_name .. ".json", preferred
end

function Store:load_ai_history(pack, card)
    local path = self:ai_path(pack, card)
    local contents = read_file(path)
    if not contents or contents == "" then return {} end
    local ok, payload = pcall(JSON.decode, contents)
    if not ok or type(payload) ~= "table" then return {} end
    if type(payload.messages) == "table" then return payload.messages end
    if type(payload) == "table" and payload[1] then return payload end
    return {}
end

function Store:save_ai_history(pack, card, history)
    local path = self:ai_path(pack, card)
    local payload = {
        card_id = card.id,
        updated_at = os.time(),
        messages = history or {},
    }
    return write_file(path, JSON.encode(payload))
end

function Store:clear_ai_history(pack, card)
    local path = self:ai_path(pack, card)
    os.remove(path)
    return true
end

local function walk_ai_files(root, files)
    if not is_directory(root) then return end
    local ok, iterator, directory_object = pcall(lfs.dir, root)
    if not ok or not iterator then return end
    for name in iterator, directory_object do
        if name ~= "." and name ~= ".." then
            local path = root .. "/" .. name
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" then
                walk_ai_files(path, files)
            elseif mode == "file" and name:match("%.json$") then
                local size = lfs.attributes(path, "size") or 0
                local mod = lfs.attributes(path, "modification") or 0
                table.insert(files, { path = path, size = size, modified = mod })
            end
        end
    end
end

function Store:ai_usage()
    local files = {}
    for _, root in ipairs(self:ai_roots()) do
        walk_ai_files(root, files)
    end
    local total = 0
    for _, item in ipairs(files) do total = total + item.size end
    return total, files
end

function Store:cleanup_ai_space(max_bytes)
    max_bytes = max_bytes or AI_MAX_TOTAL_BYTES
    local total, files = self:ai_usage()
    if total <= max_bytes then return 0, total end
    table.sort(files, function(a, b) return a.modified < b.modified end)
    local removed = 0
    for _, item in ipairs(files) do
        if total <= max_bytes then break end
        if os.remove(item.path) then
            total = total - item.size
            removed = removed + 1
        end
    end
    return removed, total
end

Store.Schedule = Schedule
Store.DEFAULT_DAILY_NEW = DEFAULT_DAILY_NEW
Store.MIN_DAILY_NEW = MIN_DAILY_NEW
Store.MAX_DAILY_NEW = MAX_DAILY_NEW
Store.AI_MAX_TOTAL_BYTES = AI_MAX_TOTAL_BYTES

return Store
