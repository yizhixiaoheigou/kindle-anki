#!/usr/bin/env lua
-- Store:load pack validation with KOReader modules stubbed out.
--   lua run_pack_validation.lua <scratch-dir>
-- Packs reach the Kindle over unauthenticated LAN pages, so anything the
-- review UI would crash on must be refused at load time. Exits 0 and prints
-- ALL OK when every scenario passes.

io.stdout:setvbuf("line")

local scratch = arg[1] or error("usage: run_pack_validation.lua <scratch-dir>")
local root = (arg[0] or ""):match("^(.*)/tests/lua_harness/[^/]+$") or "."
package.path = root .. "/plugin/kindleanki.koplugin/?.lua;" .. package.path

local failures = 0
local function check(name, ok)
    print((ok and "ok   " or "FAIL ") .. name)
    if not ok then failures = failures + 1 end
end

-- ------------------------------------------------------------------
-- KOReader stubs. JSON.decode maps a file's text to a fixture table, so
-- fixtures are written as Lua tables instead of JSON text.
-- ------------------------------------------------------------------

local FIXTURES = {}
package.preload["json"] = function()
    return { decode = function(text) return FIXTURES[text] end }
end
package.preload["datastorage"] = function()
    return {
        getDataDir = function() return scratch end,
        getSettingsDir = function() return scratch end,
    }
end
package.preload["luasettings"] = function()
    return { open = function() return { data = {}, readSetting = function(_, _, default) return default end } end }
end
package.preload["libs/libkoreader-lfs"] = function()
    return { attributes = function() return nil end, mkdir = function() return true end }
end
for _, name in ipairs({ "socket.http", "ltn12", "socket", "socketutil" }) do
    package.preload[name] = function() return {} end
end

local Store = dofile(root .. "/plugin/kindleanki.koplugin/store.lua")

local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = deep_copy(item) end
    return copy
end

local function base_pack()
    return {
        format = "kindle-anki",
        version = 1,
        title = "Demo",
        decks = { { id = 1, name = "Deck" } },
        cards = {
            { id = 1, deck_id = 1, type = "short_answer", front = "Q", back = "A",
              expected_answers = { "A" } },
            { id = 2, deck_id = 1, type = "choice", mode = "single", front = "Pick", back = "B",
              options = { "first", "second" }, correct_indices = { 1 } },
            { id = 3, deck_id = 1, type = "choice", mode = "multiple", front = "Pick", back = "A, B",
              options = { "first", "second", "third" }, correct_indices = { 0, 1 } },
        },
    }
end

local store = Store:new({ readSetting = function(_, _, default) return default end })
local counter = 0
local function load(pack)
    counter = counter + 1
    local key = "fixture-" .. counter
    FIXTURES[key] = deep_copy(pack)
    local path = scratch .. "/" .. key .. ".kindle-anki.json"
    local file = assert(io.open(path, "w"))
    file:write(key)
    file:close()
    local ok, loaded, err = pcall(store.load, store, path)
    os.remove(path)
    if not ok then return nil, "validator raised: " .. tostring(loaded) end
    return loaded, err
end

local function accepts(name, mutate)
    local pack = base_pack()
    if mutate then mutate(pack) end
    local loaded, err = load(pack)
    check("accepts " .. name, loaded ~= nil or print("  " .. tostring(err)))
end

local function rejects(name, mutate)
    local pack = base_pack()
    mutate(pack)
    local loaded, err = load(pack)
    check("rejects " .. name, loaded == nil and not tostring(err):find("validator raised", 1, true)
        or print("  " .. tostring(err)))
end

accepts("a well-formed pack")
accepts("a short answer without expected answers", function(pack) pack.cards[1].expected_answers = nil end)

rejects("a string correct index", function(pack) pack.cards[2].correct_indices = { "A" } end)
rejects("a numeric-string correct index", function(pack) pack.cards[2].correct_indices = { "1" } end)
rejects("a fractional correct index", function(pack) pack.cards[2].correct_indices = { 0.5 } end)
rejects("a negative correct index", function(pack) pack.cards[2].correct_indices = { -1 } end)
rejects("an out-of-range correct index", function(pack) pack.cards[2].correct_indices = { 2 } end)
rejects("duplicate correct indices", function(pack) pack.cards[3].correct_indices = { 1, 1 } end)
rejects("two answers on a single choice", function(pack) pack.cards[2].correct_indices = { 0, 1 } end)
rejects("empty correct indices", function(pack) pack.cards[2].correct_indices = {} end)
rejects("a table option", function(pack) pack.cards[2].options = { "first", {} } end)
rejects("a numeric option", function(pack) pack.cards[2].options = { "first", 2 } end)
rejects("expected answers as text", function(pack) pack.cards[1].expected_answers = "A" end)
rejects("a table expected answer", function(pack) pack.cards[1].expected_answers = { {} } end)
rejects("a card that is not an object", function(pack) pack.cards[4] = "card" end)
rejects("a deck that is not an object", function(pack) pack.decks[2] = 7 end)

if failures > 0 then
    print(failures .. " FAILED")
    os.exit(1)
end
print("ALL OK")
