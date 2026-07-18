-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Julien

--------------------------------------------------------------------------------
-- webdriver_worker.lua — session WebDriver persistante dans un worker Babet
--------------------------------------------------------------------------------

if type(babet) ~= "table" or not babet.workers or not babet.workers.channel then
    error("webdriver_worker: Babet 2.9.0 ou supérieur est requis", 2)
end

local M = { VERSION = "1.0.2" }
local Session = {}
Session.__index = Session
local ElementProxy = {}
ElementProxy.__index = ElementProxy

local source = debug.getinfo(1, "S").source
local MODULE_DIR = "."
if source:sub(1, 1) == "@" then
    local path = source:sub(2)
    if path:sub(1, 1) ~= "/" then
        path = babet.joinPath(babet.currentDir(), path)
    end
    MODULE_DIR = path:match("^(.*)/[^/]+$") or babet.currentDir()
end

local WORKER_OPTIONS = {
    channel_capacity = true,
    command_timeout = true,
    worker_start_timeout = true,
    stop_timeout = true,
}

-- Les channels utilisent une sérialisation structurée qui ne peut pas placer
-- directement nil au milieu d'un tableau. Ce marqueur interne préserve donc
-- fidèlement les arguments et valeurs de retour nil.
local TRANSPORT_NIL_KEY = "__babet_webdriver_internal_nil_7e8f8d7b"
local TRANSPORT_JSON_NULL_KEY = "__babet_webdriver_internal_json_null_29d6a1c4"

local function copy_driver_options(options)
    local driver = {}
    local worker = {}
    if options ~= nil then
        if type(options) ~= "table" then
            error("webdriver_worker.start: options doit être une table", 3)
        end
        for key, value in pairs(options) do
            if WORKER_OPTIONS[key] then worker[key] = value else driver[key] = value end
        end
    end
    return driver, worker
end

local function positive_number(name, value, default)
    if value == nil then return default end
    if type(value) ~= "number" or value ~= value or value <= 0
        or value == math.huge or value == -math.huge then
        error(name .. " doit être un nombre fini strictement positif", 3)
    end
    return value
end

local function positive_integer(name, value, default)
    if value == nil then return default end
    if type(value) ~= "number" or math.type(value) ~= "integer" or value <= 0 then
        error(name .. " doit être un entier strictement positif", 3)
    end
    return value
end

local function prepare_driver_path(options)
    if options.attach or options.driver_path then return true end
    local browser = tostring(options.browser or "firefox"):lower()
    if browser ~= "firefox" and browser ~= "chrome" and browser ~= "chromium" then
        return nil, "webdriver_worker: navigateur inconnu: " .. browser
    end
    local binary = browser == "firefox" and "geckodriver" or "chromedriver"
    local system_path = babet.which(binary)
    if system_path then
        options.driver_path = system_path
        return true
    end
    if options.auto_install == false then
        return true -- webdriver.lua produira le diagnostic normal.
    end
    local manager = require("driver_manager")
    local path, err = manager.install(browser, {
        trust_on_first_use = options.trust_on_first_use == true,
        expected_sha256 = options.expected_sha256,
        platform = options.platform,
        cache = options.cache,
        force = options.force_driver_download == true,
    })
    if not path then return nil, err end
    options.driver_path = path
    return true
end

