-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Julien

--------------------------------------------------------------------------------
-- webdriver_bidi_worker.lua — transport BiDi persistant dans un worker Babet
--------------------------------------------------------------------------------

if type(babet) ~= "table" or not babet.workers or not babet.workers.channel then
    error("webdriver_bidi_worker: Babet 2.22.0 ou supérieur est requis", 2)
end
local major = babet.VERSION_MAJOR or 0
local minor = babet.VERSION_MINOR or 0
if major < 2 or (major == 2 and minor < 22)
    or type(babet.websocket) ~= "table"
    or type(babet.websocket.connect) ~= "function" then
    error("webdriver_bidi_worker: Babet 2.22.0 ou supérieur avec babet.websocket.connect est requis", 2)
end

local M = { VERSION = require("webdriver_version") }
local Session = {}
Session.__index = Session

local source = debug.getinfo(1, "S").source
local MODULE_DIR = "."
if source:sub(1, 1) == "@" then
    local path = source:sub(2)
    if path:sub(1, 1) ~= "/" then path = babet.joinPath(babet.currentDir(), path) end
    MODULE_DIR = path:match("^(.*)/[^/]+$") or babet.currentDir()
end

local WORKER_OPTIONS = {
    channel_capacity = true,
    command_timeout = true,
    worker_start_timeout = true,
    stop_timeout = true,
}

local TRANSPORT_NIL_KEY = "__babet_webdriver_bidi_internal_nil_d9120f"
local TRANSPORT_JSON_NULL_KEY = "__babet_webdriver_bidi_internal_json_null_9c32a1"
local TRANSPORT_JSON_ARRAY_KEY = "__babet_webdriver_bidi_internal_json_array_b71c4e"
local JSON_ARRAY_MT = getmetatable(babet.json.as_array({}))

local function is_json_array(value)
    return JSON_ARRAY_MT ~= nil and rawequal(getmetatable(value), JSON_ARRAY_MT)
end

local function finite_positive(name, value, default)
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

local function copy_options(options)
    local bidi = {}
    local worker = {}
    if options ~= nil then
        if type(options) ~= "table" then error("webdriver_bidi_worker.start: options doit être une table", 3) end
        for key, value in pairs(options) do
            if WORKER_OPTIONS[key] then worker[key] = value else bidi[key] = value end
        end
    end
    return bidi, worker
end

local function export_parent_value(value, seen)
    if value == nil then return { [TRANSPORT_NIL_KEY] = true } end
    if value == babet.json.null then return { [TRANSPORT_JSON_NULL_KEY] = true } end
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("webdriver_bidi_worker: table cyclique non transportable", 3) end
    local json_array = is_json_array(value)
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do out[key] = export_parent_value(child, seen) end
    seen[value] = nil
    if json_array then
        return { [TRANSPORT_JSON_ARRAY_KEY] = true, value = out }
    end
    return out
end

local function import_parent_value(value, seen)
    if type(value) ~= "table" then return value end
    if value[TRANSPORT_NIL_KEY] == true then return nil end
    if value[TRANSPORT_JSON_NULL_KEY] == true then return babet.json.null end
    if value[TRANSPORT_JSON_ARRAY_KEY] == true then
        if type(value.value) ~= "table" then error("webdriver_bidi_worker: marqueur tableau JSON invalide", 3) end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local out = {}
        seen[value] = out
        for key, child in pairs(value.value) do out[key] = import_parent_value(child, seen) end
        return babet.json.as_array(out)
    end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[key] = import_parent_value(child, seen) end
    return out
end

