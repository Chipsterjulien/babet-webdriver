#!/usr/bin/env babet
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Julien

local script_dir = babet.currentDir()
local root = babet.joinPath(script_dir, "..")
package.path = root .. "/?.lua;" .. script_dir .. "/?.lua;" .. package.path

local webdriver = require("webdriver")
local browser = (arg and arg[1] or "firefox"):lower()
local headless = os.getenv("HEADLESS") == "1"
local allow_tofu = os.getenv("ALLOW_TOFU") == "1"

local constructor = webdriver[browser]
if type(constructor) ~= "function" then
    io.stderr:write("Navigateur attendu : firefox, chrome ou chromium\n")
    os.exit(2)
end

local driver
local function cleanup()
    if driver then driver:quit() end
end

assert(babet.signal.handle("INT", function() cleanup(); os.exit(130) end))
assert(babet.signal.handle("TERM", function() cleanup(); os.exit(143) end))

local function step(message)
    io.write("  • " .. message .. " … ")
    io.flush()
end

local function pass(extra)
    print("OK" .. (extra and (" (" .. extra .. ")") or ""))
end

local function abort(message)
    print("ÉCHEC")
    cleanup()
    io.stderr:write("\n  >> " .. tostring(message) .. "\n")
    os.exit(1)
end

print(("== Smoke test Babet WebDriver (%s, headless=%s) ==")
    :format(browser, tostring(headless)))

step("démarrage du driver et du navigateur")
local start_err
driver, start_err = constructor({
    headless = headless,
    window_size = { 1280, 900 },
    trust_on_first_use = allow_tofu,
    bidi = true,
})
if not driver then abort(start_err) end
local binary = driver:browser_binary()
local details = "port " .. tostring(driver:port())
if binary then details = details .. ", binaire " .. binary end
pass(details)

step("navigation vers example.com")
local opened, open_err = driver:open("https://example.com/")
if not opened then abort(open_err) end
pass()

step("lecture du titre")
local title, title_err = driver:title()
if not title then abort(title_err) end
pass(title)

step("recherche de h1")
local heading, heading_err = driver:css("h1")
if not heading then abort(heading_err) end
local text, text_err = heading:text()
if not text then abort(text_err) end
pass(text)

step("exécution JavaScript")
local user_agent, js_err = driver:js("return navigator.userAgent")
if not user_agent then abort(js_err) end
pass(user_agent:sub(1, 50) .. "…")

step("JavaScript asynchrone W3C")
local async_value, async_err = driver:js_async([[
    const done = arguments[arguments.length - 1];
    setTimeout(() => done("async-ok"), 10);
]])
if not async_value then abort(async_err) end
if async_value ~= "async-ok" then abort("retour JavaScript asynchrone inattendu") end
pass(async_value)

step("élément actif et Shadow DOM")
local prepared, prepare_err = driver:js([[
    const heading = document.querySelector("h1");
    heading.tabIndex = 0;
    heading.focus();
    const previous = document.querySelector("#babet-shadow-host");
    if (previous) previous.remove();
    const host = document.createElement("div");
    host.id = "babet-shadow-host";
    document.body.appendChild(host);
    const root = host.attachShadow({ mode: "open" });
    root.innerHTML = '<button id="inside">Shadow OK</button>';
    return true;
]])
if not prepared then abort(prepare_err) end
local active, active_err = driver:active_element()
if not active then abort(active_err) end
if webdriver.element_id(active) ~= webdriver.element_id(heading) then
    abort("l'élément actif n'est pas le h1 préparé")
end
local host, host_err = driver:css("#babet-shadow-host")
if not host then abort(host_err) end
local shadow, shadow_err = host:shadow_root()
if not shadow then abort(shadow_err) end
local inside, inside_err = shadow:find("#inside")
if not inside then abort(inside_err) end
local inside_text, inside_text_err = inside:text()
if not inside_text then abort(inside_text_err) end
if inside_text ~= "Shadow OK" then abort("contenu Shadow DOM inattendu") end
pass(inside_text)

step("lecture des timeouts W3C")
local timeouts, timeouts_err = driver:get_timeouts()
if not timeouts then abort(timeouts_err) end
if type(timeouts.implicit) ~= "number" or type(timeouts.page_load) ~= "number" then
    abort("timeouts W3C inattendus")