local WORKER_CODE = [=[
local TRANSPORT_NIL_KEY = "__babet_webdriver_internal_nil_7e8f8d7b"
local TRANSPORT_JSON_NULL_KEY = "__babet_webdriver_internal_json_null_29d6a1c4"
local root = assert(worker.args.root)
package.path = root .. "/?.lua;" .. package.path

local webdriver = require("webdriver")
local commands = assert(worker.channels.commands)
local results = assert(worker.channels.results)

local DRIVER_METHODS = {
    open=true, url=true, title=true, source=true, back=true, forward=true, refresh=true,
    find=true, find_all=true, css=true, xpath=true, id=true, name=true, tag=true,
    exists=true, wait=true, js=true, screenshot=true,
    window=true, windows=true, switch=true, switch_last=true, new_tab=true,
    close_window=true, set_window_rect=true, window_rect=true,
    frame=true, top_frame=true, parent_frame=true,
    alert_text=true, accept_alert=true, dismiss_alert=true, alert_send=true,
    cookies=true, set_cookie=true, delete_cookie=true, clear_cookies=true,
    set_timeouts=true, capabilities=true, port=true, pid=true, log_path=true,
    browser_binary=true, is_running=true,
}

local ELEMENT_METHODS = {
    click=true, clear=true, type=true, text=true, tag=true, rect=true,
    css=true, property=true, dom_attr=true, displayed=true, enabled=true,
    selected=true, attr=true, value=true, submit=true, find=true, find_all=true,
    screenshot=true, element_id=true,
}

local driver, start_err = webdriver.start(worker.args.options)
if not driver then
    results:send({ kind="ready", ok=false, error=tostring(start_err) })
    error(start_err)
end

local function import_value(value, seen)
    if type(value) ~= "table" then return value end
    if value[TRANSPORT_NIL_KEY] == true then return nil end
    if value[TRANSPORT_JSON_NULL_KEY] == true then return babet.json.null end
    if value.__babet_webdriver_element then
        return webdriver.element(driver, value.__babet_webdriver_element)
    end
    seen = seen or {}
    if seen[value] then error("worker webdriver: table cyclique reçue") end
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do out[key] = import_value(child, seen) end
    seen[value] = nil
    return out
end

local function export_value(value, seen)
    if value == nil then return { [TRANSPORT_NIL_KEY] = true } end
    if value == babet.json.null then return { [TRANSPORT_JSON_NULL_KEY] = true } end
    if webdriver.is_element(value) then
        return { __babet_webdriver_element = assert(webdriver.element_id(value)) }
    end
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("worker webdriver: résultat cyclique non transportable") end
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do out[key] = export_value(child, seen) end
    seen[value] = nil
    return out
end

results:send({
    kind = "ready",
    ok = true,
    metadata = {
        port = driver:port(),
        pid = driver:pid(),
        log_path = driver:log_path(),
        capabilities = export_value(driver:capabilities()),
    },
})

while not worker.cancelled() do
    local received, command = commands:recv(0.2)
    if not received then
        if command == "timeout" then
            -- Vérification périodique de l'annulation.
        elseif command == "closed" then
            break
        else
            driver:quit()
            error("worker webdriver: réception: " .. tostring(command))
        end
    elseif command.kind == "stop" then
        local stopped, stop_err = driver:quit()
        results:send({
            kind = "stopped",
            id = command.id,
            ok = stopped == true,
            error = stop_err,
        })
        commands:close()
        return stopped == true
    elseif command.kind == "call" then
        local target
        local allowed
        if command.target == "driver" then
            target = driver
            allowed = DRIVER_METHODS
        elseif command.target == "element" then
            target = webdriver.element(driver, assert(command.element_id))
            allowed = ELEMENT_METHODS
        end

        if not target or not allowed[command.method] then
            results:send({
                kind = "result",
                id = command.id,
                ok = false,
                error = "méthode non autorisée: " .. tostring(command.method),
            })
        else
            local arg_count = command.arg_count or 0
            local args = { n = arg_count }
            for index = 1, arg_count do
                args[index] = import_value(command.args[index])
            end
            local called = table.pack(pcall(
                target[command.method],
                target,
                table.unpack(args, 1, args.n)
            ))
            if not called[1] then
                results:send({
                    kind = "result",
                    id = command.id,
                    ok = false,
                    error = tostring(called[2]),
                })
            elseif called.n >= 3 and called[2] == nil and called[3] ~= nil then
                results:send({
                    kind = "result",
                    id = command.id,
                    ok = false,
                    error = tostring(called[3]),
                    code = called[4],
                })
            else
                local value_count = called.n - 1
                local values = {}
                for index = 1, value_count do
                    values[index] = export_value(called[index + 1])
                end
                results:send({
                    kind = "result",
                    id = command.id,
                    ok = true,
                    value_count = value_count,
                    values = values,
                })
            end
        end
    end
end

driver:quit()
return true
]=]

