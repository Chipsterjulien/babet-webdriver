# Migration depuis luapilot-webdriver

## Prérequis

WebDriver Classic nécessite **Babet 2.9.0 ou supérieur**. WebDriver BiDi,
introduit en 2.0.0, nécessite **Babet 2.22.0 ou supérieur** et `babet.websocket`.

## Renommages

```lua
-- ancien
luapilot.signal.handle(...)

-- nouveau
babet.signal.handle(...)
```

Le module reste chargé de la même manière :

```lua
local webdriver = require("webdriver")
```

Le cache change de dossier :

```text
~/.cache/luapilot-webdriver/
→ ~/.cache/babet-webdriver/
```

Les anciens drivers ne sont pas repris automatiquement : ils ne contiennent pas
le hash du binaire extrait utilisé par le nouveau format de pins.

## Changements de comportement utiles

### `exists()`

Avant, toute erreur devenait `false`. Désormais :

```lua
local exists, err = driver:exists("#optional")
assert(exists ~= nil, err)
```

Seule l'erreur WebDriver `no such element` produit `false`.

### `wait()`

Une erreur réseau, une session invalide ou un driver arrêté est propagé
immédiatement au lieu d'être masqué jusqu'au timeout.

### ports

Sans option `port`, une session lancée par la bibliothèque demande un port libre
au noyau et réessaie en cas de collision. En mode `attach`, les ports historiques
4444 et 9515 restent utilisés par défaut.

### captures

Les captures sont décodées avec `babet.base64`, leur dossier parent est créé si
nécessaire, puis elles sont publiées atomiquement.

### arrêt

Le processus est conservé comme objet Babet. `quit()` ferme la session, envoie
SIGTERM au groupe du driver, attend la période de grâce puis nettoie les
ressources. La méthode est idempotente et possède l'alias `close()`.

## Arborescence

- `pronote_example.lua` devient `examples/pronote.lua` ;
- `smoke_test.lua` devient `tests/smoke_test.lua` ;
- `check_env.lua` devient `tools/check_env.lua`.


## Mise à niveau vers babet-webdriver 1.1.0

La 1.1.0 ne retire aucune API WebDriver Classic existante. Elle ajoute toutefois
`webdriver_version.lua` comme source de vérité unique de la version. Si les
modules sont copiés manuellement dans un autre projet, il faut donc copier ce
fichier avec `webdriver.lua` et `driver_manager.lua` (et avec
`webdriver_worker.lua` lorsque le mode worker est utilisé).

Les nouveaux appels (`js_async`, Shadow DOM, impression PDF, commandes de
fenêtre supplémentaires et actions `wheel`) sont additifs. La dépendance minimale
du client WebDriver Classic reste **Babet 2.9.0**.

## Mise à niveau vers babet-webdriver 2.0.0

La 2.0.0 introduit WebDriver BiDi sans retirer l'API WebDriver Classic 1.1.x.
Un projet qui n'utilise que Classic peut continuer à fonctionner avec **Babet
2.9.0 ou supérieur** et les trois modules `webdriver.lua`,
`webdriver_version.lua` et `driver_manager.lua`.

Pour activer BiDi, il faut **Babet 2.22.0 ou supérieur** et ajouter
`webdriver_bidi.lua` :

```lua
local driver = assert(webdriver.firefox({
    headless = true,
    bidi = true,
}))
local bidi = assert(driver:bidi())
```

`bidi = true` demande la capability W3C `webSocketUrl`. La connexion BiDi est
donc attachée à la même session que le transport HTTP Classic.

Pour isoler la réception d'événements dans un worker dédié, ajoute aussi
`webdriver_bidi_worker.lua` et utilise `driver:bidi_worker()` ou, depuis une
session `webdriver_worker`, `session:bidi()`.

La surface BiDi 2.0.0 est volontairement progressive. Les helpers nommés
couvrent le socle `session`, `browsingContext` et `script`, tandis que
`bidi:call(method, params)` permet d'utiliser les autres commandes du standard
sans attendre l'ajout d'un wrapper.

La campagne complète `./run_all_tests.sh` valide désormais BiDi en plus de
Classic et nécessite donc Babet 2.22.0 ou supérieur.
