# babet-webdriver

Client **WebDriver W3C** en Lua pour **Babet 2.9.0 ou supérieur**. Il pilote
Firefox, Chrome et Chromium avec une API proche de Selenium, sans module Lua
externe et sans lancer de shell pour gérer les drivers. Babet est disponible sur
son [dépôt GitHub officiel](https://github.com/Chipsterjulien/babet).

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
- erreurs WebDriver conservées au lieu d'être transformées silencieusement en
  `false` ou en simple timeout.

## Prérequis

- Linux ;
- **[Babet 2.9.0 ou supérieur](https://github.com/Chipsterjulien/babet)** ;
- Firefox, Chrome ou Chromium ;
- un driver compatible présent dans `PATH`, ou l'autorisation de le télécharger.

Aucun `tar`, `unzip`, `base64`, `curl` ou shell externe n'est requis.

## Organisation

```text
babet-webdriver/
├── bin/                     # binaire Babet local facultatif
├── docs/                    # référence française et anglaise
├── examples/pronote.lua     # exemple réaliste, volontairement incomplet
├── tests/                   # tests mock, worker et smoke tests réels
├── tools/check_env.lua      # diagnostic de l'environnement
├── driver_manager.lua       # téléchargement, cache et vérification
├── webdriver.lua            # client WebDriver principal
├── webdriver_worker.lua     # proxy de session dans un worker
├── run_tests.sh
├── run_smoke.sh
└── run_worker_smoke.sh
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
├── driver_manager.lua
└── main.lua
```

`webdriver.lua` charge `driver_manager.lua` en interne : les deux fichiers sont
nécessaires, même lorsqu'un driver est déjà présent dans `PATH`.

Pour héberger la session dans un worker Babet, ajoute simplement :

```text
mon-projet/
├── webdriver.lua
├── driver_manager.lua
├── webdriver_worker.lua
└── main.lua
```

`tools/check_env.lua` est facultatif. Il est utile pour diagnostiquer une
machine, mais il n'est pas requis par la bibliothèque. Les dossiers `tests/`,
`examples/`, `docs/` et les scripts `run_*.sh` servent au développement de
babet-webdriver et n'ont pas besoin d'être copiés dans un projet utilisateur.

### Où placer Babet

Le binaire **n'a pas besoin d'être dans `bin/`**. Il peut être téléchargé ou
compilé depuis le [dépôt GitHub de Babet](https://github.com/Chipsterjulien/babet).
La bibliothèque nécessite au minimum la version **2.9.0**. Trois organisations
sont équivalentes :

1. **Babet local au projet**, pratique pour figer la version utilisée :

   ```text
   mon-projet/
   ├── bin/babet
   ├── webdriver.lua
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
| `attach` | se connecte à un driver déjà lancé |
| `request_timeout` | timeout HTTP WebDriver général |
| `status_timeout` | timeout court des sondes `/status` |
| `log_path` / `log_dir` | destination des logs du processus driver |

Toutes les options de `webdriver.start()` sont strictes : une faute de frappe
lève une erreur Lua au lieu d'être ignorée.

### Chromium installé par Snap

Lorsque `chromium` est résolu vers `/snap/bin/chromium`, la bibliothèque crée
automatiquement un profil temporaire dans
`~/snap/chromium/common/babet-webdriver/profiles/`. Ce chemin est visible depuis
le confinement Snap, contrairement au profil temporaire habituellement créé
par ChromeDriver dans `/tmp`. Le profil est supprimé lors de `driver:quit()`.

Il ne faut pas ajouter `--no-sandbox` pour contourner ce problème : la correction
porte sur l'emplacement du profil, sans désactiver la sandbox du navigateur.

## Gestion sécurisée des drivers

Le cache par défaut se trouve dans :

```text
~/.cache/babet-webdriver/
```

`driver_manager.lua` :

1. résout la dernière release officielle de geckodriver ou la version de
   chromedriver correspondant au navigateur installé ;
2. télécharge l'archive en streaming ;
3. vérifie son SHA-256 ;
4. extrait uniquement le binaire attendu ;
5. calcule aussi le SHA-256 du binaire extrait ;
6. enregistre un pin par artefact dans `cache/pins/` ;
7. revérifie le binaire à chaque réutilisation.

Le mode TOFU fait confiance au **premier** téléchargement réalisé par HTTPS. Il
protège les utilisations suivantes contre une modification, mais ne remplace pas
un hash obtenu par un canal indépendant. Pour un déploiement maîtrisé :

```lua
local driver = assert(webdriver.firefox({
    expected_sha256 = "<64 chiffres hexadécimaux>",
}))
```

Ou ajoute le hash dans `driver_manager.registry_pins`.

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
element:displayed(); element:enabled(); element:selected()

-- JavaScript et captures
local value = driver:js("return arguments[0].textContent", element)
assert(driver:screenshot("captures/page.png"))

-- actions W3C
assert(driver:actions()
    :move_to(element)
    :double_click()
    :send_keys(webdriver.keys.DELETE)
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
plusieurs sessions workers indépendantes. Le test d'intégration réel correspondant
se lance avec `./run_worker_smoke.sh firefox` ou `chromium`.

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
