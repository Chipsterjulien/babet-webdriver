#!/usr/bin/env babet
-- SPDX-License-Identifier: GPL-3.0-or-later

local script_dir = babet.currentDir()
local root = babet.joinPath(script_dir, "..")
package.path = root .. "/?.lua;" .. script_dir .. "/?.lua;" .. package.path

local mock = require("mock_webdriver")
local webdriver = require("webdriver")
local worker_driver = require("webdriver_worker")
local driver_manager = require("driver_manager")
local version = require("webdriver_version")

assert(version == "1.1.1")
assert(webdriver.VERSION == version)
assert(worker_driver.VERSION == version)
assert(driver_manager.VERSION == version)
assert(driver_manager.user_agent == "babet-webdriver/" .. version)

assert(babet.mkdir(script_dir .. "/tmp"))

local ok_fractional_window_size = pcall(function()
    webdriver.chromium({
        attach = true,
        port = 1,
        binary = "/bin/true",
        window_size = { 800.5, 600 },
    })
end)
assert(ok_fractional_window_size == false)

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
assert(driver:back())
assert(driver:forward())
assert(driver:refresh())

assert(driver:frame(nil))
assert(driver:parent_frame())
assert(driver:top_frame())

local js_result = assert(driver:js("return arguments", nil, "second"))
assert(js_result.count == 2 and js_result.first_is_null == true and js_result.second == "second")
assert(js_result.async == false)
local async_result = assert(driver:js_async("arguments[arguments.length - 1](arguments)", nil, "second"))
assert(async_result.count == 2 and async_result.first_is_null == true and async_result.second == "second")
assert(async_result.async == true)
assert(driver:js("return null") == babet.json.null)
assert(driver:js("return arguments[0]", babet.json.null) == babet.json.null)
assert(driver:js_async("arguments[arguments.length - 1](null)") == babet.json.null)

