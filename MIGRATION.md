# Migration depuis luapilot-webdriver

## Prérequis

La nouvelle version nécessite **Babet 2.9.0 ou supérieur**.

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
