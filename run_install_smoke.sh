#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BROWSER=${1:-chromium}

if [ -n "${BABET:-}" ]; then
    CANDIDATE=$BABET
elif [ -x "$ROOT/bin/babet" ]; then
    CANDIDATE="$ROOT/bin/babet"
elif command -v babet >/dev/null 2>&1; then
    CANDIDATE=$(command -v babet)
else
    echo "Babet 2.22.0+ introuvable pour le smoke d'installation." >&2
    exit 2
fi

if [ ! -x "$CANDIDATE" ]; then
    echo "Binaire Babet introuvable ou non exécutable : $CANDIDATE" >&2
    exit 2
fi

BABET_DIR=$(CDPATH= cd -- "$(dirname -- "$CANDIDATE")" && pwd)
BABET_NAME=$(basename -- "$CANDIDATE")
BABET="$BABET_DIR/$BABET_NAME"
if [ "$BABET_NAME" != "babet" ]; then
    TMP_BIN="$ROOT/.cache/test-bin"
    mkdir -p "$TMP_BIN"
    ln -sf "$BABET" "$TMP_BIN/babet"
    BABET_DIR="$TMP_BIN"
fi
export PATH="$BABET_DIR:$PATH"

CACHE=$(mktemp -d "${TMPDIR:-/tmp}/babet-webdriver-install.XXXXXX") || exit 1
cleanup() { rm -rf -- "$CACHE"; }
trap cleanup EXIT HUP INT TERM
export WEBDRIVER_INSTALL_CACHE="$CACHE"

"$ROOT/tests/install_smoke_test.lua" "$BROWSER"
