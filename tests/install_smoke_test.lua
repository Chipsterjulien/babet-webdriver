#!/usr/bin/env babet
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Julien

local script_dir = babet.currentDir()
local root = babet.joinPath(script_dir, "..")
package.path = root .. "/?.lua;" .. package.path

local manager = require("driver_manager")
local browser = (arg and arg[1] or "chromium"):lower()
local cache = os.getenv("WEBDRIVER_INSTALL_CACHE")

if browser ~= "firefox" and browser ~= "chrome" and browser ~= "chromium" then
    io.stderr:write("Navigateur attendu : firefox, chrome ou chromium\n")
    os.exit(2)
end
if type(cache) ~= "string" or cache == "" then
    io.stderr:write("WEBDRIVER_INSTALL_CACHE doit désigner un cache temporaire dédié.\n")
    os.exit(2)
end

local browser_binary
if browser == "chrome" then
    browser_binary = babet.which("google-chrome") or babet.which("google-chrome-stable")
elseif browser == "chromium" then
    browser_binary = babet.which("chromium") or babet.which("chromium-browser")
end
if browser ~= "firefox" and not browser_binary then
    io.stderr:write("Binaire navigateur introuvable pour " .. browser .. "\n")
    os.exit(2)
end

local describe_options = {}
if browser_binary then describe_options.browser_binary = browser_binary end
local descriptor = assert(manager.describe(browser, describe_options))

local options = {
    cache = cache,
    force = true,
    trust_on_first_use = true,
    timeout = 180,
}
if browser_binary then options.browser_binary = browser_binary end

local path = assert(manager.install(browser, options))
assert(babet.isFile(path))

local verified, verified_path = manager.verify(browser, {
    cache = cache,
    timeout = 30,
    browser_binary = browser_binary,
})
assert(verified == true, verified_path)
assert(verified_path == path)

-- Un succès doit avoir publié le binaire par rename et ne laisser aucun
-- staging .tmp issu de cette installation dans le dossier de destination.
local destination_dir = assert(babet.getPath(path))
local files = assert(babet.listFiles(destination_dir))
for _, relative in ipairs(files) do
    assert(not (relative:sub(1, #descriptor.binary + 1) == descriptor.binary .. "."
        and relative:sub(-4) == ".tmp"), "staging résiduel: " .. relative)
end

print(("install_smoke_test: OK (%s -> %s)"):format(browser, path))
