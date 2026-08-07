-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Julien

--------------------------------------------------------------------------------
-- webdriver.lua — client WebDriver W3C pour Babet 2.9+
--------------------------------------------------------------------------------

local function require_babet_29()
    if type(babet) ~= "table" then
        error("webdriver: ce module doit être exécuté avec Babet", 2)
    end
    local major = babet.VERSION_MAJOR or 0
    local minor = babet.VERSION_MINOR or 0
    if major < 2 or (major == 2 and minor < 9) then
        error(("webdriver: Babet 2.9.0 ou supérieur est requis (version détectée : %s)")
            :format(tostring(babet.VERSION or "inconnue")), 2)
    end
end

require_babet_29()

local http = assert(babet.http, "webdriver: module babet.http indisponible")
local json = assert(babet.json, "webdriver: module babet.json indisponible")
local base64 = assert(babet.base64, "webdriver: module babet.base64 indisponible")

local VERSION = require("webdriver_version")
local ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"
local SHADOW_KEY = "shadow-6066-11e4-a52e-4f735466cecf"
local M = {
    VERSION = VERSION,
    ELEMENT_KEY = ELEMENT_KEY,
    SHADOW_KEY = SHADOW_KEY,
}

local WebDriver = {}
WebDriver.__index = WebDriver

local Element = {}
Element.__index = Element

local ShadowRoot = {}
ShadowRoot.__index = ShadowRoot

local Actions = {}
Actions.__index = Actions

local function fail(message)
    return nil, "webdriver: " .. tostring(message)
end

local function strict_table(name, value, allowed)
    if value == nil then
        return {}
    end
    if type(value) ~= "table" then
        error(name .. " doit être une table", 3)
    end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then
            error(("%s : option inconnue %q"):format(name, tostring(key)), 3)
        end
    end
    return value
end

local function finite_positive(name, value, default)
    if value == nil then
        return default
    end
    if type(value) ~= "number" or value ~= value or value == math.huge
        or value == -math.huge or value <= 0 then
        error(name .. " doit être un nombre fini strictement positif", 3)
    end
    return value
end

local function positive_integer(name, value, default)
    if value == nil then
        return default
    end
    if type(value) ~= "number" or math.type(value) ~= "integer" or value <= 0 then
        error(name .. " doit être un entier strictement positif", 3)
    end
    return value
end

local function permissions_value(name, value, default)
    if value == nil then return default end
    if type(value) ~= "number" or math.type(value) ~= "integer" or value < 0 or value > tonumber("777", 8) then
        error(name .. " doit être un entier compris entre 0000 et 0777", 3)
    end
    return value
end

local function optional_boolean(name, value)
    if value ~= nil and type(value) ~= "boolean" then
        error(name .. " doit être un booléen", 3)
    end
    return value
end

local function optional_nonempty_string(name, value)
    if value ~= nil and (type(value) ~= "string" or value == "") then
        error(name .. " doit être une chaîne non vide", 3)
    end
    return value
end

local function optional_sha256(name, value)
    if value == nil then return nil end
    if type(value) ~= "string" or #value ~= 64 or not value:match("^[0-9A-Fa-f]+$") then
        error(name .. " doit contenir exactement 64 chiffres hexadécimaux", 3)
    end
    return value:lower()
end

local function finite_number(name, value, default)
    if value == nil then return default end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        error(name .. " doit être un nombre fini", 3)
    end
    return value
end

local function finite_integer(name, value, default)
    value = finite_number(name, value, default)
    if value == nil then return nil end
    local integer = math.tointeger(value)
    if integer == nil then
        error(name .. " doit être un entier fini", 3)
    end
    return integer
end

local function copy_table(source)
    local out = {}
    if source then
        for key, value in pairs(source) do
            out[key] = value
        end
    end
    return out
end

local function dense_array(values, name)
    if values == nil then
        return {}
    end
    if type(values) ~= "table" then
        error(name .. " doit être un tableau", 3)
    end
    local count = 0
    for key in pairs(values) do
        if type(key) ~= "number" or math.type(key) ~= "integer" or key < 1 then
            error(name .. " doit être un tableau dense", 3)
        end
        count = count + 1
    end
    for index = 1, count do
        if values[index] == nil then
            error(name .. " doit être un tableau dense", 3)
        end
    end
    local out = {}
    for index = 1, count do
        out[index] = values[index]
    end
    return out
end

local function as_json_array(values)
    return json.as_array(values or {})
end

local function url_segment(value)
    value = tostring(value)
    return (value:gsub("([^A-Za-z0-9%-%._~])", function(character)
        return ("%%%02X"):format(character:byte())
    end))
end

local function css_string(value)
    value = tostring(value)
    return (value:gsub("[\\\"\r\n\f]", function(character)
        if character == "\\" then return "\\\\" end
        if character == "\"" then return "\\\"" end
        return ("\\%X "):format(character:byte())
    end))
end

local LOCATOR_OPTIONS = { by = true }

local function locator(selector, opts)
    if type(selector) ~= "string" then
        error("webdriver: le sélecteur doit être une chaîne", 3)
    end
    opts = strict_table("webdriver.find(opts)", opts, LOCATOR_OPTIONS)
    local by = opts.by or "css"
    if by == "css" or by == "css selector" then
        return "css selector", selector
    elseif by == "xpath" then
        return "xpath", selector
    elseif by == "id" then
        return "css selector", '[id="' .. css_string(selector) .. '"]'
    elseif by == "name" then
        return "css selector", '[name="' .. css_string(selector) .. '"]'
    elseif by == "class" then
        return "css selector", '[class~="' .. css_string(selector) .. '"]'
    elseif by == "tag" or by == "tag name" then
        return "tag name", selector
    elseif by == "link" or by == "link text" then
        return "link text", selector
    elseif by == "plink" or by == "partial link text" then
        return "partial link text", selector
    end
    error("webdriver: stratégie de recherche inconnue: " .. tostring(by), 3)
end

