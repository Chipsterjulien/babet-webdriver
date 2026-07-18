-- SPDX-License-Identifier: GPL-3.0-or-later

local M = {}

local SERVER_CODE = [=[
local json = babet.json
local server = assert(babet.socket.listen("127.0.0.1", 0))
local address = assert(server:sockname())
assert(worker.send(address.port))

local ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"
local current_url = "about:blank"
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
            elseif method == "POST" and path == "/session/mock-session/frame" then
                reply(client, 200, json.null)
            elseif method == "POST" and path == "/session/mock-session/execute/sync" then
                local args = decoded and decoded.args or {}
                reply(client, 200, {
                    count = #args,
                    first_is_null = args[1] == json.null,
                    second = args[2],
                })
            elseif method == "POST" and path == "/session/mock-session/element" then
                local selector = decoded and decoded.value
                if selector == "#missing" then
                    reply(client, 404, error_value("no such element", "élément absent"))
                else
                    reply(client, 200, { [ELEMENT_KEY] = "mock-element" })
                end
            elseif method == "POST" and path == "/session/mock-session/elements" then
                reply(client, 200, json.as_array({ { [ELEMENT_KEY] = "mock-element" } }))
            elseif method == "GET" and path == "/session/mock-session/element/mock-element/text" then
                reply(client, 200, "Mock element")
            elseif method == "GET" and path == "/session/mock-session/element/mock-element/displayed" then
                reply(client, 200, true)
            elseif method == "GET" and path == "/session/mock-session/element/mock-element/enabled" then
                reply(client, 200, true)
            elseif method == "GET" and path == "/session/mock-session/element/mock-element/selected" then
                reply(client, 200, false)
            elseif method == "GET" and path == "/session/mock-session/screenshot" then
                reply(client, 200, assert(babet.base64.encode("PNG-MOCK\0DATA")))
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
