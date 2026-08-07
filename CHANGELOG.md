# Changelog

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
- sortie des artefacts dans `docs/pdf/`, désormais ignoré par Git.

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
