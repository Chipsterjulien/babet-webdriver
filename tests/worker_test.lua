#!/usr/bin/env babet
-- SPDX-License-Identifier: GPL-3.0-or-later

local script_dir = babet.currentDir()
local root = babet.joinPath(script_dir, "..")
package.path = root .. "/?.lua;" .. script_dir .. "/?.lua;" .. package.path

local mock = require("mock_webdriver")
local worker_driver = require("webdriver_worker")
local version = require("webdriver_version")

assert(worker_driver.VERSION == version)
assert(babet.mkdir(script_dir .. "/tmp"))

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

assert(session:websocket_url() == nil)
local classic_bidi, classic_bidi_err = session:bidi()
assert(classic_bidi == nil and tostring(classic_bidi_err):find("BiDi non négocié", 1, true))
assert(session:title() == "Mock title")
assert(session:frame(nil))
local js_result = assert(session:js("return arguments", nil, "second"))
assert(js_result.count == 2 and js_result.first_is_null == true and js_result.second == "second")
local async_result = assert(session:js_async("arguments[arguments.length - 1](arguments)", nil, "second"))
assert(async_result.async == true)
assert(session:js("return null") == babet.json.null)
assert(session:js("return arguments[0]", babet.json.null) == babet.json.null)
assert(session:js_async("arguments[arguments.length - 1](null)") == babet.json.null)
local empty_array = assert(session:js("return arguments[0]", babet.json.as_array({})))
assert(assert(babet.json.encode(empty_array)) == "[]")

local element = assert(session:css("h1"))
assert(worker_driver.is_element(element))
assert(element:text() == "Mock element")
assert(element:computed_role() == "textbox")
assert(element:computed_label() == "Mock label")
assert(element:attr("title") == "mock-attr-title")
local missing_attr, missing_attr_err = element:attr("missing")
assert(missing_attr == nil and missing_attr_err == nil)

local active = assert(session:active_element())
assert(worker_driver.is_element(active))