local WORKER_CODE = [=[
local module_dir = worker.args.module_dir
package.path = module_dir .. "/?.lua;" .. package.path

local bidi = require("webdriver_bidi")
local commands = assert(worker.channels.commands)
local results = assert(worker.channels.results)
local NIL_KEY = worker.args.nil_key
local JSON_NULL_KEY = worker.args.json_null_key
local JSON_ARRAY_KEY = worker.args.json_array_key
local JSON_ARRAY_MT = getmetatable(babet.json.as_array({}))

local function is_json_array(value)
    return JSON_ARRAY_MT ~= nil and rawequal(getmetatable(value), JSON_ARRAY_MT)
end

local function import_value(value, seen)
    if type(value) ~= "table" then return value end
    if value[NIL_KEY] == true then return nil end
    if value[JSON_NULL_KEY] == true then return babet.json.null end
    if value[JSON_ARRAY_KEY] == true then
        if type(value.value) ~= "table" then error("worker bidi: marqueur tableau JSON invalide") end
        seen = seen or {}
        if seen[value] then error("worker bidi: table cyclique reçue") end
        seen[value] = true
        local out = {}
        for key, child in pairs(value.value) do out[key] = import_value(child, seen) end
        seen[value] = nil
        return babet.json.as_array(out)
    end
    seen = seen or {}
    if seen[value] then error("worker bidi: table cyclique reçue") end
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do out[key] = import_value(child, seen) end
    seen[value] = nil
    return out
end

local function export_value(value, seen)
    if value == nil then return { [NIL_KEY] = true } end
    if value == babet.json.null then return { [JSON_NULL_KEY] = true } end
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("worker bidi: résultat cyclique non transportable") end
    local json_array = is_json_array(value)
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do out[key] = export_value(child, seen) end
    seen[value] = nil
    if json_array then
        return { [JSON_ARRAY_KEY] = true, value = out }
    end
    return out
end

local client, start_err = bidi.connect(worker.args.url, worker.args.options)
if not client then
    results:send({ kind = "ready", ok = false, error = tostring(start_err) })
    error(start_err)
end

results:send({ kind = "ready", ok = true })

local ALLOWED = {
    call = true,
    status = true,
    subscribe = true,
    unsubscribe = true,
    get_tree = true,
    navigate = true,
    evaluate = true,
    get_realms = true,
    next_event = true,
}

-- babet.websocket est volontairement synchrone. Le worker ne sonde donc jamais
-- le WebSocket de lui-même : il attend une commande parent, puis laisse le
-- client BiDi lire le réseau uniquement pendant cette commande. Cela évite
-- qu'un recv() WebSocket empêche le worker de lire son channel de commandes.
local function next_event_interruptible(timeout)
    timeout = timeout == nil and 0 or timeout
    if type(timeout) ~= "number" or timeout ~= timeout or timeout < 0
        or timeout == math.huge or timeout == -math.huge then
        error("worker bidi: next_event timeout invalide")
    end
    if timeout == 0 then return client:next_event(0) end

    local deadline = babet.monotonic() + timeout
    while not worker.cancelled() do
        local remaining = deadline - babet.monotonic()
        if remaining <= 0 then return nil, "timeout", "timeout" end
        local event, err, code = client:next_event(math.min(remaining, 0.2))
        if event then return event end
        if code ~= "timeout" then return nil, err, code end
    end
    return nil, "worker annulé", "cancelled"
end

while not worker.cancelled() do
    local received, command = commands:recv(0.2)
    if not received then
        if command == "timeout" then
            -- Vérification périodique de l'annulation.
        elseif command == "closed" or command == "cancelled" then
            break
        else
            results:send({
                kind = "fatal",
                error = "réception commandes: " .. tostring(command),
                code = "transport",
            })
            client:close(1000, "command channel error", worker.args.stop_timeout)
            error("worker bidi: réception commandes: " .. tostring(command))
        end
    elseif command.kind == "stop" then
        local ok, err = client:close(1000, "worker stop", worker.args.stop_timeout)
        results:send({ kind = "stopped", id = command.id, ok = ok == true, error = err })
        commands:close()
        return ok == true
    elseif command.kind == "call" then
        if not ALLOWED[command.method] then
            results:send({
                kind = "result", id = command.id, ok = false,
                error = "méthode BiDi non autorisée: " .. tostring(command.method),
            })
        else
            local count = command.arg_count or 0
            local args = { n = count }
            for index = 1, count do args[index] = import_value(command.args[index]) end
            local callable = command.method == "next_event" and next_event_interruptible
                or function(...) return client[command.method](client, ...) end
            local called = table.pack(pcall(callable, table.unpack(args, 1, args.n)))
            if not called[1] then
                results:send({ kind = "result", id = command.id, ok = false, error = tostring(called[2]) })
            elseif called.n >= 3 and called[2] == nil and called[3] ~= nil then
                local code = called[4]
                if code == "transport" or code == "closed" then
                    -- Une coupure WebSocket est globale à la session : elle
                    -- invalide l'appel courant et tous les appels suivants.
                    results:send({
                        kind = "fatal", id = command.id,
                        error = tostring(called[3]), code = code,
                    })
                else
                    results:send({
                        kind = "result", id = command.id, ok = false,
                        error = tostring(called[3]), code = code,
                    })
                end
            else
                local value_count = called.n - 1
                local values = {}
                for index = 1, value_count do values[index] = export_value(called[index + 1]) end
                results:send({
                    kind = "result", id = command.id, ok = true,
                    value_count = value_count, values = values,
                })
            end
        end
    end
end

client:close(1000, "worker cancelled", worker.args.stop_timeout)
return true
]=]