local element = assert(driver:css("h1"))
assert(webdriver.is_element(element))
assert(webdriver.element_id(element) == "mock-element")
assert(element:text() == "Mock element")
assert(element:tag() == "input")
local element_rect = assert(element:rect())
assert(element_rect.width == 300 and element_rect.height == 40)
assert(element:css("color") == "rgb(0, 0, 0)")
assert(element:property("value") == "mock-value")
assert(element:dom_attr("data-test") == "mock-attribute")
assert(element:displayed() == true)
assert(element:enabled() == true)
assert(element:selected() == false)
assert(element:computed_role() == "textbox")
assert(element:computed_label() == "Mock label")
assert(element:click())
assert(element:clear())
assert(element:type("Hello"))
assert(webdriver.is_element(assert(element:find("span"))))
assert(#assert(element:find_all("span")) == 1)

local active = assert(driver:active_element())
assert(webdriver.element_id(active) == "mock-element")

local shadow = assert(element:shadow_root())
assert(webdriver.is_shadow_root(shadow))
assert(webdriver.shadow_root_id(shadow) == "mock-shadow")
assert(webdriver.is_element(assert(shadow:find("button"))))
assert(#assert(shadow:find_all("button")) == 1)
local missing_shadow, missing_shadow_err, missing_shadow_code = shadow:find("#missing")
assert(missing_shadow == nil and missing_shadow_err and missing_shadow_code == "no such element")

local exists, exists_err = driver:exists("#missing")
assert(exists == false, exists_err)
assert(driver:wait("#missing", { state = "gone", timeout = 1 }))

local missing, missing_err, missing_code = driver:find("#missing")
assert(missing == nil and missing_err and missing_code == "no such element")

local initial_timeouts = assert(driver:get_timeouts())
assert(initial_timeouts.implicit == 0)
assert(initial_timeouts.page_load == 300)
assert(initial_timeouts.script == 30)
assert(driver:set_timeouts({ implicit = 0.25, page_load = 45, script = 7.5 }))
local updated_timeouts = assert(driver:get_timeouts())
assert(updated_timeouts.implicit == 0.25)
assert(updated_timeouts.page_load == 45)
assert(updated_timeouts.script == 7.5)
assert(driver:set_timeouts({ script = babet.json.null }))
assert(assert(driver:get_timeouts()).script == babet.json.null)
assert(driver:set_timeouts({ script = 7.5 }))

assert(driver:window() == "mock-window-1")
local handles = assert(driver:windows())
assert(#handles == 1 and handles[1] == "mock-window-1")
local tab_handle, tab_type = assert(driver:new_tab())
assert(tab_handle == "mock-window-2" and tab_type == "tab")
assert(driver:switch(tab_handle))
assert(driver:window() == tab_handle)
local window_handle, window_type = assert(driver:new_window("window"))
assert(window_handle == "mock-window-3" and window_type == "window")
assert(driver:switch_last())
assert(driver:window() == window_handle)
local set_rect = assert(driver:set_window_rect({ x = 5, y = 6, width = 800, height = 600 }))
assert(set_rect.x == 5 and set_rect.width == 800)
local rect = assert(driver:window_rect())
assert(rect.y == 6 and rect.height == 600)
assert(assert(driver:maximize()).width == 1920)
assert(assert(driver:minimize()).width == 320)
assert(assert(driver:fullscreen()).height == 1080)
local remaining = assert(driver:close_window())
assert(#remaining == 2)
assert(driver:switch_last())

assert(driver:alert_text() == "Mock alert")
assert(driver:alert_send("answer"))
assert(driver:alert_text() == "answer")
assert(driver:accept_alert())
assert(driver:dismiss_alert())

local theme = assert(driver:cookie("theme"))
assert(theme.value == "light")
local absent_cookie, absent_cookie_err, absent_cookie_code = driver:cookie("absent")
assert(absent_cookie == nil and absent_cookie_err and absent_cookie_code == "no such cookie")
assert(driver:set_cookie({ name = "a/b", value = "encoded", path = "/" }))
assert(assert(driver:cookie("a/b")).value == "encoded")
assert(driver:delete_cookie("a/b"))
local all_cookies = assert(driver:cookies())
assert(#all_cookies == 1 and all_cookies[1].name == "theme")
assert(driver:clear_cookies())
assert(#assert(driver:cookies()) == 0)

local screenshot_base64 = assert(driver:screenshot())
assert(type(screenshot_base64) == "string" and #screenshot_base64 > 0)
local screenshot_path = script_dir .. "/tmp/mock.png"
assert(driver:screenshot(screenshot_path) == screenshot_path)
local file = assert(io.open(screenshot_path, "rb"))
local content = file:read("a")
file:close()
assert(content == "PNG-MOCK\0DATA")

local element_screenshot_path = script_dir .. "/tmp/mock-element.png"
assert(element:screenshot(element_screenshot_path) == element_screenshot_path)
local element_file = assert(io.open(element_screenshot_path, "rb"))
local element_content = element_file:read("a")
element_file:close()
assert(element_content == "PNG-ELEMENT-MOCK\0DATA")

local encoded_pdf = assert(driver:print())
assert(encoded_pdf == assert(babet.base64.encode("PDF-MOCK\0DATA")))

local print_options = {
    orientation = "landscape",
    scale = 0.8,
    background = true,
    page = { width = 21, height = 29.7 },
    margin = { top = 1, bottom = 1.5, left = 2, right = 2.5 },
    shrink_to_fit = false,
    page_ranges = { "1-2", 4 },
}
local pdf_path = script_dir .. "/tmp/mock.pdf"
assert(driver:print(print_options, pdf_path) == pdf_path)
local pdf = assert(io.open(pdf_path, "rb"))
local pdf_content = pdf:read("a")
pdf:close()
assert(pdf_content == "PDF-MOCK\0DATA")

local actions = driver:actions()
assert(actions
    :move_to(element)
    :send_keys("A")
    :scroll(12, -34, { origin = element, x = 3, y = 4, duration = 25 })
    :perform())
-- perform() remet le builder à zéro et il doit rester réutilisable sans wheel.
assert(actions:click(element):perform())
assert(actions:clear())

local ok_invalid_window = pcall(function() driver:new_window("popup") end)
assert(ok_invalid_window == false)
local ok_invalid_print = pcall(function() driver:print({ scale = 3 }) end)
assert(ok_invalid_print == false)
local ok_invalid_scroll = pcall(function() driver:actions():scroll(1, 2, { origin = "pointer" }) end)
assert(ok_invalid_scroll == false)
local ok_fractional_scroll = pcall(function() driver:actions():scroll(1.5, 2) end)
assert(ok_fractional_scroll == false)
local ok_fractional_move = pcall(function() driver:actions():move_by(0.5, 1) end)
assert(ok_fractional_move == false)
local ok_fractional_pause = pcall(function() driver:actions():pause(0.5) end)
assert(ok_fractional_pause == false)
local ok_multi_key = pcall(function() driver:actions():key_down("ab") end)
assert(ok_multi_key == false)
local ok_invalid_rect = pcall(function() driver:set_window_rect({ width = -1 }) end)
assert(ok_invalid_rect == false)
local ok_invalid_frame = pcall(function() driver:frame(65536) end)
assert(ok_invalid_frame == false)

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
assert(babet.rmdirAll(script_dir .. "/tmp"))
print("protocol_test: OK")
