-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Julien

--------------------------------------------------------------------------------
-- driver_manager.lua — téléchargement, vérification et cache des WebDrivers
-- Cible : Babet 2.9.0+
--------------------------------------------------------------------------------

if type(babet) ~= "table" then
    error("driver_manager: ce module doit être exécuté avec Babet", 2)
end
if (babet.VERSION_MAJOR or 0) < 2
    or ((babet.VERSION_MAJOR or 0) == 2 and (babet.VERSION_MINOR or 0) < 9) then
    error("driver_manager: Babet 2.9.0 ou supérieur est requis", 2)
end

local DM = { VERSION = "1.0.2" }
local json = assert(babet.json)
local http = assert(babet.http)

local home = os.getenv("HOME") or "/tmp"
DM.cache_dir = home .. "/.cache/babet-webdriver"
DM.pins_file = DM.cache_dir .. "/pins.json" -- ancien format, lu pour migration
DM.pins_dir = DM.cache_dir .. "/pins"
DM.chrome_version = nil
DM.gecko_version = nil
DM.user_agent = "babet-webdriver/1.0"

-- Pins intégrés facultatifs : ["nom|plateforme|version"] = sha256_archive.
DM.registry_pins = {}

local INSTALL_OPTIONS = {
    platform = true,
    cache = true,
    force = true,
    trust_on_first_use = true,
    expected_sha256 = true,
    timeout = true,
    max_download_size = true,
}

local function strict_options(name, value, allowed)
    if value == nil then return {} end
    if type(value) ~= "table" then error(name .. " doit être une table", 3) end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then
            error(("%s : option inconnue %q"):format(name, tostring(key)), 3)
        end
    end
    return value
end

local function parse_sha256(value, name)
    if value == nil or value == "" then return nil end
    if type(value) ~= "string" or not value:match("^[0-9a-fA-F]+$") or #value ~= 64 then
        return nil, (name or "sha256") .. " doit contenir exactement 64 chiffres hexadécimaux"
    end
    return value:lower()
end

local function validate_sha256(value, name)
    local normalized, err = parse_sha256(value, name)
    if err then error(err, 3) end
    return normalized
end

local function nonempty_string(name, value, optional)
    if value == nil and optional then return nil end
    if type(value) ~= "string" or value == "" then
        error(name .. " doit être une chaîne non vide", 3)
    end
    return value
end

local function finite_positive(name, value, default)
    if value == nil then return default end
    if type(value) ~= "number" or value ~= value or value <= 0
        or value == math.huge or value == -math.huge then
        error(name .. " doit être un nombre fini strictement positif", 3)
    end
    return value
end

local function normalize_platform(sysname, machine)
    sysname = tostring(sysname or ""):lower()
    machine = tostring(machine or ""):lower()
    local arch_aliases = {
        amd64 = "x86_64",
        x64 = "x86_64",
        arm64 = "aarch64",
        i386 = "i686",
        i486 = "i686",
        i586 = "i686",
        i686 = "i686",
    }
    machine = arch_aliases[machine] or machine
    return sysname .. "-" .. machine
end

function DM.platform()
    local info, err = babet.uname()
    if not info then return nil, "driver: uname: " .. tostring(err) end
    return normalize_platform(info.sysname, info.machine)
end

local function driver_name(browser)
    browser = tostring(browser or "firefox"):lower()
    if browser == "firefox" then return "geckodriver" end
    if browser == "chrome" or browser == "chromium" then return "chromedriver" end
    return nil, "driver: navigateur non géré: " .. browser
end

local function safe_component(value, label)
    value = tostring(value or "")
    if value == "" or not value:match("^[A-Za-z0-9._-]+$") then
        return nil, ("driver: %s invalide: %q"):format(label, value)
    end
    return value
end

local function api_get(url, timeout, max_body_size)
    local response, err = http.get(url, {
        headers = {
            ["User-Agent"] = DM.user_agent,
            ["Accept"] = "application/json",
        },
        timeout = timeout or 30,
        follow_redirects = true,
        max_body_size = max_body_size or 4 * 1024 * 1024,
    })
    if not response then return nil, "driver: requête API: " .. tostring(err) end
    if response.status < 200 or response.status >= 300 then
        return nil, ("driver: API HTTP %d pour %s"):format(response.status, url)
    end
    local data, decode_err = json.decode(response.body)
    if not data then return nil, "driver: réponse API JSON invalide: " .. tostring(decode_err) end
    return data
