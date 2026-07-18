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

local screenshot = "/tmp/babet-webdriver-smoke.png"
step("capture d'écran vers " .. screenshot)
local saved, screenshot_err = driver:screenshot(screenshot)
if not saved then abort(screenshot_err) end
pass()

step("fermeture propre")
local stopped, stop_err = driver:quit()
driver = nil
if not stopped then abort(stop_err) end
pass()

print("\n== TOUT EST VERT ==")
print("Capture : " .. screenshot)