local function import_parent_value(session, value, seen)
    if type(value) ~= "table" then return value end
    if value[TRANSPORT_NIL_KEY] == true then return nil end
    if value[TRANSPORT_JSON_NULL_KEY] == true then return babet.json.null end
    if value.__babet_webdriver_element then
        return setmetatable({
            session = session,
            element_id_value = value.__babet_webdriver_element,
        }, ElementProxy)
    end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[key] = import_parent_value(session, child, seen) end
    return out
end

local function export_parent_value(value, seen)
    if value == nil then return { [TRANSPORT_NIL_KEY] = true } end
    if value == babet.json.null then return { [TRANSPORT_JSON_NULL_KEY] = true } end
    if type(value) ~= "table" then return value end
    if getmetatable(value) == ElementProxy then
        return { __babet_webdriver_element = value.element_id_value }
    end
    seen = seen or {}
    if seen[value] then
        error("webdriver_worker: table cyclique non transportable", 3)
    end
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do out[key] = export_parent_value(child, seen) end
    seen[value] = nil
    return out
end

function Session:_receive(expected_id, timeout)
    local ok, response = self.results:recv(timeout)
    if not ok then
        return nil, "webdriver_worker: réception: " .. tostring(response)
    end
    if type(response) ~= "table" or response.id ~= expected_id then
        return nil, "webdriver_worker: réponse inattendue ou désynchronisée"
    end
    if not response.ok then
        return nil, "webdriver_worker: " .. tostring(response.error), response.code
    end
    local value_count = response.value_count or 0
    local values = { n = value_count }
    for index = 1, value_count do
        values[index] = import_parent_value(self, response.values[index])
    end
    return table.unpack(values, 1, values.n)
end

function Session:_call(target, element_id, method, ...)
    if self.closed then return nil, "webdriver_worker: session fermée" end
    self.next_id = self.next_id + 1
    local id = self.next_id
    local count = select("#", ...)
    local args = {}
    for index = 1, count do
        args[index] = export_parent_value(select(index, ...))
    end
    local sent, send_err = self.commands:send({
        kind = "call",
        id = id,
        target = target,
        element_id = element_id,
        method = method,
        arg_count = count,
        args = args,
    }, self.command_timeout)
    if not sent then return nil, "webdriver_worker: envoi: " .. tostring(send_err) end
    return self:_receive(id, self.command_timeout)
end

function Session:metadata()
    return self.metadata_value
end

function Session:status()
    return self.job:status()
end

function Session:cancel()
    if self.closed then return true end
    self.commands:close()
    local ok, err = self.job:cancel()
    self.results:close()
    self.closed = true
    if not ok then return nil, "webdriver_worker: annulation: " .. tostring(err) end
    return true
end

function Session:stop(timeout)
    if self.closed then return true end
    timeout = positive_number("webdriver_worker.stop: timeout", timeout, self.stop_timeout)
    self.next_id = self.next_id + 1
    local id = self.next_id
    local sent, send_err = self.commands:send({ kind = "stop", id = id }, timeout)
    if not sent then
        self.job:cancel()
        self.commands:close()
        self.results:close()
        self.closed = true
        return nil, "webdriver_worker: arrêt: " .. tostring(send_err)
    end
    local received, response = self.results:recv(timeout)
    if not received or type(response) ~= "table" or response.id ~= id then
        self.job:cancel()
        self.commands:close()
        self.results:close()
        self.closed = true
        return nil, "webdriver_worker: arrêt sans confirmation: " .. tostring(response)
    end
    self.commands:close()
    local joined, join_value = self.job:join(timeout)
    self.results:close()
    self.closed = true
    if joined == nil then
        self.job:cancel()
        return nil, "webdriver_worker: timeout pendant la terminaison"
    end
    if joined == false then
        return nil, "webdriver_worker: erreur du worker: " .. tostring(join_value)
    end
    if not response.ok then
        return nil, "webdriver_worker: " .. tostring(response.error)
    end
    return true
