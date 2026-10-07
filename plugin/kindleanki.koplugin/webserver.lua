-- Tiny LAN HTTP server that lets a phone or computer browser convert an
-- .apkg in the browser and push the finished pack onto the Kindle.
--
-- The plugin never unpacks Anki files: this server only accepts a finished
-- kindle-anki zip and hands it to Store:import_from_path. Conversion happens
-- entirely inside the visitor's browser (web/apkg.js + web/convert.js).
--
-- Socket posture mirrors the desktop pack server: unauthenticated, home
-- Wi-Fi only, bound to all interfaces on port 8767 (8766 stays the
-- computer-side converter).

local JSON = require("json")
local lfs = require("libs/libkoreader-lfs")
local socket = require("socket")
local UIManager = require("ui/uimanager")

local WebServer = {}
WebServer.__index = WebServer

-- The running server, shared by every KindleAnki plugin instance (main.lua
-- sets it); nil while the import page is closed.
WebServer.active = nil

WebServer.DEFAULT_PORT = 8767
WebServer.MAX_UPLOAD_BYTES = 512 * 1024 * 1024
WebServer.MAX_JSON_BODY = 64 * 1024
WebServer.HEADER_LIMIT = 64 * 1024
WebServer.IDLE_TIMEOUT = 60
-- Browsers open several parallel connections (preconnects, scripts, XHR);
-- handling one at a time starves the rest and stalls every request.
WebServer.MAX_CONNECTIONS = 8
-- A real client sends its request head right after connecting; a connection
-- that stays silent this long is a browser preconnect and must not hold a
-- slot for the full idle timeout.
WebServer.HEAD_TIMEOUT = 15
-- Wrong pairing codes allowed per server run. The code is 4 digits, so an
-- unlimited endpoint falls to a LAN brute force in seconds; once locked,
-- stopping and reopening the page on the Kindle issues a fresh code.
WebServer.MAX_AI_ATTEMPTS = 5
-- Poll every 50ms while a connection is open (large responses go out in
-- many partial sends), but only twice a second while nobody is connected:
-- the page may stay open for hours on a battery-powered e-reader.
WebServer.ACTIVE_POLL = 0.05
WebServer.IDLE_POLL = 0.5
-- Close the page after this long with no connections at all. It has no
-- password, so it should not sit open on the LAN for days.
WebServer.IDLE_STOP_SECONDS = 30 * 60

-- Upload bodies must carry one of these types. A cross-site page can only
-- send text/plain, form, or multipart bodies without a CORS preflight, so
-- requiring a zip type keeps other websites from pushing packs here.
local UPLOAD_CONTENT_TYPES = {
    ["application/zip"] = true,
    ["application/x-zip-compressed"] = true,
    ["application/octet-stream"] = true,
}

-- Suffixes a home router or mDNS hands out. DNS rebinding needs a public
-- name the attacker controls, so public names are refused while IPs,
-- single-label names, and these local suffixes keep working.
local LOCAL_NAME_SUFFIXES = { ".local", ".lan", ".home", ".internal", ".home.arpa" }

local STATIC_FILES = {
    ["/"] = { file = "index.html", type = "text/html; charset=utf-8" },
    ["/index.html"] = { file = "index.html", type = "text/html; charset=utf-8" },
    ["/apkg.js"] = { file = "apkg.js", type = "text/javascript; charset=utf-8" },
    ["/convert.js"] = { file = "convert.js", type = "text/javascript; charset=utf-8" },
    ["/app.js"] = { file = "app.js", type = "text/javascript; charset=utf-8" },
}

local function this_dir()
    -- Resolve this plugin's own folder so the web/ assets can be served
    -- regardless of where KOReader installed the plugin.
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then
        return source:sub(2):match("^(.*)/[^/]+$") or "."
    end
    return "."
end

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

local function basename(path)
    return path:match("([^/]+)$") or path
end

local function usable_ip(ip)
    -- Reject addresses a phone can never reach: loopback, link-local,
    -- 0.0.0.0, and the 192.168.15.x USBNetwork subnet (usb0 on the Kindle
    -- answers there even while Wi-Fi holds the real LAN address).
    if type(ip) ~= "string" then return false end
    if ip == "0.0.0.0" or ip == "" then return false end
    if ip:sub(1, 4) == "127." then return false end
    if ip:sub(1, 8) == "169.254." then return false end
    if ip:sub(1, 11) == "192.168.15." then return false end
    return ip:match("^%d+%.%d+%.%d+%.%d+$") ~= nil
