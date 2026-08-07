# Changelog

## 2.0.0 — WebDriver BiDi sur le WebSocket natif de Babet

### Dernière passe de prépublication

- corrige le nom public `BABET_WEBDRIVER_GITHUB_TOKEN` avant publication ;
- traite le motif Babet `cancelled` comme un arrêt coopératif dans les workers Classic et BiDi ;
- évite l'attente `stop_timeout` inutile lorsqu'un worker BiDi a déjà déclaré son transport en panne ;
- dimensionne le budget parent de `switch_last()` pour ses deux requêtes HTTP successives ;
- distingue un driver réellement injoignable d'un driver joignable mais `ready=false` en mode `attach` ;
- ajoute `RUN_INSTALL_SMOKE=1` pour valider le chemin réel téléchargement -> extraction -> chmod -> hash -> publication atomique dans un cache vierge ;
- préserve le marqueur `babet.json.as_array()` lors des copies profondes et à travers les channels Classic/BiDi, notamment pour conserver `[]` au lieu de `{}` ;
- applique une deadline monotone unique à l'arrêt des workers Classic et BiDi afin que `stop(timeout)` / `close(timeout)` représentent un budget global, fermeture d'un transport BiDi attaché incluse ;
- transmet les clés internes de transport au worker Classic via `worker.args`, comme le worker BiDi, afin d'éviter toute divergence silencieuse entre parent et worker ;
- utilise systématiquement la valeur retournée par `babet.json.as_array()` lors de la reconstruction des tableaux JSON.

### Transport et négociation

- ajoute `webdriver_bidi.lua`, client WebDriver BiDi synchrone basé sur `babet.websocket` de Babet 2.22.0 ;
- ajoute l'option de démarrage `bidi = true`, qui demande la capability W3C `webSocketUrl` pendant la création de la session Classic ;
- valide la présence de `webSocketUrl` et nettoie la session, le driver et le profil temporaire si la négociation BiDi est incomplète ;
- ajoute `driver:websocket_url()`, `driver:bidi()` et `driver:bidi_worker()` ;
- conserve Babet 2.9.0 comme minimum pour le client Classic, tandis que BiDi exige Babet 2.22.0 ou supérieur.

### API BiDi

- ajoute `call(method, params)` comme accès générique au protocole vivant WebDriver BiDi ;
- encapsule `session.status`, `session.subscribe`, `session.unsubscribe`, `browsingContext.getTree`, `browsingContext.navigate`, `script.evaluate` et `script.getRealms` ;
- accepte les filtres de souscription par browsing contexts et user contexts ;
- valide les readiness states de navigation et les principales options de sérialisation/ownership de `script.evaluate` ;
- conserve les erreurs BiDi distantes avec leur code de protocole.

### Événements et robustesse

- multiplexe réponses de commandes et événements sur la même connexion sans désynchroniser les identifiants ;
- draine les réponses tardives de commandes ayant expiré sans réinitialiser la deadline de la commande courante ;
- ajoute `next_event()`, `on()`, `off()` et `dispatch()` pour consommer explicitement les événements ;
- borne la file d'événements du client direct et signale les pertes via `babetWebDriver.eventOverflow` ;
- ajoute `webdriver_bidi_worker.lua`, worker dédié propriétaire du WebSocket, piloté par le channel de commandes ;
- aligne l'attente du parent sur le timeout explicite de chaque commande BiDi worker, même lorsqu'il dépasse le `command_timeout` par défaut ;
- évite tout polling WebSocket au repos dans le worker BiDi : `next_event()` devient une commande explicite, ce qui empêche un `recv()` synchrone de bloquer la réception des commandes parent ;
- ferme systématiquement tous les channels du worker BiDi, y compris après un arrêt ou une jointure en erreur ;
- ferme automatiquement les transports BiDi attachés depuis `driver:quit()` et `session:stop()` ;
- ajoute `__close` aux clients BiDi directs et workers.

### Durcissement pré-release

