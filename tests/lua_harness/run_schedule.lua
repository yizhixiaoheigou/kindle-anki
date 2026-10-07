#!/usr/bin/env lua
-- Schedule.today() follows the device's local midnight.
--   TZ=<zone> lua run_schedule.lua <zone>
-- Exits 0 and prints ALL OK when every scenario passes.

io.stdout:setvbuf("line")

local zone = arg[1] or error("usage: TZ=<zone> run_schedule.lua <zone>")
local root = (arg[0] or ""):match("^(.*)/tests/lua_harness/[^/]+$") or "."
local Schedule = dofile(root .. "/plugin/kindleanki.koplugin/schedule.lua")

local failures = 0
local function check(name, ok)
    print((ok and "ok   " or "FAIL ") .. name)
    if not ok then failures = failures + 1 end
end

-- 2026-10-06 23:30:00 UTC.
local base = 1791329400
check("fixture timestamp is 23:30 UTC", os.date("!%Y-%m-%d %H:%M", base) == "2026-10-06 23:30")

if zone == "UTC" then
    check("UTC offset is zero", Schedule.utc_offset(base) == 0)
    check("UTC day matches the epoch day", Schedule.today(base) == math.floor(base / 86400))
elseif zone == "Asia/Shanghai" then
    check("Shanghai offset is +8h", Schedule.utc_offset(base) == 8 * 3600)
    -- 07:30 and 09:00 on 2026-10-07 in Beijing are the same study day...
    check("07:30 and 09:00 share a day", Schedule.today(base) == Schedule.today(base + 90 * 60))
    -- ...and 23:00 to 00:30 crosses into the next one.
    local evening = base + 15 * 3600 + 30 * 60 -- 23:00 Beijing
    check("23:00 and 00:30 are different days", Schedule.today(evening) + 1 == Schedule.today(evening + 90 * 60))
    check("Beijing day is one ahead of UTC at 07:30", Schedule.today(base) == math.floor(base / 86400) + 1)
elseif zone == "America/New_York" then
    check("New York offset is -4h in October (DST)", Schedule.utc_offset(base) == -4 * 3600)
    check("19:30 New York is still the UTC day", Schedule.today(base) == math.floor(base / 86400))
end

if failures > 0 then
    print(failures .. " FAILED")
    os.exit(1)
end
print("ALL OK")
