-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Julien

--------------------------------------------------------------------------------
-- webdriver_bidi.lua — transport WebDriver BiDi pour Babet 2.22+
--------------------------------------------------------------------------------

local function require_babet_22()
    if type(babet) ~= "table" then
        error("webdriver_bidi: ce module doit être exécuté avec Babet", 2)
    end
    local major = babet.VERSION_MAJOR or 0
    local minor = babet.VERSION_MINOR or 0
    if major < 2 or (major == 2 and minor < 22) then
        error(("webdriver_bidi: Babet 2.22.0 ou supérieur est requis (version détectée : %s)")
            :format(tostring(babet.VERSION or "inconnue")), 2)
    end
    if type(babet.websocket) ~= "table" or type(babet.websocket.connect) ~= "function" then
        error("webdriver_bidi: babet.websocket.connect indisponible", 2)
    end
end

require_babet_22()

local json = assert(babet.json, "webdriver_bidi: module babet.json indisponible")
local VERSION = require("webdriver_version")

local M = { VERSION = VERSION }
local Client = {}
Client.__index = Client

local CONNECT_OPTIONS = {
    timeout = true,
    verify = true,
    ca_cert = true,
    ca_path = true,
    hostname = true,
    min_version = true,
    max_message_bytes = true,
    max_frame_bytes = true,
    command_timeout = true,
    close_timeout = true,
    event_queue_limit = true,
}

local SUBSCRIBE_OPTIONS = { contexts = true, user_contexts = true }
local TREE_OPTIONS = { max_depth = true, root = true }
local NAVIGATE_OPTIONS = { wait = true }
local EVALUATE_OPTIONS = {
    await_promise = true,
    result_ownership = true,
    serialization_options = true,
    user_activation = true,
}
local REALMS_OPTIONS = { context = true, type = true }

local function fail(message, code)
    return nil, "webdriver_bidi: " .. tostring(message), code
end

local function strict_table(name, value, allowed)
    if value == nil then return {} end
    if type(value) ~= "table" then error(name .. " doit être une table", 3) end
    for key in next, value do
        if type(key) ~= "string" or not allowed[key] then
            error(("%s : option inconnue %q"):format(name, tostring(key)), 3)
        end
    end
    return value
end

local function finite_nonnegative(name, value, default)
    if value == nil then return default end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge
        or value < 0 then
        error(name .. " doit être un nombre fini positif ou nul", 3)
    end
    return value
end

local function finite_positive(name, value, default)
    value = finite_nonnegative(name, value, default)
    if value <= 0 then error(name .. " doit être strictement positif", 3) end
    return value
end

local function positive_integer(name, value, default)
    if value == nil then return default end
    if type(value) ~= "number" or math.type(value) ~= "integer" or value <= 0 then
        error(name .. " doit être un entier strictement positif", 3)
    end
    return value
end

local function nonnegative_integer(name, value, default)
    if value == nil then return default end
    if type(value) ~= "number" or math.type(value) ~= "integer" or value < 0 then
        error(name .. " doit être un entier positif ou nul", 3)
    end
    return value
end

local function optional_boolean(name, value)
    if value ~= nil and type(value) ~= "boolean" then
        error(name .. " doit être un booléen", 3)
    end
    return value
end

local function nonempty_string(name, value)
    if type(value) ~= "string" or value == "" then
        error(name .. " doit être une chaîne non vide", 3)
    end
    return value
end

local function optional_nonempty_string(name, value)
    if value ~= nil then return nonempty_string(name, value) end
    return nil
end

local function dense_array(values, name)
    if type(values) ~= "table" then error(name .. " doit être un tableau", 3) end
    local count = 0
    for key in next, values do
        if type(key) ~= "number" or math.type(key) ~= "integer" or key < 1 then
            error(name .. " doit être un tableau dense", 3)
        end
        count = count + 1
    end
    local out = {}
    for index = 1, count do
        local value = rawget(values, index)
        if value == nil then error(name .. " doit être un tableau dense", 3) end
        out[index] = value
    end
    return out