- corrige les multi-retours Lua de `string.gsub()` dans les versions/tokens internes ;
- affiche explicitement les navigateurs et drivers absents dans `tools/check_env.lua` ;
- aligne le budget d'attente du worker Classic sur `request_timeout` et sur le timeout logique de `wait()` ;
- fait correspondre chromedriver au binaire Chrome ou Chromium réellement sélectionné ;
- publie les binaires de driver atomiquement après extraction dans un fichier temporaire unique ;
- évite le cache partagé `/tmp/.cache/babet-webdriver` lorsque `HOME` est absent ;
- accepte `BABET_WEBDRIVER_GITHUB_TOKEN`, `GH_TOKEN` ou `GITHUB_TOKEN` pour `api.github.com`, avec repli anonyme si un token GitHub Actions limité au dépôt courant est refusé ;
- rend les erreurs de transport BiDi worker réellement fatales et fail-fast pour les appels suivants ;
- rend `next_event()` interruptible par tranches courtes dans le worker BiDi ;
- évite que `webdriver.start()` modifie la table d'options fournie par l'appelant ;
- fait renvoyer `nil` par `Element:attr()` lorsqu'un attribut/propriété est absent, tout en conservant `babet.json.null` pour les résultats JavaScript génériques ;
- complète `webdriver.keys` avec `SEPARATOR`, les modificateurs droits et leurs alias ;
- corrige l'ancienne mention erronée indiquant que `docs/pdf/` était ignoré par Git.

### Tests et documentation

- ajoute `tests/bidi_test.lua` pour le multiplexage, les subscriptions, les erreurs, les timeouts, les réponses tardives, les callbacks et les débordements de file ;
- étend les tests de protocole et de worker à la négociation `webSocketUrl` ;
- étend les smoke tests Firefox et Chromium pour valider BiDi réel, `browsingContext`, `script.evaluate`, les logs et les événements réseau ;
- ajoute `examples/bidi.lua` et documente le client direct, le worker BiDi, leurs options et leur cycle de vie en français et en anglais.
- simplifie le journal de `run_all_tests.sh` sur le modèle de Babet : temporaire unique puis publication finale atomique, sans verrou `flock` persistant ni faux positif de verrouillage.

## 1.1.1 — durcissement du transport worker et des validations

- rend le proxy worker récupérable après un `command_timeout` : les réponses tardives d'appels déjà expirés sont drainées sans désynchroniser l'appel suivant ;
- applique une deadline monotone unique pendant ce drainage afin qu'une suite de réponses obsolètes ne puisse pas prolonger indéfiniment l'attente ;
- utilise le même mécanisme robuste lors de `Session:stop()`, qui n'est plus perturbé par une ancienne réponse encore présente dans le channel ;
- refuse désormais les dimensions fractionnaires dans `window_size` au lieu de les tronquer silencieusement ;
- conserve les diagnostics d'arrêt du driver et de nettoyage du profil lorsqu'une réponse de création de session est mal formée ;
- ajoute des tests de rétablissement après timeout worker et de validation stricte de `window_size`.

## 1.1.0 — WebDriver Classic complet et socle prêt pour BiDi

### Corrections de validation

- Corrige le transport des appels worker comportant plusieurs arguments quand le premier est une table (par exemple `session:print(options, path)`).
- Ajoute `run_all_tests.sh`, qui exécute toute la campagne tout en affichant la sortie dans le terminal et en l’enregistrant dans `babet-webdriver-tests.txt`.
- Durcit ce journal de tests : temporaire unique dans le répertoire cible, publication finale atomique, conservation de l’ancien journal en cas d’interruption et verrou `flock` contre deux campagnes concurrentes.

- version centralisée dans `webdriver_version.lua`, partagée par le client, le worker et le gestionnaire de drivers ;
- ajout de `active_element()` et `get_timeouts()` ;
- ajout de `new_window()`, `maximize()`, `minimize()` et `fullscreen()` ;
- ajout de `js_async()` pour `Execute Async Script` et préservation explicite de `babet.json.null` dans les arguments/résultats JavaScript ;
- ajout de `cookie(name)` pour lire un cookie individuel ;
- prise en charge W3C du Shadow DOM avec objets `ShadowRoot`, `find()` et `find_all()` ;
- ajout de `computed_role()` et `computed_label()` sur les éléments ;
- ajout de `print()` avec validation stricte des options W3C et publication atomique des PDF ;
- ajout de la source d'actions `wheel` via `actions():scroll()`, avec validation des entiers W3C ;
- validation renforcée des timeouts (`json.null` compris), rectangles de fenêtre et index de frame ;
- parité du proxy worker pour les nouvelles commandes et transport des références `ShadowRoot` ;
- extension du faux serveur WebDriver et des tests de protocole/worker à la nouvelle surface Classic ;
- smoke tests réels enrichis et nettoyage/ignorance des artefacts temporaires de test ;
- documentation française et anglaise mise à jour, avec conservation de Babet 2.9.0 comme version minimale pour WebDriver Classic.