local shadow = assert(element:shadow_root())
assert(worker_driver.is_shadow_root(shadow))
assert(shadow:shadow_root_id() == "mock-shadow")
local shadow_element = assert(shadow:find("button"))
assert(worker_driver.is_element(shadow_element))
assert(#assert(shadow:find_all("button")) == 1)
local missing_shadow, missing_shadow_err, missing_shadow_code = shadow:find("#missing")
assert(missing_shadow == nil and missing_shadow_err and missing_shadow_code == "no such element")

local exists, err = session:exists("#missing")
assert(exists == false, err)
local missing, missing_err, missing_code = session:find("#missing")
assert(missing == nil and missing_err and missing_code == "no such element")

assert(session:set_timeouts({ implicit = 0.5, page_load = 60, script = 8 }))
local timeouts = assert(session:get_timeouts())
assert(timeouts.implicit == 0.5 and timeouts.page_load == 60 and timeouts.script == 8)
assert(session:set_timeouts({ script = babet.json.null }))
assert(assert(session:get_timeouts()).script == babet.json.null)
assert(session:set_timeouts({ script = 8 }))

assert(assert(session:cookie("theme")).value == "light")
local absent_cookie, absent_cookie_err, absent_cookie_code = session:cookie("absent")
assert(absent_cookie == nil and absent_cookie_err and absent_cookie_code == "no such cookie")
assert(session:set_cookie({ name = "worker", value = "ok", path = "/" }))
assert(assert(session:cookie("worker")).value == "ok")

local tab_handle, tab_type = assert(session:new_tab())
assert(tab_handle == "mock-window-2" and tab_type == "tab")
assert(session:switch(tab_handle))
local window_handle, window_type = assert(session:new_window("window"))
assert(window_handle == "mock-window-3" and window_type == "window")
assert(session:switch_last())
assert(assert(session:maximize()).width == 1920)
assert(assert(session:minimize()).width == 320)
assert(assert(session:fullscreen()).height == 1080)

local encoded_pdf = assert(session:print())
assert(encoded_pdf == assert(babet.base64.encode("PDF-MOCK\0DATA")))

local worker_pdf_path = script_dir .. "/tmp/mock-worker.pdf"
assert(session:print({
    orientation = "landscape",
    scale = 0.8,
    background = true,
    page = { width = 21, height = 29.7 },
    margin = { top = 1, bottom = 1.5, left = 2, right = 2.5 },
    shrink_to_fit = false,
    page_ranges = { "1-2", 4 },
}, worker_pdf_path) == worker_pdf_path)
local pdf = assert(io.open(worker_pdf_path, "rb"))
assert(pdf:read("a") == "PDF-MOCK\0DATA")
pdf:close()

assert(session:stop())
local joined, result = server.job:join(5)
assert(joined, result)

local timeout_server = assert(mock.start())
local timeout_session = assert(worker_driver.start({
    browser = "firefox",
    attach = true,
    port = timeout_server.port,
    request_timeout = 5,
    status_timeout = 1,
    start_timeout = 5,
    command_timeout = 0.05,
    worker_start_timeout = 10,
    stop_timeout = 1,
}))
local timed_value, timed_err = timeout_session:wait("#missing", {
    timeout = 0.08,
    interval = 0.02,
})
assert(timed_value == nil and tostring(timed_err):find("webdriver: timeout", 1, true))
assert(not tostring(timed_err):find("réception: timeout", 1, true))

-- Le budget parent suit maintenant le timeout logique de wait(). Le drainage
-- reste défensif : injecte une réponse dupliquée devenue obsolète et vérifie
-- que l'appel suivant retrouve bien sa propre réponse.
assert(timeout_session.results:send({
    kind = "result", id = timeout_session.next_id, ok = true,
    value_count = 1, values = { "stale" },
}, 1))
assert(timeout_session:title() == "Mock title")
assert(timeout_session:stop())
local timeout_joined, timeout_result = timeout_server.job:join(5)
assert(timeout_joined, timeout_result)

-- La négociation BiDi passe également à travers le worker Classic. Ce test ne
-- connecte pas le faux WebSocket : il valide uniquement la capability et les
-- métadonnées transportées vers le parent.
local bidi_server = assert(mock.start())
local bidi_session = assert(worker_driver.start({
    browser = "firefox",
    attach = true,
    port = bidi_server.port,
    request_timeout = 5,
    status_timeout = 1,
    start_timeout = 5,
    command_timeout = 5,
    worker_start_timeout = 10,
    stop_timeout = 5,
    bidi = true,
}))
assert(bidi_session:websocket_url() == "ws://127.0.0.1:65535/mock-session")
assert(bidi_session:stop())
local bidi_joined, bidi_result = bidi_server.job:join(5)
assert(bidi_joined, bidi_result)

-- Une annulation Babet réveille channel:recv() avec le motif "cancelled".
-- Le worker Classic doit traiter ce motif comme un arrêt coopératif, pas comme
-- une erreur de transport. L'accès direct au job est volontaire ici : il
-- exerce précisément la frontière native que Session:cancel() enveloppe.
local cancel_server = assert(mock.start())
local cancel_session = assert(worker_driver.start({
    browser = "firefox",
    attach = true,
    port = cancel_server.port,
    request_timeout = 5,
    status_timeout = 1,
    start_timeout = 5,
    command_timeout = 5,
    worker_start_timeout = 10,
    stop_timeout = 5,
}))
babet.sleep(50, "ms")
assert(cancel_session.job:cancel())
local cancel_joined, cancel_result = cancel_session.job:join(5)
assert(cancel_joined, cancel_result)
cancel_session.commands:close()
cancel_session.results:close()
cancel_session.closed = true
local cancel_server_joined, cancel_server_result = cancel_server.job:join(5)
assert(cancel_server_joined, cancel_server_result)

assert(babet.rmdirAll(script_dir .. "/tmp"))
print("worker_test: OK")