end

local GECKO_ASSETS = {
    ["linux-x86_64"] = "linux64.tar.gz",
    ["linux-aarch64"] = "linux-aarch64.tar.gz",
    ["linux-i686"] = "linux32.tar.gz",
}

local function resolve_geckodriver(platform, timeout)
    local asset_suffix = GECKO_ASSETS[platform]
    if not asset_suffix then
        return nil, "driver: geckodriver indisponible pour " .. platform
    end

    if DM.gecko_version and DM.gecko_version ~= "" then
        local version, version_err = safe_component(DM.gecko_version:gsub("^v", ""), "version geckodriver")
        if not version then return nil, version_err end
        local file = ("geckodriver-v%s-%s"):format(version, asset_suffix)
        return {
            name = "geckodriver",
            version = version,
            url = ("https://github.com/mozilla/geckodriver/releases/download/v%s/%s")
                :format(version, file),
            file = file,
            entry = "geckodriver",
            binary = "geckodriver",
        }
    end

    local release, release_err = api_get(
        "https://api.github.com/repos/mozilla/geckodriver/releases/latest",
        timeout,
        8 * 1024 * 1024
    )
    if not release then return nil, release_err end
    local version = tostring(release.tag_name or ""):gsub("^v", "")
    local valid_version, version_err = safe_component(version, "version geckodriver")
    if not valid_version then return nil, version_err end
    local expected_name = ("geckodriver-v%s-%s"):format(valid_version, asset_suffix)
    local assets = release.assets
    if type(assets) ~= "table" then
        return nil, "driver: réponse GitHub sans liste d'artefacts"
    end
    for _, asset in ipairs(assets) do
        if asset.name == expected_name and type(asset.browser_download_url) == "string" then
            return {
                name = "geckodriver",
                version = valid_version,
                url = asset.browser_download_url,
                file = expected_name,
                entry = "geckodriver",
                binary = "geckodriver",
            }
        end
    end
    return nil, "driver: artefact geckodriver introuvable: " .. expected_name
end

local CFT_PLATFORM = {
    ["linux-x86_64"] = "linux64",
}

local function detect_chrome_major()
    local candidates = {
        "chromium",
        "chromium-browser",
        "google-chrome",
        "google-chrome-stable",
        "chrome",
    }
    for _, command in ipairs(candidates) do
        local path = babet.which(command)
        if path then
            local result = babet.exec(path, { "--version" }, {
                timeout = 5,
                max_output = 64 * 1024,
            })
            if result and result.code == 0 then
                local output = tostring(result.stdout or "") .. "\n" .. tostring(result.stderr or "")
                local major = output:match("(%d+)%.%d+%.%d+")
                if major then return tonumber(major), path end
            end
        end
    end
    return nil
end

local function resolve_chromedriver(platform, timeout)
    local cft_platform = CFT_PLATFORM[platform]
    if not cft_platform then
        return nil, "driver: chromedriver indisponible pour " .. platform
            .. " (Chrome for Testing ne publie pas de binaire Linux pour cette architecture)"
    end

    if DM.chrome_version and DM.chrome_version ~= "" then
        local version, version_err = safe_component(DM.chrome_version, "version chromedriver")
        if not version then return nil, version_err end
        local file = "chromedriver-" .. cft_platform .. ".zip"
        return {
            name = "chromedriver",
            version = version,
            url = ("https://storage.googleapis.com/chrome-for-testing-public/%s/%s/%s")
                :format(version, cft_platform, file),
            file = file,
            entry = "chromedriver-" .. cft_platform .. "/chromedriver",
            binary = "chromedriver",
        }
    end

    local major = detect_chrome_major()
    if not major then
        return nil, "driver: Chrome/Chromium introuvable; installe le navigateur ou fixe "
            .. "driver_manager.chrome_version"
    end

    local data, data_err = api_get(
        "https://googlechromelabs.github.io/chrome-for-testing/"
            .. "latest-versions-per-milestone-with-downloads.json",
        timeout,
        16 * 1024 * 1024
    )
    if not data then return nil, data_err end
    local milestone = type(data.milestones) == "table" and data.milestones[tostring(major)] or nil
    if type(milestone) ~= "table" then
        return nil, ("driver: aucun chromedriver publié pour le milestone %d"):format(major)
    end
    local version, version_err = safe_component(milestone.version, "version chromedriver")
    if not version then return nil, version_err end
    local downloads = type(milestone.downloads) == "table" and milestone.downloads.chromedriver or nil
    if type(downloads) ~= "table" then
        return nil, "driver: réponse Chrome for Testing sans téléchargements chromedriver"
    end
    for _, download in ipairs(downloads) do
        if download.platform == cft_platform and type(download.url) == "string" then
            return {
                name = "chromedriver",
                version = version,
                url = download.url,
                file = download.url:match("[^/]+$") or ("chromedriver-" .. cft_platform .. ".zip"),
                entry = "chromedriver-" .. cft_platform .. "/chromedriver",
                binary = "chromedriver",
            }
        end
    end
    return nil, "driver: URL chromedriver absente pour " .. cft_platform