local function remaining_until(deadline)
    local remaining = deadline - babet.monotonic()
    return remaining > 0 and remaining or 0
end

local function receive_matching_response(session, expected_id, timeout)
    local deadline = babet.monotonic() + timeout
    while true do
        local remaining = deadline - babet.monotonic()
        if remaining <= 0 then return nil, "timeout" end
        local ok, response = session.results:recv(remaining)
        if not ok then return nil, response end
        if type(response) ~= "table" then return nil, "réponse inattendue ou désynchronisée" end
        -- fatal décrit l'état du transport entier, pas une réponse RPC : il
        -- doit donc faire échouer immédiatement l'appel courant quel que soit id.
        if response.kind == "fatal" then return response end
        if type(response.id) ~= "number" then return nil, "réponse sans identifiant" end
        if response.id == expected_id then return response end
        if response.id > expected_id then return nil, "réponse future inattendue ou désynchronisée" end
        -- Une commande parent précédente peut avoir expiré : sa réponse tardive
        -- est obsolète et est drainée sans réinitialiser la deadline.
    end
end

function Session:_receive(id, timeout)
    local response, err = receive_matching_response(self, id, timeout)
    if not response then return nil, "webdriver_bidi_worker: réception: " .. tostring(err) end
    if response.kind == "fatal" then
        self.transport_failed = true
        return nil, "webdriver_bidi_worker: " .. tostring(response.error), response.code
    end
    if not response.ok then return nil, "webdriver_bidi_worker: " .. tostring(response.error), response.code end
    local count = response.value_count or 0
    local values = { n = count }
    for index = 1, count do values[index] = import_parent_value(response.values[index]) end
    return table.unpack(values, 1, values.n)
end

function Session:_invoke(method, response_timeout, ...)
    if self.closed then return nil, "webdriver_bidi_worker: session fermée" end
    if self.transport_failed then return nil, "webdriver_bidi_worker: transport BiDi arrêté" end
    response_timeout = finite_positive(
        "webdriver_bidi_worker: timeout de réponse", response_timeout, self.command_timeout)
    self.next_id = self.next_id + 1
    local id = self.next_id
    local count = select("#", ...)
    local args = {}
    for index = 1, count do args[index] = export_parent_value((select(index, ...))) end
    local sent, send_err = self.commands:send({
        kind = "call", id = id, method = method, arg_count = count, args = args,
    }, self.command_timeout)
    if not sent then return nil, "webdriver_bidi_worker: envoi: " .. tostring(send_err) end
    -- Le parent attend au moins aussi longtemps que le client BiDi enfant. Une
    -- seconde de marge couvre uniquement le transport du résultat sur le channel
    -- et n'est jamais réutilisée pour prolonger une commande WebSocket.
    return self:_receive(id, response_timeout + 1)
end

function Session:call(method, params, timeout)
    return self:_invoke("call", timeout, method, params, timeout)
