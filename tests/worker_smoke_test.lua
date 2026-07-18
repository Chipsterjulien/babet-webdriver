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
pass(result.userAgent:sub(1, 50) .. "…")

local screenshot = "/tmp/babet-webdriver-worker-smoke.png"
step("capture d'écran depuis le worker vers " .. screenshot)
local saved, screenshot_err = session:screenshot(screenshot)
if not saved then abort(screenshot_err) end
if not babet.isFile(screenshot) then abort("la capture n'a pas été créée") end
pass()

step("arrêt coopératif et jointure du worker")
local stopped, stop_err = session:stop(15)
session = nil
if not stopped then abort(stop_err) end
pass()

print("\n== TOUT EST VERT VIA LE WORKER ==")
print("Capture : " .. screenshot)
