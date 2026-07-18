#!/usr/bin/env babet
-- SPDX-License-Identifier: GPL-3.0-or-later

local script_dir = babet.currentDir()
local root = babet.joinPath(script_dir, "..")
package.path = root .. "/?.lua;" .. script_dir .. "/?.lua;" .. package.path

local mock = require("mock_webdriver")
local worker_driver = require("webdriver_worker")

local server = assert(mock.start())
local session = assert(worker_driver.start({
    browser = "firefox",
    attach = true,
    port = server.port,
    request_timeout = 5,
    status_timeout = 1,
    start_timeout = 5,
    command_timeout = 5,
    worker_start_timeout = 10,
    stop_timeout = 5,
}))

assert(session:title() == "Mock title")
assert(session:frame(nil))
local js_result = assert(session:js("return arguments", nil, "second"))
assert(js_result.count == 2 and js_result.first_is_null == true and js_result.second == "second")
local element = assert(session:css("h1"))
assert(worker_driver.is_element(element))
assert(element:text() == "Mock element")
local exists, err = session:exists("#missing")
assert(exists == false, err)
local missing, missing_err, missing_code = session:find("#missing")
assert(missing == nil and missing_err and missing_code == "no such element")
assert(session:stop())

local joined, result = server.job:join(5)
assert(joined, result)
print("worker_test: OK")