end
function Session:status(timeout) return self:_invoke("status", timeout, timeout) end
function Session:subscribe(events, options, timeout)
    return self:_invoke("subscribe", timeout, events, options, timeout)
end
function Session:unsubscribe(subscriptions, timeout)
    return self:_invoke("unsubscribe", timeout, subscriptions, timeout)
end
function Session:get_tree(options, timeout)
    return self:_invoke("get_tree", timeout, options, timeout)
end
function Session:navigate(context, url, options, timeout)
    return self:_invoke("navigate", timeout, context, url, options, timeout)
end
function Session:evaluate(expression, target, options, timeout)
    return self:_invoke("evaluate", timeout, expression, target, options, timeout)
end
function Session:get_realms(options, timeout)
    return self:_invoke("get_realms", timeout, options, timeout)
end

function Session:next_event(timeout)
    if self.closed then return nil, "webdriver_bidi_worker: session fermée" end
    timeout = timeout == nil and 0 or timeout
    if type(timeout) ~= "number" or timeout ~= timeout or timeout < 0
        or timeout == math.huge or timeout == -math.huge then
        error("webdriver_bidi_worker.next_event(timeout) doit être un nombre fini positif ou nul", 2)
    end
    -- next_event(0) est non bloquant côté WebSocket, mais le parent garde une
    -- petite marge pour le trajet commande -> worker -> résultat.
    local response_timeout = math.max(timeout, 0.001)
    local event, err, code = self:_invoke("next_event", response_timeout, timeout)
    if not event and code == "timeout" then return nil, "timeout", "timeout" end
    return event, err, code
end