end

local function string_array(value, name)
    local values
    if type(value) == "string" then
        values = { value }
    else
        values = dense_array(value, name)
    end
    if #values == 0 then error(name .. " ne doit pas être vide", 3) end
    for index = 1, #values do
        nonempty_string(("%s[%d]"):format(name, index), values[index])
    end
    return json.as_array(values)
end

local function deadline_after(timeout)
    return babet.monotonic() + timeout
end

local function remaining(deadline)
    local value = deadline - babet.monotonic()
    if value <= 0 then return 0 end
    return value
end

local function format_remote_error(message)
    local code = tostring(message.error or "unknown error")
    local text = tostring(message.message or "")
    local details = "webdriver_bidi: " .. code
    if text ~= "" then details = details .. ": " .. text end
    return details, code
end

local function overflow_event(count)
    return {
        type = "event",
        method = "babetWebDriver.eventOverflow",
        params = { dropped = count },
    }
end

function Client:_event_count()
    if self.event_tail < self.event_head then return 0 end
    return self.event_tail - self.event_head + 1
end

function Client:_queue_event(event)
    if self:_event_count() >= self.event_queue_limit then
        self.dropped_events = self.dropped_events + 1
        return false
    end
    self.event_tail = self.event_tail + 1
    self.event_queue[self.event_tail] = event
    return true
end

function Client:_pop_event()
    if self.event_tail >= self.event_head then
        local event = self.event_queue[self.event_head]
        self.event_queue[self.event_head] = nil
        self.event_head = self.event_head + 1
        if self.event_head > self.event_tail then
            self.event_head = 1
            self.event_tail = 0
        end
        return event
    end
    if self.dropped_events > 0 then
        local count = self.dropped_events
        self.dropped_events = 0
        return overflow_event(count)
    end
    return nil
end

function Client:_read(timeout)
    if self.closed then return fail("connexion fermée", "closed") end
    local message, recv_err = self.transport:recv(timeout)
    if not message then
        return nil, tostring(recv_err), recv_err == "timeout" and "timeout" or "transport"
    end
    if message.type == "close" then
        self.closed = true
        local suffix = ""
        if message.code then suffix = " (code " .. tostring(message.code) .. ")" end
        if message.reason and message.reason ~= "" then suffix = suffix .. ": " .. tostring(message.reason) end
        return fail("connexion fermée par le serveur" .. suffix, "closed")
    end
    if message.type ~= "text" then
        return fail("message WebSocket binaire inattendu", "invalid response")
    end
    local decoded, decode_err = json.decode(message.data)
    if not decoded then return fail("JSON BiDi invalide: " .. tostring(decode_err), "invalid response") end
    if type(decoded) ~= "table" then return fail("message BiDi non objet", "invalid response") end
    return decoded
end

function Client:_receive_response(expected_id, deadline)
    while true do
        local wait = remaining(deadline)
        if wait <= 0 then return nil, "webdriver_bidi: timeout", "timeout" end
        local message, err, code = self:_read(wait)
        if not message then return nil, err, code end

        if message.type == "event" then
            if type(message.method) ~= "string" or type(message.params) ~= "table" then
                return fail("événement BiDi mal formé", "invalid response")
            end
            self:_queue_event(message)
        elseif message.type == "success" or message.type == "error" then
            if type(message.id) ~= "number" or math.type(message.id) ~= "integer" or message.id < 0 then
                return fail("identifiant de réponse BiDi invalide", "invalid response")
            end
            if message.id == expected_id then
                if message.type == "error" then
                    local details, remote_code = format_remote_error(message)
                    return nil, details, remote_code
                end
                if rawget(message, "result") == nil then
                    return fail("réponse BiDi success sans result", "invalid response")
                end
                return message.result
            elseif message.id > expected_id then
                return fail("réponse BiDi future inattendue", "invalid response")
            end
            -- Réponse tardive d'une commande qui a expiré côté client : elle est
            -- obsolète et doit être drainée sans modifier la deadline courante.
        else
            return fail("type de message BiDi inattendu: " .. tostring(message.type), "invalid response")
        end
    end
