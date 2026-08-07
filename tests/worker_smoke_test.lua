#!/usr/bin/env babet
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Julien

local script_dir = babet.currentDir()
local root = babet.joinPath(script_dir, "..")
package.path = root .. "/?.lua;" .. script_dir .. "/?.lua;" .. package.path

local worker_driver = require("webdriver_worker")
local browser = (arg and arg[1] or "firefox"):lower()
local headless = os.getenv("HEADLESS") == "1"
local allow_tofu = os.getenv("ALLOW_TOFU") == "1"

if browser ~= "firefox" and browser ~= "chrome" and browser ~= "chromium" then
    io.stderr:write("Navigateur attendu : firefox, chrome ou chromium\n")
    os.exit(2)
end

local session
local function cleanup(force)
    if not session then return end
    if force then
        session:cancel()
    else
        session:stop()
    end
    session = nil
end

assert(babet.signal.handle("INT", function() cleanup(true); os.exit(130) end))
assert(babet.signal.handle("TERM", function() cleanup(true); os.exit(143) end))

local function step(message)
    io.write("  • " .. message .. " … ")
    io.flush()
end

local function pass(extra)
    print("OK" .. (extra and (" (" .. extra .. ")") or ""))
end

local function abort(message)
    print("ÉCHEC")
    cleanup(true)
    io.stderr:write("\n  >> " .. tostring(message) .. "\n")
    os.exit(1)
end

print(("== Smoke test Babet WebDriver via worker (%s, headless=%s) ==")
    :format(browser, tostring(headless)))

step("création du worker, du driver et du navigateur")
local start_err
session, start_err = worker_driver.start({
    browser = browser,
    headless = headless,
    window_size = { 1280, 900 },
    trust_on_first_use = allow_tofu,
    bidi = true,
    command_timeout = 120,
    worker_start_timeout = 60,
    stop_timeout = 15,
})
if not session then abort(start_err) end

local metadata = session:metadata()
local binary, binary_err = session:browser_binary()
if binary == nil and binary_err then abort(binary_err) end
local details = "port " .. tostring(metadata.port or session:port())
if binary then details = details .. ", binaire " .. binary end
pass(details)

step("vérification de l'état du worker")
local state = session:status()
if state ~= "running" then abort("état inattendu du worker : " .. tostring(state)) end
pass(state)

step("navigation vers example.com à travers les channels")
local opened, open_err = session:open("https://example.com/")
if not opened then abort(open_err) end
pass()

step("lecture du titre à travers le proxy")
local title, title_err = session:title()
if not title then abort(title_err) end
pass(title)

step("création et utilisation d'un proxy d'élément")
local heading, heading_err = session:css("h1")
if not heading then abort(heading_err) end
if not worker_driver.is_element(heading) then abort("l'objet retourné n'est pas un proxy d'élément") end
local text, text_err = heading:text()
if not text then abort(text_err) end
pass(text)

step("exécution JavaScript et retour structuré")
local result, js_err = session:js([[
    return {
        userAgent: navigator.userAgent,
        title: document.title,
        hasBody: document.body !== null
    }
]])
if not result then abort(js_err) end
if result.title ~= title or result.hasBody ~= true or type(result.userAgent) ~= "string" then
    abort("résultat JavaScript inattendu")
end
local empty_array, empty_array_err = session:js("return arguments[0]", babet.json.as_array({}))
if not empty_array then abort(empty_array_err) end
if assert(babet.json.encode(empty_array)) ~= "[]" then
    abort("tableau JSON vide Classic worker transformé en objet")
end
pass(result.userAgent:sub(1, 50) .. "…")

step("JavaScript asynchrone à travers le worker")
local async_value, async_err = session:js_async([[
    const done = arguments[arguments.length - 1];
    setTimeout(() => done("async-worker-ok"), 10);
]])
if not async_value then abort(async_err) end
if async_value ~= "async-worker-ok" then abort("retour JavaScript asynchrone inattendu") end
pass(async_value)

step("élément actif et ShadowRoot à travers les channels")
local prepared, prepare_err = session:js([[
    const heading = document.querySelector("h1");
    heading.tabIndex = 0;
    heading.focus();
    const previous = document.querySelector("#babet-shadow-host");
    if (previous) previous.remove();
    const host = document.createElement("div");
    host.id = "babet-shadow-host";
    document.body.appendChild(host);
    const root = host.attachShadow({ mode: "open" });
    root.innerHTML = '<button id="inside">Shadow Worker OK</button>';
    return true;
]])
if not prepared then abort(prepare_err) end
local active, active_err = session:active_element()
if not active then abort(active_err) end
if not worker_driver.is_element(active) then abort("élément actif non transporté") end
local host, host_err = session:css("#babet-shadow-host")
if not host then abort(host_err) end
local shadow, shadow_err = host:shadow_root()
if not shadow then abort(shadow_err) end
if not worker_driver.is_shadow_root(shadow) then abort("ShadowRoot non transporté") end
local inside, inside_err = shadow:find("#inside")
if not inside then abort(inside_err) end
local inside_text, inside_text_err = inside:text()
if not inside_text then abort(inside_text_err) end
if inside_text ~= "Shadow Worker OK" then abort("contenu Shadow DOM inattendu") end
pass(inside_text)