end

Session.close = Session.stop
Session.__close = function(self) self:stop() end

local DRIVER_METHODS = {
    "open", "url", "title", "source", "back", "forward", "refresh",
    "find", "find_all", "css", "xpath", "id", "name", "tag", "exists", "wait",
    "js", "screenshot", "window", "windows", "switch", "switch_last", "new_tab",
    "close_window", "set_window_rect", "window_rect", "frame", "top_frame",
    "parent_frame", "alert_text", "accept_alert", "dismiss_alert", "alert_send",
    "cookies", "set_cookie", "delete_cookie", "clear_cookies", "set_timeouts",
    "capabilities", "port", "pid", "log_path", "browser_binary", "is_running",
}

for _, method in ipairs(DRIVER_METHODS) do
    Session[method] = function(self, ...)
        return self:_call("driver", nil, method, ...)
    end
end

function ElementProxy:element_id()
    return self.element_id_value
end

local ELEMENT_METHODS = {
    "click", "clear", "type", "text", "tag", "rect", "css", "property",
    "dom_attr", "displayed", "enabled", "selected", "attr", "value", "submit",
    "find", "find_all", "screenshot",
}

for _, method in ipairs(ELEMENT_METHODS) do
    ElementProxy[method] = function(self, ...)
        return self.session:_call("element", self.element_id_value, method, ...)
    end
end

function M.is_element(value)
    return type(value) == "table" and getmetatable(value) == ElementProxy
end

function M.start(options)
    local driver_options, worker_options = copy_driver_options(options)
    local capacity = positive_integer(
        "webdriver_worker.start: channel_capacity",
        worker_options.channel_capacity,
        64
    )
    local command_timeout = positive_number(
        "webdriver_worker.start: command_timeout",
        worker_options.command_timeout,
        120
    )
    local worker_start_timeout = positive_number(
        "webdriver_worker.start: worker_start_timeout",
        worker_options.worker_start_timeout,
        30
    )
    local stop_timeout = positive_number(
        "webdriver_worker.start: stop_timeout",
        worker_options.stop_timeout,
        10
    )

    local prepared, prepare_err = prepare_driver_path(driver_options)
    if not prepared then return nil, prepare_err end

    local commands, command_err = babet.workers.channel({ capacity = capacity })
    if not commands then return nil, "webdriver_worker: channel commandes: " .. tostring(command_err) end
    local results, result_err = babet.workers.channel({ capacity = capacity })
    if not results then
        commands:close()
        return nil, "webdriver_worker: channel résultats: " .. tostring(result_err)
    end

    local job, spawn_err = babet.workers.spawn(WORKER_CODE, {
        root = MODULE_DIR,
        options = driver_options,
    }, {
        channels = {
            commands = commands,
            results = results,
        },
    })
    if not job then
        commands:close(); results:close()
        return nil, "webdriver_worker: création du worker: " .. tostring(spawn_err)
    end

    local received, ready = results:recv(worker_start_timeout)
    if not received or type(ready) ~= "table" or ready.kind ~= "ready" then
        job:cancel(); commands:close(); results:close()
        return nil, "webdriver_worker: démarrage sans réponse: " .. tostring(ready)
    end
    if not ready.ok then
        local joined, worker_err = job:join(1)
        if joined == nil then job:cancel() end
        commands:close(); results:close()
        return nil, "webdriver_worker: " .. tostring(ready.error or worker_err)
    end

    return setmetatable({
        job = job,
        commands = commands,
        results = results,
        metadata_value = ready.metadata or {},
        command_timeout = command_timeout,
        stop_timeout = stop_timeout,
        next_id = 0,
        closed = false,
    }, Session)
end

return M