end

local function ifconfig_candidates()
    -- Parse ifconfig into per-interface blocks and prefer the Wi-Fi card:
    -- on the Kindle, usb0 (USBNetwork) often sorts before wlan0, and the
    -- first-match logic used to show the unreachable 192.168.15.244.
    local handle = io.popen("ifconfig 2>/dev/null")
    if not handle then return {} end
    local blocks, current = {}, nil
    for line in handle:lines() do
        if line:sub(1, 1) ~= " " and line:sub(1, 1) ~= "\t" and line ~= "" then
            current = { name = line:match("^(%S+):?") or "?", ip = nil }
            table.insert(blocks, current)
        end
        if current then
            local addr = line:match("inet addr:(%d+%.%d+%.%d+%.%d+)")
                or line:match("inet (%d+%.%d+%.%d+%.%d+)")
            if addr and not current.ip then
                current.ip = addr
            end
        end
    end
    handle:close()
    local wlan, others = {}, {}
    for _, block in ipairs(blocks) do
        if block.ip and usable_ip(block.ip) and block.name ~= "lo" then
            if block.name:sub(1, 4) == "wlan" then
                table.insert(wlan, block.ip)
            elseif block.name:sub(1, 3) ~= "usb" then
                table.insert(others, block.ip)
            end
        end
    end
    local ordered = {}
    for _, ip in ipairs(wlan) do table.insert(ordered, ip) end
    for _, ip in ipairs(others) do table.insert(ordered, ip) end
    return ordered
end

local function detect_ip()
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if ok and NetworkMgr then
        for _, name in ipairs{ "getNetworkIpAddress", "getCurrentIPAddress" } do
            local getter = NetworkMgr[name]
            if type(getter) == "function" then
                local got, ip = pcall(getter, NetworkMgr)
                if got and usable_ip(ip) then
                    return ip
                end
            end
        end
    end
    local candidates = ifconfig_candidates()
    if candidates[1] then
        return candidates[1]
    end
    -- Last resort: ask the routing table which local address points at the
    -- internet; on UDP this binds without sending anything.
    local ok_udp, udp = pcall(socket.udp)
    if ok_udp and udp then
        pcall(function() udp:setpeername("8.8.8.8", 80) end)
        local ip = udp:getsockname()
        pcall(function() udp:close() end)
        if usable_ip(ip) then
            return ip
        end
    end
    return nil
end

local function host_name(value)
    -- "192.168.1.5:8767" -> "192.168.1.5"; "[fe80::1]:8767" -> "fe80::1".
    local text = tostring(value or ""):lower()
    local bracketed = text:match("^%[([^%]]*)%]")
    if bracketed then return bracketed end
    return (text:gsub(":%d*$", ""))
end

local function is_local_host(value)
    local name = host_name(value)
    if name == "" then return false end
    if name:match("^%d+%.%d+%.%d+%.%d+$") or name:find(":", 1, true) then return true end
    if not name:find(".", 1, true) then return true end
    for _, suffix in ipairs(LOCAL_NAME_SUFFIXES) do
        if name:sub(-#suffix) == suffix then return true end
    end
    return false
end

local function origin_host(origin)
    return origin:match("^%a[%w+.-]*://([^/]+)")
end

local function url_decode(value, plus_is_space)
    -- In a query string "+" means space, but that must be applied before
    -- %XX decoding: a literal "+" arrives as %2B and has to stay "+".
    local text = tostring(value or "")
    if plus_is_space then text = text:gsub("+", " ") end
    return (text:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16) or 0)
    end))
end

local function parse_head(head)
    local first_line, rest = head:match("^([^\r\n]*)\r?\n(.*)$")
    first_line = first_line or head
    local method, target = first_line:match("^(%S+)%s+(%S+)%s+HTTP/%S+$")
    if not method or not target then return nil end
    local path, query = target:match("^([^?]*)%??(.*)$")
    local headers = {}
    if rest then
        -- The final header line has no trailing CRLF of its own (it belongs
        -- to the \r\n\r\n terminator), so append one before scanning.
        for line in (rest .. "\n"):gmatch("([^\r\n]*)\r?\n") do
            local key, value = line:match("^([^:]+):%s*(.-)%s*$")
            if key and value then
                local lowered = key:lower()
                if headers[lowered] == nil then
                    headers[lowered] = value
                end
            end
        end
    end
    return {
        method = method,
        path = url_decode(path),
        raw_query = query or "",
        headers = headers,
    }