## 1.0.6 — lien officiel et version minimale de Babet

- ajout du dépôt officiel de Babet dans le README et les documentations française et anglaise ;
- indication explicite que babet-webdriver nécessite Babet 2.9.0 au minimum ;
- ajout de la même information dans `bin/README.md` pour l'installation locale facultative.

## 1.0.5 — démarrage d'un nouveau projet et Babet facultatif dans `bin/`

- ajout d'une section complète « Démarrer un nouveau projet » dans le README ;
- ajout des mêmes instructions et exemples dans les références française et anglaise ;
- distinction claire entre les fichiers obligatoires, le proxy worker et les outils facultatifs ;
- exemples pour un Babet local, installé dans le `PATH` ou situé à un chemin quelconque ;
- exemples d'arborescences à la racine et avec les modules rangés dans `lib/` ;
- scripts de test capables de résoudre Babet via `BABET`, `bin/babet`, puis le `PATH` ;
- clarification du caractère facultatif du dossier `bin/`.

## 1.0.4 — parité complète de la documentation anglaise

- alignement intégral de `docs/webdriver.en.md` sur la référence française ;
- ajout des sections et exemples manquants sur les options, recherches, éléments,
  timeouts W3C, gestion des drivers, TOFU, extraction et cycle de vie des workers ;
- structure, nombre de sections et couverture fonctionnelle désormais identiques
  dans les deux langues ;
- génération validée : 10 pages en français et 10 pages en anglais.

## 1.0.3

- ajout de `build_docs.sh` pour générer automatiquement un PDF par documentation localisée ;
- détection automatique des futures langues selon la convention `docs/<nom>.<langue>.md` ;
- sortie des artefacts générés dans `docs/pdf/`.

## 1.0.2 — smoke test worker réel

- ajout de `tests/worker_smoke_test.lua` et `run_worker_smoke.sh` ;
- validation complète parent → channels → worker → WebDriver → navigateur ;
- test d'un proxy d'élément, de JavaScript structuré et d'une capture d'écran ;
- exposition effective de `browser_binary()` sur le proxy parent ;
- versions des modules portées à 1.0.2.

## 1.0.1 — compatibilité Chromium Snap

- détection automatique du binaire Chromium dans le `PATH` ;
- passage explicite de `/snap/bin/chromium` à ChromeDriver ;
- création d'un profil temporaire sous `~/snap/chromium/common` pour respecter
  le confinement Snap ;
- nettoyage automatique de ce profil à la fermeture ;
- nouvelle option `user_data_dir` pour Chrome et Chromium ;
- ajout de `driver:browser_binary()` ;
- ajout du chemin du journal aux erreurs de création de session ;
- couverture du chemin Chrome/Chromium dans les tests de protocole.

## 1.0.0 — migration Babet 2.9.0

- renommage complet LuaPilot → Babet ;
- dépendance minimale fixée à Babet 2.9.0 ;
- lancement des drivers avec `babet.spawn()` et redirection native des logs ;
- suppression de `sh -c`, `echo $!`, `kill(1)`, `tar`, `unzip` et `base64(1)` ;
- choix automatique d'un port avec reprise en cas de collision ;
- timeouts de transport et de démarrage configurables ;
- téléchargement progressif avec `babet.http.download()` ;
- extraction ciblée avec `babet.archive.extractFile()` ;
- pins atomiques par artefact, hash de l'archive et du binaire ;
- captures Base64 décodées nativement et écrites atomiquement ;
- propagation des erreurs dans `exists()`, `wait()` et les méthodes booléennes ;
- encodage sûr des segments d'URL WebDriver ;
- ajout de `webdriver_worker.lua` basé sur les channels Babet ;
- transport worker fidèle des arguments `nil`, des valeurs multiples, des
  références JSON null et des codes d'erreur W3C ;
- déplacement des exemples, outils et tests dans des dossiers dédiés ;
- ajout de tests de protocole sans navigateur et de tests workers ;
- réécriture de la documentation française et anglaise.
