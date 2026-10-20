#!/usr/bin/env lua
-- AI requests in ai.lua with the network and KOReader modules stubbed.
--   lua run_ai.lua
-- Covers card images that cannot be sent, the text-only retry for models
-- that refuse image parts, and the provider's error text in failures.
-- Exits 0 and prints ALL OK when every scenario passes.

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
-- Stubs
-- ------------------------------------------------------------------

-- JSON without a parser: encode keeps the payload table and hands back a
-- token; decode maps canned body strings to tables.
local payloads = {}
local BODIES = {}
package.preload["json"] = function()
    return {
        encode = function(value)
            table.insert(payloads, value)
            return "payload-" .. #payloads
        end,
        decode = function(text)
            if BODIES[text] == nil then error("not JSON: " .. tostring(text)) end
            return BODIES[text]
        end,
    }
end

-- Each request takes the next scripted { code, body } reply.
local replies = {}
local function fake_request(request)
    local reply = table.remove(replies, 1) or { code = 500, body = "" }
    request.sink(reply.body)
    request.sink(nil)
    return 1, reply.code, {}, "HTTP/1.1 " .. reply.code
end
package.preload["socket.http"] = function() return { request = fake_request } end
package.preload["ssl.https"] = function() return { request = fake_request } end
package.preload["socket"] = function()
    return { skip = function(count, ...) return select(count + 1, ...) end }
end
package.preload["socketutil"] = function()
    return { set_timeout = function() end, reset_timeout = function() end }
end
package.preload["ltn12"] = function()
    return {
        source = { string = function(text) return text end },
        sink = {
            table = function(chunks)
                return function(chunk)
                    if chunk then table.insert(chunks, chunk) end
                    return 1
                end
            end,
        },
    }
end
package.preload["mime"] = function() return { b64 = function() return "QUJD" end } end
package.preload["util"] = function()
    return {
        splitToChars = function(text)
            local chars = {}
            for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do table.insert(chars, char) end
            return chars
        end,
    }
end
package.preload["ffi/util"] = function()
    return { utf8charcode = function(char) return char:byte(1) end }
end

require("i18n").set_locale("en")
local AI = dofile(plugin_dir .. "/ai.lua")

-- ------------------------------------------------------------------
-- Fixtures
-- ------------------------------------------------------------------

local dir = os.tmpname() .. "-kindle-ai"
os.execute("mkdir -p '" .. dir .. "'")
local function write(name, data)
    local file = assert(io.open(dir .. "/" .. name, "wb"))
    file:write(data)
    file:close()
    return dir .. "/" .. name
end
local PNG = "\137PNG\r\n\026\n"
local good = write("good.png", PNG .. "pixels")
local text_file = write("notes.txt", "not an image")
local big = write("big.png", PNG .. string.rep("x", 200))
local missing = dir .. "/missing.png"
AI.MAX_IMAGE_BYTES = 100

local config = { endpoint = "https://api.deepseek.com", model = "deepseek-chat", api_key = "sk-test" }
local card = { type = "short_answer", front = "Q", back = "A" }

BODIES["answer"] = { choices = { { message = { content = "the answer" } } } }
BODIES["no images"] = { error = { message = "unknown variant `image_url`, expected `text`", type = "invalid_request_error" } }
BODIES["long"] = { error = { message = string.rep("e", 300) } }
BODIES["string error"] = { error = "invalid api key" }

local function image_parts(payload)
    local content = payload.messages[2].content
    if type(content) ~= "table" then return 0 end
    return #content - 1
end

local function run(paths, script)
    payloads, replies = {}, script
    return AI:request(config, card, {}, "why?", true, paths)
end

-- ------------------------------------------------------------------
-- Scenarios
-- ------------------------------------------------------------------

local messages, count = AI.build_messages(config, card, {}, "why?", true, { good, text_file, missing, big })
check("unusable images are left out, not fatal", messages ~= nil and count == 1
    and type(messages[2].content) == "table" and #messages[2].content == 2
    and messages[2].content[2].image_url.url:find("^data:image/png;base64,") ~= nil)
messages, count = AI.build_messages(config, card, {}, "why?", true, { missing })
check("no usable image sends plain text", count == 0 and type(messages[2].content) == "string")

local result = run({ good }, { { code = 200, body = "answer" } })
check("a model with vision gets the image once", result.ok and result.text == "the answer"
    and #payloads == 1 and image_parts(payloads[1]) == 1)

result = run({ good }, { { code = 400, body = "no images" }, { code = 200, body = "answer" } })
check("a 400 with images retries once as text", result.ok and result.text == "the answer"
    and #payloads == 2 and image_parts(payloads[1]) == 1 and image_parts(payloads[2]) == 0)

result = run({ good }, { { code = 422, body = "no images" }, { code = 200, body = "answer" } })
check("a 422 with images retries too", result.ok and #payloads == 2)

result = run({ good }, { { code = 400, body = "no images" }, { code = 400, body = "no images" } })
check("a second refusal is not retried again", not result.ok and #payloads == 2)
check("the failure carries the provider's message", result.error
    == "AI request failed (HTTP 400): unknown variant `image_url`, expected `text`")

result = run(nil, { { code = 400, body = "no images" }, { code = 200, body = "answer" } })
check("a text-only request is not retried", not result.ok and #payloads == 1)

result = run({ good }, { { code = 500, body = "answer" } })
check("other errors are not retried", not result.ok and #payloads == 1)

result = run(nil, { { code = 400, body = "long" } })
check("a long provider message is cut to 200 characters", result.error
    == "AI request failed (HTTP 400): " .. string.rep("e", 200) .. "…")

result = run(nil, { { code = 401, body = "string error" } })
check("a plain-string error is shown", result.error == "AI request failed (HTTP 401): invalid api key")

result = run(nil, { { code = 502, body = "<html>Bad gateway</html>" } })
check("a non-JSON error body keeps the plain message", result.error == "AI request failed (HTTP 502)")

os.execute("rm -rf '" .. dir .. "'")
os.remove((dir:gsub("%-kindle%-ai$", "")))

if failures > 0 then
    print(failures .. " FAILED")
    os.exit(1)
end
print("ALL OK")
