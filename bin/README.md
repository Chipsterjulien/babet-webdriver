# Binaire Babet local facultatif

Tu peux télécharger ou compiler **Babet 2.9.0 ou supérieur** depuis son
[dépôt GitHub officiel](https://github.com/Chipsterjulien/babet), puis placer ici
le binaire sous le nom :

```text
bin/babet
```

Cette organisation permet de conserver une version de Babet propre au projet,
mais elle n'est pas obligatoire. Les scripts du dépôt cherchent le binaire dans
cet ordre :

1. variable `BABET` ;
2. `bin/babet` ;
3. commande `babet` disponible dans le `PATH`.

Exemples :

```sh
./run_tests.sh
BABET=/opt/babet/bin/babet ./run_tests.sh
```

Le binaire n'est volontairement pas inclus dans le dépôt.