local function new_element(driver, id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    return setmetatable({ driver = driver, id = id }, Element)
end

local function new_shadow_root(driver, id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    return setmetatable({ driver = driver, id = id }, ShadowRoot)
end

local function wrap_element(driver, value)
    if type(value) ~= "table" then
        return nil
    end
    return new_element(driver, value[ELEMENT_KEY])
end

local function wrap_shadow_root(driver, value)
    if type(value) ~= "table" then
        return nil
    end
    return new_shadow_root(driver, value[SHADOW_KEY])
end

local function wrap_result(driver, value, seen)
    if value == json.null then
        return json.null
    end
    if type(value) ~= "table" then
        return value
    end
    if value[ELEMENT_KEY] then
        return wrap_element(driver, value)
    end
    if value[SHADOW_KEY] then
        return wrap_shadow_root(driver, value)
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[wrap_result(driver, key, seen)] = wrap_result(driver, child, seen)
    end
    return out
end

local function encode_argument(value, seen)
    if value == json.null then
        return json.null
    end
    if type(value) ~= "table" then
        return value
    end
    if getmetatable(value) == Element then
        return { [ELEMENT_KEY] = value.id }
    end
    if getmetatable(value) == ShadowRoot then
        return { [SHADOW_KEY] = value.id }
    end
    seen = seen or {}
    if seen[value] then
        error("webdriver: une table cyclique ne peut pas être envoyée au driver", 3)
    end
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do
        out[key] = encode_argument(child, seen)
    end
    seen[value] = nil
    return out
end

local function decode_response(response)
    if response.body == nil or response.body == "" then
        return nil, nil
    end
    local decoded, err = json.decode(response.body)
    if not decoded then
        return nil, err
    end
    if type(decoded) ~= "table" then
        return nil, "la racine JSON n'est pas un objet"
    end
    return decoded.value, nil
end

local function transport_request(method, url, body, timeout, max_body_size)
    local options = {
        url = url,
        method = method,
        headers = { ["Content-Type"] = "application/json; charset=utf-8" },
        timeout = timeout,
        max_body_size = max_body_size,
    }
    if body ~= nil then
        if type(body) == "string" then
            options.body = body
        else
            local encoded, encode_err = json.encode(body)
            if not encoded then
                return nil, "webdriver: encodage JSON: " .. tostring(encode_err), "json encode"
            end
            options.body = encoded
        end
    end

    local response, transport_err = http.request(options)
    if not response then
        return nil, "webdriver: transport: " .. tostring(transport_err), "transport"
    end

    local value, decode_err = decode_response(response)
    if decode_err then
        return nil, ("webdriver: réponse non-JSON (HTTP %d): %s")
            :format(response.status, tostring(decode_err)), "invalid response"
    end

    if response.status < 200 or response.status >= 300 then
        local code = "unknown error"
        local message = ""
        if type(value) == "table" then
            code = tostring(value.error or code)
            message = tostring(value.message or "")
        end
        return nil, ("webdriver: %s%s"):format(
            code,
            message ~= "" and (": " .. message) or ""
        ), code
    end

    return value, nil, nil
end

function WebDriver:_request(method, url, body, timeout)
    if self.closed then
        return nil, "webdriver: session fermée", "invalid session id"
    end
    return transport_request(
        method,
        url,
        body,
        timeout or self.request_timeout,
        self.max_body_size
    )
end

local function base64_to_file(encoded, path, max_output, permissions, durable, label)
    if type(encoded) ~= "string" then
        return fail(label .. " Base64 invalide")
    end
    if type(path) ~= "string" or path == "" then
        error("webdriver: le chemin " .. label .. " doit être une chaîne non vide", 3)
    end
    local binary, decode_err = base64.decode(encoded, { max_output = max_output })
    if not binary then
        return fail("décodage Base64 " .. label .. ": " .. tostring(decode_err))
    end
    local parent = babet.getPath(path)
    if parent == "" or parent == "." then parent = nil end
    if parent then
        local created, mkdir_err = babet.mkdir(parent)
        if not created then
            return fail("création du dossier " .. label .. ": " .. tostring(mkdir_err))
        end
    end
    local ok, write_err = babet.writeFileAtomic(path, binary, {
        overwrite = true,
        permissions = permissions,
        durable = durable,
    })
    if not ok then
        return fail("écriture " .. label .. ": " .. tostring(write_err))
    end
    return path
end

local function screenshot_to_file(encoded, path, max_output, permissions, durable)
    return base64_to_file(encoded, path, max_output, permissions, durable, "de capture")
end

local DRIVERS = {
    firefox = {
        default_port = 4444,
        driver_binary = "geckodriver",
        browser_name = "firefox",
        options_key = "moz:firefoxOptions",
        headless_argument = "-headless",
    },
    chrome = {
        default_port = 9515,
        driver_binary = "chromedriver",
        browser_name = "chrome",
        options_key = "goog:chromeOptions",
        headless_argument = "--headless=new",
    },
}
DRIVERS.chromium = {
    default_port = 9515,
    driver_binary = "chromedriver",
    browser_name = "chrome",
    options_key = "goog:chromeOptions",
    headless_argument = "--headless=new",
}

local START_OPTIONS = {
    browser = true,
    headless = true,
    args = true,
    binary = true,
    user_data_dir = true,
    window_size = true,
    port = true,
    port_attempts = true,
    driver_path = true,
    auto_install = true,
    trust_on_first_use = true,
    expected_sha256 = true,
    platform = true,
    cache = true,
    force_driver_download = true,
    attach = true,
    accept_insecure_certs = true,
    request_timeout = true,
    status_timeout = true,
    start_timeout = true,
    poll_interval = true,
    max_body_size = true,
    screenshot_max_size = true,
    screenshot_permissions = true,
    screenshot_durable = true,
    print_max_size = true,
    print_permissions = true,
    print_durable = true,
    log_path = true,
    log_dir = true,
    log_append = true,
    log_permissions = true,
    terminate_grace = true,
}

local function validate_port(port)
    if type(port) ~= "number" or math.type(port) ~= "integer" or port < 1 or port > 65535 then
        error("webdriver: port doit être un entier compris entre 1 et 65535", 3)
    end
    return port
end

local function reserve_free_port()
    local server, listen_err = babet.socket.listen("127.0.0.1", 0)
    if not server then
        return nil, "webdriver: recherche d'un port libre: " .. tostring(listen_err)
    end
    local address, address_err = server:sockname()
    local close_ok, close_err = server:close()
    if not address then
        return nil, "webdriver: lecture du port libre: " .. tostring(address_err)
    end
    if not close_ok then
        return nil, "webdriver: libération du port temporaire: " .. tostring(close_err)
    end
    return address.port
end

local function path_parent(path)
    local parent = babet.getPath(path)
    if parent == nil or parent == "" or parent == "." then
        return nil
    end
    return parent
end

local function timestamp_token()
    local value = babet.monotonic()
    return tostring(value):gsub("[^0-9]", "")
end

local function default_log_path(opts, descriptor, port)
    if opts.log_path then
        local parent = path_parent(opts.log_path)
        if parent then
            local ok, err = babet.mkdir(parent)
            if not ok then
                return nil, "webdriver: création du dossier de logs: " .. tostring(err)
            end
        end
        return opts.log_path
    end

    local log_dir = opts.log_dir
    if not log_dir then
        local manager = require("driver_manager")
        log_dir = manager.cache_dir .. "/logs"
    end
    local ok, err = babet.mkdir(log_dir)
    if not ok then
        return nil, "webdriver: création du dossier de logs: " .. tostring(err)
    end
    return ("%s/%s-%d-%s.log"):format(
        log_dir,
        descriptor.driver_binary,
        port,
        timestamp_token()
    )
end

local function wait_ready(base_url, process, start_timeout, status_timeout, poll_interval, log_path)
    local start = babet.monotonic()
    local last_error
    while babet.monotonic() - start < start_timeout do
        if process then
            local running, running_err = process:is_running()
            if running == nil then
                return nil, "webdriver: état du driver: " .. tostring(running_err)
            end
            if not running then
                local result, wait_err = process:wait(0)
                local code = type(result) == "table" and result.code or "?"
                local details = wait_err and ("; wait: " .. tostring(wait_err)) or ""
                local log = log_path and (", log: " .. log_path) or ""
                return nil, ("webdriver: le driver s'est arrêté avant d'être prêt (code %s%s%s)")
                    :format(tostring(code), details, log)
            end
        end

        local value, request_err = transport_request(
            "GET",
            base_url .. "/status",
            nil,
            status_timeout,
            1024 * 1024
        )
        if type(value) == "table" and value.ready == true then
            return true
        end
        last_error = request_err
        babet.sleep(poll_interval, "s")
    end
    return nil, ("webdriver: driver injoignable après %.3fs%s%s")
        :format(
            start_timeout,
            last_error and ("; dernière erreur: " .. last_error) or "",
            log_path and ("; log: " .. log_path) or ""
        )
end

local function resolve_driver_path(opts, descriptor, browser)
    if opts.driver_path then
        if not babet.isFile(opts.driver_path) then
            return nil, "webdriver: driver introuvable: " .. opts.driver_path
        end
        return opts.driver_path
    end

    local found = babet.which(descriptor.driver_binary)
    if found then
        return found
    end
    if opts.auto_install == false then
        return nil, ("webdriver: %s introuvable dans PATH et auto_install=false")
            :format(descriptor.driver_binary)
    end

    local manager = require("driver_manager")
    return manager.install(browser, {
        trust_on_first_use = opts.trust_on_first_use == true,
        expected_sha256 = opts.expected_sha256,
        platform = opts.platform,
        cache = opts.cache,
        force = opts.force_driver_download == true,
    })
end

local function has_user_data_dir_argument(arguments)
    for _, argument in ipairs(arguments) do
        if argument == "--user-data-dir" or argument:match("^%-%-user%-data%-dir=") then
            return true
        end
    end
    return false
end

local function first_executable(candidates)
    for _, candidate in ipairs(candidates) do
        local path = babet.which(candidate)
        if path then return path end
    end
    return nil
end

local function resolve_browser_binary(opts, browser)
    if opts.binary ~= nil then
        if type(opts.binary) ~= "string" or opts.binary == "" then
            error("webdriver: binary doit être une chaîne non vide", 3)
        end
        if not babet.isFile(opts.binary) then
            return nil, "webdriver: binaire du navigateur introuvable: " .. opts.binary
        end
        return opts.binary
    end

    if browser == "chromium" then
        local path = first_executable({ "chromium", "chromium-browser" })
        if not path then
            return nil, "webdriver: Chromium introuvable dans PATH; utilisez l'option binary"
        end
        return path
    end

    if browser == "chrome" then
        return first_executable({ "google-chrome-stable", "google-chrome", "chrome" })
    end

    return nil
end

local function is_snap_chromium(browser, binary)
    if browser ~= "chromium" or type(binary) ~= "string" then return false end
    return binary:match("^/snap/bin/") ~= nil
        or binary:match("^/snap/chromium/") ~= nil
end

local function make_snap_profile_path(port)
    local home = os.getenv("HOME")
    if type(home) ~= "string" or home == "" then
        return nil, "webdriver: HOME indisponible pour créer le profil temporaire Chromium Snap"
    end
    return babet.joinPath(
        home,
        "snap",
        "chromium",
        "common",
        "babet-webdriver",
        "profiles",
        ("session-%d-%s"):format(port, timestamp_token())
    )
end

local function remove_tree_best_effort(path)
    if not path then return true end
    if not babet.fileExists(path) then return true end
    local ok, err = babet.rmdirAll(path)
    if not ok then
        return nil, "webdriver: nettoyage du profil temporaire: " .. tostring(err)
    end
    return true
end

local function build_capabilities(opts, descriptor, browser_binary, user_data_dir)
    local arguments = dense_array(opts.args, "webdriver.start(args)")
    if opts.headless == true then
        table.insert(arguments, 1, descriptor.headless_argument)
    elseif opts.headless ~= nil and opts.headless ~= false then
        error("webdriver: headless doit être un booléen", 3)
    end

    if opts.window_size ~= nil then
        local dimensions = dense_array(opts.window_size, "webdriver: window_size")
        if #dimensions ~= 2 then
            error("webdriver: window_size doit être exactement { largeur, hauteur }", 3)
        end
        local raw_width = finite_number("webdriver: largeur de window_size", dimensions[1])
        local raw_height = finite_number("webdriver: hauteur de window_size", dimensions[2])
        local width = math.floor(raw_width)
        local height = math.floor(raw_height)
        if width <= 0 or height <= 0 then
            error("webdriver: les dimensions de window_size doivent être positives", 3)
        end
        if descriptor.browser_name == "firefox" then
            arguments[#arguments + 1] = "--width=" .. width
            arguments[#arguments + 1] = "--height=" .. height
        else
            arguments[#arguments + 1] = ("--window-size=%d,%d"):format(width, height)
        end
    end

    if opts.user_data_dir ~= nil and has_user_data_dir_argument(arguments) then
        error("webdriver: user_data_dir ne peut pas être combiné avec --user-data-dir dans args", 3)
    end
    if user_data_dir ~= nil and not has_user_data_dir_argument(arguments) then
        arguments[#arguments + 1] = "--user-data-dir=" .. user_data_dir
    end

    local browser_options = { args = as_json_array(arguments) }
    if browser_binary ~= nil then
        browser_options.binary = browser_binary
    end

    local always_match = {
        browserName = descriptor.browser_name,
        acceptInsecureCerts = opts.accept_insecure_certs == true,
        [descriptor.options_key] = browser_options,
    }
    if opts.accept_insecure_certs ~= nil and type(opts.accept_insecure_certs) ~= "boolean" then
        error("webdriver: accept_insecure_certs doit être un booléen", 3)
    end
    return { capabilities = { alwaysMatch = always_match } }
end

function M.start(options)
    local opts = strict_table("webdriver.start(opts)", options, START_OPTIONS)
    local browser = tostring(opts.browser or "firefox"):lower()
    local descriptor = DRIVERS[browser]
    if not descriptor then
        return fail("navigateur inconnu: " .. browser)
    end

    optional_boolean("webdriver: auto_install", opts.auto_install)
    optional_boolean("webdriver: trust_on_first_use", opts.trust_on_first_use)
    optional_boolean("webdriver: force_driver_download", opts.force_driver_download)
    optional_boolean("webdriver: attach", opts.attach)
    optional_boolean("webdriver: log_append", opts.log_append)
    optional_boolean("webdriver: screenshot_durable", opts.screenshot_durable)
    optional_boolean("webdriver: print_durable", opts.print_durable)
    optional_nonempty_string("webdriver: driver_path", opts.driver_path)
    optional_nonempty_string("webdriver: platform", opts.platform)
    optional_nonempty_string("webdriver: cache", opts.cache)
    optional_nonempty_string("webdriver: log_path", opts.log_path)
    optional_nonempty_string("webdriver: log_dir", opts.log_dir)
    optional_nonempty_string("webdriver: user_data_dir", opts.user_data_dir)
    if browser == "firefox" and opts.user_data_dir ~= nil then
        error("webdriver: user_data_dir est réservé à Chrome et Chromium", 2)
    end
    opts.expected_sha256 = optional_sha256("webdriver: expected_sha256", opts.expected_sha256)
    if opts.port ~= nil then validate_port(opts.port) end
    if opts.port_attempts ~= nil then
        positive_integer("webdriver: port_attempts", opts.port_attempts)
    end

    local request_timeout = finite_positive("webdriver: request_timeout", opts.request_timeout, 120)
    local status_timeout = finite_positive("webdriver: status_timeout", opts.status_timeout, 1)
    local start_timeout = finite_positive("webdriver: start_timeout", opts.start_timeout, 15)
    local poll_interval = finite_positive("webdriver: poll_interval", opts.poll_interval, 0.1)
    local max_body_size = positive_integer("webdriver: max_body_size", opts.max_body_size, 64 * 1024 * 1024)
    local screenshot_max_size = positive_integer(
        "webdriver: screenshot_max_size",
        opts.screenshot_max_size,
        64 * 1024 * 1024
    )
    local screenshot_permissions = permissions_value(
        "webdriver: screenshot_permissions",
        opts.screenshot_permissions,
        tonumber("644", 8)
    )
    local print_max_size = positive_integer(
        "webdriver: print_max_size",
        opts.print_max_size,
        64 * 1024 * 1024
    )
    local print_permissions = permissions_value(
        "webdriver: print_permissions",
        opts.print_permissions,
        tonumber("644", 8)
    )
    local log_permissions = permissions_value(
        "webdriver: log_permissions",
        opts.log_permissions,
        tonumber("600", 8)
    )
    local terminate_grace = finite_positive("webdriver: terminate_grace", opts.terminate_grace, 2)
    local log_append = opts.log_append ~= false
    local screenshot_durable = opts.screenshot_durable ~= false
    local print_durable = opts.print_durable ~= false

    local browser_binary, browser_binary_err = resolve_browser_binary(opts, browser)
    if browser_binary_err then return nil, browser_binary_err end

    -- Valide les capabilities avant de lancer un processus afin qu'une erreur
    -- de programmation ne puisse jamais laisser un driver orphelin.
    build_capabilities(opts, descriptor, browser_binary, opts.user_data_dir)

    local driver_path
    if not opts.attach then
        local path_err
        driver_path, path_err = resolve_driver_path(opts, descriptor, browser)
        if not driver_path then
            return nil, path_err
        end
    end

    local explicit_port = opts.port ~= nil
    local attempts = (explicit_port or opts.attach) and 1
        or positive_integer("webdriver: port_attempts", opts.port_attempts, 5)
    local process
    local port
    local base_url
    local log_path
    local ready_err

    for _ = 1, attempts do
        if explicit_port then
            port = validate_port(opts.port)
        elseif opts.attach then
            port = descriptor.default_port
        else
            port, ready_err = reserve_free_port()
            if not port then
                return nil, ready_err
            end
        end
        base_url = ("http://127.0.0.1:%d"):format(port)

        if opts.attach then
            local ok
            ok, ready_err = wait_ready(base_url, nil, start_timeout, status_timeout, poll_interval, nil)
            if ok then break end
            return nil, ready_err
        end

        log_path, ready_err = default_log_path(opts, descriptor, port)
        if not log_path then
            return nil, ready_err
        end

        process, ready_err = babet.spawn(driver_path, {
            "--port=" .. tostring(port),
        }, {
            stdin = "null",
            stdout = {
                file = log_path,
                append = log_append,
                permissions = log_permissions,
            },
            stderr = "stdout",
        })

        if process then
            local ready
            ready, ready_err = wait_ready(
                base_url,
                process,
                start_timeout,
                status_timeout,
                poll_interval,
                log_path
            )
            if ready then
                break
            end
            process:terminate(terminate_grace)
            process:close()
            process = nil
        end
    end

    if not opts.attach and not process then
        return nil, ready_err or "webdriver: impossible de lancer le driver"
    end

    local temporary_profile_dir
    local user_data_dir = opts.user_data_dir
    if user_data_dir == nil and is_snap_chromium(browser, browser_binary) then
        local profile_err
        user_data_dir, profile_err = make_snap_profile_path(port)
        if not user_data_dir then
            if process then
                process:terminate(terminate_grace)
                process:close()
            end
            return nil, profile_err
        end
        temporary_profile_dir = user_data_dir
    end

    if user_data_dir ~= nil and not has_user_data_dir_argument(dense_array(opts.args, "webdriver.start(args)")) then
        local profile_ok, profile_err = babet.mkdir(user_data_dir)
        if not profile_ok then
            if process then
                process:terminate(terminate_grace)
                process:close()
            end
            return nil, "webdriver: création du profil navigateur: " .. tostring(profile_err)
        end
    end

    local session_body = build_capabilities(
        opts,
        descriptor,
        browser_binary,
        user_data_dir
    )

    local session_value, session_err = transport_request(
        "POST",
        base_url .. "/session",
        session_body,
        request_timeout,
        max_body_size
    )
    if not session_value then
        if process then
            process:terminate(terminate_grace)
            process:close()
        end
        local _, cleanup_err = remove_tree_best_effort(temporary_profile_dir)
        local details = tostring(session_err)
        if log_path then details = details .. "; log: " .. log_path end
        if cleanup_err then details = details .. "; " .. cleanup_err end
        return nil, details
    end

    local session_id
    local capabilities = {}
    if type(session_value) == "table" then
        session_id = session_value.sessionId
        capabilities = session_value.capabilities or {}
    end
    if type(session_id) ~= "string" or session_id == "" then
        if process then
            process:terminate(terminate_grace)
            process:close()
        end
        remove_tree_best_effort(temporary_profile_dir)
        return fail("réponse de création de session sans sessionId")
    end

    local driver = setmetatable({
        browser = browser,
        base_url = base_url,
        session_id = session_id,
        session = base_url .. "/session/" .. url_segment(session_id),
        capabilities_value = capabilities,
        process = process,
        owns_process = process ~= nil,
        port_value = port,
        log_path_value = log_path,
        browser_binary_value = browser_binary,
        temporary_profile_dir = temporary_profile_dir,
        request_timeout = request_timeout,
        status_timeout = status_timeout,
        max_body_size = max_body_size,
        screenshot_max_size = screenshot_max_size,
        screenshot_permissions = screenshot_permissions,
        screenshot_durable = screenshot_durable,
        print_max_size = print_max_size,
        print_permissions = print_permissions,
        print_durable = print_durable,
        terminate_grace = terminate_grace,
        closed = false,
    }, WebDriver)

    return driver
end

local function with_browser(options, browser)
    local opts = copy_table(options)
    opts.browser = browser
    return M.start(opts)
end

function M.firefox(options) return with_browser(options, "firefox") end
function M.chrome(options) return with_browser(options, "chrome") end
function M.chromium(options) return with_browser(options, "chromium") end

function M.is_element(value)
    return type(value) == "table" and getmetatable(value) == Element
end

function M.element_id(value)
    if not M.is_element(value) then
        return nil
    end
    return value.id
end

function M.element(driver, id)
    if getmetatable(driver) ~= WebDriver then
        error("webdriver.element: driver invalide", 2)
    end
    if type(id) ~= "string" or id == "" then
        error("webdriver.element: id doit être une chaîne non vide", 2)
    end
    return new_element(driver, id)
end

function M.is_shadow_root(value)
    return type(value) == "table" and getmetatable(value) == ShadowRoot
end

function M.shadow_root_id(value)
    if not M.is_shadow_root(value) then return nil end
    return value.id
end

function M.shadow_root(driver, id)
    if getmetatable(driver) ~= WebDriver then
        error("webdriver.shadow_root: driver invalide", 2)
    end
    if type(id) ~= "string" or id == "" then
        error("webdriver.shadow_root: id doit être une chaîne non vide", 2)
    end
    return new_shadow_root(driver, id)
end

function WebDriver:capabilities()
    return self.capabilities_value
end

function WebDriver:port()
    return self.port_value
end

function WebDriver:pid()
    if not self.process then return nil end
    return self.process:pid()
end

function WebDriver:log_path()
    return self.log_path_value
end

function WebDriver:browser_binary()
    return self.browser_binary_value
end

function WebDriver:is_running()
    if not self.process then
        return not self.closed
    end
    return self.process:is_running()
end

function WebDriver:open(url)
    if type(url) ~= "string" or url == "" then
        error("webdriver.open: url doit être une chaîne non vide", 2)
    end
    local _, err = self:_request("POST", self.session .. "/url", { url = url })
    if err then return nil, err end
    return true
end

function WebDriver:url() return self:_request("GET", self.session .. "/url") end
function WebDriver:title() return self:_request("GET", self.session .. "/title") end
function WebDriver:source() return self:_request("GET", self.session .. "/source") end

local function navigation(driver, name)
    local _, err = driver:_request("POST", driver.session .. "/" .. name, {})
    if err then return nil, err end
    return true
end

function WebDriver:back() return navigation(self, "back") end
function WebDriver:forward() return navigation(self, "forward") end
function WebDriver:refresh() return navigation(self, "refresh") end

function WebDriver:find(selector, opts)
    local using, value = locator(selector, opts)
    local response, err, code = self:_request("POST", self.session .. "/element", {
        using = using,
        value = value,
    })
    if response == nil then return nil, err, code end
    local element = wrap_element(self, response)
    if not element then
        return fail("réponse d'élément invalide")
    end
    return element
end

function WebDriver:find_all(selector, opts)
    local using, value = locator(selector, opts)
    local response, err, code = self:_request("POST", self.session .. "/elements", {
        using = using,
        value = value,
    })
    if response == nil then return nil, err, code end
    if type(response) ~= "table" then
        return fail("réponse de liste d'éléments invalide")
    end
    local out = {}
    for _, raw in ipairs(response) do
        local element = wrap_element(self, raw)
        if not element then
            return fail("réponse de liste d'éléments invalide")
        end
        out[#out + 1] = element
    end
    return out
end

function WebDriver:active_element()
    local response, err, code = self:_request("GET", self.session .. "/element/active")
    if response == nil then return nil, err, code end
    local element = wrap_element(self, response)
    if not element then return fail("réponse d'élément actif invalide") end
    return element
end

function WebDriver:css(selector) return self:find(selector, { by = "css" }) end
function WebDriver:xpath(selector) return self:find(selector, { by = "xpath" }) end
function WebDriver:id(selector) return self:find(selector, { by = "id" }) end
function WebDriver:name(selector) return self:find(selector, { by = "name" }) end
function WebDriver:tag(selector) return self:find(selector, { by = "tag" }) end

function WebDriver:exists(selector, opts)
    local element, err, code = self:find(selector, opts)
    if element then return true end
    if code == "no such element" then return false end
    return nil, err
end

function WebDriver:wait_until(callback, timeout, interval)
    if type(callback) ~= "function" then
        error("webdriver.wait_until: callback doit être une fonction", 2)
    end
    timeout = finite_positive("webdriver.wait_until: timeout", timeout, 10)
    interval = finite_positive("webdriver.wait_until: interval", interval, 0.2)
    local started = babet.monotonic()
    local last_error
    while true do
        local called, value, callback_err = pcall(callback)
        if not called then
            return fail("callback d'attente: " .. tostring(value))
        end
        if value then
            return value
        end
        if callback_err ~= nil then
            last_error = tostring(callback_err)
        end
        if babet.monotonic() - started >= timeout then
            return nil, "webdriver: timeout" .. (last_error and (": " .. last_error) or "")
        end
        babet.sleep(interval, "s")
    end
end

local WAIT_OPTIONS = {
    by = true,
    state = true,
    timeout = true,
    interval = true,
    ignore_stale = true,
}

function WebDriver:wait(selector, options)
    local opts = strict_table("webdriver.wait(opts)", options, WAIT_OPTIONS)
    local timeout = finite_positive("webdriver.wait: timeout", opts.timeout, 10)
    local interval = finite_positive("webdriver.wait: interval", opts.interval, 0.2)
    local state = opts.state or "present"
    local valid_states = { present = true, visible = true, clickable = true, gone = true }
    if not valid_states[state] then
        error("webdriver: état d'attente inconnu: " .. tostring(state), 2)
    end
    if opts.ignore_stale ~= nil and type(opts.ignore_stale) ~= "boolean" then
        error("webdriver.wait: ignore_stale doit être un booléen", 2)
    end
    local ignore_stale = opts.ignore_stale ~= false
    local locator_opts = { by = opts.by }
    local started = babet.monotonic()
    local last_error

    while true do
        local element, find_err, find_code = self:find(selector, locator_opts)
        if not element then
            if find_code == "no such element" then
                if state == "gone" then return true end
            elseif ignore_stale and find_code == "stale element reference" then
                -- Nouvelle tentative.
            else
                return nil, find_err
            end
            last_error = find_err
        elseif state == "present" then
            return element
        elseif state == "gone" then
            last_error = "l'élément est encore présent"
        else
            local displayed, displayed_err, displayed_code = element:displayed()
            if displayed == nil then
                if ignore_stale and displayed_code == "stale element reference" then
                    last_error = displayed_err
                else
                    return nil, displayed_err
                end
            elseif state == "visible" and displayed then
                return element
            elseif state == "clickable" and displayed then
                local enabled, enabled_err, enabled_code = element:enabled()
                if enabled == nil then
                    if ignore_stale and enabled_code == "stale element reference" then
                        last_error = enabled_err
                    else
                        return nil, enabled_err
                    end
                elseif enabled then
                    return element
                end
            end
        end

        if babet.monotonic() - started >= timeout then
            return nil, ("webdriver: timeout (%s) en attendant %q%s")
                :format(state, selector, last_error and ("; " .. last_error) or "")
        end
        babet.sleep(interval, "s")
    end
end

local function execute_script(driver, endpoint, label, script, ...)
    if type(script) ~= "string" then
        error("webdriver." .. label .. ": script doit être une chaîne", 3)
    end
    local count = select("#", ...)
    local arguments = {}
    for index = 1, count do
        local argument = select(index, ...)
        arguments[index] = argument == nil and json.null or encode_argument(argument)
    end
    local value, err, code = driver:_request("POST", driver.session .. endpoint, {
        script = script,
        args = as_json_array(arguments),
    })
    if err then return nil, err, code end
    return wrap_result(driver, value)
end

function WebDriver:js(script, ...)
    return execute_script(self, "/execute/sync", "js", script, ...)
end

function WebDriver:js_async(script, ...)
    return execute_script(self, "/execute/async", "js_async", script, ...)
end

function WebDriver:screenshot(path)
    local encoded, err = self:_request("GET", self.session .. "/screenshot")
    if encoded == nil then return nil, err end
    if path == nil then return encoded end
    return screenshot_to_file(
        encoded,
        path,
        self.screenshot_max_size,
        self.screenshot_permissions,
        self.screenshot_durable
    )
end

local PRINT_OPTIONS = {
    orientation = true,
    scale = true,
    background = true,
    page = true,
    margin = true,
    shrink_to_fit = true,
    page_ranges = true,
}

local function finite_range(name, value, minimum, maximum)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge
        or value < minimum or (maximum ~= nil and value > maximum) then
        error(("%s doit être un nombre fini compris entre %s et %s")
            :format(name, tostring(minimum), maximum and tostring(maximum) or "+inf"), 3)
    end
    return value
end

local function print_parameters(options)
    local opts = strict_table("webdriver.print(opts)", options, PRINT_OPTIONS)
    local body = {}
    if opts.orientation ~= nil then
        if opts.orientation ~= "portrait" and opts.orientation ~= "landscape" then
            error("webdriver.print: orientation doit valoir 'portrait' ou 'landscape'", 3)
        end
        body.orientation = opts.orientation
    end
    if opts.scale ~= nil then
        body.scale = finite_range("webdriver.print: scale", opts.scale, 0.1, 2)
    end
    if opts.background ~= nil then
        if type(opts.background) ~= "boolean" then
            error("webdriver.print: background doit être un booléen", 3)
        end
        body.background = opts.background
    end
    if opts.shrink_to_fit ~= nil then
        if type(opts.shrink_to_fit) ~= "boolean" then
            error("webdriver.print: shrink_to_fit doit être un booléen", 3)
        end
        body.shrinkToFit = opts.shrink_to_fit
    end
    if opts.page ~= nil then
        local page = strict_table("webdriver.print: page", opts.page, { width = true, height = true })
        local encoded = {}
        if page.width ~= nil then
            encoded.width = finite_range("webdriver.print: page.width", page.width, 2.54 / 72)
        end
        if page.height ~= nil then
            encoded.height = finite_range("webdriver.print: page.height", page.height, 2.54 / 72)
        end
        body.page = encoded
    end
    if opts.margin ~= nil then
        local margin = strict_table("webdriver.print: margin", opts.margin, {
            top = true, bottom = true, left = true, right = true,
        })
        local encoded = {}
        for _, name in ipairs({ "top", "bottom", "left", "right" }) do
            if margin[name] ~= nil then
                encoded[name] = finite_range("webdriver.print: margin." .. name, margin[name], 0)
            end
        end
        body.margin = encoded
    end
    if opts.page_ranges ~= nil then
        local ranges = dense_array(opts.page_ranges, "webdriver.print: page_ranges")
        local encoded = {}
        for index, value in ipairs(ranges) do
            local value_type = type(value)
            if value_type == "number" then
                if math.type(value) ~= "integer" or value < 0 then
                    error("webdriver.print: page_ranges contient un numéro de page invalide", 3)
                end
            elseif value_type ~= "string" then
                error("webdriver.print: page_ranges doit contenir des chaînes ou entiers", 3)
            end
            encoded[index] = value
        end
        body.pageRanges = as_json_array(encoded)
    end
    return body
end

function WebDriver:print(options, path)
    if type(options) == "string" and path == nil then
        path, options = options, nil
    end
    local body = print_parameters(options)
    local encoded, err = self:_request("POST", self.session .. "/print", body)
    if encoded == nil then return nil, err end
    if path == nil then return encoded end
    return base64_to_file(
        encoded,
        path,
        self.print_max_size,
        self.print_permissions,
        self.print_durable,
        "du PDF"
    )
end

function WebDriver:window() return self:_request("GET", self.session .. "/window") end
function WebDriver:windows() return self:_request("GET", self.session .. "/window/handles") end

function WebDriver:switch(handle)
    if type(handle) ~= "string" or handle == "" then
        error("webdriver.switch: handle doit être une chaîne non vide", 2)
    end
    local _, err = self:_request("POST", self.session .. "/window", { handle = handle })
    if err then return nil, err end
    return true
end

function WebDriver:switch_last()
    local handles, err = self:windows()
    if not handles then return nil, err end
    local handle = handles[#handles]
    if not handle then return fail("aucune fenêtre disponible") end
    return self:switch(handle)
end

function WebDriver:new_window(kind)
    if kind ~= nil and kind ~= "tab" and kind ~= "window" then
        error("webdriver.new_window: type attendu = 'tab', 'window' ou nil", 2)
    end
    local body = kind and { type = kind } or {}
    local value, err, code = self:_request("POST", self.session .. "/window/new", body)
    if value == nil then return nil, err, code end
    if type(value) ~= "table" or type(value.handle) ~= "string" or value.handle == "" then
        return fail("réponse de création de fenêtre invalide")
    end
    return value.handle, value.type
end

function WebDriver:new_tab()
    return self:new_window("tab")
end

function WebDriver:close_window()
    return self:_request("DELETE", self.session .. "/window")
end

function WebDriver:set_window_rect(rect)
    rect = strict_table("webdriver.set_window_rect(rect)", rect, {
        x = true, y = true, width = true, height = true,
    })

    local function coordinate(name, value, minimum, maximum)
        if value == nil then return nil end
        if value == json.null then return json.null end
        value = finite_number("webdriver.set_window_rect: " .. name, value)
        if value < minimum or value > maximum then
            error(string.format(
                "webdriver.set_window_rect: %s doit être compris entre %d et %d",
                name, minimum, maximum
            ), 3)
        end
        return value
    end

    local body = {}
    body.x = coordinate("x", rect.x, -2147483648, 2147483647)
    body.y = coordinate("y", rect.y, -2147483648, 2147483647)
    body.width = coordinate("width", rect.width, 0, 2147483647)
    body.height = coordinate("height", rect.height, 0, 2147483647)

    local value, err = self:_request("POST", self.session .. "/window/rect", body)
    if err then return nil, err end
    return value
end

function WebDriver:window_rect()
    return self:_request("GET", self.session .. "/window/rect")
end

local function window_state(driver, endpoint)
    return driver:_request("POST", driver.session .. "/window/" .. endpoint, {})
end

function WebDriver:maximize() return window_state(self, "maximize") end
function WebDriver:minimize() return window_state(self, "minimize") end
function WebDriver:fullscreen() return window_state(self, "fullscreen") end

function WebDriver:frame(target)
    local id
    if target == nil then
        id = json.null
    elseif type(target) == "number" and math.type(target) == "integer"
        and target >= 0 and target <= 65535 then
        id = target
    elseif M.is_element(target) then
        id = { [ELEMENT_KEY] = target.id }
    else
        error("webdriver.frame: cible attendue = nil, index entier 0..65535 ou Element", 2)
    end
    local _, err = self:_request("POST", self.session .. "/frame", { id = id })
    if err then return nil, err end
    return true
end

function WebDriver:top_frame() return self:frame(nil) end

function WebDriver:parent_frame()
    local _, err = self:_request("POST", self.session .. "/frame/parent", {})
    if err then return nil, err end
    return true
end

function WebDriver:alert_text()
    return self:_request("GET", self.session .. "/alert/text")
end

local function alert_action(driver, verb)
    local _, err = driver:_request("POST", driver.session .. "/alert/" .. verb, {})
    if err then return nil, err end
    return true
end

function WebDriver:accept_alert() return alert_action(self, "accept") end
function WebDriver:dismiss_alert() return alert_action(self, "dismiss") end

function WebDriver:alert_send(text)
    if type(text) ~= "string" then
        error("webdriver.alert_send: text doit être une chaîne", 2)
    end
    local _, err = self:_request("POST", self.session .. "/alert/text", { text = text })
    if err then return nil, err end
    return true
end

function WebDriver:cookies()
    return self:_request("GET", self.session .. "/cookie")
end

function WebDriver:cookie(name)
    if type(name) ~= "string" or name == "" then
        error("webdriver.cookie: name doit être une chaîne non vide", 2)
    end
    return self:_request("GET", self.session .. "/cookie/" .. url_segment(name))
end

function WebDriver:set_cookie(cookie)
    if type(cookie) ~= "table" then
        error("webdriver.set_cookie: cookie doit être une table", 2)
    end
    local _, err = self:_request("POST", self.session .. "/cookie", { cookie = cookie })
    if err then return nil, err end
    return true
end

function WebDriver:delete_cookie(name)
    if type(name) ~= "string" or name == "" then
        error("webdriver.delete_cookie: name doit être une chaîne non vide", 2)
    end
    local _, err = self:_request("DELETE", self.session .. "/cookie/" .. url_segment(name))
    if err then return nil, err end
    return true
end

function WebDriver:clear_cookies()
    local _, err = self:_request("DELETE", self.session .. "/cookie")
    if err then return nil, err end
    return true
end

function WebDriver:get_timeouts()
    local value, err, code = self:_request("GET", self.session .. "/timeouts")
    if value == nil then return nil, err, code end
    if type(value) ~= "table" then return fail("réponse de timeouts invalide") end
    local function from_milliseconds(name, raw)
        if raw == json.null then return json.null end
        if type(raw) ~= "number" or raw ~= raw or raw < 0
            or raw == math.huge or raw == -math.huge then
            error("webdriver: timeout W3C invalide reçu pour " .. name, 3)
        end
        return raw / 1000
    end
    return {
        implicit = from_milliseconds("implicit", value.implicit),
        page_load = from_milliseconds("pageLoad", value.pageLoad),
        script = from_milliseconds("script", value.script),
    }
end

function WebDriver:set_timeouts(timeouts)
    timeouts = strict_table("webdriver.set_timeouts(timeouts)", timeouts, {
        implicit = true,
        page_load = true,
        script = true,
    })
    local body = {}
    local function to_milliseconds(name, value)
        if value == nil then return nil end
        if value == json.null then return json.null end
        if type(value) ~= "number" or value ~= value or value < 0
            or value == math.huge or value == -math.huge then
            error("webdriver.set_timeouts: " .. name
                .. " doit être un nombre fini positif, nul ou json.null", 3)
        end
        local milliseconds = value * 1000
        if milliseconds > 9007199254740991 then
            error("webdriver.set_timeouts: " .. name .. " dépasse la limite W3C sûre", 3)
        end
        return math.floor(milliseconds)
    end
    body.implicit = to_milliseconds("implicit", timeouts.implicit)
    body.pageLoad = to_milliseconds("page_load", timeouts.page_load)
    body.script = to_milliseconds("script", timeouts.script)
    local _, err = self:_request("POST", self.session .. "/timeouts", body)
    if err then return nil, err end
    return true
end

function WebDriver:quit()
    if self.closed then return true end
    local session_error
    if self.session_id then
        local _, err = self:_request("DELETE", self.session, nil, math.min(self.request_timeout, 5))
        session_error = err
        self.session_id = nil
    end
    self.closed = true

    local process_error
    if self.process then
        local _, terminate_err = self.process:terminate(self.terminate_grace)
        if terminate_err then process_error = terminate_err end
        local _, close_err = self.process:close()
        if close_err and not process_error then process_error = close_err end
        self.process = nil
    end

    local profile_error
    if self.temporary_profile_dir then
        local _, cleanup_err = remove_tree_best_effort(self.temporary_profile_dir)
        profile_error = cleanup_err
        self.temporary_profile_dir = nil
    end

    if process_error then
        return fail("arrêt du driver: " .. tostring(process_error))
    end
    if profile_error then
        return nil, profile_error
    end
    if session_error then
        return nil, session_error
    end
    return true
end

WebDriver.close = WebDriver.quit
WebDriver.__close = function(self) self:quit() end

local function element_url(element, suffix)
    return element.driver.session .. "/element/" .. url_segment(element.id) .. suffix
end

local function element_post(element, suffix, body)
    local _, err = element.driver:_request("POST", element_url(element, suffix), body or {})
    if err then return nil, err end
    return true
end

function Element:element_id() return self.id end
function Element:click() return element_post(self, "/click") end
function Element:clear() return element_post(self, "/clear") end

function Element:type(text)
    if type(text) ~= "string" then
        error("webdriver Element:type: text doit être une chaîne", 2)
    end
    return element_post(self, "/value", { text = text })
end

function Element:text() return self.driver:_request("GET", element_url(self, "/text")) end
function Element:tag() return self.driver:_request("GET", element_url(self, "/name")) end
function Element:rect() return self.driver:_request("GET", element_url(self, "/rect")) end
function Element:computed_role() return self.driver:_request("GET", element_url(self, "/computedrole")) end
function Element:computed_label() return self.driver:_request("GET", element_url(self, "/computedlabel")) end

function Element:shadow_root()
    local value, err, code = self.driver:_request("GET", element_url(self, "/shadow"))
    if value == nil then return nil, err, code end
    local shadow = wrap_shadow_root(self.driver, value)
    if not shadow then return fail("réponse de ShadowRoot invalide") end
    return shadow
end
local function element_name(name, label)
    if type(name) ~= "string" or name == "" then
        error("webdriver Element:" .. label .. ": nom doit être une chaîne non vide", 3)
    end
    return name
end

function Element:css(name)
    return self.driver:_request("GET", element_url(self, "/css/" .. url_segment(element_name(name, "css"))))
end
function Element:property(name)
    return self.driver:_request("GET", element_url(self, "/property/" .. url_segment(element_name(name, "property"))))
end
function Element:dom_attr(name)
    return self.driver:_request("GET", element_url(self, "/attribute/" .. url_segment(element_name(name, "dom_attr"))))
end

local function element_boolean(element, suffix)
    local value, err, code = element.driver:_request("GET", element_url(element, suffix))
    if value == nil then return nil, err, code end
    return value == true
end

function Element:displayed() return element_boolean(self, "/displayed") end
function Element:enabled() return element_boolean(self, "/enabled") end
function Element:selected() return element_boolean(self, "/selected") end

local ATTRIBUTE_SCRIPT = [[
var e = arguments[0], name = arguments[1];
var v = e.getAttribute(name);
if (v === null && name in e) { v = e[name]; }
if (typeof v === 'boolean') { v = v ? 'true' : null; }
return v === undefined ? null : v;
]]

function Element:attr(name)
    return self.driver:js(ATTRIBUTE_SCRIPT, self, name)
end

function Element:value() return self:property("value") end

local SUBMIT_SCRIPT = [[
var e = arguments[0];
var f = (e.tagName && e.tagName.toLowerCase() === 'form') ? e : e.closest('form');
if (!f) { throw new Error('aucun formulaire englobant'); }
if (typeof f.requestSubmit === 'function') { f.requestSubmit(); } else { f.submit(); }
return true;
]]

function Element:submit()
    local _, err = self.driver:js(SUBMIT_SCRIPT, self)
    if err then return nil, err end
    return true
end

function Element:find(selector, opts)
    local using, value = locator(selector, opts)
    local response, err, code = self.driver:_request("POST", element_url(self, "/element"), {
        using = using,
        value = value,
    })
    if response == nil then return nil, err, code end
    local element = wrap_element(self.driver, response)
    if not element then return fail("réponse d'élément imbriqué invalide") end
    return element
end

function Element:find_all(selector, opts)
    local using, value = locator(selector, opts)
    local response, err, code = self.driver:_request("POST", element_url(self, "/elements"), {
        using = using,
        value = value,
    })
    if response == nil then return nil, err, code end
    if type(response) ~= "table" then
        return fail("réponse de liste d'éléments imbriqués invalide")
    end
    local out = {}
    for _, raw in ipairs(response) do
        local element = wrap_element(self.driver, raw)
        if not element then return fail("réponse de liste d'éléments imbriqués invalide") end
        out[#out + 1] = element
    end
    return out
end

function Element:screenshot(path)
    local encoded, err = self.driver:_request("GET", element_url(self, "/screenshot"))
    if encoded == nil then return nil, err end
    if path == nil then return encoded end
    return screenshot_to_file(
        encoded,
        path,
        self.driver.screenshot_max_size,
        self.driver.screenshot_permissions,
        self.driver.screenshot_durable
    )
end

function ShadowRoot:shadow_root_id() return self.id end

local function shadow_url(shadow, suffix)
    return shadow.driver.session .. "/shadow/" .. url_segment(shadow.id) .. suffix
end

function ShadowRoot:find(selector, opts)
    local using, value = locator(selector, opts)
    local response, err, code = self.driver:_request("POST", shadow_url(self, "/element"), {
        using = using,
        value = value,
    })
    if response == nil then return nil, err, code end
    local element = wrap_element(self.driver, response)
    if not element then return fail("réponse d'élément Shadow DOM invalide") end
    return element
end

function ShadowRoot:find_all(selector, opts)
    local using, value = locator(selector, opts)
    local response, err, code = self.driver:_request("POST", shadow_url(self, "/elements"), {
        using = using,
        value = value,
    })
    if response == nil then return nil, err, code end
    if type(response) ~= "table" then return fail("réponse de liste Shadow DOM invalide") end
    local out = {}
    for _, raw in ipairs(response) do
        local element = wrap_element(self.driver, raw)
        if not element then return fail("réponse de liste Shadow DOM invalide") end
        out[#out + 1] = element
    end
    return out
end

function WebDriver:actions()
    return setmetatable({
        driver = self,
        key = {},
        pointer = {},
        wheel = {},
        wheel_active = false,
    }, Actions)
end

local function add_action(actions, device, action)
    for _, current in ipairs({ "key", "pointer", "wheel" }) do
        if current == device then
            actions[current][#actions[current] + 1] = action
        else
            actions[current][#actions[current] + 1] = { type = "pause", duration = 0 }
        end
    end
    if device == "wheel" then actions.wheel_active = true end
end

local function pointer_down(actions, button)
    add_action(actions, "pointer", { type = "pointerDown", button = button or 0 })
end

local function pointer_up(actions, button)
    add_action(actions, "pointer", { type = "pointerUp", button = button or 0 })
end

local function key_event(actions, kind, character)
    if type(character) ~= "string" or character == "" then
        error("webdriver Actions: touche doit être une chaîne non vide", 3)
    end
    local ok, length = pcall(utf8.len, character)
    if not ok or length ~= 1 then
        error("webdriver Actions: key_down/key_up attend exactement un caractère Unicode", 3)
    end
    add_action(actions, "key", { type = kind, value = character })
end

function Actions:move_to(element, x, y)
    if element ~= nil and not M.is_element(element) then
        error("webdriver Actions:move_to: element invalide", 2)
    end
    x = finite_integer("webdriver Actions:move_to: x", x, 0)
    y = finite_integer("webdriver Actions:move_to: y", y, 0)
    add_action(self, "pointer", {
        type = "pointerMove",
        duration = 100,
        origin = element and { [ELEMENT_KEY] = element.id } or "viewport",
        x = x,
        y = y,
    })
    return self
end

function Actions:move_by(x, y)
    x = finite_integer("webdriver Actions:move_by: x", x)
    y = finite_integer("webdriver Actions:move_by: y", y)
    add_action(self, "pointer", {
        type = "pointerMove",
        duration = 100,
        origin = "pointer",
        x = x,
        y = y,
    })
    return self
end

function Actions:click(element)
    if element then self:move_to(element) end
    pointer_down(self)
    pointer_up(self)
    return self
end

function Actions:double_click(element)
    if element then self:move_to(element) end
    pointer_down(self); pointer_up(self)
    pointer_down(self); pointer_up(self)
    return self
end

function Actions:context_click(element)
    if element then self:move_to(element) end
    pointer_down(self, 2)
    pointer_up(self, 2)
    return self
end

function Actions:click_and_hold(element)
    if element then self:move_to(element) end
    pointer_down(self)
    return self
end

function Actions:release()
    pointer_up(self)
    return self
end

function Actions:key_down(character)
    key_event(self, "keyDown", character)
    return self
end

function Actions:key_up(character)
    key_event(self, "keyUp", character)
    return self
end

function Actions:send_keys(text)
    if type(text) ~= "string" then
        error("webdriver Actions:send_keys: text doit être une chaîne", 2)
    end
    for _, codepoint in utf8.codes(text) do
        local character = utf8.char(codepoint)
        key_event(self, "keyDown", character)
        key_event(self, "keyUp", character)
    end
    return self
end

function Actions:pause(milliseconds)
    milliseconds = finite_integer("webdriver Actions:pause: durée", milliseconds, 0)
    if milliseconds < 0 then
        error("webdriver Actions:pause: durée positive ou nulle attendue", 2)
    end
    for _, current in ipairs({ "key", "pointer", "wheel" }) do
        self[current][#self[current] + 1] = { type = "pause", duration = milliseconds }
    end
    return self
end

local SCROLL_OPTIONS = { x = true, y = true, duration = true, origin = true }

function Actions:scroll(delta_x, delta_y, options)
    delta_x = finite_integer("webdriver Actions:scroll: delta_x", delta_x)
    delta_y = finite_integer("webdriver Actions:scroll: delta_y", delta_y)
    local opts = strict_table("webdriver Actions:scroll(opts)", options, SCROLL_OPTIONS)
    local x = finite_integer("webdriver Actions:scroll: x", opts.x, 0)
    local y = finite_integer("webdriver Actions:scroll: y", opts.y, 0)
    local duration = finite_integer("webdriver Actions:scroll: duration", opts.duration, 0)
    if duration < 0 then error("webdriver Actions:scroll: duration doit être positive ou nulle", 2) end
    local origin = opts.origin or "viewport"
    if M.is_element(origin) then
        origin = { [ELEMENT_KEY] = origin.id }
    elseif origin ~= "viewport" then
        error("webdriver Actions:scroll: origin doit valoir 'viewport' ou être un Element", 2)
    end
    add_action(self, "wheel", {
        type = "scroll",
        duration = duration,
        origin = origin,
        x = x,
        y = y,
        deltaX = delta_x,
        deltaY = delta_y,
    })
    return self
end

function Actions:drag_and_drop(source, destination)
    return self:move_to(source):click_and_hold():move_to(destination):release()
end

function Actions:perform()
    local function sequence(list)
        if #list == 0 then
            return as_json_array({ { type = "pause", duration = 0 } })
        end
        return as_json_array(list)
    end
    local sources = {
        {
            type = "key",
            id = "keyboard",
            actions = sequence(self.key),
        },
        {
            type = "pointer",
            id = "mouse",
            parameters = { pointerType = "mouse" },
            actions = sequence(self.pointer),
        },
    }
    if self.wheel_active then
        sources[#sources + 1] = {
            type = "wheel",
            id = "wheel",
            actions = sequence(self.wheel),
        }
    end
    local body = { actions = as_json_array(sources) }
    local _, err = self.driver:_request("POST", self.driver.session .. "/actions", body)
    self.key, self.pointer, self.wheel, self.wheel_active = {}, {}, {}, false
    if err then return nil, err end
    return true
end

function Actions:clear()
    local _, err = self.driver:_request("DELETE", self.driver.session .. "/actions")
    self.key, self.pointer, self.wheel, self.wheel_active = {}, {}, {}, false
    if err then return nil, err end
    return true
end

M.keys = {
    NULL = "\u{E000}", CANCEL = "\u{E001}", HELP = "\u{E002}", BACKSPACE = "\u{E003}",
    TAB = "\u{E004}", CLEAR = "\u{E005}", RETURN = "\u{E006}", ENTER = "\u{E007}",
    SHIFT = "\u{E008}", CONTROL = "\u{E009}", ALT = "\u{E00A}", PAUSE = "\u{E00B}",
    ESCAPE = "\u{E00C}", SPACE = "\u{E00D}", PAGE_UP = "\u{E00E}", PAGE_DOWN = "\u{E00F}",
    END = "\u{E010}", HOME = "\u{E011}", LEFT = "\u{E012}", UP = "\u{E013}",
    RIGHT = "\u{E014}", DOWN = "\u{E015}", INSERT = "\u{E016}", DELETE = "\u{E017}",
    SEMICOLON = "\u{E018}", EQUALS = "\u{E019}",
    NUMPAD0 = "\u{E01A}", NUMPAD1 = "\u{E01B}", NUMPAD2 = "\u{E01C}", NUMPAD3 = "\u{E01D}",
    NUMPAD4 = "\u{E01E}", NUMPAD5 = "\u{E01F}", NUMPAD6 = "\u{E020}", NUMPAD7 = "\u{E021}",
    NUMPAD8 = "\u{E022}", NUMPAD9 = "\u{E023}",
    MULTIPLY = "\u{E024}", ADD = "\u{E025}", SUBTRACT = "\u{E027}", DECIMAL = "\u{E028}",
    DIVIDE = "\u{E029}",
    F1 = "\u{E031}", F2 = "\u{E032}", F3 = "\u{E033}", F4 = "\u{E034}", F5 = "\u{E035}",
    F6 = "\u{E036}", F7 = "\u{E037}", F8 = "\u{E038}", F9 = "\u{E039}", F10 = "\u{E03A}",
    F11 = "\u{E03B}", F12 = "\u{E03C}", META = "\u{E03D}", COMMAND = "\u{E03D}",
}

return M