end

function Client:call(method, params, timeout)
    if self.closed then return fail("connexion fermée", "closed") end
    nonempty_string("webdriver_bidi.call(method)", method)
    if params == nil then params = {} end
    if type(params) ~= "table" then error("webdriver_bidi.call(params) doit être une table", 2) end
    timeout = finite_positive("webdriver_bidi.call(timeout)", timeout, self.command_timeout)

    self.next_id = self.next_id + 1
    local id = self.next_id
    local payload, encode_err = json.encode({ id = id, method = method, params = params })
    if not payload then return fail("encodage JSON: " .. tostring(encode_err), "json encode") end

    local deadline = deadline_after(timeout)
    local sent, send_err = self.transport:send_text(payload, remaining(deadline))
    if not sent then return fail("envoi WebSocket: " .. tostring(send_err), "transport") end
    return self:_receive_response(id, deadline)
end

function Client:status(timeout)
    return self:call("session.status", {}, timeout)
end

function Client:subscribe(events, options, timeout)
    options = strict_table("webdriver_bidi.subscribe(opts)", options, SUBSCRIBE_OPTIONS)
    local params = { events = string_array(events, "webdriver_bidi.subscribe(events)") }
    if options.contexts ~= nil then
        params.contexts = string_array(options.contexts, "webdriver_bidi.subscribe(contexts)")
    end
    if options.user_contexts ~= nil then
        params.userContexts = string_array(options.user_contexts, "webdriver_bidi.subscribe(user_contexts)")
    end
    local result, err, code = self:call("session.subscribe", params, timeout)
    if not result then return nil, err, code end
    -- Le standard WebDriver BiDi impose `subscription` dans
    -- session.SubscribeResult. Son absence est donc une réponse invalide, pas
    -- une compatibilité permissive à accepter silencieusement.
    if type(result.subscription) ~= "string" or result.subscription == "" then
        return fail("session.subscribe sans identifiant de souscription", "invalid response")
    end
    return result.subscription
end

function Client:unsubscribe(subscriptions, timeout)
    local params = { subscriptions = string_array(subscriptions, "webdriver_bidi.unsubscribe(subscriptions)") }
    return self:call("session.unsubscribe", params, timeout)
end

function Client:get_tree(options, timeout)
    options = strict_table("webdriver_bidi.get_tree(opts)", options, TREE_OPTIONS)
    local params = {}
    if options.max_depth ~= nil then
        params.maxDepth = nonnegative_integer("webdriver_bidi.get_tree(max_depth)", options.max_depth)
    end
    if options.root ~= nil then
        params.root = nonempty_string("webdriver_bidi.get_tree(root)", options.root)
    end
    return self:call("browsingContext.getTree", params, timeout)
end

function Client:navigate(context, url, options, timeout)
    nonempty_string("webdriver_bidi.navigate(context)", context)
    nonempty_string("webdriver_bidi.navigate(url)", url)
    options = strict_table("webdriver_bidi.navigate(opts)", options, NAVIGATE_OPTIONS)
    local params = { context = context, url = url }
    if options.wait ~= nil then
        if options.wait ~= "none" and options.wait ~= "interactive" and options.wait ~= "complete" then
            error("webdriver_bidi.navigate(wait) doit valoir 'none', 'interactive' ou 'complete'", 2)
        end
        params.wait = options.wait
    end
    return self:call("browsingContext.navigate", params, timeout)
end