end

function WebServer:new(options)
    options = options or {}
    return setmetatable({
        store = assert(options.store, "webserver needs a store"),
        web_dir = options.web_dir or (this_dir() .. "/web"),
        port = tonumber(options.port) or WebServer.DEFAULT_PORT,
        version = tostring(options.version or ""),
        on_result = options.on_result,
        on_ai_settings = options.on_ai_settings,
        on_delete_pack = options.on_delete_pack,
        on_idle_stop = options.on_idle_stop,
        ai_code = options.ai_code,
        ai_failures = 0,
        upload_path = options.upload_path,
        running = false,
        server = nil,
        conns = {},
        upload_conn = nil,
    }, self)
end

function WebServer:is_running()
    return self.running
end

function WebServer:start()
    if self.running then return true end
    -- Try IPv4 first: phones reach http://<ipv4>:8767, and IPv6-only wildcard
    -- sockets reject IPv4 connections on systems where v6only defaults on.
    local candidates = {}
    local ok4, tcp4 = pcall(socket.tcp4)
    if ok4 and tcp4 then candidates[#candidates + 1] = tcp4 end
    local ok6, tcp6 = pcall(socket.tcp6)
    if ok6 and tcp6 then candidates[#candidates + 1] = tcp6 end
    if #candidates == 0 then
        local ok, tcp = pcall(socket.tcp)
        if ok and tcp then candidates[#candidates + 1] = tcp end
    end
    if #candidates == 0 then return nil, "no socket support in this KOReader build" end
    for _, tcp in ipairs(candidates) do
        pcall(function() tcp:setoption("reuseaddr", true) end)
        -- Browsers open a handful of parallel connections for the page and
        -- its scripts; a tiny backlog makes them retry with backoff.
        if tcp:bind("*", self.port) and tcp:listen(8) then
            tcp:settimeout(0)
            self.server = tcp
            self.running = true
            self.last_activity = socket.gettime()
            self:schedule_pump()
            return true
        end
        pcall(function() tcp:close() end)
    end
    return nil, "cannot bind port " .. self.port
end

function WebServer:stop()
    self.running = false
    for _, conn in ipairs(self.conns or {}) do
        pcall(function() conn.socket:close() end)
    end
    self.conns = {}
    self.upload_conn = nil
    if self.server then
        pcall(function() self.server:close() end)
        self.server = nil
    end
end

function WebServer:url()
    local ip = detect_ip()
    if ip then
        return string.format("http://%s:%d/", ip, self.port)
    end
    return string.format("http://<kindle-ip>:%d/", self.port)
end

function WebServer:schedule_pump()
    if not self.running then return end
    -- Fast cadence only while serving: a large response over Wi-Fi is sent
    -- in many partial chunks, and each yielded send must not wait long.
    local delay = #self.conns > 0 and WebServer.ACTIVE_POLL or WebServer.IDLE_POLL
    UIManager:scheduleIn(delay, function()
        pcall(function() self:pump() end)
    end)
end

function WebServer:pump()
    if not self.running then return end
    -- Retire connections whose deadline passed: idle browser preconnects,
    -- stalled uploads, dead peers.
    for index = #self.conns, 1, -1 do
        local conn = self.conns[index]
        if socket.gettime() > (conn.deadline or 0) then
            self:drop_connection(conn)
        end
    end
    -- Step ready connections, then keep going while sockets stay ready:
    -- back-to-back partial sends then run within one pump instead of one
    -- chunk per tick. Each handler runs in its own coroutine, so one slow
    -- upload never blocks the other connections.
    for _ = 1, 32 do
        local read_set, write_set = {}, {}
        for _, conn in ipairs(self.conns) do
            if conn.wait then
                if conn.wait.read then table.insert(read_set, conn.socket) end
                if conn.wait.write then table.insert(write_set, conn.socket) end
            end
        end
        if #read_set == 0 and #write_set == 0 then break end
        local readable, writable = socket.select(read_set, write_set, 0)
        local ready = {}
        for _, sock in ipairs(readable or {}) do ready[sock] = true end
        for _, sock in ipairs(writable or {}) do ready[sock] = true end
        local stepped = false
        for index = #self.conns, 1, -1 do
            local conn = self.conns[index]
            if ready[conn.socket] then
                self:step_connection(conn)
                stepped = true
            end
        end
        if not stepped then break end
    end
    -- Keep accepting while under the cap so preconnects cannot starve the
    -- real requests waiting behind them.
    while self.running and self.server and #self.conns < WebServer.MAX_CONNECTIONS do
        local client = self.server:accept()
        if not client then break end
        client:settimeout(0)
        self.last_activity = socket.gettime()
        local conn = {
            socket = client,
            co = coroutine.create(function() return self:handle(client) end),
            wait = { read = true },
            deadline = socket.gettime() + WebServer.HEAD_TIMEOUT,
        }
        table.insert(self.conns, conn)
        self:step_connection(conn)
    end
    if self.running and #self.conns == 0
            and socket.gettime() - (self.last_activity or 0) > WebServer.IDLE_STOP_SECONDS then
        self:stop()
        if self.on_idle_stop then pcall(self.on_idle_stop) end
        return
    end
    if self.running then
        self:schedule_pump()
    end
end

function WebServer:conn_for(client)
    for _, conn in ipairs(self.conns) do
        if conn.socket == client then return conn end
    end
end

function WebServer:drop_connection(conn)
    for index, item in ipairs(self.conns) do
        if item == conn then
            table.remove(self.conns, index)
            break
        end
    end
    if self.upload_conn == conn then
        -- The peer vanished or timed out mid-upload: its partial file would
        -- otherwise sit in the packs folder until the next upload.
        self.upload_conn = nil
        self:remove_upload()
    end
    pcall(function() conn.socket:close() end)
end

function WebServer:step_connection(conn)
    if socket.gettime() > (conn.deadline or 0) then
        self:drop_connection(conn)
        return
    end
    if conn.wait then
        local readable, writable = socket.select(
            conn.wait.read and { conn.socket } or {},
            conn.wait.write and { conn.socket } or {},
            0)
        if conn.wait.read and #(readable or {}) == 0 then return end
        if conn.wait.write and #(writable or {}) == 0 then return end
    end
    conn.wait = nil
    local ok, yielded = coroutine.resume(conn.co)
    if not ok then
        if self.on_result then
            pcall(self.on_result, { ok = false, error = tostring(yielded) })
        end
        self:drop_connection(conn)
        return
    end
    if coroutine.status(conn.co) == "dead" then
        self:drop_connection(conn)
        return
    end
    if type(yielded) == "table" then
        conn.wait = yielded
        if yielded.deadline then conn.deadline = yielded.deadline end
    else
        self:drop_connection(conn)
    end
end

-- Handlers run in a coroutine and yield {read/write = true, deadline = ...}
-- whenever the non-blocking socket would stall; pump resumes them.

local function yield_for(direction, deadline)
    coroutine.yield({ [direction] = true, deadline = deadline })
end

function WebServer:send_all(client, data)
    -- luasocket's send(data, i) returns the index of the LAST byte sent
    -- (and nil, err, last on a stall). Over slow Wi-Fi a large response is
    -- always sent in pieces; resuming from the wrong offset splices HTTP
    -- headers into the middle of script bodies and kills the page.
    local deadline = socket.gettime() + WebServer.IDLE_TIMEOUT
    local offset = 1
    while offset <= #data do
        local sent, err, last = client:send(data, offset)
        if sent then
            offset = sent + 1
            deadline = socket.gettime() + WebServer.IDLE_TIMEOUT
        elseif err == "timeout" or err == "wantwrite" then
            if type(last) == "number" and last >= offset then
                offset = last + 1
                deadline = socket.gettime() + WebServer.IDLE_TIMEOUT
            end
            if socket.gettime() > deadline then return false end
            yield_for("write", deadline)
        else
            return false
        end
    end
    return true
end

function WebServer:remove_upload()
    if self.upload_path then
        pcall(function() os.remove(self.upload_path) end)
    end
end

function WebServer:send_response(client, status, content_type, body)
    local reasons = {
        [200] = "OK", [400] = "Bad Request", [403] = "Forbidden", [404] = "Not Found",
        [405] = "Method Not Allowed", [408] = "Request Timeout",
        [409] = "Conflict", [411] = "Length Required", [413] = "Payload Too Large",
        [415] = "Unsupported Media Type", [429] = "Too Many Requests",
        [431] = "Request Header Fields Too Large",
        [500] = "Internal Server Error",
    }
    local head = string.format(
        "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n",
        status, reasons[status] or "OK", content_type, #body)
    return self:send_all(client, head .. body)
end

function WebServer:send_json(client, status, payload)
    return self:send_response(client, status, "application/json; charset=utf-8",
        JSON.encode(payload))
end

function WebServer:read_head(client)
    -- A real browser sends its request head immediately after connecting;
    -- 15s covers even a slow phone, while silent preconnects get retired.
    local deadline = socket.gettime() + WebServer.HEAD_TIMEOUT
    local buffer = ""
    while true do
        local head_end = buffer:find("\r\n\r\n", 1, true)
        if head_end then
            local request = parse_head(buffer:sub(1, head_end - 1))
            if not request then
                self:send_json(client, 400, { ok = false, error = "malformed request" })
                return nil
            end
            request.body_prefix = buffer:sub(head_end + 4)
            return request
        end
        if #buffer > WebServer.HEADER_LIMIT then
            self:send_json(client, 431, { ok = false, error = "headers too large" })
            return nil
        end
        if socket.gettime() > deadline then return nil end
        local chunk, err, partial = client:receive(8192)
        -- A timeout still carries whatever arrived as `partial` — and when
        -- nothing arrived that partial is the *empty string*, which is
        -- truthy in Lua. Compare lengths, never truthiness, or this loop
        -- busy-spins on EAGAIN instead of yielding.
        buffer = buffer .. (chunk or partial or "")
        if not chunk and err ~= "timeout" and err ~= "wantread" then
            return nil
        end
        if not chunk and #(partial or "") == 0 then
            yield_for("read", deadline)
        end
    end
end

function WebServer:receive_body(client, request)
    -- Uploads share one temp file: a second concurrent upload must not
    -- clobber the first one mid-stream.
    local conn = self:conn_for(client)
    if self.upload_conn ~= nil and self.upload_conn ~= conn then
        self:send_json(client, 409, { ok = false, error = "another upload is in progress" })
        return false
    end
    self.upload_conn = conn
    local length = tonumber(request.headers["content-length"] or "")
    if not length then
        self:send_json(client, 411, { ok = false, error = "content-length required" })
        return false
    end
    if length > WebServer.MAX_UPLOAD_BYTES then
        self:send_json(client, 413, { ok = false, error = "pack is larger than 512 MB" })
        return false
    end
    local path = self.upload_path
    if not path then
        self:send_json(client, 500, { ok = false, error = "no upload path configured" })
        return false
    end
    ensure_directory(path:match("^(.*)/[^/]+$") or path)
    local file, open_err = io.open(path, "wb")
    if not file then
        self:send_json(client, 500, { ok = false, error = tostring(open_err or "cannot write upload") })
        return false
    end
    local deadline = socket.gettime() + WebServer.IDLE_TIMEOUT
    local pending = request.body_prefix or ""
    local written = 0
    while written < length do
        if #pending > 0 then
            local take = math.min(#pending, length - written)
            file:write(pending:sub(1, take))
            written = written + take
            pending = pending:sub(take + 1)
            deadline = socket.gettime() + WebServer.IDLE_TIMEOUT
        else
            local chunk, err, partial = client:receive(65536)
            pending = chunk or partial or ""
            if not chunk and err ~= "timeout" and err ~= "wantread" then
                file:close()
                self:remove_upload()
                return false
            end
            if not chunk and #pending == 0 then
                if socket.gettime() > deadline then
                    file:close()
                    self:remove_upload()
                    self:send_json(client, 408, { ok = false, error = "upload stalled" })
                    return false
                end
                yield_for("read", deadline)
            end
        end
    end
    file:close()
    return true
end

function WebServer:receive_json_body(client, request)
    -- Read a small JSON body into memory (AI settings, not pack uploads).
    local length = tonumber(request.headers["content-length"] or "")
    if not length then
        self:send_json(client, 411, { ok = false, error = "content-length required" })
        return nil
    end
    if length > WebServer.MAX_JSON_BODY then
        self:send_json(client, 413, { ok = false, error = "body is too large" })
        return nil
    end
    local deadline = socket.gettime() + WebServer.IDLE_TIMEOUT
    local buffer = request.body_prefix or ""
    while #buffer < length do
        local chunk, err, partial = client:receive(65536)
        buffer = buffer .. (chunk or partial or "")
        if not chunk and err ~= "timeout" and err ~= "wantread" then
            return nil
        end
        if #buffer < length then
            if socket.gettime() > deadline then
                self:send_json(client, 408, { ok = false, error = "request stalled" })
                return nil
            end
            if not chunk and #(partial or "") == 0 then
                yield_for("read", deadline)
            end
        end
    end
    local ok, payload = pcall(JSON.decode, buffer:sub(1, length))
    if not ok or type(payload) ~= "table" then
        self:send_json(client, 400, { ok = false, error = "body must be a JSON object" })
        return nil
    end
    return payload
end

function WebServer:handle_delete_pack(client, request)
    -- Delete an existing pack by its JSON filename. The name must match a
    -- pack the store itself lists; the store's own guards (library folders
    -- only, JSON only, progress and AI chats cleaned) do the real work.
    local name = self:query_param(request, "name") or ""
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return self:send_json(client, 400, { ok = false, error = "missing pack name" })
    end
    if name:find("[/\\]") or name:find("%.%.") or not name:lower():match("%.json$") then
        return self:send_json(client, 400, { ok = false, error = "invalid pack name" })
    end
    if type(self.on_delete_pack) ~= "function" then
        return self:send_json(client, 500, { ok = false, error = "deletion is not configured" })
    end
    local target
    for _, pack in ipairs(self.store:list() or {}) do
        if basename(pack._path or "") == name then
            target = pack
            break
        end
    end
    if not target then
        return self:send_json(client, 404, { ok = false, error = "no pack named " .. name })
    end
    local ok, result = pcall(self.on_delete_pack, target)
    if not ok or type(result) ~= "table" then
        return self:send_json(client, 500, {
            ok = false, error = tostring(result or "could not delete pack"),
        })
    end
    return self:send_json(client, result.ok and 200 or 400, result)
end

function WebServer:handle_ai_settings(client, request)
    -- Write-only and code-gated: a visitor may replace the Kindle's AI
    -- profile but can never read it back through this page.
    -- JSON only: a cross-site page can POST text/plain without a CORS
    -- preflight, but not application/json, so this keeps other sites the
    -- visitor has open from submitting settings here.
    local content_type = (request.headers["content-type"] or ""):lower()
    if not content_type:match("^application/json") then
        return self:send_json(client, 415, { ok = false, error = "send the settings as application/json" })
    end
    if self.ai_failures >= WebServer.MAX_AI_ATTEMPTS then
        return self:send_json(client, 429, {
            ok = false,
            error = "too many wrong pairing codes; stop and reopen the import page on the Kindle for a new code",
        })
    end
    local code = tostring(self:query_param(request, "code") or "")
    code = code:gsub("^%s+", ""):gsub("%s+$", "")
    if self.ai_code == nil or code == "" or code ~= self.ai_code then
        self.ai_failures = self.ai_failures + 1
        return self:send_json(client, 403, {
            ok = false,
            error = "pairing code mismatch; check the code shown on the Kindle",
        })
    end
    if type(self.on_ai_settings) ~= "function" then
        return self:send_json(client, 500, { ok = false, error = "AI settings are not configured" })
    end
    local payload = self:receive_json_body(client, request)
    if not payload then return end
    local ok, result = pcall(self.on_ai_settings, payload)
    if not ok or type(result) ~= "table" then
        return self:send_json(client, 500, {
            ok = false, error = tostring(result or "could not save AI settings"),
        })
    end
    return self:send_json(client, result.ok and 200 or 400, result)
end

function WebServer:send_file(client, name, content_type)
    local path = self.web_dir .. "/" .. name
    local file = io.open(path, "rb")
    if not file then
        return self:send_json(client, 404, { ok = false, error = "missing web asset " .. name })
    end
    local body = file:read("*a")
    file:close()
    return self:send_response(client, 200, content_type, body or "")
end

function WebServer:query_param(request, key)
    for pair in request.raw_query:gmatch("[^&]+") do
        local name, value = pair:match("^([^=]*)=?(.*)$")
        if url_decode(name, true) == key then
            return url_decode(value, true)
        end
    end
    return nil
end

function WebServer:upload_name(request)
    -- Returns the cleaned pack name, or nil plus the 400 payload. Checked
    -- before the body is read so a refused upload never reaches the disk.
    local name = self:query_param(request, "name") or ""
    name = name:gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return nil, { ok = false, error = "missing pack name" }
    end
    if #name > 160 or name:find("[/\\]") or name:find("%.%.") then
        return nil, { ok = false, error = "invalid pack name" }
    end
    if name:lower():match("%.apkg$") then
        return nil, {
            ok = false,
            error = "pick the .apkg in this page so the browser can convert it; " ..
                "the Kindle only accepts converted .kindle-anki.zip packs",
        }
    end
    return name
end

function WebServer:handle_upload(client, name)
    local pack, err = self.store:import_from_path(self.upload_path)
    self:remove_upload()
    if not pack then
        local result = { ok = false, name = name, error = tostring(err or "import failed") }
        if self.on_result then pcall(self.on_result, result) end
        return self:send_json(client, 400, result)
    end
    local result = {
        ok = true,
        name = name,
        title = tostring(pack.title or name),
        cards = #(pack.cards or {}),
    }
    if self.on_result then pcall(self.on_result, result) end
    return self:send_json(client, 200, result)
end

function WebServer:request_refusal(request)
    -- Returns status and message for a request that must not be served.
    local host = request.headers["host"]
    if host ~= nil and not is_local_host(host) then
        -- A public Host header means a DNS-rebinding page is talking to us
        -- under its own origin; serve nothing to it.
        return 403, "this page only answers on the Kindle's local address"
    end
    if request.method ~= "GET" then
        local origin = request.headers["origin"]
        if origin ~= nil and (origin_host(origin) or ""):lower() ~= tostring(host or ""):lower() then
            return 403, "requests from other websites are refused"
        end
    end
    return nil
end

function WebServer:dispatch(client, request)
    local method = request.method
    if method ~= "GET" and method ~= "POST" and method ~= "DELETE" then
        return self:send_json(client, 405, { ok = false, error = "method not allowed" })
    end
    local refused_status, refusal = self:request_refusal(request)
    if refused_status then
        return self:send_json(client, refused_status, { ok = false, error = refusal })
    end
    if method == "GET" then
        local static = STATIC_FILES[request.path]
        if static then
            return self:send_file(client, static.file, static.type)
        end
        if request.path == "/api/info" then
            return self:send_json(client, 200, {
                ok = true,
                app = "kindle-anki",
                version = self.version,
                ip = detect_ip(),
                port = self.port,
                packs_dir = self.store:pack_dir(),
            })
        end
        if request.path == "/api/packs" then
            local packs = {}
            for _, pack in ipairs(self.store:list() or {}) do
                table.insert(packs, {
                    name = basename(pack._path or ""),
                    title = tostring(pack.title or ""),
                    cards = #(pack.cards or {}),
                })
            end
            return self:send_json(client, 200, { ok = true, packs = packs })
        end
    elseif method == "POST" and request.path == "/api/packs" then
        local name, refusal = self:upload_name(request)
        if not name then return self:send_json(client, 400, refusal) end
        local content_type = (request.headers["content-type"] or ""):lower():match("^%s*([^;%s]+)")
        if not UPLOAD_CONTENT_TYPES[content_type or ""] then
            return self:send_json(client, 415, { ok = false, error = "send the pack as application/zip" })
        end
        if not self:receive_body(client, request) then return end
        return self:handle_upload(client, name)
    elseif method == "POST" and request.path == "/api/ai-settings" then
        return self:handle_ai_settings(client, request)
    elseif method == "DELETE" and request.path == "/api/packs" then
        return self:handle_delete_pack(client, request)
    end
    return self:send_json(client, 404, { ok = false, error = "not found" })
end

function WebServer:handle(client)
    local request = self:read_head(client)
    if not request then return end
    self:dispatch(client, request)
end

WebServer.detect_ip = detect_ip
WebServer.is_local_host = is_local_host

return WebServer
