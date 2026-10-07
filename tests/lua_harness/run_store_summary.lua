#!/usr/bin/env lua
-- Store:deck_summary / Store:pack_summary, the counts the library and deck
-- screens show, with KOReader modules stubbed out.
--   lua run_store_summary.lua
-- Exits 0 and prints ALL OK when every scenario passes.

io.stdout:setvbuf("line")

local root = (arg[0] or ""):match("^(.*)/tests/lua_harness/[^/]+$") or "."
package.path = root .. "/plugin/kindleanki.koplugin/?.lua;" .. package.path

local failures = 0
local function check(name, ok)
    print((ok and "ok   " or "FAIL ") .. name)
    if not ok then failures = failures + 1 end
end

package.preload["json"] = function() return {} end
package.preload["datastorage"] = function()
    return { getDataDir = function() return "/tmp" end, getSettingsDir = function() return "/tmp" end }
end
package.preload["luasettings"] = function() return {} end
package.preload["libs/libkoreader-lfs"] = function() return {} end
for _, name in ipairs({ "socket.http", "ltn12", "socket", "socketutil" }) do
    package.preload[name] = function() return {} end
end

local Store = dofile(root .. "/plugin/kindleanki.koplugin/store.lua")
local Schedule = require("schedule")

local saved = {}
local settings = {
    readSetting = function(_, key, default) if saved[key] ~= nil then return saved[key] end return default end,
    saveSetting = function(self, key, value) saved[key] = value return self end,
    flush = function() end,
}
local store = Store:new(settings)

-- Two decks: deck 1 has 30 cards, deck 2 has 10.
local pack = { _path = "/packs/demo.kindle-anki.json", title = "Demo", decks = {
    { id = 1, name = "One" }, { id = 2, name = "Two" } }, cards = {} }
for id = 1, 40 do
    table.insert(pack.cards, { id = id, deck_id = id <= 30 and 1 or 2, type = "short_answer", front = "q", back = "a" })
end

local summary = store:deck_summary(pack, pack.decks[1])
check("unset quota offers no new cards today", summary.new == 30 and summary.new_today == 0 and summary.today == 0)
check("unset quota is reported as nil", summary.daily_new == nil)

store:set_daily_new(pack, 20)
summary = store:deck_summary(pack, pack.decks[1])
check("quota caps new cards for today", summary.new_today == 20 and summary.today == 20)
check("deck counts its own cards", summary.total == 30)

-- Review 5 new cards in deck 1: they leave "new", and the quota shrinks.
local today = Schedule.today()
for id = 1, 5 do store:record_review(pack, pack.cards[id], "good") end
store:record_review(pack, pack.cards[6], "again")
store:toggle_star(pack, pack.cards[7])
summary = store:deck_summary(pack, pack.decks[1])
check("reviewed cards are no longer new", summary.new == 24)
check("quota left after 6 new cards", summary.new_today == 14)
check("an Again card waits 10 minutes before it is due", summary.due == 0)
check("missed and starred are counted", summary.missed == 1 and summary.starred == 1)
check("today is due plus new", summary.today == 14)

-- A card due yesterday counts as due.
local state = store:card_state(pack, pack.cards[2])
state.due = today - 1
summary = store:deck_summary(pack, pack.decks[1])
check("overdue card is due", summary.due == 1)

local whole = store:pack_summary(pack)
check("pack totals both decks", whole.total == 40 and whole.new == 34)
check("pack applies the shared quota once", whole.new_today == 14)
check("pack today is due plus new", whole.today == 15)

if failures > 0 then
    print(failures .. " FAILED")
    os.exit(1)
end
print("ALL OK")
