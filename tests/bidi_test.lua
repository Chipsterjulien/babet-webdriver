#!/usr/bin/env babet
-- SPDX-License-Identifier: GPL-3.0-or-later

local script_dir = babet.currentDir()
local root = babet.joinPath(script_dir, "..")
package.path = root .. "/?.lua;" .. script_dir .. "/?.lua;" .. package.path

local bidi = require("webdriver_bidi")
local version = require("webdriver_version")
assert(version == "2.0.0")
assert(bidi.VERSION == version)

local FakeTransport = {}
FakeTransport.__index = FakeTransport

function FakeTransport.new()
    return setmetatable({ inbox = {}, sent = {}, closed = false, stale_id = nil }, FakeTransport)
end

function FakeTransport:_push(value)
    self.inbox[#self.inbox + 1] = {
        type = "text",
        data = assert(babet.json.encode(value)),
    }
end

function FakeTransport:send_text(payload)
    assert(not self.closed)
    local command = assert(babet.json.decode(payload))
    self.sent[#self.sent + 1] = command

    if command.method == "session.status" then
        if self.stale_id then
            self:_push({ type = "success", id = self.stale_id, result = { ignored = true } })
            self.stale_id = nil
        end
        self:_push({
            type = "event",
            method = "log.entryAdded",
            params = { type = "console", level = "info", text = "queued-before-status" },
        })
        self:_push({
            type = "success",
            id = command.id,
            result = { ready = true, message = "mock bidi ready" },
        })
    elseif command.method == "session.subscribe" then
        assert(type(command.params.events) == "table" and command.params.events[1] == "log.entryAdded")
        self:_push({ type = "success", id = command.id, result = { subscription = "sub-1" } })
    elseif command.method == "session.unsubscribe" then
        assert(command.params.subscriptions[1] == "sub-1")
        self:_push({ type = "success", id = command.id, result = {} })
    elseif command.method == "browsingContext.getTree" then
        self:_push({
            type = "success", id = command.id,
            result = { contexts = babet.json.as_array({ {
                context = "ctx-1", url = "about:blank", children = babet.json.as_array({}),
            } }) },
        })
    elseif command.method == "browsingContext.navigate" then
        assert(command.params.context == "ctx-1")
        assert(command.params.url == "https://example.test/")
        assert(command.params.wait == "complete")
        self:_push({
            type = "event", method = "network.beforeRequestSent",
            params = { context = "ctx-1", request = { request = "req-1", url = command.params.url } },
        })
        self:_push({
            type = "success", id = command.id,
            result = { navigation = "nav-1", url = command.params.url },
        })
    elseif command.method == "script.evaluate" then
        assert(command.params.expression == "document.title")
        assert(command.params.target.context == "ctx-1")
        assert(command.params.awaitPromise == true)
        self:_push({
            type = "success", id = command.id,
            result = {
                type = "success", realm = "realm-1",
                result = { type = "string", value = "Mock BiDi title" },
            },
        })
    elseif command.method == "script.getRealms" then
        self:_push({
            type = "success", id = command.id,
            result = { realms = babet.json.as_array({ {
                realm = "realm-1", origin = "https://example.test", type = "window", context = "ctx-1",
            } }) },
        })
    elseif command.method == "test.error" then
        self:_push({
            type = "error", id = command.id,
            error = "invalid argument", message = "mock invalid argument", stacktrace = "",
        })
    elseif command.method == "test.timeout" then
        -- Aucun message immédiat. La réponse tardive sera injectée avant la
        -- prochaine réponse pour vérifier le drainage par identifiant.
        self.stale_id = command.id
    elseif command.method == "test.array" then
        assert(assert(babet.json.encode(command.params.value)) == "[]")
        self:_push({
            type = "success", id = command.id,
            result = { value = babet.json.as_array({}) },
        })
    else
        self:_push({ type = "success", id = command.id, result = { echoed = command.method } })
    end
    return #payload
end

function FakeTransport:recv()
    if #self.inbox == 0 then return nil, "timeout" end
    return table.remove(self.inbox, 1)
end

function FakeTransport:close()
    self.closed = true
    return true
end

local transport = FakeTransport.new()
local client = bidi._from_transport(transport, {
    command_timeout = 0.05,
    event_queue_limit = 2,
})
assert(bidi.is_client(client))

local status = assert(client:status())
assert(status.ready == true and status.message == "mock bidi ready")

-- L'événement arrivé avant la réponse doit rester disponible et ne jamais
-- désynchroniser la commande.
local queued = assert(client:next_event(0))
assert(queued.method == "log.entryAdded")
assert(queued.params.text == "queued-before-status")

local subscription = assert(client:subscribe("log.entryAdded", { contexts = { "ctx-1" } }))
assert(subscription == "sub-1")
assert(client:unsubscribe(subscription))

local tree = assert(client:get_tree({ max_depth = 1 }))
assert(tree.contexts[1].context == "ctx-1")

local navigation = assert(client:navigate("ctx-1", "https://example.test/", { wait = "complete" }))
assert(navigation.navigation == "nav-1")
local network_event = assert(client:next_event(0))
assert(network_event.method == "network.beforeRequestSent")

local evaluated = assert(client:evaluate("document.title", "ctx-1"))
assert(evaluated.type == "success")
assert(evaluated.result.type == "string" and evaluated.result.value == "Mock BiDi title")

local realms = assert(client:get_realms({ context = "ctx-1" }))
assert(realms.realms[1].realm == "realm-1")

local value, err, code = client:call("test.error", {})
assert(value == nil and err:find("mock invalid argument", 1, true) and code == "invalid argument")

local timed, timeout_err, timeout_code = client:call("test.timeout", {}, 0.01)
assert(timed == nil and timeout_err and timeout_code == "timeout")
local recovered = assert(client:status(0.05))
assert(recovered.ready == true)
local array_result = assert(client:call("test.array", { value = babet.json.as_array({}) }))
assert(assert(babet.json.encode(array_result.value)) == "[]")
-- Le status de récupération injecte lui aussi volontairement un événement
-- avant sa réponse. Il doit rester disponible, puis être drainé avant le test
-- indépendant de saturation de la file.
local recovered_event = assert(client:next_event(0))
assert(recovered_event.method == "log.entryAdded")
assert(recovered_event.params.text == "queued-before-status")

-- File bornée : les événements en excès sont comptés puis signalés par un
-- événement synthétique au lieu de provoquer une croissance mémoire infinie.
assert(transport:_push({ type = "event", method = "a", params = {} }) == nil)
assert(transport:_push({ type = "event", method = "b", params = {} }) == nil)
assert(transport:_push({ type = "event", method = "c", params = {} }) == nil)
assert(client:call("noop", {}))
assert(assert(client:next_event(0)).method == "a")
assert(assert(client:next_event(0)).method == "b")
local overflow = assert(client:next_event(0))
assert(overflow.method == "babetWebDriver.eventOverflow")
assert(overflow.params.dropped >= 1)

local callbacks = 0
client:on("custom.event", function(event)
    assert(event.params.value == 42)
    callbacks = callbacks + 1
end)
transport:_push({ type = "event", method = "custom.event", params = { value = 42 } })
assert(client:dispatch(0, 1) == 1)
assert(callbacks == 1)

local invalid_wait = pcall(function()
    client:navigate("ctx-1", "https://example.test/", { wait = "later" })
end)
assert(invalid_wait == false)

assert(client:close())
assert(client:is_closed())
print("bidi_test: OK")