function Client:evaluate(expression, target, options, timeout)
    nonempty_string("webdriver_bidi.evaluate(expression)", expression)
    if type(target) == "string" then
        target = { context = nonempty_string("webdriver_bidi.evaluate(target)", target) }
    elseif type(target) ~= "table" then
        error("webdriver_bidi.evaluate(target) doit être un contexte ou une table target", 2)
    end
    options = strict_table("webdriver_bidi.evaluate(opts)", options, EVALUATE_OPTIONS)
    local params = {
        expression = expression,
        target = target,
        awaitPromise = options.await_promise ~= false,
    }
    optional_boolean("webdriver_bidi.evaluate(await_promise)", options.await_promise)
    optional_boolean("webdriver_bidi.evaluate(user_activation)", options.user_activation)
    if options.result_ownership ~= nil then
        if options.result_ownership ~= "none" and options.result_ownership ~= "root" then
            error("webdriver_bidi.evaluate(result_ownership) doit valoir 'none' ou 'root'", 2)
        end
        params.resultOwnership = options.result_ownership
    end
    if options.serialization_options ~= nil then
        if type(options.serialization_options) ~= "table" then
            error("webdriver_bidi.evaluate(serialization_options) doit être une table", 2)
        end
        params.serializationOptions = options.serialization_options
    end
    if options.user_activation ~= nil then params.userActivation = options.user_activation end
    return self:call("script.evaluate", params, timeout)
end

function Client:get_realms(options, timeout)
    options = strict_table("webdriver_bidi.get_realms(opts)", options, REALMS_OPTIONS)
    local params = {}
    if options.context ~= nil then params.context = nonempty_string("webdriver_bidi.get_realms(context)", options.context) end
    if options.type ~= nil then params.type = nonempty_string("webdriver_bidi.get_realms(type)", options.type) end
    return self:call("script.getRealms", params, timeout)
end

function Client:next_event(timeout)
    local queued = self:_pop_event()
    if queued then return queued end
    timeout = finite_nonnegative("webdriver_bidi.next_event(timeout)", timeout, 0)
    local deadline = deadline_after(timeout)

    while true do
        local wait = remaining(deadline)
        if timeout == 0 then wait = 0 end
        local message, err, code = self:_read(wait)
        if not message then return nil, err, code end
        if message.type == "event" then
            if type(message.method) ~= "string" or type(message.params) ~= "table" then
                return fail("événement BiDi mal formé", "invalid response")
            end
            return message
        elseif message.type == "success" or message.type == "error" then
            if type(message.id) ~= "number" or math.type(message.id) ~= "integer" then
                return fail("identifiant de réponse BiDi invalide", "invalid response")
            end
            if message.id > self.next_id then
                return fail("réponse BiDi future inattendue", "invalid response")
            end
            -- Une réponse tardive après timeout est obsolète : on la draine.
        else
            return fail("type de message BiDi inattendu: " .. tostring(message.type), "invalid response")
        end

        if timeout == 0 or remaining(deadline) <= 0 then
            return nil, "timeout", "timeout"
        end
    end
end

