#!/usr/bin/env lua
-- End-to-end smoke test for webserver.lua with KOReader modules stubbed out.
-- Drives the real luasocket server over a real localhost socket:
--   lua run_webserver.lua <upload-blob-path>
-- Exits 0 and prints ALL OK when every scenario passes.

local socket = require("socket")
-- Line buffering keeps the log tail readable if the run is killed by a timer.
io.stdout:setvbuf("line")

local blob_path = arg[1] or error("usage: run_webserver.lua <upload-blob-path>")

-- ------------------------------------------------------------------
-- KOReader stubs
-- ------------------------------------------------------------------

local PENDING = {}
package.preload["ui/uimanager"] = function()
    return { scheduleIn = function(_, delay, fn) table.insert(PENDING, fn) end }
end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(_, key)
            if key == "mode" then return "directory" end
            return nil
        end,
        mkdir = function() return true end,
        dir = function() return function() return nil end, nil end,
    }
end
package.preload["json"] = function()
    -- Minimal decoder for the harness's own flat test bodies (objects with
    -- string values); the real plugin uses KOReader's json module.
    local function decode(text)
        -- Minimal decoder for the harness's own flat test bodies (objects,
        -- arrays, strings, numbers, booleans, null). Whitespace and commas
        -- are handled separately: swallowing commas in skip_space breaks the
        -- object/array loops, which expect to see them.
        local pos = 1
        local function skip_space()
            while pos <= #text and text:sub(pos, pos):match("%s") do pos = pos + 1 end
        end
        local function parse_value()
            skip_space()
            local char = text:sub(pos, pos)
            if char == "{" then
                pos = pos + 1
                local object = {}
                skip_space()
                if text:sub(pos, pos) == "}" then pos = pos + 1 return object end
                while true do
                    local key = parse_value()
                    skip_space()
                    if text:sub(pos, pos) ~= ":" then error("expected : at " .. pos) end
                    pos = pos + 1
                    object[key] = parse_value()
                    skip_space()
                    local next_char = text:sub(pos, pos)
                    if next_char == "}" then pos = pos + 1 return object end
                    if next_char ~= "," then error("expected , or } at " .. pos) end
                    pos = pos + 1
                end
            elseif char == "[" then
                pos = pos + 1
                local array = {}
                skip_space()
                if text:sub(pos, pos) == "]" then pos = pos + 1 return array end
                while true do
                    array[#array + 1] = parse_value()
                    skip_space()
                    local next_char = text:sub(pos, pos)
                    if next_char == "]" then pos = pos + 1 return array end
                    if next_char ~= "," then error("expected , or ] at " .. pos) end
                    pos = pos + 1
                end
            elseif char == "\"" then
                pos = pos + 1
                local out = {}
                while pos <= #text do
                    local c = text:sub(pos, pos)
                    if c == "\"" then pos = pos + 1 return table.concat(out) end
                    if c == "\\" then
                        local escape = text:sub(pos + 1, pos + 1)
                        pos = pos + 2
                        local mapped = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ["\""] = "\"", ["/"] = "/" }
                        out[#out + 1] = mapped[escape] or error("bad escape at " .. pos)
                    else
                        out[#out + 1] = c
                        pos = pos + 1
                    end
                end
                error("unterminated string")
            elseif text:match("^true", pos) then
                pos = pos + 4 return true
            elseif text:match("^false", pos) then
                pos = pos + 5 return false
            elseif text:match("^null", pos) then
                pos = pos + 4 return nil
            else
                local number = text:match("^-?%d+%.?%d*", pos)
                if not number then error("unexpected character at " .. pos) end
                pos = pos + #number
                return tonumber(number)
            end
        end
        local value = parse_value()
        skip_space()
        if pos <= #text then error("trailing data at " .. pos) end
        return value
    end
    local function encode(value)
        local kind = type(value)
        if kind == "nil" then return "null" end
        if kind == "boolean" then return tostring(value) end
        if kind == "number" then
            if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
                return string.format("%d", value)
            end
            return tostring(value)
        end
        if kind == "string" then
            local escaped = value:gsub('[%c"\\]', function(c)
                if c == '"' then return '\\"' end
                if c == "\\" then return "\\\\" end
                if c == "\n" then return "\\n" end
                if c == "\r" then return "\\r" end
                if c == "\t" then return "\\t" end
                return string.format("\\u%04x", c:byte())
            end)
            return '"' .. escaped .. '"'
        end
        if kind == "table" then
            local count = 0
            for _ in pairs(value) do count = count + 1 end
            if count == 0 then return "{}" end
            if #value == count then
                local parts = {}
                for _, item in ipairs(value) do
                    parts[#parts + 1] = encode(item)
                end
                return "[" .. table.concat(parts, ",") .. "]"
            end
            local parts = {}
            for key, item in pairs(value) do
                parts[#parts + 1] = encode(tostring(key)) .. ":" .. encode(item)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        error("cannot encode " .. kind)
    end
    return { encode = encode, decode = decode }
end

-- ------------------------------------------------------------------
-- Store stub
-- ------------------------------------------------------------------

local blob_file = assert(io.open(blob_path, "rb"))
local expected_blob = blob_file:read("*a")
blob_file:close()

local upload_dir = os.tmpname() .. "-kindle-web"
os.execute("mkdir -p " .. upload_dir)
local imported_path = nil
local imported_bytes = nil

local store = {}
local packs_on_device = {
    { title = "已有卡包", cards = { 1, 2, 3 }, _path = upload_dir .. "/x.json" },
}
function store:list()
    return packs_on_device
end
function store:pack_dir() return upload_dir end
function store:delete_pack(pack)
    for index, item in ipairs(packs_on_device) do
        if item._path == pack._path then
            table.remove(packs_on_device, index)
            return true
        end
    end
    return nil, "pack is not in the library folder"
end
function store:import_from_path(path)
    imported_path = path
    local file = assert(io.open(path, "rb"))
    imported_bytes = file:read("*a")
    file:close()
    return { title = "测试卡包", cards = { 1, 2 } }
end

-- ------------------------------------------------------------------
-- Server under test
-- ------------------------------------------------------------------

local here = arg[0]:match("^(.*)/[^/]+$") or "."
local root = here:match("^(.*)/tests/lua_harness$") or (here .. "/../..")
local WebServer = dofile(root .. "/plugin/kindleanki.koplugin/webserver.lua")

local results = {}
local ai_payloads = {}
local server = WebServer:new{
    store = store,
    port = 18799,
    upload_path = upload_dir .. "/.upload.kindle-anki.zip",
    ai_code = "2468",
    on_delete_pack = function(pack) return store:delete_pack(pack) and { ok = true, title = tostring(pack.title or "") } end,
    on_result = function(result) results[#results + 1] = result end,
    on_ai_settings = function(payload)
        ai_payloads[#ai_payloads + 1] = payload
        local key = payload.api_key or ""
        local masked = key ~= "" and (string.rep("•", math.max(#key - 4, 0)) .. key:sub(-4)) or ""
        return { ok = true, endpoint = payload.endpoint or "", model = payload.model or "", key_masked = masked }
    end,
}
assert(server:start(), "server failed to start")
assert(server:is_running())

-- ------------------------------------------------------------------
-- Drive helpers
-- ------------------------------------------------------------------

local function pump_step()
    local callbacks = PENDING
    PENDING = {}
    for _, fn in ipairs(callbacks) do fn() end
end

local function connect()
    local client = assert(socket.tcp())
    client:settimeout(5)
    assert(client:connect("127.0.0.1", 18799))
    client:settimeout(0)
    return client
end

-- Let the server pump reap a finished connection before the next one dials;
-- the server accepts one connection at a time.
local function reap()
    for _ = 1, 20 do pump_step() end
end

local function response_complete(buffer)
    local head_end = buffer:find("\r\n\r\n", 1, true)
    if not head_end then return false end
    local length = tonumber(buffer:match("Content%-Length: (%d+)") or
        buffer:match("content%-length: (%d+)"))
    if not length then return false end
    return #buffer >= head_end + 3 + length
end

local function drive(client, timeout)
    local buffer = ""
    local started = socket.gettime()
    while not response_complete(buffer) do
        pump_step()
        local readable = socket.select({ client }, nil, 0)
        if readable and #readable > 0 then
            local chunk, err, partial = client:receive(65536)
            buffer = buffer .. (chunk or partial or "")
            if err and err ~= "timeout" and err ~= "wantread" then
                -- Connection: close means a clean shutdown after the body;
                -- only treat it as a failure if the response is incomplete.
                if response_complete(buffer) then break end
                error("client receive failed: " .. tostring(err))
            end
        end
        if socket.gettime() - started > (timeout or 20) then
            error("drive timeout; got " .. #buffer .. " bytes: " .. buffer:sub(1, 200))
        end
        socket.sleep(0.002)
    end
    local head, body = buffer:match("^(.-\r\n\r\n)(.*)$")
    return head, body
end

local function pump_until(predicate, timeout)
    local started = socket.gettime()
    while not predicate() do
        pump_step()
        if socket.gettime() - started > (timeout or 20) then
            error("pump_until timeout")
        end
        socket.sleep(0.002)
    end
end

local failures = {}
local function check(name, condition, detail)
    if condition then
        print("ok   " .. name)
    else
        failures[#failures + 1] = name
        print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
    end
end

-- ------------------------------------------------------------------
-- Scenarios
-- ------------------------------------------------------------------

do
    local client = connect()
    client:send("GET / HTTP/1.1\r\nHost: kindle\r\n\r\n")
    local head, body = drive(client)
    check("GET / is 200 html", head:find("200 OK", 1, true) ~= nil
        and head:find("text/html", 1, true) ~= nil)
    check("GET / serves the page", body:find("Kindle Anki", 1, true) ~= nil)
    client:close()
    reap()
end

local web_dir = root .. "/plugin/kindleanki.koplugin/web"
local function read_repo(name)
    local file = assert(io.open(web_dir .. "/" .. name, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

-- Byte-exact asset checks: a status-200 check once let a corrupted body
-- (HTTP headers spliced mid-file by a bad partial-send resume) pass.
for _, asset in ipairs({ "index.html", "apkg.js", "convert.js", "app.js" }) do
    local client = connect()
    client:send("GET /" .. asset .. " HTTP/1.1\r\nHost: kindle\r\n\r\n")
    local head, body = drive(client)
    local expected = read_repo(asset)
    check("GET /" .. asset .. " is byte-exact",
        head:find("200 OK", 1, true) ~= nil and body == expected,
        (#body) .. " vs " .. (#expected) .. " bytes")
    client:close()
    reap()
end

do
    -- Slow reader: request the largest asset and read it in tiny chunks with
    -- pauses, forcing the server through partial-send resumes.
    local client = connect()
    client:send("GET /convert.js HTTP/1.1\r\nHost: kindle\r\n\r\n")
    local buffer = ""
    local started = socket.gettime()
    while not response_complete(buffer) do
        pump_step()
        local readable = socket.select({ client }, nil, 0)
        if readable and #readable > 0 then
            local chunk, err, partial = client:receive(2048)
            buffer = buffer .. (chunk or partial or "")
            if err and err ~= "timeout" and err ~= "wantread" then break end
        end
        if socket.gettime() - started > 30 then break end
        socket.sleep(0.01)
    end
    local head, body = buffer:match("^(.-\r\n\r\n)(.*)$")
    check("slow-reader convert.js is byte-exact",
        body == read_repo("convert.js"))
    client:close()
    reap()
end

do
    local client = connect()
    client:send("GET /api/info HTTP/1.1\r\nHost: kindle\r\n\r\n")
    local head, body = drive(client)
    check("GET /api/info is 200", head:find("200 OK", 1, true) ~= nil)
    check("api/info identifies the app", body:find("kindle-anki", 1, true) ~= nil)
    check("api/info carries the port", body:find('"port":18799', 1, true) ~= nil)
    local shown_ip = body:match('"ip":"(%d+%.%d+%.%d+%.%d+)"')
    check("api/info shows a reachable ip",
        shown_ip ~= nil
            and shown_ip:sub(1, 4) ~= "127."
            and shown_ip:sub(1, 8) ~= "169.254."
            and shown_ip:sub(1, 11) ~= "192.168.15.",
        shown_ip)
    client:close()
    reap()
end

do
    local client = connect()
    client:send("GET /api/packs HTTP/1.1\r\nHost: kindle\r\n\r\n")
    local head, body = drive(client)
    check("GET /api/packs lists packs", body:find("已有卡包", 1, true) ~= nil)
    client:close()
    reap()
end

do
    local client = connect()
    client:send("GET /nope HTTP/1.1\r\nHost: kindle\r\n\r\n")
    local head = drive(client)
    check("GET /nope is 404", head:find(" 404 ", 1, true) ~= nil)
    client:close()
    reap()
end

do
    -- Full upload: 1 MB blob in one POST; the store stub verifies the bytes.
    local client = connect()
    local encoded_name = "%E6%B5%8B%E8%AF%95%E5%8D%A1%E5%8C%85"
    local head_bytes = "POST /api/packs?name=" .. encoded_name ..
        " HTTP/1.1\r\nHost: kindle\r\nContent-Type: application/zip\r\nContent-Length: "
        .. #expected_blob .. "\r\n\r\n"
    client:settimeout(0)
    assert(client:send(head_bytes))
    local offset = 1
    local started = socket.gettime()
    while offset <= #expected_blob do
        pump_step()
        local _, writable = socket.select(nil, { client }, 0)
        if writable and #writable > 0 then
            local chunk = expected_blob:sub(offset, offset + 131071)
            local sent, err = client:send(chunk)
            if sent then offset = offset + sent end
            if err and err ~= "timeout" and err ~= "wantwrite" then
                error("upload send failed: " .. tostring(err))
            end
        end
        if socket.gettime() - started > 60 then error("upload send timeout") end
        socket.sleep(0.002)
    end
    local head, body = drive(client)
    check("upload stored at the temp path", imported_path ~= nil
        and imported_path:match("%.upload%.kindle%-anki%.zip$") ~= nil)
    check("upload bytes survived the trip", imported_bytes == expected_blob)
    check("upload answered 200", head:find("200 OK", 1, true) ~= nil)
    check("upload response names the pack", body:find("测试卡包", 1, true) ~= nil)
    pump_until(function() return #results > 0 end)
    check("on_result fired with ok", results[1] and results[1].ok == true)
    client:close()
    reap()
end

do
    -- .apkg uploads are refused with a pointer back to the browser page.
    local client = connect()
    local request = "POST /api/packs?name=demo.apkg HTTP/1.1\r\nHost: kindle\r\nContent-Length: 0\r\n\r\n"
    client:settimeout(5)
    assert(client:send(request))
    client:settimeout(0)
    local head, body = drive(client)
    check("apkg upload is rejected", head:find(" 400 ", 1, true) ~= nil)
    check("apkg rejection points at the page",
        body:find("the Kindle only accepts converted", 1, true) ~= nil)
    client:close()
    reap()
end

do
    -- AI settings: wrong pairing code is refused.
    local client = connect()
    local body = '{"endpoint":"https://api.example/v1","api_key":"sk-test-1234"}'
    local request = "POST /api/ai-settings?code=0000 HTTP/1.1\r\nHost: kindle\r\n" ..
        "Content-Type: application/json\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body
    client:settimeout(5)
    assert(client:send(request))
    client:settimeout(0)
    local head = drive(client)
    check("ai-settings wrong code is 403", head:find(" 403 ", 1, true) ~= nil)
    check("ai-settings wrong code saved nothing", #ai_payloads == 0)
    client:close()
    reap()
end

do
    -- AI settings: missing code is refused too.
    local client = connect()
    local request = "POST /api/ai-settings HTTP/1.1\r\nHost: kindle\r\n" ..
        "Content-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"
    client:settimeout(5)
    assert(client:send(request))
    client:settimeout(0)
    local head = drive(client)
    check("ai-settings missing code is 403", head:find(" 403 ", 1, true) ~= nil)
    client:close()
    reap()
end

do
    -- AI settings: the right code saves the payload and returns a masked key.
    local client = connect()
    local body = '{"endpoint":"https://api.example/v1","model":"demo-model","api_key":"sk-test-1234","system_prompt":"Explain clearly."}'
    local request = "POST /api/ai-settings?code=2468 HTTP/1.1\r\nHost: kindle\r\n" ..
        "Content-Type: application/json\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body
    client:settimeout(5)
    assert(client:send(request))
    client:settimeout(0)
    local head, response_body = drive(client)
    check("ai-settings correct code is 200", head:find("200 OK", 1, true) ~= nil)
    check("ai-settings reached the handler", #ai_payloads == 1
        and ai_payloads[1].endpoint == "https://api.example/v1"
        and ai_payloads[1].api_key == "sk-test-1234")
    check("ai-settings response masks the key",
        response_body:find("sk-test", 1, true) == nil
            and response_body:find("••••1234", 1, true) ~= nil)
    client:close()
    reap()
end

do
    -- AI settings: a non-JSON body is a 400, not a crash.
    local client = connect()
    local body = "not-json"
    local request = "POST /api/ai-settings?code=2468 HTTP/1.1\r\nHost: kindle\r\n" ..
        "Content-Type: application/json\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body
    client:settimeout(5)
    assert(client:send(request))
    client:settimeout(0)
    local head = drive(client)
    check("ai-settings invalid JSON is 400", head:find(" 400 ", 1, true) ~= nil)
    client:close()
    reap()
end

do
    -- AI settings: a browser "simple" cross-site POST (text/plain, no
    -- preflight) must not reach the handler even with the right code.
    local client = connect()
    local body = '{"endpoint":"https://attacker.example/v1"}'
    local request = "POST /api/ai-settings?code=2468 HTTP/1.1\r\nHost: kindle\r\n" ..
        "Content-Type: text/plain\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body
    client:settimeout(5)
    assert(client:send(request))
    client:settimeout(0)
    local head = drive(client)
    check("ai-settings non-JSON content type is 415", head:find(" 415 ", 1, true) ~= nil)
    check("ai-settings non-JSON content type saved nothing", #ai_payloads == 1)
    client:close()
    reap()
end

do
    -- Pack management: DELETE removes a listed pack from the store.
    local client = connect()
    local request = "DELETE /api/packs?name=x.json HTTP/1.1\r\nHost: kindle\r\n\r\n"
    client:settimeout(5)
    assert(client:send(request))
    client:settimeout(0)
    local head, body = drive(client)
    check("delete answers 200", head:find("200 OK", 1, true) ~= nil)
    check("delete names the pack", body:find("已有卡包", 1, true) ~= nil)
    check("pack is gone from the list", #store:list() == 0)
    client:close()
    reap()
end

do
    -- A literal "+" arrives as %2B (encodeURIComponent) and must stay "+";
    -- decoding %XX first and "+" afterwards turned "C++" into "C  ".
    table.insert(packs_on_device,
        { title = "C++", cards = { 1 }, _path = upload_dir .. "/C++ basics.json" })
    local client = connect()
    local request = "DELETE /api/packs?name=C%2B%2B%20basics.json HTTP/1.1\r\nHost: kindle\r\n\r\n"
    client:settimeout(5)
    assert(client:send(request))
    client:settimeout(0)
    local head = drive(client)
    check("delete of a name with + is 200", head:find("200 OK", 1, true) ~= nil, head)
    check("pack with + is gone", #store:list() == 0)
    client:close()
    reap()
end

do
    -- An upload with a bad name is refused before its body touches disk.
    local client = connect()
    -- Head only: the server must answer from the name alone, without
    -- waiting for (or storing) the promised body.
    local request = "POST /api/packs?name=a%2Fb.zip HTTP/1.1\r\nHost: kindle\r\n" ..
        "Content-Type: application/zip\r\nContent-Length: 4096\r\n\r\n"
    client:settimeout(5)
    assert(client:send(request))
    client:settimeout(0)
    local head = drive(client)
    check("upload with a bad name is 400", head:find(" 400 ", 1, true) ~= nil)
    check("upload with a bad name leaves no temp file",
        io.open(upload_dir .. "/.upload.kindle-anki.zip", "rb") == nil)
    client:close()
    reap()
end

do
    -- Pack management: unknown or unsafe names are refused.
    local client = connect()
    local request = "DELETE /api/packs?name=missing.json HTTP/1.1\r\nHost: kindle\r\n\r\n"
    client:settimeout(5)
    assert(client:send(request))
    client:settimeout(0)
    local head = drive(client)
    check("delete of unknown pack is 404", head:find(" 404 ", 1, true) ~= nil)
    client:close()
    reap()
end

do
    local client = connect()
    local request = "DELETE /api/packs?name=..%2Fsecret HTTP/1.1\r\nHost: kindle\r\n\r\n"
    client:settimeout(5)
    assert(client:send(request))
    client:settimeout(0)
    local head = drive(client)
    check("delete with path traversal is 400", head:find(" 400 ", 1, true) ~= nil)
    client:close()
    reap()
end

do
    -- A browser preconnect (TCP open, no data) must not starve real
    -- requests: the one-connection-at-a-time design stalled everything
    -- behind an idle connection until its timeout.
    local idle = connect()
    local real = connect()
    real:settimeout(0)
    assert(real:send("GET /api/info HTTP/1.1\r\nHost: kindle\r\n\r\n"))
    local ok, head = pcall(function() return drive(real, 6) end)
    check("real request served while a preconnect idles",
        ok and head:find("200 OK", 1, true) ~= nil)
    real:close()
    idle:close()
    reap()
end

do
    -- Two concurrent requests both complete.
    local one = connect()
    local two = connect()
    one:settimeout(0)
    two:settimeout(0)
    assert(one:send("GET /api/info HTTP/1.1\r\nHost: kindle\r\n\r\n"))
    assert(two:send("GET /api/packs HTTP/1.1\r\nHost: kindle\r\n\r\n"))
    local ok_one, head_one = pcall(function() return drive(one, 10) end)
    local ok_two, head_two = pcall(function() return drive(two, 10) end)
    check("first concurrent request served",
        ok_one and head_one:find("200 OK", 1, true) ~= nil)
    check("second concurrent request served",
        ok_two and head_two:find("200 OK", 1, true) ~= nil)
    one:close()
    two:close()
    reap()
end

do
    -- A stalled upload (content-length promised, body never finished) must
    -- not block other connections either.
    local stalled = connect()
    local partial = "POST /api/packs?name=stalled HTTP/1.1\r\nHost: kindle\r\n" ..
        "Content-Length: 4096\r\n\r\nonly-16-bytes"
    stalled:settimeout(0)
    assert(stalled:send(partial))
    local other = connect()
    other:settimeout(0)
    assert(other:send("GET /api/info HTTP/1.1\r\nHost: kindle\r\n\r\n"))
    local ok, head = pcall(function() return drive(other, 6) end)
    check("request served while an upload stalls",
        ok and head:find("200 OK", 1, true) ~= nil)
    other:close()
    stalled:close()
    reap()
end

do
    -- Pairing-code brute force: after MAX_AI_ATTEMPTS wrong codes (two were
    -- spent above) the endpoint locks, even for the right code.
    local function post_code(code)
        local client = connect()
        local body = '{"endpoint":"https://attacker.example/v1"}'
        local request = "POST /api/ai-settings?code=" .. code .. " HTTP/1.1\r\nHost: kindle\r\n" ..
            "Content-Type: application/json\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body
        client:settimeout(5)
        assert(client:send(request))
        client:settimeout(0)
        local head = drive(client)
        client:close()
        reap()
        return head
    end
    check("lockout limit is 5", WebServer.MAX_AI_ATTEMPTS == 5)
    for code = 1, 3 do
        check("wrong code " .. code .. " is still 403",
            post_code(string.format("%04d", code)):find(" 403 ", 1, true) ~= nil)
    end
    check("sixth wrong code is 429", post_code("0004"):find(" 429 ", 1, true) ~= nil)
    check("right code after lockout is 429", post_code("2468"):find(" 429 ", 1, true) ~= nil)
    check("lockout saved nothing", #ai_payloads == 1)
end

do
    -- A rejected or abandoned upload must not leave its temp file behind.
    local file = assert(io.open(upload_dir .. "/.upload.kindle-anki.zip", "wb"))
    file:write("partial")
    file:close()
    local stalled = connect()
    stalled:settimeout(0)
    assert(stalled:send("POST /api/packs?name=gone.zip HTTP/1.1\r\nHost: kindle\r\n" ..
        "Content-Length: 4096\r\n\r\nonly-some-bytes"))
    pump_until(function() return server.upload_conn ~= nil end, 5)
    stalled:close()
    pump_until(function() return server.upload_conn == nil end, 5)
    check("abandoned upload removes its temp file",
        io.open(upload_dir .. "/.upload.kindle-anki.zip", "rb") == nil)
end

server:stop()
check("server stops", not server:is_running())

if #failures > 0 then
    print(table.concat(failures, "\n"))
    os.exit(1)
end
print("ALL OK")
