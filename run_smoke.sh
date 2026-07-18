#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BROWSER=${1:-firefox}

if [ -n "${BABET:-}" ]; then
    CANDIDATE=$BABET
elif [ -x "$ROOT/bin/babet" ]; then
    CANDIDATE="$ROOT/bin/babet"
elif command -v babet >/dev/null 2>&1; then
    CANDIDATE=$(command -v babet)
else
    echo "Babet 2.9.0+ introuvable." >&2
    echo "Définis BABET=/chemin/vers/babet, place-le dans bin/babet ou ajoute-le au PATH." >&2
    exit 2
fi

if [ ! -x "$CANDIDATE" ]; then
    echo "Binaire Babet introuvable ou non exécutable : $CANDIDATE" >&2
    exit 2
fi

BABET_DIR=$(CDPATH= cd -- "$(dirname -- "$CANDIDATE")" && pwd)
BABET_NAME=$(basename -- "$CANDIDATE")
BABET="$BABET_DIR/$BABET_NAME"

# Les scripts Lua utilisent #!/usr/bin/env babet. Si le fichier fourni porte un
# autre nom, expose temporairement un lien nommé babet sans modifier le système.
if [ "$BABET_NAME" != "babet" ]; then
    TMP_BIN="$ROOT/.cache/test-bin"
    mkdir -p "$TMP_BIN"
    ln -sf "$BABET" "$TMP_BIN/babet"
    BABET_DIR="$TMP_BIN"
fi

export PATH="$BABET_DIR:$PATH"
exec "$ROOT/tests/smoke_test.lua" "$BROWSER"
