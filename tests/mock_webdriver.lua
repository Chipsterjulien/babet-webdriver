-- SPDX-License-Identifier: GPL-3.0-or-later

local M = {}

local SERVER_CODE = [=[
local json = babet.json
local server = assert(babet.socket.listen("127.0.0.1", 0))
local address = assert(server:sockname())
assert(worker.send(address.port))

local ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"
local SHADOW_KEY = "shadow-6066-11e4-a52e-4f735466cecf"
local current_url = "about:blank"
local current_window = "mock-window-1"
local windows = { "mock-window-1" }
local timeouts = { implicit = 0, pageLoad = 300000, script = 30000 }
local cookies = {
    theme = { name = "theme", value = "light", path = "/" },
}
local window_rect = { x = 10, y = 20, width = 1024, height = 768 }
local alert_text = "Mock alert"
local stopping = false

local function receive_exact(socket, count)
    local chunks, total = {}, 0
    while total < count do
        local chunk, err = socket:recv(count - total, 5)
        assert(chunk, err)
        chunks[#chunks + 1] = chunk
        total = total + #chunk
    end
    return table.concat(chunks)
end

local function reply(socket, status, value)
    local body = assert(json.encode({ value = value }))
    local reason = status == 200 and "OK" or status == 404 and "Not Found" or "Error"
    local response = table.concat({
        ("HTTP/1.1 %d %s\r\n"):format(status, reason),
        "Content-Type: application/json\r\n",
        ("Content-Length: %d\r\n"):format(#body),
        "Connection: close\r\n\r\n",
        body,
    })
    assert(socket:send(response))
end

local function error_value(code, message)
    return { error = code, message = message, stacktrace = "" }
end

local function percent_decode(value)
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function cookie_list()
    local out = {}
    for _, cookie in pairs(cookies) do out[#out + 1] = cookie end
    table.sort(out, function(a, b) return a.name < b.name end)
    return json.as_array(out)
end

local function copy_rect()
    return {
        x = window_rect.x,
        y = window_rect.y,
        width = window_rect.width,
        height = window_rect.height,
    }
end

while not stopping and not worker.cancelled() do
    local client, accept_err = server:accept(0.2)
    if client then
        assert(client:set_timeout(5))
        local request_line, line_err = client:recv_line(5)
        if request_line then
            local method, path = request_line:match("^(%S+)%s+(%S+)%s+HTTP/")
            local length = 0
            while true do
                local line = assert(client:recv_line(5))
                if line == "" then break end
                local name, value = line:match("^([^:]+):%s*(.*)$")
                if name and name:lower() == "content-length" then length = tonumber(value) or 0 end
            end
            local body = length > 0 and receive_exact(client, length) or ""
            local decoded = body ~= "" and json.decode(body) or nil

            local element_suffix = path:match("^/session/mock%-session/element/mock%-element(/.*)$")
            local shadow_suffix = path:match("^/session/mock%-session/shadow/mock%-shadow(/.*)$")
            local cookie_name = path:match("^/session/mock%-session/cookie/(.+)$")

            if method == "GET" and path == "/status" then
                reply(client, 200, { ready = true, message = "mock ready" })
            elseif method == "POST" and path == "/session" then
                reply(client, 200, {
                    sessionId = "mock-session",
                    capabilities = { browserName = "mock", platformName = "linux" },
                })

            elseif method == "POST" and path == "/session/mock-session/url" then
                current_url = decoded and decoded.url or current_url
                reply(client, 200, json.null)
            elseif method == "GET" and path == "/session/mock-session/url" then
                reply(client, 200, current_url)
            elseif method == "GET" and path == "/session/mock-session/title" then
                reply(client, 200, "Mock title")
            elseif method == "GET" and path == "/session/mock-session/source" then
                reply(client, 200, "<html><h1>Mock title</h1></html>")
            elseif method == "POST" and (
                path == "/session/mock-session/back"
                or path == "/session/mock-session/forward"
                or path == "/session/mock-session/refresh"
            ) then
                reply(client, 200, json.null)

            elseif method == "POST" and path == "/session/mock-session/execute/sync" then
                local args = decoded and decoded.args or {}
                if decoded and decoded.script == "return null" then
                    reply(client, 200, json.null)
                elseif decoded and decoded.script == "return arguments[0]" then
                    reply(client, 200, args[1] == nil and json.null or args[1])
                else
                    reply(client, 200, {
                        count = #args,
                        first_is_null = args[1] == json.null,
                        second = args[2],
                        async = false,
                    })
                end
            elseif method == "POST" and path == "/session/mock-session/execute/async" then
                local args = decoded and decoded.args or {}
                if decoded and decoded.script == "arguments[arguments.length - 1](null)" then
                    reply(client, 200, json.null)
                else
                    reply(client, 200, {
                        count = #args,
                        first_is_null = args[1] == json.null,
                        second = args[2],
                        async = true,
                    })
                end

            elseif method == "POST" and path == "/session/mock-session/element" then
                local selector = decoded and decoded.value
                if selector == "#missing" then
                    reply(client, 404, error_value("no such element", "élément absent"))
                else
                    reply(client, 200, { [ELEMENT_KEY] = "mock-element" })
                end
            elseif method == "POST" and path == "/session/mock-session/elements" then
                reply(client, 200, json.as_array({ { [ELEMENT_KEY] = "mock-element" } }))
            elseif method == "GET" and path == "/session/mock-session/element/active" then
                reply(client, 200, { [ELEMENT_KEY] = "mock-element" })

            elseif method == "POST" and element_suffix == "/element" then
                reply(client, 200, { [ELEMENT_KEY] = "mock-element" })
            elseif method == "POST" and element_suffix == "/elements" then
                reply(client, 200, json.as_array({ { [ELEMENT_KEY] = "mock-element" } }))
            elseif method == "POST" and (
                element_suffix == "/click" or element_suffix == "/clear" or element_suffix == "/value"
            ) then
                reply(client, 200, json.null)
            elseif method == "GET" and element_suffix == "/text" then
                reply(client, 200, "Mock element")
            elseif method == "GET" and element_suffix == "/name" then
                reply(client, 200, "input")
            elseif method == "GET" and element_suffix == "/rect" then
                reply(client, 200, { x = 1, y = 2, width = 300, height = 40 })
            elseif method == "GET" and element_suffix == "/computedrole" then
                reply(client, 200, "textbox")
            elseif method == "GET" and element_suffix == "/computedlabel" then
                reply(client, 200, "Mock label")
            elseif method == "GET" and element_suffix == "/shadow" then
                reply(client, 200, { [SHADOW_KEY] = "mock-shadow" })
            elseif method == "GET" and element_suffix == "/displayed" then
                reply(client, 200, true)
            elseif method == "GET" and element_suffix == "/enabled" then
                reply(client, 200, true)
            elseif method == "GET" and element_suffix == "/selected" then
                reply(client, 200, false)
            elseif method == "GET" and element_suffix == "/screenshot" then
                reply(client, 200, assert(babet.base64.encode("PNG-ELEMENT-MOCK\0DATA")))
            elseif method == "GET" and element_suffix and element_suffix:match("^/css/") then
                reply(client, 200, "rgb(0, 0, 0)")
            elseif method == "GET" and element_suffix and element_suffix:match("^/property/") then
                reply(client, 200, "mock-value")
            elseif method == "GET" and element_suffix and element_suffix:match("^/attribute/") then
                reply(client, 200, "mock-attribute")

            elseif method == "POST" and shadow_suffix == "/element" then
                if decoded and decoded.value == "#missing" then
                    reply(client, 404, error_value("no such element", "élément Shadow DOM absent"))
                else
                    reply(client, 200, { [ELEMENT_KEY] = "mock-element" })
                end
            elseif method == "POST" and shadow_suffix == "/elements" then
                reply(client, 200, json.as_array({ { [ELEMENT_KEY] = "mock-element" } }))

            elseif method == "GET" and path == "/session/mock-session/screenshot" then
                reply(client, 200, assert(babet.base64.encode("PNG-MOCK\0DATA")))
            elseif method == "POST" and path == "/session/mock-session/print" then
                local empty = type(decoded) == "table" and next(decoded) == nil
                local valid = empty or (decoded
                    and decoded.orientation == "landscape"
                    and decoded.scale == 0.8
                    and decoded.background == true
                    and decoded.shrinkToFit == false
                    and type(decoded.page) == "table"
                    and decoded.page.width == 21
                    and decoded.page.height == 29.7
                    and type(decoded.margin) == "table"
                    and decoded.margin.top == 1
                    and decoded.margin.bottom == 1.5
                    and decoded.margin.left == 2
                    and decoded.margin.right == 2.5
                    and type(decoded.pageRanges) == "table"
                    and decoded.pageRanges[1] == "1-2"
                    and decoded.pageRanges[2] == 4)
                if valid then
                    reply(client, 200, assert(babet.base64.encode("PDF-MOCK\0DATA")))
                else
                    reply(client, 400, error_value("invalid argument", "paramètres print inattendus"))
                end

            elseif method == "GET" and path == "/session/mock-session/window" then
                reply(client, 200, current_window)
            elseif method == "GET" and path == "/session/mock-session/window/handles" then
                reply(client, 200, json.as_array(windows))
            elseif method == "POST" and path == "/session/mock-session/window" then
                current_window = decoded and decoded.handle or current_window
                reply(client, 200, json.null)
            elseif method == "POST" and path == "/session/mock-session/window/new" then
                local kind = decoded and decoded.type or "window"
                local handle = "mock-window-" .. tostring(#windows + 1)
                windows[#windows + 1] = handle
                reply(client, 200, { handle = handle, type = kind })
            elseif method == "DELETE" and path == "/session/mock-session/window" then
                local remaining = {}
                for _, handle in ipairs(windows) do
                    if handle ~= current_window then remaining[#remaining + 1] = handle end
                end
                windows = remaining
                current_window = windows[#windows] or ""
                reply(client, 200, json.as_array(windows))
            elseif method == "GET" and path == "/session/mock-session/window/rect" then
                reply(client, 200, copy_rect())
            elseif method == "POST" and path == "/session/mock-session/window/rect" then
                for _, key in ipairs({ "x", "y", "width", "height" }) do
                    if decoded and decoded[key] ~= nil then window_rect[key] = decoded[key] end
                end
                reply(client, 200, copy_rect())
            elseif method == "POST" and path == "/session/mock-session/window/maximize" then
                window_rect = { x = 0, y = 0, width = 1920, height = 1080 }
                reply(client, 200, copy_rect())
            elseif method == "POST" and path == "/session/mock-session/window/minimize" then
                window_rect = { x = 0, y = 0, width = 320, height = 200 }
                reply(client, 200, copy_rect())
            elseif method == "POST" and path == "/session/mock-session/window/fullscreen" then
                window_rect = { x = 0, y = 0, width = 1920, height = 1080 }
                reply(client, 200, copy_rect())

            elseif method == "POST" and path == "/session/mock-session/frame" then
                reply(client, 200, json.null)
            elseif method == "POST" and path == "/session/mock-session/frame/parent" then
                reply(client, 200, json.null)

            elseif method == "GET" and path == "/session/mock-session/alert/text" then
                reply(client, 200, alert_text)
            elseif method == "POST" and path == "/session/mock-session/alert/text" then
                alert_text = decoded and decoded.text or ""
                reply(client, 200, json.null)
            elseif method == "POST" and (
                path == "/session/mock-session/alert/accept"
                or path == "/session/mock-session/alert/dismiss"
            ) then
                reply(client, 200, json.null)

            elseif method == "GET" and path == "/session/mock-session/cookie" then
                reply(client, 200, cookie_list())
            elseif method == "GET" and cookie_name ~= nil then
                local name = percent_decode(cookie_name)
                local cookie = cookies[name]
                if cookie then reply(client, 200, cookie)
                else reply(client, 404, error_value("no such cookie", "cookie absent")) end
            elseif method == "POST" and path == "/session/mock-session/cookie" then
                local cookie = decoded and decoded.cookie
                if type(cookie) == "table" and type(cookie.name) == "string" then
                    cookies[cookie.name] = cookie
                    reply(client, 200, json.null)
                else
                    reply(client, 400, error_value("invalid argument", "cookie invalide"))
                end
            elseif method == "DELETE" and cookie_name ~= nil then
                cookies[percent_decode(cookie_name)] = nil
                reply(client, 200, json.null)
            elseif method == "DELETE" and path == "/session/mock-session/cookie" then
                cookies = {}
                reply(client, 200, json.null)

            elseif method == "GET" and path == "/session/mock-session/timeouts" then
                reply(client, 200, timeouts)
            elseif method == "POST" and path == "/session/mock-session/timeouts" then
                for key, value in pairs(decoded or {}) do timeouts[key] = value end
                reply(client, 200, json.null)

            elseif method == "POST" and path == "/session/mock-session/actions" then
                local key_source, pointer_source, wheel
                for _, source in ipairs((decoded and decoded.actions) or {}) do
                    if source.type == "key" then key_source = source
                    elseif source.type == "pointer" then pointer_source = source
                    elseif source.type == "wheel" then wheel = source end
                end
                local key_actions = key_source and key_source.actions or {}
                local pointer_actions = pointer_source and pointer_source.actions or {}
                local lengths_match = #key_actions == #pointer_actions
                if wheel then
                    local wheel_actions = wheel.actions or {}
                    local scroll = wheel_actions[#wheel_actions]
                    local origin = scroll and scroll.origin
                    local valid_origin = type(origin) == "table"
                        and origin[ELEMENT_KEY] == "mock-element"
                    local valid = lengths_match
                        and #wheel_actions == #key_actions
                        and #wheel_actions == 4
                        and scroll and scroll.type == "scroll"
                        and scroll.duration == 25
                        and scroll.x == 3 and scroll.y == 4
                        and scroll.deltaX == 12 and scroll.deltaY == -34
                        and valid_origin
                    if valid then reply(client, 200, json.null)
                    else reply(client, 400, error_value("invalid argument", "source wheel invalide")) end
                elseif key_source and pointer_source and lengths_match then
                    reply(client, 200, json.null)
                else
                    reply(client, 400, error_value("invalid argument", "sources actions invalides"))
                end
            elseif method == "DELETE" and path == "/session/mock-session/actions" then
                reply(client, 200, json.null)

            elseif method == "DELETE" and path == "/session/mock-session" then
                reply(client, 200, json.null)
                stopping = true
            else
                reply(client, 404, error_value("unknown command", method .. " " .. path))
            end
        elseif line_err ~= "closed" then
            client:close()
            server:close()
            error(line_err)
        end
        client:close()
    elseif accept_err ~= "timeout" then
        server:close()
        error(accept_err)
    end
end

server:close()
return true
]=]

function M.start()
    local job, err = babet.workers.spawn(SERVER_CODE)
    if not job then return nil, err end
    local ok, port = job:recv(5)
    if not ok then
        job:cancel()
        return nil, port
    end
    return { job = job, port = port }
end

return M
