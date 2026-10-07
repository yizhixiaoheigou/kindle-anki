#!/usr/bin/env lua
-- Zip-slip and zip-bomb guards in store.lua, with KOReader modules stubbed.
--   lua run_zip_extract.lua <scratch-dir>
-- The scratch dir holds good.zip, slip.zip, and backslash.zip, written by
-- tests/test_kindle_store_lua.py. Exits 0 and prints ALL OK when every
-- scenario passes.

io.stdout:setvbuf("line")

local scratch = arg[1] or error("usage: run_zip_extract.lua <scratch-dir>")
local root = (arg[0] or ""):match("^(.*)/tests/lua_harness/[^/]+$") or "."
package.path = root .. "/plugin/kindleanki.koplugin/?.lua;" .. package.path

local failures = 0
local function check(name, ok)
    print((ok and "ok   " or "FAIL ") .. name)
    if not ok then failures = failures + 1 end
end

local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function exists(path) return os.execute("test -e " .. quote(path)) == true or false end

-- Minimal lfs over the shell: the harness interpreter has no lfs.
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path, key)
            if key ~= "mode" then return nil end
            if os.execute("test -d " .. quote(path)) == true then return "directory" end
            if os.execute("test -f " .. quote(path)) == true then return "file" end
            return nil
        end,
        symlinkattributes = function(path, key)
            if key == "mode" and os.execute("test -L " .. quote(path)) == true then return "link" end
            return nil
        end,
        mkdir = function(path) return os.execute("mkdir -p " .. quote(path)) == true end,
        dir = function(path)
            local handle = io.popen("ls -a " .. quote(path))
            local names = {}
            for line in handle:lines() do table.insert(names, line) end
            handle:close()
            local index = 0
            return function() index = index + 1 return names[index] end
        end,
    }
end
package.preload["json"] = function() return {} end
package.preload["datastorage"] = function()
    return { getDataDir = function() return scratch end, getSettingsDir = function() return scratch end }
end
package.preload["luasettings"] = function() return {} end
for _, name in ipairs({ "socket.http", "ltn12", "socket", "socketutil" }) do
    package.preload[name] = function() return {} end
end

-- A fake ffi/archiver whose "archive" is a Lua list of entries, so the
-- libarchive branch can be exercised without libarchive.
local FAKE_ARCHIVES = {}
local extracted = {}
local FakeArchiver = { Reader = {} }
function FakeArchiver.Reader:new() return setmetatable({}, { __index = FakeArchiver.Reader }) end
function FakeArchiver.Reader:open(path)
    self.entries = FAKE_ARCHIVES[path]
    return self.entries ~= nil
end
function FakeArchiver.Reader:iterate()
    local index = 0
    return function()
        index = index + 1
        return self.entries[index]
    end
end
function FakeArchiver.Reader:extractToPath(key, dest_path)
    table.insert(extracted, { key = key, dest = dest_path })
    return true
end
function FakeArchiver.Reader:close() end

local Store = dofile(root .. "/plugin/kindleanki.koplugin/store.lua")

-- ------------------------------------------------------------------
-- unzip fallback (KOReader before 2025.08 has no ffi/archiver)
-- ------------------------------------------------------------------

package.loaded["ffi/archiver"] = nil
package.preload["ffi/archiver"] = function() error("module 'ffi/archiver' not found") end

local function fresh(name)
    local path = scratch .. "/" .. name
    os.execute("rm -rf " .. quote(path))
    return path
end

local out = fresh("out-good")
check("unzip: good pack extracts", Store._extract_zip(scratch .. "/good.zip", out) == true)
check("unzip: pack json present", exists(out .. "/demo.kindle-anki.json"))
check("unzip: media present", exists(out .. "/demo.kindle-anki.media/a.png"))

out = fresh("out-slip")
check("unzip: ../ entry is refused", Store._extract_zip(scratch .. "/slip.zip", out .. "/inner") == false)
check("unzip: nothing escaped", not exists(out .. "/escape.txt"))
check("unzip: refused zip wrote nothing", not exists(out .. "/inner/ok.txt"))

out = fresh("out-backslash")
check("unzip: backslash entry is refused", Store._extract_zip(scratch .. "/backslash.zip", out) == false)

out = fresh("out-missing")
check("unzip: unreadable zip is refused", Store._extract_zip(scratch .. "/missing.zip", out) == false)

-- busybox has no `unzip -Z1`; names come from `unzip -l` rows.
local busybox = table.concat({
    "Archive:  demo.kindle-anki.zip",
    "  Length     Date   Time    Name",
    " --------    ----   ----    ----",
    "      120  09-15-2026 10:00   demo.kindle-anki.json",
    "     2048  09-15-2026 10:00   demo.kindle-anki.media/a b.png",
    " --------                     -------",
    "     2168                     2 files",
}, "\n")
local names = Store._zip_names_from_listing(busybox)
check("listing: busybox rows parse", #names == 2 and names[1] == "demo.kindle-anki.json"
    and names[2] == "demo.kindle-anki.media/a b.png")

-- ------------------------------------------------------------------
-- ffi/archiver branch
-- ------------------------------------------------------------------

package.loaded["ffi/archiver"] = nil
package.preload["ffi/archiver"] = function() return FakeArchiver end

FAKE_ARCHIVES["fake-good"] = {
    { path = "demo.kindle-anki.json", mode = "file", size = 100 },
    { path = "demo.kindle-anki.media/", mode = "directory", size = 0 },
    { path = "demo.kindle-anki.media/a.png", mode = "file", size = 100 },
    { path = "demo.kindle-anki.media/link", mode = "link", size = 0 },
}
FAKE_ARCHIVES["fake-slip"] = {
    { path = "ok.txt", mode = "file", size = 1 },
    { path = "../escape.txt", mode = "file", size = 1 },
}
FAKE_ARCHIVES["fake-absolute"] = { { path = "/etc/passwd", mode = "file", size = 1 } }
FAKE_ARCHIVES["fake-bomb"] = {
    { path = "a.bin", mode = "file", size = 700 * 1024 * 1024 },
    { path = "b.bin", mode = "file", size = 700 * 1024 * 1024 },
}

out = fresh("out-fake")
extracted = {}
check("archiver: good pack extracts", Store._extract_zip("fake-good", out) == true)
check("archiver: only regular files are written", #extracted == 2
    and extracted[1].dest == out .. "/demo.kindle-anki.json"
    and extracted[2].dest == out .. "/demo.kindle-anki.media/a.png")

for _, name in ipairs({ "fake-slip", "fake-absolute", "fake-bomb" }) do
    extracted = {}
    check("archiver: " .. name .. " is refused", Store._extract_zip(name, fresh("out-" .. name)) == false)
    check("archiver: " .. name .. " wrote nothing", #extracted == 0)
end

if failures > 0 then
    print(failures .. " FAILED")
    os.exit(1)
end
print("ALL OK")