end

local function resolve(browser, platform, timeout)
    local name, name_err = driver_name(browser)
    if not name then return nil, name_err end
    if not platform then
        local platform_err
        platform, platform_err = DM.platform()
        if not platform then return nil, platform_err end
    end
    if name == "geckodriver" then
        return resolve_geckodriver(platform, timeout)
    end
    return resolve_chromedriver(platform, timeout)
end

function DM.describe(browser, options)
    local opts = strict_options("driver_manager.describe(opts)", options, {
        platform = true,
        timeout = true,
    })
    if opts.platform ~= nil then
        nonempty_string("driver_manager.describe: platform", opts.platform)
    end
    local timeout = finite_positive("driver_manager.describe: timeout", opts.timeout, 30)
    local platform = opts.platform
    if not platform then
        local platform_err
        platform, platform_err = DM.platform()
        if not platform then return nil, platform_err end
    end
    local descriptor, err = resolve(browser, platform, timeout)
    if not descriptor then return nil, err end
    descriptor.platform = platform
    descriptor.key = ("%s|%s|%s"):format(
        descriptor.name,
        descriptor.platform,
        descriptor.version
    )
    return descriptor
end

function DM.url_for(browser, platform)
    local descriptor, err = DM.describe(browser, { platform = platform })
    if not descriptor then return nil, err end
    return descriptor.url
end

local function ensure_directory(path, label)
    local ok, err = babet.mkdir(path)
    if not ok then return nil, ("driver: création %s: %s"):format(label, tostring(err)) end
    return true
end

