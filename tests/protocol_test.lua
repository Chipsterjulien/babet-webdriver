#!/usr/bin/env babet
-- SPDX-License-Identifier: GPL-3.0-or-later

local script_dir = babet.currentDir()
local root = babet.joinPath(script_dir, "..")
package.path = root .. "/?.lua;" .. script_dir .. "/?.lua;" .. package.path

local mock = require("mock_webdriver")
local webdriver = require("webdriver")

assert(babet.mkdir(script_dir .. "/tmp"))
local server = assert(mock.start())

local driver = assert(webdriver.firefox({
    attach = true,
    port = server.port,
    request_timeout = 5,
    status_timeout = 1,
    start_timeout = 5,
}))

assert(driver:open("https://example.test/path"))
assert(driver:url() == "https://example.test/path")
assert(driver:title() == "Mock title")
assert(driver:source():find("Mock title", 1, true))
assert(driver:frame(nil))
local js_result = assert(driver:js("return arguments", nil, "second"))
assert(js_result.count == 2 and js_result.first_is_null == true and js_result.second == "second")

local element = assert(driver:css("h1"))
assert(element:text() == "Mock element")
assert(element:displayed() == true)
assert(element:enabled() == true)
assert(element:selected() == false)

local exists, exists_err = driver:exists("#missing")
assert(exists == false, exists_err)
assert(driver:wait("#missing", { state = "gone", timeout = 1 }))

local screenshot_path = script_dir .. "/tmp/mock.png"
assert(driver:screenshot(screenshot_path) == screenshot_path)
local file = assert(io.open(screenshot_path, "rb"))
local content = file:read("a")
file:close()
assert(content == "PNG-MOCK\0DATA")

assert(driver:quit())
local joined, result = server.job:join(5)
assert(joined, result)

local chromium_server = assert(mock.start())
local chromium_profile = script_dir .. "/tmp/chromium-profile"
local chromium = assert(webdriver.chromium({
    attach = true,
    port = chromium_server.port,
    binary = "/bin/true",
    user_data_dir = chromium_profile,
    headless = true,
    request_timeout = 5,
    status_timeout = 1,
    start_timeout = 5,
}))
assert(chromium:browser_binary() == "/bin/true")
assert(chromium:quit())
local chromium_joined, chromium_result = chromium_server.job:join(5)
assert(chromium_joined, chromium_result)
assert(babet.rmdirAll(chromium_profile))
print("protocol_test: OK")