step("lecture des timeouts W3C à travers le worker")
local timeouts, timeouts_err = session:get_timeouts()
if not timeouts then abort(timeouts_err) end
if type(timeouts.implicit) ~= "number" or type(timeouts.page_load) ~= "number" then
    abort("timeouts W3C inattendus")
end
pass(("implicit=%ss, page_load=%ss"):format(timeouts.implicit, timeouts.page_load))

step("démarrage du worker BiDi dédié")
local websocket_url = session:websocket_url()
if type(websocket_url) ~= "string" or websocket_url == "" then abort("webSocketUrl absente du worker") end
local bidi, bidi_err = session:bidi({ command_timeout = 1, worker_start_timeout = 15 })
if not bidi then abort(bidi_err) end
pass("connecté")

step("session.status via worker BiDi")
local bidi_status, bidi_status_err = bidi:status(10)
if not bidi_status then abort(bidi_status_err) end
pass("ready=" .. tostring(bidi_status.ready))

step("browsingContext.getTree via worker BiDi")
local tree, tree_err = bidi:get_tree({ max_depth = 0 }, 10)
if not tree then abort(tree_err) end
local context = tree.contexts and tree.contexts[1] and tree.contexts[1].context
if type(context) ~= "string" then abort("contexte BiDi worker introuvable") end
pass(context)

step("script.evaluate via worker BiDi")
local evaluated, evaluate_err = bidi:evaluate("document.title", context, nil, 10)
if not evaluated then abort(evaluate_err) end
if evaluated.type ~= "success" or evaluated.result.value ~= title then
    abort("script.evaluate via worker BiDi inattendu")
end
local evaluated_array, evaluated_array_err = bidi:evaluate("[]", context, nil, 10)
if not evaluated_array then abort(evaluated_array_err) end
local remote_array = evaluated_array.result and evaluated_array.result.value
if type(remote_array) ~= "table" or assert(babet.json.encode(remote_array)) ~= "[]" then
    abort("tableau JSON vide BiDi worker transformé en objet")
end
pass(evaluated.result.value)

step("timeout explicite supérieur au défaut BiDi worker")
-- Le timeout explicite d'une commande peut dépasser command_timeout du worker :
-- le parent doit conserver le même budget et ne pas expirer avant le WebSocket.
local delayed, delayed_err = bidi:evaluate([[
    new Promise(resolve => setTimeout(() => resolve("delayed-worker-ok"), 1200))
]], context, nil, 3)
if not delayed then abort(delayed_err) end
if delayed.type ~= "success" or delayed.result.value ~= "delayed-worker-ok" then
    abort("timeout explicite BiDi worker mal propagé")
end
pass(delayed.result.value)

step("événement log.entryAdded via worker BiDi")
local subscription, subscribe_err = bidi:subscribe("log.entryAdded", nil, 10)
if not subscription then abort(subscribe_err) end
local logged, log_err = bidi:evaluate('console.log("babet-bidi-worker-smoke"); "logged"', context, nil, 10)
if not logged then abort(log_err) end
local saw_log = false
local deadline = babet.monotonic() + 10
while babet.monotonic() < deadline do
    local event, event_err, event_code = bidi:next_event(math.max(0, deadline - babet.monotonic()))
    if not event then
        if event_code ~= "timeout" then abort(event_err) end
        break
    end
    if event.method == "log.entryAdded" then
        local text_value = event.params and event.params.text
        if type(text_value) == "string" and text_value:find("babet%-bidi%-worker%-smoke") then
            saw_log = true
            break
        end
    end
end
if not saw_log then abort("log.entryAdded non reçu via worker BiDi") end
assert(bidi:unsubscribe(subscription, 10))
pass("reçu")

step("annulation coopérative du worker BiDi")
local bidi_job = bidi.job
local cancelled, cancel_err = bidi:cancel()
if not cancelled then abort(cancel_err) end
local cancel_joined, cancel_result = bidi_job:join(10)
if not cancel_joined then abort(cancel_result) end
pass("worker terminé sans erreur")

local screenshot = "/tmp/babet-webdriver-worker-smoke.png"
step("capture d'écran depuis le worker vers " .. screenshot)
local saved, screenshot_err = session:screenshot(screenshot)
if not saved then abort(screenshot_err) end
if not babet.isFile(screenshot) then abort("la capture n'a pas été créée") end
pass()

local pdf = "/tmp/babet-webdriver-worker-smoke.pdf"
step("impression PDF depuis le worker vers " .. pdf)
local printed, print_err = session:print({ background = true }, pdf)
if not printed then abort(print_err) end
if not babet.isFile(pdf) then abort("le PDF worker n'a pas été créé") end
pass()

step("arrêt coopératif et jointure du worker")
local stopped, stop_err = session:stop(15)
session = nil
if not stopped then abort(stop_err) end
pass()

print("\n== TOUT EST VERT VIA LE WORKER ==")
print("Capture : " .. screenshot)
print("PDF     : " .. pdf)