local function read_text(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("a")
    file:close()
    return content
end

local function decode_json_file(path)
    local content = read_text(path)
    if not content then return nil end
    local value = json.decode(content)
    if type(value) == "table" then return value end
    return nil
end

local function safe_key(key)
    return (key:gsub("[^A-Za-z0-9._-]", "_"))
end

local function pin_path(cache, key)
    return cache .. "/pins/" .. safe_key(key) .. ".json"
end

local function load_legacy_pin(cache, key)
    local legacy = decode_json_file(cache .. "/pins.json")
    if type(legacy) ~= "table" then return nil end
    local value = legacy[key]
    if type(value) == "string" and value:match("^[0-9a-fA-F]+$") and #value == 64 then
        return { archive_sha256 = value:lower(), legacy = true }
    end
    return nil
end

local function load_record(cache, key)
    return decode_json_file(pin_path(cache, key)) or load_legacy_pin(cache, key)
end

local function save_record(cache, key, record)
    local ok, err = ensure_directory(cache .. "/pins", "du dossier des pins")
    if not ok then return nil, err end
    local encoded, encode_err = json.encode(record, { indent = 2 })
    if not encoded then return nil, "driver: encodage du pin: " .. tostring(encode_err) end
    local written, write_err = babet.writeFileAtomic(pin_path(cache, key), encoded .. "\n", {
        overwrite = true,
        permissions = tonumber("600", 8),
        durable = true,
    })
    if not written then return nil, "driver: écriture du pin: " .. tostring(write_err) end
    return true
end

local function remove_best_effort(path)
    if babet.fileExists(path) then babet.remove(path) end
end

local function hash_file(path, label)
    local hash, err = babet.sha256sum(path)
    if not hash then return nil, ("driver: SHA256 %s: %s"):format(label, tostring(err)) end
    return hash:lower()
end

local function unique_token()
    local raw = tostring(babet.monotonic()) .. "-" .. tostring(math.random(0, 0x7fffffff))
    return raw:gsub("[^0-9]", "")
end

local function expected_archive_hash(descriptor, options, record)
    local expected = validate_sha256(
        options.expected_sha256,
        "driver_manager.install: expected_sha256"
    )
    if expected then return expected end

    expected = validate_sha256(
        DM.registry_pins[descriptor.key],
        "driver_manager.registry_pins"
    )
    if expected then return expected end

    if type(record) == "table" and record.archive_sha256 ~= nil then
        local pinned, pin_err = parse_sha256(record.archive_sha256, "pin archive_sha256")
        if not pinned then return nil, "driver: fichier de pin corrompu: " .. tostring(pin_err) end
        return pinned
    end
    return nil
end

local function verify_cached_binary(binary_path, record)
    if not babet.isFile(binary_path) then return false end
    if type(record) ~= "table" or record.binary_sha256 == nil then
        return false
    end
    local expected, pin_err = parse_sha256(record.binary_sha256, "pin binary_sha256")
    if not expected then return nil, "driver: fichier de pin corrompu: " .. tostring(pin_err) end
    local actual, err = hash_file(binary_path, "du binaire en cache")
    if not actual then return nil, err end
    return actual == expected
end

function DM.verify(browser, options)
    local opts = strict_options("driver_manager.verify(opts)", options, {
        platform = true,
        cache = true,
        timeout = true,
    })
    if opts.cache ~= nil then nonempty_string("driver_manager.verify: cache", opts.cache) end
    local descriptor, err = DM.describe(browser, {
        platform = opts.platform,
        timeout = opts.timeout,
    })
    if not descriptor then return nil, err end
    local cache = opts.cache or DM.cache_dir
    local record = load_record(cache, descriptor.key)
    local binary_path = ("%s/%s-%s/%s"):format(
        cache,
        descriptor.name,
        descriptor.version,
        descriptor.binary
    )
    local valid, verify_err = verify_cached_binary(binary_path, record)
    if valid == nil then return nil, verify_err end
    if not valid then return false, "driver: binaire absent, non pinné ou modifié" end
    return true, binary_path
end

function DM.install(browser, options)
    local opts = strict_options("driver_manager.install(opts)", options, INSTALL_OPTIONS)
    if opts.force ~= nil and type(opts.force) ~= "boolean" then
        error("driver_manager.install: force doit être un booléen", 2)
    end
    if opts.trust_on_first_use ~= nil and type(opts.trust_on_first_use) ~= "boolean" then
        error("driver_manager.install: trust_on_first_use doit être un booléen", 2)
    end
    if opts.cache ~= nil then nonempty_string("driver_manager.install: cache", opts.cache) end
    if opts.platform ~= nil then nonempty_string("driver_manager.install: platform", opts.platform) end
    local timeout = finite_positive("driver_manager.install: timeout", opts.timeout, 180)
    local max_download_size = opts.max_download_size or 512 * 1024 * 1024
    if type(max_download_size) ~= "number" or math.type(max_download_size) ~= "integer"
        or max_download_size <= 0 then
        error("driver_manager.install: max_download_size doit être un entier positif", 2)
    end

    local descriptor, describe_err = DM.describe(browser, {
        platform = opts.platform,
        timeout = timeout,
    })
    if not descriptor then return nil, describe_err end

    local cache = opts.cache or DM.cache_dir
    local destination_dir = ("%s/%s-%s"):format(cache, descriptor.name, descriptor.version)
    local binary_path = destination_dir .. "/" .. descriptor.binary
    local record = load_record(cache, descriptor.key)

    if not opts.force then
        local cached, cache_err = verify_cached_binary(binary_path, record)
        if cached == nil then return nil, cache_err end
        if cached then return binary_path end
    end

    local expected, expected_err = expected_archive_hash(descriptor, opts, record)
    if expected_err then return nil, expected_err end
    if not expected and not opts.trust_on_first_use then
        return nil, ("driver: SHA256 non pinné pour %s (%s). "
            .. "Fournis expected_sha256 ou active trust_on_first_use=true pour le premier téléchargement.")
            :format(descriptor.name, descriptor.key)
    end

    local ok, dir_err = ensure_directory(cache, "du cache")
    if not ok then return nil, dir_err end
    ok, dir_err = ensure_directory(destination_dir, "du dossier du driver")
    if not ok then return nil, dir_err end
    local download_dir = cache .. "/downloads"
    ok, dir_err = ensure_directory(download_dir, "du dossier de téléchargement")
    if not ok then return nil, dir_err end

    local archive_path = ("%s/%s-%s-%s.download"):format(
        download_dir,
        descriptor.name,
        descriptor.version,
        unique_token()
    )

    local download, download_err = http.download(descriptor.url, archive_path, {
        headers = { ["User-Agent"] = DM.user_agent },
        timeout = timeout,
        follow_redirects = true,
        max_file_size = max_download_size,
    })
    if not download then
        remove_best_effort(archive_path)
        return nil, "driver: téléchargement: " .. tostring(download_err)
    end
    if not download.saved then
        remove_best_effort(archive_path)
        return nil, ("driver: téléchargement HTTP %d pour %s")
            :format(download.status, descriptor.url)
    end

    local archive_hash, hash_err = hash_file(archive_path, "de l'archive")
    if not archive_hash then
        remove_best_effort(archive_path)
        return nil, hash_err
    end
    if expected and archive_hash ~= expected then
        remove_best_effort(archive_path)
        return nil, ("driver: SHA256 invalide pour %s\n  attendu : %s\n  obtenu  : %s")
            :format(descriptor.file, expected, archive_hash)
    end

    local extracted, extract_err = babet.archive.extractFile(
        archive_path,
        descriptor.entry,
        binary_path,
        {
            overwrite = true,
            max_entries = 1000,
            max_entry_size = 256 * 1024 * 1024,
            max_total_size = 512 * 1024 * 1024,
        }
    )
    remove_best_effort(archive_path)
    if not extracted then
        return nil, "driver: extraction: " .. tostring(extract_err)
    end

    local mode_ok, mode_err = babet.setMode(binary_path, tonumber("755", 8))
    if not mode_ok then
        remove_best_effort(binary_path)
        return nil, "driver: permissions du binaire: " .. tostring(mode_err)
    end

    local binary_hash, binary_hash_err = hash_file(binary_path, "du binaire extrait")
    if not binary_hash then
        remove_best_effort(binary_path)
        return nil, binary_hash_err
    end

    local saved, save_err = save_record(cache, descriptor.key, {
        schema = 2,
        name = descriptor.name,
        version = descriptor.version,
        platform = descriptor.platform,
        url = descriptor.url,
        archive_sha256 = archive_hash,
        binary_sha256 = binary_hash,
    })
    if not saved then
        remove_best_effort(binary_path)
        return nil, save_err
    end

    if not expected then
        io.stderr:write(("driver: [TOFU] %s auto-pinné (%s…) ; "
            .. "les utilisations suivantes vérifieront l'archive et le binaire.\n")
            :format(descriptor.file, archive_hash:sub(1, 16)))
    end

    return binary_path
end

function DM.hash_url(url, destination, options)
    if type(url) ~= "string" or url == "" then
        return nil, "driver: URL manquante"
    end
    if destination ~= nil then
        nonempty_string("driver_manager.hash_url: destination", destination)
    end
    options = strict_options("driver_manager.hash_url(opts)", options, {
        timeout = true,
        max_download_size = true,
    })
    local timeout = finite_positive("driver_manager.hash_url: timeout", options.timeout, 180)
    local max_size = options.max_download_size or 512 * 1024 * 1024
    if type(max_size) ~= "number" or math.type(max_size) ~= "integer" or max_size <= 0 then
        error("driver_manager.hash_url: max_download_size doit être un entier positif", 2)
    end
    destination = destination or ("/tmp/babet-driver-%s.download"):format(unique_token())
    local result, err = http.download(url, destination, {
        headers = { ["User-Agent"] = DM.user_agent },
        timeout = timeout,
        follow_redirects = true,
        max_file_size = max_size,
    })
    if not result then return nil, err end
    if not result.saved then
        remove_best_effort(destination)
        return nil, "HTTP " .. tostring(result.status) .. " pour " .. url
    end
    local hash, hash_err = hash_file(destination, "du téléchargement")
    remove_best_effort(destination)
    if not hash then return nil, hash_err end
    return hash
end

return DM
