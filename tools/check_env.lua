#!/usr/bin/env babet
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Julien

local script_dir = babet.currentDir()
local root = babet.joinPath(script_dir, "..")
package.path = root .. "/?.lua;" .. package.path

local expected_version = require("webdriver_version")
local webdriver = require("webdriver")
local worker_driver = require("webdriver_worker")
local driver_manager = require("driver_manager")

local function resolve(path)
    local current = _G
    for part in path:gmatch("[^.]+") do
        if type(current) ~= "table" then return nil end
        current = current[part]
        if current == nil then return nil end
    end
    return current
end

local required = {
    "babet.http.request", "babet.http.get", "babet.http.download",
    "babet.json.encode", "babet.json.decode", "babet.json.as_array",
    "babet.base64.encode", "babet.base64.decode",
    "babet.spawn", "babet.exec", "babet.which", "babet.uname",
    "babet.monotonic", "babet.sleep", "babet.sha256sum",
    "babet.fileExists", "babet.isFile", "babet.mkdir", "babet.setMode",
    "babet.remove", "babet.getPath", "babet.writeFileAtomic",
    "babet.archive.extractFile", "babet.socket.listen", "babet.websocket.connect",
    "babet.workers.spawn", "babet.workers.channel",
    "babet.signal.handle", "utf8.codes", "utf8.char",
}

print("== Vérification de l'environnement Babet WebDriver ==")
print("Babet détecté : " .. tostring(babet.VERSION or "inconnu"))
print("babet-webdriver : " .. tostring(expected_version))
local compatible_classic = (babet.VERSION_MAJOR or 0) > 2
    or ((babet.VERSION_MAJOR or 0) == 2 and (babet.VERSION_MINOR or 0) >= 9)
local compatible_bidi = (babet.VERSION_MAJOR or 0) > 2
    or ((babet.VERSION_MAJOR or 0) == 2 and (babet.VERSION_MINOR or 0) >= 22)

local bidi_driver, bidi_worker
local bidi_modules_ok = false
local bidi_module_error
if compatible_bidi then
    local ok_driver, driver_or_err = pcall(require, "webdriver_bidi")
    local ok_worker, worker_or_err = pcall(require, "webdriver_bidi_worker")
    if ok_driver and ok_worker then
        bidi_driver, bidi_worker = driver_or_err, worker_or_err
        bidi_modules_ok = true
    else
        bidi_module_error = not ok_driver and driver_or_err or worker_or_err
    end
end

local version_ok = webdriver.VERSION == expected_version
    and worker_driver.VERSION == expected_version
    and driver_manager.VERSION == expected_version
    and (not compatible_bidi or (bidi_modules_ok
        and bidi_driver.VERSION == expected_version
        and bidi_worker.VERSION == expected_version))
    and driver_manager.user_agent == "babet-webdriver/" .. expected_version
print(("  [%s] version interne cohérente"):format(version_ok and "OK " or "NON"))
print(("  [%s] Classic : Babet >= 2.9.0"):format(compatible_classic and "OK " or "NON"))
print(("  [%s] BiDi    : Babet >= 2.22.0"):format(compatible_bidi and "OK " or "NON"))
if compatible_bidi then
    print(("  [%s] modules BiDi chargeables%s"):format(
        bidi_modules_ok and "OK " or "NON",
        bidi_modules_ok and "" or (bidi_module_error and (" : " .. tostring(bidi_module_error)) or "")
    ))
end

local missing = 0
for _, path in ipairs(required) do
    local present = type(resolve(path)) == "function"
    if not present then missing = missing + 1 end
    print(("  [%s] %s"):format(present and "OK " or "ABSENT", path))
end

print("\n-- Vérifications fonctionnelles sans réseau --")

local base64_ok = false
local base64_encode = resolve("babet.base64.encode")
local base64_decode = resolve("babet.base64.decode")
if type(base64_encode) == "function" and type(base64_decode) == "function" then
    local called, encoded = pcall(base64_encode, "AB\0CD")
    if called and encoded then
        local decoded, decode_err = base64_decode(encoded)
        base64_ok = decoded == "AB\0CD"
        if not base64_ok and decode_err then
            io.stderr:write("  Base64 : ", tostring(decode_err), "\n")
        end
    end
end
print(("  [%s] Base64 binaire"):format(base64_ok and "OK " or "NON"))

local atomic_ok = false
local atomic_err
local write_atomic = resolve("babet.writeFileAtomic")
if type(write_atomic) == "function" then
    local token = tostring(babet.monotonic and babet.monotonic() or os.time())
        :gsub("[^0-9]", "")
    local temp = "/tmp/babet-webdriver-check-" .. token .. ".json"
    atomic_ok, atomic_err = write_atomic(temp, '{"ready":true}', {
        overwrite = false,
        permissions = tonumber("600", 8),
        durable = false,
    })
    if atomic_ok and type(babet.remove) == "function" then babet.remove(temp) end
end
print(("  [%s] writeFileAtomic%s"):format(
    atomic_ok and "OK " or "NON",
    atomic_ok and "" or (atomic_err and (" : " .. tostring(atomic_err)) or "")
))

local channel_ok = false
local channel_err
local channel_factory = resolve("babet.workers.channel")
if type(channel_factory) == "function" then
    local channel
    channel, channel_err = channel_factory({ capacity = 1 })
    if channel then
        local sent, send_err = channel:send({ ready = true }, 0)
        local received, value = channel:recv(0)
        channel_ok = sent == true and received == true
            and type(value) == "table" and value.ready == true
        if not channel_ok then channel_err = send_err or value end
        channel:close()
    end
end
print(("  [%s] channel worker%s"):format(
    channel_ok and "OK " or "NON",
    channel_ok and "" or (channel_err and (" : " .. tostring(channel_err)) or "")
))

local which = resolve("babet.which")
local function find_program(name)
    if type(which) ~= "function" then return nil end
    return which(name)
end
local browser_candidates = {
    { "firefox", find_program("firefox") },
    { "chromium", find_program("chromium") or find_program("chromium-browser") },
    { "chrome", find_program("google-chrome") or find_program("google-chrome-stable") },
    { "geckodriver", find_program("geckodriver") },
    { "chromedriver", find_program("chromedriver") },
}
print("\n-- Navigateurs et drivers présents dans PATH --")
for _, candidate in ipairs(browser_candidates) do
    local name, path = candidate[1], candidate[2]
    print(("  %-13s %s"):format(name .. ":", path or "absent"))
end

print(("\n== %d fonction(s) manquante(s) =="):format(missing))
if compatible_classic and compatible_bidi and version_ok and missing == 0 and base64_ok and atomic_ok and channel_ok then
    print("Environnement Babet compatible avec la bibliothèque.")
    os.exit(0)
end
os.exit(1)