function Session:on(method, callback)
    if type(method) ~= "string" or method == "" then error("webdriver_bidi_worker.on(method) invalide", 2) end
    if type(callback) ~= "function" then error("webdriver_bidi_worker.on(callback) doit être une fonction", 2) end
    local callbacks = self.callbacks[method]
    if not callbacks then callbacks = {}; self.callbacks[method] = callbacks end
    callbacks[#callbacks + 1] = callback
    return callback
end

function Session:off(method, callback)
    local callbacks = self.callbacks[method]
    if not callbacks then return false end
    for index = #callbacks, 1, -1 do
        if callbacks[index] == callback then
            table.remove(callbacks, index)
            if #callbacks == 0 then self.callbacks[method] = nil end
            return true
        end
    end
    return false
end

function Session:dispatch(timeout, max_events)
    max_events = positive_integer("webdriver_bidi_worker.dispatch(max_events)", max_events, 1)
    local count = 0
    for index = 1, max_events do
        local event, err, code = self:next_event(index == 1 and timeout or 0)
        if not event then
            if code == "timeout" then return count end
            return nil, err, code
        end
        local groups = { self.callbacks[event.method], self.callbacks["*"] }
        for _, callbacks in ipairs(groups) do
            if callbacks then
                for callback_index = 1, #callbacks do
                    local ok, callback_err = pcall(callbacks[callback_index], event)
                    if not ok then
                        return nil, "webdriver_bidi_worker: callback " .. tostring(event.method)
                            .. ": " .. tostring(callback_err), "callback"
                    end
                end
            end
        end
        count = count + 1
    end
    return count
end

function Session:worker_status() return self.job:status() end
function Session:is_closed() return self.closed end

function Session:close(timeout)
    if self.closed then return true end
    timeout = finite_positive("webdriver_bidi_worker.close(timeout)", timeout, self.stop_timeout)
    local deadline = babet.monotonic() + timeout

    local function finish_cancelled(reason, prefix)
        self.job:cancel()
        local remaining = remaining_until(deadline)
        local joined, join_err
        if remaining > 0 then joined, join_err = self.job:join(remaining) end
        self.commands:close()
        self.results:close()
        self.closed = true
        if joined then return true end
        local detail = reason or join_err or "timeout"
        return nil, prefix .. tostring(detail)
    end

    if self.transport_failed then
        -- Le transport est déjà perdu : le worker ne peut plus effectuer un
        -- arrêt BiDi utile. Annule-le directement au lieu d'attendre en vain
        -- une confirmation de stop sur une connexion morte.
        return finish_cancelled(nil, "webdriver_bidi_worker: arrêt après panne transport: ")
    end
    self.next_id = self.next_id + 1
    local id = self.next_id
    local remaining = remaining_until(deadline)
    if remaining <= 0 then
        return finish_cancelled("timeout", "webdriver_bidi_worker: arrêt: ")
    end
    local sent, send_err = self.commands:send({ kind = "stop", id = id }, remaining)
    if not sent then
        return finish_cancelled(send_err, "webdriver_bidi_worker: arrêt: ")
    end
    remaining = remaining_until(deadline)
    if remaining <= 0 then
        return finish_cancelled("timeout", "webdriver_bidi_worker: arrêt: ")
    end
    local response, receive_err = receive_matching_response(self, id, remaining)
    if not response then
        return finish_cancelled(receive_err, "webdriver_bidi_worker: arrêt: ")
    end
    remaining = remaining_until(deadline)
    if remaining <= 0 then
        return finish_cancelled("timeout", "webdriver_bidi_worker: jointure: ")
    end
    local joined, join_err = self.job:join(remaining)
    self.commands:close()
    self.results:close()
    self.closed = true
    if not joined then return nil, "webdriver_bidi_worker: jointure: " .. tostring(join_err) end
    if not response.ok then return nil, "webdriver_bidi_worker: " .. tostring(response.error) end
    return true
end

function Session:cancel()
    if self.closed then return true end
    self.job:cancel()
    self.commands:close()
    self.results:close()
    self.closed = true
    return true
end

Session.__close = function(self) self:close() end

function M.start(url, options)
    if type(url) ~= "string" or url == "" then error("webdriver_bidi_worker.start: url invalide", 2) end
    local bidi_options, worker_options = copy_options(options)
    local channel_capacity = positive_integer(
        "webdriver_bidi_worker.start(channel_capacity)", worker_options.channel_capacity, 16)
    local command_timeout = finite_positive(
        "webdriver_bidi_worker.start(command_timeout)", worker_options.command_timeout, 30)
    local worker_start_timeout = finite_positive(
        "webdriver_bidi_worker.start(worker_start_timeout)", worker_options.worker_start_timeout, 10)
    local stop_timeout = finite_positive(
        "webdriver_bidi_worker.start(stop_timeout)", worker_options.stop_timeout, 5)
    if bidi_options.command_timeout == nil then bidi_options.command_timeout = command_timeout end
    local commands = assert(babet.workers.channel({ capacity = channel_capacity }))
    local results = assert(babet.workers.channel({ capacity = channel_capacity }))
    local job, spawn_err = babet.workers.spawn(WORKER_CODE, {
        module_dir = MODULE_DIR,
        url = url,
        options = bidi_options,
        nil_key = TRANSPORT_NIL_KEY,
        json_null_key = TRANSPORT_JSON_NULL_KEY,
        json_array_key = TRANSPORT_JSON_ARRAY_KEY,
        stop_timeout = stop_timeout,
    }, { channels = { commands = commands, results = results } })
    if not job then
        commands:close(); results:close()
        return nil, "webdriver_bidi_worker: création du worker: " .. tostring(spawn_err)
    end

    local ok, ready = results:recv(worker_start_timeout)
    if not ok or type(ready) ~= "table" or ready.kind ~= "ready" or not ready.ok then
        job:cancel()
        commands:close(); results:close()
        local details = type(ready) == "table" and ready.error or ready
        return nil, "webdriver_bidi_worker: démarrage: " .. tostring(details or "timeout")
    end

    return setmetatable({
        job = job,
        commands = commands,
        results = results,
        command_timeout = command_timeout,
        stop_timeout = stop_timeout,
        next_id = 0,
        callbacks = {},
        closed = false,
        transport_failed = false,
    }, Session)
end

function M.is_session(value)
    return type(value) == "table" and getmetatable(value) == Session
end

return M