end
pass(("implicit=%ss, page_load=%ss"):format(timeouts.implicit, timeouts.page_load))

step("action wheel W3C")
local wheel_ok, wheel_err = driver:actions():scroll(0, 100):perform()
if not wheel_ok then abort(wheel_err) end
pass()

step("négociation WebDriver BiDi")
local websocket_url = driver:websocket_url()
if type(websocket_url) ~= "string" or websocket_url == "" then
    abort("capability webSocketUrl absente")
end
local bidi, bidi_err = driver:bidi({ timeout = 10, command_timeout = 15 })
if not bidi then abort(bidi_err) end
local bidi_status, bidi_status_err = bidi:status()
if not bidi_status then abort(bidi_status_err) end
if type(bidi_status.ready) ~= "boolean" then abort("session.status BiDi invalide") end
pass("webSocketUrl négociée")

step("arbre des contextes BiDi")
local tree, tree_err = bidi:get_tree({ max_depth = 0 })
if not tree then abort(tree_err) end
local context = tree.contexts and tree.contexts[1] and tree.contexts[1].context
if type(context) ~= "string" or context == "" then abort("contexte BiDi principal introuvable") end
pass(context)

step("script.evaluate BiDi")
local evaluated, evaluate_err = bidi:evaluate("document.title", context)
if not evaluated then abort(evaluate_err) end
if evaluated.type ~= "success" or type(evaluated.result) ~= "table"
    or evaluated.result.type ~= "string" or evaluated.result.value ~= title then
    abort("résultat script.evaluate inattendu")
end
pass(evaluated.result.value)

step("événements log et network BiDi")
local subscription, subscribe_err = bidi:subscribe({
    "log.entryAdded",
    "network.beforeRequestSent",
    "browsingContext.load",
})
if not subscription then abort(subscribe_err) end
local nav_url = "https://example.com/?babet-bidi-smoke=1"
local navigated, navigate_err = bidi:navigate(context, nav_url, { wait = "complete" })
if not navigated then abort(navigate_err) end
local logged, log_err = bidi:evaluate('console.log("babet-bidi-smoke"); "logged"', context)
if not logged then abort(log_err) end

local saw_network, saw_log = false, false
local deadline = babet.monotonic() + 10
while babet.monotonic() < deadline and (not saw_network or not saw_log) do
    local event, event_err, event_code = bidi:next_event(math.max(0, deadline - babet.monotonic()))
    if not event then
        if event_code ~= "timeout" then abort(event_err) end
        break
    end
    if event.method == "network.beforeRequestSent" then
        local request = event.params and event.params.request
        if type(request) == "table" and type(request.url) == "string"
            and request.url:find("babet%-bidi%-smoke=1") then
            saw_network = true
        end
    elseif event.method == "log.entryAdded" then
        local text_value = event.params and event.params.text
        if type(text_value) == "string" and text_value:find("babet%-bidi%-smoke") then
            saw_log = true
        end
    end
end
if not saw_network then abort("événement network.beforeRequestSent non reçu") end
if not saw_log then abort("événement log.entryAdded non reçu") end
assert(bidi:unsubscribe(subscription))
pass("log + network")

step("fermeture du transport BiDi")
local bidi_closed, bidi_close_err = bidi:close(1000, "smoke complete", 5)
if not bidi_closed then abort(bidi_close_err) end
pass()

local screenshot = "/tmp/babet-webdriver-smoke.png"
step("capture d'écran vers " .. screenshot)
local saved, screenshot_err = driver:screenshot(screenshot)
if not saved then abort(screenshot_err) end
pass()

local pdf = "/tmp/babet-webdriver-smoke.pdf"
step("impression PDF W3C vers " .. pdf)
local printed, print_err = driver:print({ background = true }, pdf)
if not printed then abort(print_err) end
if not babet.isFile(pdf) then abort("le PDF n'a pas été créé") end
pass()

step("fermeture propre")
local stopped, stop_err = driver:quit()
driver = nil
if not stopped then abort(stop_err) end
pass()

print("\n== TOUT EST VERT ==")
print("Capture : " .. screenshot)
print("PDF     : " .. pdf)