function Client:on(method, callback)
    nonempty_string("webdriver_bidi.on(method)", method)
    if type(callback) ~= "function" then error("webdriver_bidi.on(callback) doit être une fonction", 2) end
    local callbacks = self.callbacks[method]
    if not callbacks then callbacks = {}; self.callbacks[method] = callbacks end
    callbacks[#callbacks + 1] = callback
    return callback
end

function Client:off(method, callback)
    nonempty_string("webdriver_bidi.off(method)", method)
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

function Client:dispatch(timeout, max_events)
    max_events = positive_integer("webdriver_bidi.dispatch(max_events)", max_events, 1)
    local dispatched = 0
    for index = 1, max_events do
        local event, err, code = self:next_event(index == 1 and timeout or 0)
        if not event then
            if code == "timeout" then return dispatched end
            return nil, err, code
        end
        local groups = { self.callbacks[event.method], self.callbacks["*"] }
        for _, callbacks in ipairs(groups) do
            if callbacks then
                for callback_index = 1, #callbacks do
                    local ok, callback_err = pcall(callbacks[callback_index], event)
                    if not ok then
                        return nil, "webdriver_bidi: callback " .. tostring(event.method)
                            .. ": " .. tostring(callback_err), "callback"
                    end
                end
            end
        end
        dispatched = dispatched + 1
    end
    return dispatched
end

function Client:is_closed()
    return self.closed
end

function Client:close(code, reason, timeout)
    if self.closed then return true end
    timeout = finite_nonnegative("webdriver_bidi.close(timeout)", timeout, self.close_timeout)
    local ok, err = self.transport:close(code or 1000, reason or "", timeout)
    self.closed = true
    if not ok then return fail("fermeture WebSocket: " .. tostring(err), "transport") end
    return true
end

Client.__close = function(self) self:close() end

local function new_client(transport, options)
    return setmetatable({
        transport = transport,
        command_timeout = finite_positive(
            "webdriver_bidi.connect(command_timeout)", options.command_timeout, 30),
        close_timeout = finite_nonnegative(
            "webdriver_bidi.connect(close_timeout)", options.close_timeout, 5),
        event_queue_limit = positive_integer(
            "webdriver_bidi.connect(event_queue_limit)", options.event_queue_limit, 1024),
        event_queue = {},
        event_head = 1,
        event_tail = 0,
        dropped_events = 0,
        callbacks = {},
        next_id = 0,
        closed = false,
    }, Client)
end

function M.connect(url, options)
    nonempty_string("webdriver_bidi.connect(url)", url)
    local opts = strict_table("webdriver_bidi.connect(opts)", options, CONNECT_OPTIONS)
    optional_boolean("webdriver_bidi.connect(verify)", opts.verify)
    optional_nonempty_string("webdriver_bidi.connect(ca_cert)", opts.ca_cert)
    optional_nonempty_string("webdriver_bidi.connect(ca_path)", opts.ca_path)
    optional_nonempty_string("webdriver_bidi.connect(hostname)", opts.hostname)
    finite_nonnegative("webdriver_bidi.connect(timeout)", opts.timeout, 5)
    finite_positive("webdriver_bidi.connect(command_timeout)", opts.command_timeout, 30)
    finite_nonnegative("webdriver_bidi.connect(close_timeout)", opts.close_timeout, 5)
    positive_integer("webdriver_bidi.connect(event_queue_limit)", opts.event_queue_limit, 1024)
    if opts.max_message_bytes ~= nil then
        positive_integer("webdriver_bidi.connect(max_message_bytes)", opts.max_message_bytes)
    end
    if opts.max_frame_bytes ~= nil then
        positive_integer("webdriver_bidi.connect(max_frame_bytes)", opts.max_frame_bytes)
    end
    if opts.min_version ~= nil and opts.min_version ~= "1.2" and opts.min_version ~= "1.3" then
        error("webdriver_bidi.connect(min_version) doit valoir '1.2' ou '1.3'", 2)
    end

    local ws_options = {}
    for _, key in ipairs({
        "timeout", "verify", "ca_cert", "ca_path", "hostname", "min_version",
        "max_message_bytes", "max_frame_bytes",
    }) do
        if opts[key] ~= nil then ws_options[key] = opts[key] end
    end
    if ws_options.timeout == nil then ws_options.timeout = 5 end
    local transport, connect_err = babet.websocket.connect(url, ws_options)
    if not transport then return fail("connexion WebSocket: " .. tostring(connect_err), "transport") end
    return new_client(transport, opts)
end

-- Crochet volontairement privé pour les tests de protocole : il permet de
-- tester le multiplexage BiDi sans réseau ni navigateur. Il n'est pas documenté
-- comme API publique et peut évoluer sans garantie de compatibilité.
function M._from_transport(transport, options)
    if type(transport) ~= "table" and type(transport) ~= "userdata" then
        error("webdriver_bidi._from_transport: transport invalide", 2)
    end
    return new_client(transport, options or {})
end

function M.is_client(value)
    return type(value) == "table" and getmetatable(value) == Client
end

return M
