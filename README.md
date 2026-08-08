# babet-webdriver

**WebDriver browser automation in Lua, powered by Babet.**

Official repository: https://github.com/Chipsterjulien/babet-webdriver

`babet-webdriver` is a **Lua library** for W3C WebDriver Classic and WebDriver
BiDi. You write browser automation directly in **Lua**, and Babet executes the
scripts while providing the native HTTP, WebSocket, process, worker and utility
APIs used by the library. The Classic API works with **Babet 2.9.0 or newer**;
the BiDi transport requires **Babet 2.22.0 or newer**. The library drives
Firefox, Chrome and Chromium with a Selenium-like API, without external Lua
modules and without spawning a shell to manage drivers. Babet is available from
its [official GitHub repository](https://github.com/Chipsterjulien/babet).

```lua
local webdriver = require("webdriver")

local driver = assert(webdriver.firefox({ headless = true }))
assert(driver:open("https://example.com"))
print(assert(driver:title()))
print(assert(assert(driver:css("h1")):text()))
assert(driver:quit())
```

## What the Babet version provides

- direct launch of `geckodriver` or `chromedriver` with `babet.spawn()`;
- native log redirection to a file, without `sh -c` or parsed PIDs;
- clean shutdown through the process object (`terminate`, then `close`);
- streaming downloads and atomic publication of archives;
- safe internal ZIP/TAR extraction with `babet.archive.extractFile()`;
- SHA-256 verification of both the archive and the cached binary;
- screenshots decoded with `babet.base64` and written with `writeFileAtomic()`;
- automatic ports with retries when a selected port is taken;
- persistent sessions in workers through Babet 2.9.0 channels;
- **WebDriver BiDi** transport over `babet.websocket` with Babet 2.22.0+;
- a dedicated command-driven BiDi worker to isolate the WebSocket from the
  Classic worker;
- WebDriver errors preserved instead of being silently converted to `false` or
  plain timeouts.

## Requirements

- Linux;
- **[Babet 2.9.0 or newer](https://github.com/Chipsterjulien/babet)** for WebDriver Classic;
- **Babet 2.22.0 or newer** for WebDriver BiDi and the complete 2.0 test suite;
- Firefox, Chrome or Chromium;
- a compatible driver available in `PATH`, or permission to download it.

No external `tar`, `unzip`, `base64`, `curl` or shell is required.

## Repository layout

```text
babet-webdriver/
├── bin/                     # optional local Babet binary
├── docs/                    # English and French reference documentation
├── examples/pronote.lua     # realistic Classic example, intentionally incomplete
├── examples/bidi.lua        # minimal WebDriver BiDi example
├── tests/                   # mock, BiDi, worker and real smoke tests
├── tools/check_env.lua      # environment diagnostics
├── driver_manager.lua       # download, cache and verification
├── webdriver_version.lua    # version source of truth
├── webdriver.lua            # main WebDriver Classic client
├── webdriver_worker.lua     # Classic proxy running in a worker
├── webdriver_bidi.lua       # direct WebDriver BiDi client
├── webdriver_bidi_worker.lua # BiDi transport in a dedicated worker
├── run_tests.sh
├── run_smoke.sh
├── run_worker_smoke.sh
└── run_all_tests.sh         # complete campaign + .txt log
```

The main modules remain at the repository root to keep usage simple:

```lua
local webdriver = require("webdriver")
```

## Starting a new project

### What to download

For a new application, you need two projects:

1. **babet-webdriver**: download the source archive for the desired release from
   [babet-webdriver Releases](https://github.com/Chipsterjulien/babet-webdriver/releases).
   There is no separate package to install: the runtime is made of the Lua modules
   listed below.
2. **Babet**: download a Linux build from
   [Babet Releases](https://github.com/Chipsterjulien/babet/releases), or build it
   from the [Babet repository](https://github.com/Chipsterjulien/babet). Use Babet
   **2.22.0 or newer** for the complete babet-webdriver 2.0 feature set. Classic-only
   projects can run with Babet **2.9.0 or newer**.
   On a typical 64-bit Intel/AMD Linux machine, choose the
   `babet-<version>-linux-x86_64` release asset; ARM builds are published separately.

The simplest layout, if you want every Classic, worker and BiDi feature available, is:

```text
my-project/
├── bin/
│   └── babet
├── webdriver.lua
├── webdriver_version.lua
├── driver_manager.lua
├── webdriver_worker.lua
├── webdriver_bidi.lua
├── webdriver_bidi_worker.lua
└── main.lua
```

Then make the local Babet executable runnable and start the application with:

```sh
chmod +x bin/babet
./bin/babet main.lua
```

Keeping `babet` in `bin/` is only a convenient project-local layout. A Babet
executable installed in `PATH` or stored elsewhere works just as well; see
[Where to place Babet](#where-to-place-babet). The six Lua modules may also live
in another directory as long as that directory is reachable through `package.path`.

You do **not** need to copy `tests/`, `examples/`, `docs/`, `tools/`, `run_*.sh` or
`build_docs.sh` into an application project. Browser drivers are separate: either
provide `geckodriver`/`chromedriver` in `PATH`, set `driver_path`, or let
`driver_manager.lua` install them. The first unpinned automatic download must be
explicitly trusted with `trust_on_first_use = true` (or validated with
`expected_sha256`).

### Files to copy

For a direct WebDriver project, the strict minimum is:

```text
my-project/
├── webdriver.lua
├── webdriver_version.lua
├── driver_manager.lua
└── main.lua
```

`webdriver.lua` loads `driver_manager.lua` and `webdriver_version.lua`
internally, so all three files are required even when a driver is already
available in `PATH`.

To host the session inside a Babet worker, simply add:

```text
my-project/
├── webdriver.lua
├── webdriver_version.lua
├── driver_manager.lua
├── webdriver_worker.lua
└── main.lua
```

For BiDi on a direct session, add `webdriver_bidi.lua`:

```text
my-project/
├── webdriver.lua
├── webdriver_version.lua
├── driver_manager.lua
├── webdriver_bidi.lua
└── main.lua
```

To receive BiDi events from a dedicated worker, also add
`webdriver_bidi_worker.lua`. With a Classic session already hosted by
`webdriver_worker.lua`, these two modules attach the BiDi transport to the same
browser.

`tools/check_env.lua` is optional. It is useful for diagnosing a machine, but is
not required by the library. The `tests/`, `examples/`, `docs/` directories and
the `run_*.sh` scripts are development files and do not need to be copied into
an application project.

### Where to place Babet

The executable **does not need to live in `bin/`**. It may be downloaded or
built from the [Babet GitHub repository](https://github.com/Chipsterjulien/babet).
Classic requires at least **2.9.0** and BiDi requires **2.22.0**. These three
layouts are equivalent:

1. **Project-local Babet**, useful for pinning the exact version used:

   ```text
   my-project/
   ├── bin/babet
   ├── webdriver.lua
   ├── webdriver_version.lua
   ├── driver_manager.lua
   └── main.lua
   ```

   ```sh
   ./bin/babet main.lua
   ```

2. **Babet installed in `PATH`**, useful when one installation is shared by
   several projects:

   ```sh
   babet main.lua
   ```

3. **Babet stored anywhere**, by invoking its path directly:

   ```sh
   /opt/babet/bin/babet main.lua
   ```

For the repository test scripts, the `BABET` variable can also point to any
location:

```sh
BABET=/opt/babet/bin/babet ./run_tests.sh
```

To run the complete 2.0 campaign (local Classic/BiDi tests + Firefox/Chromium
smoke tests + workers) and produce a shareable log at the same time, use Babet
2.22.0 or newer:

```sh
./run_all_tests.sh
```

Headless mode is enabled by default. Output remains visible live in the terminal
and is copied to `babet-webdriver-tests.txt`. Each campaign first builds a unique
temporary log in the target directory, then publishes it atomically at the end:
an older complete log is never truncated while tests are running, and two
accidentally parallel campaigns never mix their contents. If several campaigns
target the same file, the one that finishes last simply becomes the current log.
Use `TEST_LOG=/path/file.txt` to select another destination.

The scripts now look for Babet in this order: `BABET`, `bin/babet`, then `PATH`.

### First direct script

When the modules are next to `main.lua`, no `package.path` change is required:

```lua
#!/usr/bin/env babet

local webdriver = require("webdriver")

local driver, err = webdriver.firefox({
    headless = true,
})

if not driver then
    io.stderr:write(tostring(err), "\n")
    os.exit(1)
end

local ok, run_err = xpcall(function()
    assert(driver:open("https://example.com"))
    print(assert(driver:title()))

    local heading = assert(driver:css("h1"))
    print(assert(heading:text()))
end, debug.traceback)

local quit_ok, quit_err = driver:quit()
if not quit_ok then
    io.stderr:write("WebDriver shutdown: ", tostring(quit_err), "\n")
end

if not ok then
    io.stderr:write(tostring(run_err), "\n")
    os.exit(1)
end
```

With Babet in `PATH`:

```sh
chmod +x main.lua
./main.lua
```

With a project-local Babet without modifying `PATH`:

```sh
./bin/babet main.lua
```

### Modules stored under `lib/`

Another layout remains possible:

```text
my-project/
├── lib/
│   ├── webdriver.lua
│   ├── webdriver_version.lua
│   ├── driver_manager.lua
│   └── webdriver_worker.lua
└── main.lua
```

In that case, add the directory before the first `require`:

```lua
package.path = "./lib/?.lua;" .. package.path

local webdriver = require("webdriver")
```

## Using a local or installed Babet

If you keep a local executable, place it under `bin/babet`, then run:

```sh
chmod +x bin/babet
./run_tests.sh
```

The protocol tests use neither the Internet nor a browser: they start a fake
local WebDriver server with `babet.socket`.

The real smoke test uses a browser:

```sh
./run_smoke.sh firefox
HEADLESS=1 ./run_smoke.sh chromium

# Same path, but with WebDriver hosted inside a Babet worker
HEADLESS=1 ./run_worker_smoke.sh firefox
HEADLESS=1 ./run_worker_smoke.sh chromium
```

The first automatic download is rejected until a hash is known. To explicitly
allow TOFU mode during the smoke test:

```sh
ALLOW_TOFU=1 HEADLESS=1 ./run_smoke.sh firefox
```

## Starting a session

```lua
local driver = assert(webdriver.chromium({
    headless = true,
    window_size = { 1440, 900 },
    request_timeout = 60,
    start_timeout = 15,
}))
```

Common options:

| Option | Purpose |
|---|---|
| `browser` | `firefox`, `chrome` or `chromium` |
| `headless` | enables headless mode |
| `args` | additional browser arguments |
| `binary` | browser executable to use; Chromium is detected in `PATH` |
| `user_data_dir` | explicit profile for Chrome/Chromium |
| `window_size` | `{ width, height }` |
| `port` | forced port; otherwise chosen automatically |
| `port_attempts` | retries if an automatic port is taken |
| `driver_path` | explicit path to geckodriver/chromedriver |
| `auto_install` | downloads the driver when missing; enabled by default |
| `trust_on_first_use` | allows the first unpinned download |
| `attach` | connects to an already-running driver **ready to create a new session** |
| `request_timeout` | general WebDriver HTTP timeout |
| `status_timeout` | short timeout for `/status` probes |
| `print_max_size` | PDF size limit after Base64 decoding |
| `print_permissions` / `print_durable` | atomic PDF publication options |
| `log_path` / `log_dir` | driver process log destination |
| `bidi` | requests the W3C `webSocketUrl` capability; requires Babet 2.22+ |

All `webdriver.start()` options are strict: a typo raises a Lua error instead of
being silently ignored.

With `attach = true`, the external driver must answer `/status` with
`ready = true`: it must therefore be free to create **a new session**. This mode
does not resume an existing Selenium session. Geckodriver, which supports only
one session at a time, normally reports `ready = false` while already busy; the
diagnostic now distinguishes that state from an unreachable driver.

### Chromium installed through Snap

When `chromium` resolves to `/snap/bin/chromium`, the library automatically
creates a temporary profile under
`~/snap/chromium/common/babet-webdriver/profiles/`. This path is visible from
inside the Snap sandbox, unlike the temporary profile ChromeDriver would
normally create under `/tmp`. The profile is removed by `driver:quit()`.

Do not add `--no-sandbox` to work around this issue: the fix changes the profile
location without disabling the browser sandbox.

## Secure driver management

The cache follows `XDG_CACHE_HOME` when it is set, otherwise it uses:

```text
~/.cache/babet-webdriver/
```

If `HOME` is missing, a private per-user/UID cache is created under `/tmp`
instead of using a shared directory that may have unsuitable permissions.

`driver_manager.lua`:

1. resolves the latest official geckodriver release, or the chromedriver version
   matching the actually selected Chrome/Chromium binary;
2. downloads the archive as a stream;
3. verifies its SHA-256;
4. extracts only the expected binary into a unique temporary file;
5. computes the SHA-256 of the extracted binary as well;
6. publishes the binary atomically into the cache through a rename;
7. stores one artifact pin under `cache/pins/`;
8. re-verifies the binary every time it is reused.

TOFU trusts the **first** download performed over HTTPS. It protects subsequent
uses against modification, but does not replace a hash obtained through an
independent channel. For a controlled deployment:

```lua
local driver = assert(webdriver.firefox({
    expected_sha256 = "<64 hexadecimal digits>",
}))
```

Or add the hash to `driver_manager.registry_pins`.

To validate the complete download/extraction/publication path with a truly empty
cache before a release, the full campaign can also run the explicit network
preflight:

```bash
RUN_INSTALL_SMOKE=1 ./run_all_tests.sh
```

This test uses an independent temporary cache, enables TOFU only inside that
cache, actually downloads geckodriver and chromedriver, verifies their pins and
binaries, then destroys the temporary cache. It never removes the user's cache.

To avoid the low unauthenticated GitHub API rate limit in CI,
`driver_manager.lua` accepts `BABET_WEBDRIVER_GITHUB_TOKEN`, `GH_TOKEN` or
`GITHUB_TOKEN`. The token is sent only to `https://api.github.com/`. If a
GitHub Actions `GITHUB_TOKEN` restricted to the current repository is rejected
by the public geckodriver repository, the request is automatically retried
without authentication.

## Main API

```lua
-- navigation
assert(driver:open(url))
driver:url(); driver:title(); driver:source()
driver:back(); driver:forward(); driver:refresh()

-- locating elements
local element = driver:css("main h1")
driver:xpath("//button")
driver:find("submit", { by = "id" })
driver:find_all("article", { by = "tag" })

-- waits
local button = driver:wait("#submit", {
    state = "clickable", -- present, visible, clickable, gone
    timeout = 20,
})

-- elements
assert(element:click())
assert(element:type("text"))
element:text(); element:attr("href"); element:property("value")
-- attr() returns nil when the attribute/property is absent
element:displayed(); element:enabled(); element:selected()
element:computed_role(); element:computed_label()
local shadow = element:shadow_root()
local inside = shadow:find("button")

-- synchronous/asynchronous JavaScript and outputs
local value = driver:js("return arguments[0].textContent", element)
local async_value = driver:js_async("arguments[arguments.length - 1](42)")
assert(driver:screenshot("captures/page.png"))
assert(driver:print({ orientation = "landscape" }, "captures/page.pdf"))

-- W3C actions
assert(driver:actions()
    :move_to(element)
    :double_click()
    :send_keys(webdriver.keys.DELETE)
    :send_keys(webdriver.keys.RIGHT_SHIFT)
    :scroll(0, 600, { origin = element })
    :perform())
```

`exists()` distinguishes a normal missing element from a transport error:

```lua
local exists, err = driver:exists("#optional")
assert(exists ~= nil, err)
if exists then
    -- the element exists
end
```

### WebDriver Classic

The Classic branch now also covers modern W3C commands that were previously
missing: active element, timeout retrieval, new window or tab,
maximize/minimize/fullscreen, asynchronous JavaScript, individual cookie,
Shadow DOM, computed role/label, PDF printing and the `wheel` action source. The
worker mode also transports `ShadowRoot` objects and all new serializable
commands; only the chainable `actions()` builder intentionally remains limited
to direct sessions.

## WebDriver BiDi

WebDriver BiDi is negotiated on **the same browser session** as WebDriver
Classic. Request the `webSocketUrl` capability at startup:

```lua
local webdriver = require("webdriver")

local driver = assert(webdriver.firefox({
    headless = true,
    bidi = true,
}))

local bidi = assert(driver:bidi())
local status = assert(bidi:status())
print(status.ready, status.message)

local tree = assert(bidi:get_tree({ max_depth = 0 }))
local context = assert(tree.contexts[1]).context

local subscription = assert(bidi:subscribe({
    "log.entryAdded",
    "network.beforeRequestSent",
}))

assert(bidi:navigate(context, "https://example.com", { wait = "complete" }))
local result = assert(bidi:evaluate("document.title", context))
print(result.result.value)

local event, event_err = bidi:next_event(5)
if event then
    print(event.method)
elseif event_err ~= "timeout" then
    error(event_err)
end

assert(bidi:unsubscribe(subscription))
assert(driver:quit()) -- also closes the BiDi transport
```

The typed 2.0.0 surface provides `status()`, `subscribe()`, `unsubscribe()`,
`get_tree()`, `navigate()`, `evaluate()` and `get_realms()`. `call(method,
params)` intentionally remains available as a low-level escape hatch for BiDi
commands not yet wrapped by this first high-level surface.

Events received while waiting for a response are kept in a bounded queue.
`next_event()` dequeues them, while `on()` / `off()` / `dispatch()` provide an
explicit callback-based interface. Queue overflow is reported through the
synthetic `babetWebDriver.eventOverflow` event instead of allowing unbounded
memory growth.

### BiDi in a dedicated worker

To isolate the BiDi WebSocket connection from the Classic worker, use the
dedicated BiDi worker:

```lua
local driver = assert(webdriver.chromium({ headless = true, bidi = true }))
local bidi = assert(driver:bidi_worker())

local sub = assert(bidi:subscribe("log.entryAdded"))
assert(bidi:evaluate("console.log('hello bidi')", assert(bidi:get_tree()).contexts[1].context))

local event = assert(bidi:next_event(5))
print(event.method, event.params.text)

assert(bidi:unsubscribe(sub))
assert(driver:quit())
```

With `webdriver_worker.lua`, `session:bidi()` automatically creates this
separate BiDi worker from `session:websocket_url()`. The Classic worker and the
BiDi transport therefore share neither their connection nor their wait loop.

Because Babet's WebSocket transport is synchronous, the BiDi worker is
intentionally command-driven: it waits on its parent channel and reads from the
WebSocket only during `call()`, named wrappers or `next_event()`. Events received
during a command remain in the BiDi client's bounded queue
(`event_queue_limit`). `next_event(timeout)` explicitly performs network reads
inside the worker in bounded slices so cooperative cancellation remains
responsive. This architecture prevents an idle WebSocket `recv()` from blocking
the worker from receiving its next command.

BiDi is a living standard: the named wrappers cover the foundation validated by
this release, while `call()` provides access to newer commands without waiting
for a new convenience method.

## Session inside a worker

```lua
local worker_driver = require("webdriver_worker")

local session = assert(worker_driver.start({
    browser = "firefox",
    headless = true,
}))

assert(session:open("https://example.com"))
local heading = assert(session:css("h1"))
print(assert(heading:text()))
assert(session:stop())
```

The browser and WebDriver object remain inside the worker's Lua state. Channels
transport only serializable commands and results. Returned elements become
proxies usable by the parent.

A proxy session processes one command at a time. For parallelism, create several
independent worker sessions. The parent waits for at least the HTTP
`request_timeout` budget plus a small transport margin; `wait()` extends that
budget further to cover its logical timeout. A stale response is drained
defensively so it can never desynchronize the following call.

`stop_timeout` (or the explicit `timeout` passed to `session:stop(timeout)`) is a
global budget for the complete shutdown sequence. When a BiDi transport is
attached to the Classic session, closing it consumes part of that same budget
before the Classic worker is stopped and joined.

## Error contract

Normal operations return:

```lua
value, nil
nil, "webdriver: ..."
```

Invalid types, unknown options and invalid strategies are programming errors and
raise a Lua error.

## Documentation

- [`docs/webdriver.en.md`](docs/webdriver.en.md) — English reference;
- [`docs/webdriver.fr.md`](docs/webdriver.fr.md) — French reference;
- [`MIGRATION.md`](MIGRATION.md) — migration from LuaPilot to Babet 2.9.0;
- [`CHANGELOG.md`](CHANGELOG.md) — library changes.

### Generating the PDFs

`build_docs.sh` automatically converts each `docs/<name>.<language>.md` file to
`docs/pdf/<name>.<language>.pdf`. Any additional translation following this
naming convention is therefore picked up automatically.

Pandoc and either `xelatex` or `lualatex` are required:

```sh
./build_docs.sh
```

To remove generated PDFs:

```sh
./build_docs.sh --clean
```

## License

GNU GPL v3 or later (`GPL-3.0-or-later`). See [`LICENSE`](LICENSE).
