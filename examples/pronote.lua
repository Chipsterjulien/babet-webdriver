#!/usr/bin/env babet
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Julien

-- Exemple volontairement non exécutable tel quel : les URL, sélecteurs et
-- identifiants sont des placeholders. Il montre la transposition des patterns
-- Selenium classiques vers babet-webdriver sans contenir de secret réel.

local script_dir = babet.currentDir()
local root = babet.joinPath(script_dir, "..")
package.path = root .. "/?.lua;" .. script_dir .. "/?.lua;" .. package.path

local webdriver = require("webdriver")
local log = require("logging")
log.set_level("info")

local driver = assert(webdriver.firefox({
    window_size = { 1920, 1080 },
    -- trust_on_first_use = true, -- uniquement après lecture de la section sécurité.
}))

local function stop(code)
    driver:quit()
    os.exit(code or 0)
end
assert(babet.signal.handle("TERM", function() stop(143) end))
assert(babet.signal.handle("INT", function() stop(130) end))

log.info("Connexion à l'ENT…")
assert(driver:open("https://cas.ent.example/login?service=..."))

local profile, profile_err = driver:xpath("/html/body/main/.../li[1]/div/label")
if profile then
    assert(profile:click())
elseif profile_err and not profile_err:find("no such element", 1, true) then
    error(profile_err)
else
    assert(assert(driver:xpath("/html/body/main/.../legend/button")):click())
    assert(assert(driver:xpath("/html/body/main/.../li[1]/div/label")):click())
end

assert(assert(driver:id("button-submit")):click())
local user = assert(driver:wait("username", { by = "id", timeout = 20 }))
assert(user:type("mon_identifiant"))
assert(assert(driver:id("password-input")):type("mon_mot_de_passe"))

local submit = assert(driver:wait("submit-button", {
    by = "id",
    state = "clickable",
    timeout = 20,
}))
assert(driver:js("arguments[0].click();", submit))

local verification, verification_err = driver:exists(
    "//h1[contains(text(),'Vérification')]",
    { by = "xpath" }
)
assert(verification ~= nil, verification_err)
if verification then
    assert(assert(driver:name("j_password")):type("01/01/2000"))
    assert(driver:js("arguments[0].click();", assert(driver:id("submit-button"))))
end

local cookies, cookies_err = driver:exists("tarteaucitronPersonalize2", { by = "id" })
assert(cookies ~= nil, cookies_err)
if cookies then
    babet.sleep(0.5, "s")
    assert(assert(driver:id("tarteaucitronPersonalize2")):click())
end

for index = 1, 12 do
    local button, button_err = driver:xpath(("/html/body/header/nav/ul[2]/li[%d]"):format(index))
    if button then
        local text = assert(button:text())
        if text:lower():find("pronote", 1, true) then
            assert(button:click())
            break
        end
    elseif button_err and not button_err:find("no such element", 1, true) then
        error(button_err)
    end
end
assert(driver:switch_last())

local cell = assert(driver:wait("GInterface.Instances[2].Instances[1]_5_0_div", {
    by = "id",
    timeout = 20,
}))
assert(driver:actions():move_to(cell):click():send_keys("14"):perform())
assert(driver:actions():move_to(cell):double_click():send_keys(webdriver.keys.DELETE):perform())

local class_button = assert(driver:id("...bouton"))
log.info("classe sélectionnée :", assert(class_button:attr("textContent")))

assert(driver:quit())
log.info("terminé")
