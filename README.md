# babet-webdriver

Dépôt officiel : https://github.com/Chipsterjulien/babet-webdriver

Client **WebDriver W3C Classic et WebDriver BiDi** en Lua pour Babet. La partie
Classic reste utilisable avec **Babet 2.9.0 ou supérieur** ; le transport BiDi
nécessite **Babet 2.22.0 ou supérieur** et son client WebSocket natif. La
bibliothèque pilote Firefox, Chrome et Chromium avec une API proche de Selenium,
sans module Lua externe et sans lancer de shell pour gérer les drivers. Babet
est disponible sur son [dépôt GitHub officiel](https://github.com/Chipsterjulien/babet).

```lua
local webdriver = require("webdriver")

local driver = assert(webdriver.firefox({ headless = true }))
assert(driver:open("https://example.com"))
print(assert(driver:title()))
print(assert(assert(driver:css("h1")):text()))
assert(driver:quit())
```

## Ce que la version Babet apporte

- lancement direct de `geckodriver` ou `chromedriver` avec `babet.spawn()` ;
- logs redirigés nativement vers un fichier, sans `sh -c` ni PID analysé ;
- arrêt propre par l'objet processus (`terminate`, puis `close`) ;
- téléchargement progressif et publication atomique des archives ;
- extraction ZIP/TAR interne et sécurisée avec `babet.archive.extractFile()` ;
- vérification SHA-256 de l'archive **et** du binaire conservé dans le cache ;
- captures décodées avec `babet.base64` et écrites avec `writeFileAtomic()` ;
- ports automatiques avec nouvelles tentatives en cas de collision ;
- sessions persistantes dans des workers via les channels de Babet 2.9.0 ;
- transport **WebDriver BiDi** sur `babet.websocket` à partir de Babet 2.22.0 ;
- worker BiDi dédié piloté par commandes pour isoler le WebSocket du worker Classic ;
- erreurs WebDriver conservées au lieu d'être transformées silencieusement en
  `false` ou en simple timeout.

## Prérequis

- Linux ;
- **[Babet 2.9.0 ou supérieur](https://github.com/Chipsterjulien/babet)** pour WebDriver Classic ;
- **Babet 2.22.0 ou supérieur** pour WebDriver BiDi et pour la suite de tests complète 2.0 ;
- Firefox, Chrome ou Chromium ;
- un driver compatible présent dans `PATH`, ou l'autorisation de le télécharger.

Aucun `tar`, `unzip`, `base64`, `curl` ou shell externe n'est requis.

## Organisation

```text
babet-webdriver/
├── bin/                     # binaire Babet local facultatif
├── docs/                    # référence française et anglaise
├── examples/pronote.lua     # exemple Classic réaliste, volontairement incomplet
├── examples/bidi.lua        # exemple minimal WebDriver BiDi
├── tests/                   # tests mock, BiDi, worker et smoke tests réels
├── tools/check_env.lua      # diagnostic de l'environnement
├── driver_manager.lua       # téléchargement, cache et vérification
├── webdriver_version.lua    # source de vérité de la version
├── webdriver.lua            # client WebDriver Classic principal
├── webdriver_worker.lua     # proxy Classic dans un worker
├── webdriver_bidi.lua       # client WebDriver BiDi direct
├── webdriver_bidi_worker.lua # transport BiDi dans un worker dédié
├── run_tests.sh
├── run_smoke.sh
├── run_worker_smoke.sh
└── run_all_tests.sh       # campagne complète + journal .txt
```

Les modules principaux restent à la racine pour conserver un usage simple :

```lua
local webdriver = require("webdriver")
```

## Démarrer un nouveau projet

### Fichiers à copier

Pour un projet WebDriver direct, le strict minimum est :

```text
mon-projet/
├── webdriver.lua
├── webdriver_version.lua
├── driver_manager.lua
└── main.lua
```

`webdriver.lua` charge `driver_manager.lua` et `webdriver_version.lua` en interne :
les trois fichiers sont nécessaires, même lorsqu'un driver est déjà présent dans `PATH`.

Pour héberger la session dans un worker Babet, ajoute simplement :

```text
mon-projet/
├── webdriver.lua
├── webdriver_version.lua
├── driver_manager.lua
├── webdriver_worker.lua
└── main.lua
```

Pour activer BiDi sur une session directe, ajoute `webdriver_bidi.lua` :

```text
mon-projet/
├── webdriver.lua
├── webdriver_version.lua
├── driver_manager.lua
├── webdriver_bidi.lua
└── main.lua
```

Pour recevoir les événements BiDi depuis un worker dédié, ajoute aussi
`webdriver_bidi_worker.lua`. Avec une session Classic déjà hébergée dans
`webdriver_worker.lua`, ces deux modules permettent d'attacher le transport BiDi
au même navigateur.

`tools/check_env.lua` est facultatif. Il est utile pour diagnostiquer une
machine, mais il n'est pas requis par la bibliothèque. Les dossiers `tests/`,
`examples/`, `docs/` et les scripts `run_*.sh` servent au développement de
babet-webdriver et n'ont pas besoin d'être copiés dans un projet utilisateur.

### Où placer Babet

Le binaire **n'a pas besoin d'être dans `bin/`**. Il peut être téléchargé ou
compilé depuis le [dépôt GitHub de Babet](https://github.com/Chipsterjulien/babet).
La partie Classic nécessite au minimum la version **2.9.0**. BiDi nécessite
**2.22.0**. Trois organisations sont équivalentes :

1. **Babet local au projet**, pratique pour figer la version utilisée :

   ```text
   mon-projet/
   ├── bin/babet
   ├── webdriver.lua
   ├── webdriver_version.lua
   ├── driver_manager.lua
   └── main.lua
   ```

   ```sh
   ./bin/babet main.lua
   ```

2. **Babet installé dans le `PATH`**, pratique lorsqu'une seule installation
   est partagée par plusieurs projets :

   ```sh
   babet main.lua
   ```

3. **Babet situé n'importe où**, en appelant son chemin directement :

   ```sh
   /opt/babet/bin/babet main.lua
   ```

Pour les scripts de test du dépôt, la variable `BABET` permet aussi d'indiquer
un chemin quelconque :

```sh
BABET=/opt/babet/bin/babet ./run_tests.sh
```

Pour lancer toute la campagne 2.0 (tests locaux Classic/BiDi + smoke
Firefox/Chromium + workers) et obtenir en même temps un journal prêt à partager,
il faut Babet 2.22.0 ou supérieur :

```sh
./run_all_tests.sh
```

Le mode headless est activé par défaut. La sortie reste visible en direct dans
le terminal et est copiée dans `babet-webdriver-tests.txt`. Chaque campagne
construit d'abord un journal temporaire unique dans le répertoire cible, puis le
publie atomiquement à la fin : un ancien journal complet n'est jamais tronqué
pendant les tests et deux campagnes accidentellement parallèles ne mélangent pas
leurs contenus. Si plusieurs campagnes visent le même fichier, celle qui termine
en dernier devient simplement le journal courant. `TEST_LOG=/chemin/fichier.txt`
permet de choisir un autre emplacement.

Les scripts cherchent désormais Babet dans cet ordre : `BABET`, `bin/babet`,
puis le `PATH`.

### Premier script direct

Lorsque les modules sont placés à côté de `main.lua`, aucun réglage de
`package.path` n'est nécessaire :

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
    io.stderr:write("Fermeture WebDriver : ", tostring(quit_err), "\n")
end

if not ok then
    io.stderr:write(tostring(run_err), "\n")
    os.exit(1)
end
```

Avec un Babet présent dans le `PATH` :

```sh
chmod +x main.lua
./main.lua
```

Avec un Babet local sans modifier le `PATH` :

```sh
./bin/babet main.lua
```

### Modules rangés dans `lib/`

Une autre organisation reste possible :

```text
mon-projet/
├── lib/
│   ├── webdriver.lua
│   ├── webdriver_version.lua
│   ├── driver_manager.lua
│   └── webdriver_worker.lua
└── main.lua
```

Dans ce cas, ajoute le dossier avant le premier `require` :

```lua
package.path = "./lib/?.lua;" .. package.path

local webdriver = require("webdriver")
```

## Utilisation avec un Babet local ou installé

Si tu conserves un binaire local, place-le sous `bin/babet`, puis :

```sh
chmod +x bin/babet
./run_tests.sh
```

Les tests de protocole n'utilisent ni Internet ni navigateur : ils lancent un
faux serveur WebDriver local avec `babet.socket`.

Le smoke test réel utilise un navigateur :

```sh
./run_smoke.sh firefox
HEADLESS=1 ./run_smoke.sh chromium

# Même parcours, mais avec WebDriver hébergé dans un worker Babet
HEADLESS=1 ./run_worker_smoke.sh firefox
HEADLESS=1 ./run_worker_smoke.sh chromium
```

Le premier téléchargement automatique est refusé tant qu'aucun hash n'est
connu. Pour autoriser explicitement le mode TOFU pendant le smoke test :

```sh
ALLOW_TOFU=1 HEADLESS=1 ./run_smoke.sh firefox
```

## Démarrage d'une session

```lua
local driver = assert(webdriver.chromium({
    headless = true,
    window_size = { 1440, 900 },
    request_timeout = 60,
    start_timeout = 15,
}))
```

Options courantes :

| Option | Rôle |
|---|---|
| `browser` | `firefox`, `chrome` ou `chromium` |
| `headless` | active le mode sans fenêtre |
| `args` | arguments supplémentaires du navigateur |
| `binary` | binaire du navigateur à utiliser ; Chromium est détecté dans le `PATH` |
| `user_data_dir` | profil explicite pour Chrome/Chromium |
| `window_size` | `{ largeur, hauteur }` |
| `port` | port imposé ; sinon choix automatique |
| `port_attempts` | nouvelles tentatives si un port automatique est repris |
| `driver_path` | chemin explicite de geckodriver/chromedriver |
| `auto_install` | téléchargement si le driver est absent, actif par défaut |
| `trust_on_first_use` | autorise le premier téléchargement non pinné |
| `attach` | se connecte à un driver déjà lancé **et prêt à créer une nouvelle session** |
| `request_timeout` | timeout HTTP WebDriver général |
| `status_timeout` | timeout court des sondes `/status` |
| `print_max_size` | limite du PDF après décodage Base64 |
| `print_permissions` / `print_durable` | publication atomique des PDF |
| `log_path` / `log_dir` | destination des logs du processus driver |
| `bidi` | demande la capability W3C `webSocketUrl` ; nécessite Babet 2.22+ |

Toutes les options de `webdriver.start()` sont strictes : une faute de frappe
lève une erreur Lua au lieu d'être ignorée.

Avec `attach = true`, le driver externe doit répondre à `/status` avec
`ready = true` : il doit donc être libre pour créer **une nouvelle session**.
Ce mode ne reprend pas une session Selenium déjà existante. Geckodriver, qui ne
gère qu'une session à la fois, renvoie normalement `ready = false` lorsqu'il est
déjà occupé ; le diagnostic distingue maintenant ce cas d'un driver injoignable.

### Chromium installé par Snap

Lorsque `chromium` est résolu vers `/snap/bin/chromium`, la bibliothèque crée
automatiquement un profil temporaire dans
`~/snap/chromium/common/babet-webdriver/profiles/`. Ce chemin est visible depuis
le confinement Snap, contrairement au profil temporaire habituellement créé
par ChromeDriver dans `/tmp`. Le profil est supprimé lors de `driver:quit()`.

Il ne faut pas ajouter `--no-sandbox` pour contourner ce problème : la correction
porte sur l'emplacement du profil, sans désactiver la sandbox du navigateur.

## Gestion sécurisée des drivers

Le cache suit `XDG_CACHE_HOME` lorsqu'il est défini, sinon :

```text
~/.cache/babet-webdriver/
```

Si `HOME` est absent, un cache privé par utilisateur/UID est créé sous `/tmp`
au lieu d'utiliser un répertoire partagé susceptible d'avoir de mauvaises permissions.

`driver_manager.lua` :

1. résout la dernière release officielle de geckodriver ou la version de
   chromedriver correspondant au binaire Chrome/Chromium réellement sélectionné ;
2. télécharge l'archive en streaming ;
3. vérifie son SHA-256 ;
4. extrait uniquement le binaire attendu dans un fichier temporaire unique ;
5. calcule aussi le SHA-256 du binaire extrait ;
6. publie le binaire par renommage atomique dans le cache ;
7. enregistre un pin par artefact dans `cache/pins/` ;
8. revérifie le binaire à chaque réutilisation.

Le mode TOFU fait confiance au **premier** téléchargement réalisé par HTTPS. Il
protège les utilisations suivantes contre une modification, mais ne remplace pas
un hash obtenu par un canal indépendant. Pour un déploiement maîtrisé :

```lua
local driver = assert(webdriver.firefox({
    expected_sha256 = "<64 chiffres hexadécimaux>",
}))
```

Ou ajoute le hash dans `driver_manager.registry_pins`.

Pour valider avant une release le chemin de téléchargement/extraction/publication
avec un cache réellement vierge, la campagne complète peut aussi lancer le
préflight réseau explicite :

```bash
RUN_INSTALL_SMOKE=1 ./run_all_tests.sh
```

Ce test utilise un cache temporaire indépendant, active le TOFU uniquement dans
ce cache, télécharge réellement geckodriver et chromedriver, vérifie leur pin et
leur binaire, puis détruit le cache temporaire. Il n'efface jamais le cache
utilisateur.

Pour éviter la limite basse des appels GitHub non authentifiés en CI,
`driver_manager.lua` accepte `BABET_WEBDRIVER_GITHUB_TOKEN`, `GH_TOKEN` ou
`GITHUB_TOKEN`. Le token n'est envoyé qu'à `https://api.github.com/`. Si un
`GITHUB_TOKEN` GitHub Actions limité au dépôt courant est refusé par le dépôt
public de geckodriver, la requête est automatiquement retentée sans
authentification.

## API principale

```lua
-- navigation
assert(driver:open(url))
driver:url(); driver:title(); driver:source()
driver:back(); driver:forward(); driver:refresh()

-- recherche
local element = driver:css("main h1")
driver:xpath("//button")
driver:find("submit", { by = "id" })
driver:find_all("article", { by = "tag" })

-- attentes
local button = driver:wait("#submit", {
    state = "clickable", -- present, visible, clickable, gone
    timeout = 20,
})

-- éléments
assert(element:click())
assert(element:type("texte"))
element:text(); element:attr("href"); element:property("value")
-- attr() renvoie nil si l'attribut/propriété est absent
element:displayed(); element:enabled(); element:selected()
element:computed_role(); element:computed_label()
local shadow = element:shadow_root()
local inside = shadow:find("button")

-- JavaScript synchrone/asynchrone et sorties
local value = driver:js("return arguments[0].textContent", element)
local async_value = driver:js_async("arguments[arguments.length - 1](42)")
assert(driver:screenshot("captures/page.png"))
assert(driver:print({ orientation = "landscape" }, "captures/page.pdf"))

-- actions W3C
assert(driver:actions()
    :move_to(element)
    :double_click()
    :send_keys(webdriver.keys.DELETE)
    :send_keys(webdriver.keys.RIGHT_SHIFT)
    :scroll(0, 600, { origin = element })
    :perform())
```

`exists()` distingue l'absence normale d'un élément des erreurs de transport :

```lua
local exists, err = driver:exists("#optional")
assert(exists ~= nil, err)
if exists then
    -- l'élément existe
end
```

### WebDriver Classic

La branche Classic couvre désormais aussi les commandes W3C modernes qui
manquaient encore : élément actif, lecture des timeouts, nouvelle fenêtre ou
nouvel onglet, maximisation/minimisation/plein écran, JavaScript asynchrone,
cookie individuel, Shadow DOM, rôle/label calculés, impression PDF et source
d'actions `wheel`. Le mode worker transporte également les `ShadowRoot` et toutes
les nouvelles commandes sérialisables ; seul le builder chaînable `actions()`
reste volontairement réservé aux sessions directes.


## WebDriver BiDi

WebDriver BiDi est négocié sur **la même session navigateur** que WebDriver
Classic. Il faut demander la capability `webSocketUrl` au démarrage :

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
assert(driver:quit()) -- ferme aussi le transport BiDi
```

La surface typée 2.0.0 fournit `status()`, `subscribe()`, `unsubscribe()`,
`get_tree()`, `navigate()`, `evaluate()` et `get_realms()`. `call(method,
params)` reste volontairement disponible comme accès bas niveau aux commandes
BiDi que cette première surface n'encapsule pas encore.

Les événements reçus pendant l'attente d'une réponse sont conservés dans une
file bornée. `next_event()` les dépile, tandis que `on()` / `off()` / `dispatch()`
permettent une utilisation par callbacks explicites. Un dépassement de la file
est signalé par l'événement synthétique `babetWebDriver.eventOverflow` plutôt que
par une croissance mémoire non bornée.

### BiDi dans un worker dédié

Pour isoler la connexion WebSocket BiDi du worker Classic, utilise le worker BiDi
dédié :

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

Avec `webdriver_worker.lua`, `session:bidi()` crée automatiquement ce worker
BiDi séparé à partir de `session:websocket_url()`. Le worker Classic et le
transport BiDi ne partagent donc ni leur connexion ni leur boucle d'attente.

Le transport WebSocket de Babet étant synchrone, le worker BiDi est volontairement
piloté par commandes : il attend son channel parent et ne lit le WebSocket que
pendant `call()`, les wrappers nommés ou `next_event()`. Les événements reçus
pendant une commande restent dans la file bornée du client BiDi
(`event_queue_limit`). `next_event(timeout)` effectue explicitement la lecture
réseau dans le worker, par tranches bornées afin qu'une annulation reste réactive.
Cette architecture évite qu'un `recv()` WebSocket au repos empêche le worker de
recevoir la commande suivante.

Le protocole BiDi est un standard vivant : les wrappers nommés couvrent le socle
validé par les tests de cette version, et `call()` constitue l'échappatoire pour
les commandes plus récentes sans attendre une nouvelle méthode de confort.

## Session dans un worker

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

Le navigateur et l'objet WebDriver restent dans l'état Lua du worker. Les
channels transportent uniquement des commandes et des résultats sérialisables.
Les éléments renvoyés deviennent des proxies utilisables par le parent.

Une session proxy traite une commande à la fois. Pour du parallélisme, crée
plusieurs sessions workers indépendantes. Le parent attend au minimum le budget
HTTP `request_timeout` plus une petite marge de transport ; `wait()` étend encore
ce budget pour couvrir son timeout logique. Une réponse devenue obsolète reste
drainée défensivement afin de ne jamais désynchroniser l'appel suivant.

`stop_timeout` (ou le `timeout` explicite passé à `session:stop(timeout)`) est un
budget global pour toute la séquence d'arrêt. Lorsqu'un transport BiDi est
attaché à la session Classic, sa fermeture consomme donc une partie de ce même
budget avant l'arrêt et la jointure du worker Classic.

## Contrat d'erreur

Les opérations normales renvoient :

```lua
value, nil
nil, "webdriver: ..."
```

Les mauvais types, options inconnues et stratégies invalides sont des erreurs de
programmation et lèvent une erreur Lua.

## Documentation

- [`docs/webdriver.fr.md`](docs/webdriver.fr.md) — référence française ;
- [`docs/webdriver.en.md`](docs/webdriver.en.md) — English reference ;

### Générer les PDF

Le script `build_docs.sh` convertit automatiquement chaque fichier
`docs/<nom>.<langue>.md` en `docs/pdf/<nom>.<langue>.pdf`. Il traite donc
aussi toute nouvelle traduction ajoutée ultérieurement selon cette convention.

Il nécessite Pandoc et `xelatex` ou `lualatex` :

```sh
./build_docs.sh
```

Pour supprimer les PDF générés :

```sh
./build_docs.sh --clean
```
- [`MIGRATION.md`](MIGRATION.md) — passage de LuaPilot à Babet 2.9.0 ;
- [`CHANGELOG.md`](CHANGELOG.md) — changements de la bibliothèque.

## Licence

GNU GPL v3 ou ultérieure (`GPL-3.0-or-later`). Voir [`LICENSE`](LICENSE).
