#!/usr/bin/env babet
-- SPDX-License-Identifier: GPL-3.0-or-later

local script_dir = babet.currentDir()
local root = babet.joinPath(script_dir, "..")
package.path = root .. "/?.lua;" .. package.path

local webdriver = require("webdriver")

local driver, err = webdriver.firefox({
    headless = true,
    bidi = true,
})
if not driver then
    io.stderr:write(tostring(err), "\n")
    os.exit(1)
end

local ok, run_err = xpcall(function()
    local bidi = assert(driver:bidi())
    local status = assert(bidi:status())
    print("BiDi ready:", status.ready, status.message)

    local tree = assert(bidi:get_tree({ max_depth = 0 }))
    local context = assert(tree.contexts[1], "aucun browsing context").context

    local subscription = assert(bidi:subscribe({
        "log.entryAdded",
        "network.beforeRequestSent",
    }))

    assert(bidi:navigate(context, "https://example.com", { wait = "complete" }))
    local evaluated = assert(bidi:evaluate("document.title", context))
    if evaluated.type == "success" and evaluated.result then
        print("Titre:", evaluated.result.value)
    end

    assert(bidi:evaluate("console.log('babet-webdriver BiDi')", context))
    local deadline = babet.monotonic() + 5
    while babet.monotonic() < deadline do
        local event, event_err, event_code = bidi:next_event(deadline - babet.monotonic())
        if event then
            print("Événement:", event.method)
            if event.method == "log.entryAdded" then break end
        elseif event_code ~= "timeout" then
            error(event_err)
        end
    end

    assert(bidi:unsubscribe(subscription))
end, debug.traceback)

local quit_ok, quit_err = driver:quit()
if not quit_ok then
    io.stderr:write("Fermeture WebDriver : ", tostring(quit_err), "\n")
end

if not ok then
    io.stderr:write(tostring(run_err), "\n")
    os.exit(1)
end
