#!/usr/bin/env bash
set -u
set -o pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOG=${TEST_LOG:-"$ROOT/babet-webdriver-tests.txt"}
HEADLESS=${HEADLESS:-1}
RUN_INSTALL_SMOKE=${RUN_INSTALL_SMOKE:-0}
export HEADLESS RUN_INSTALL_SMOKE

LOG_DIR=$(dirname -- "$LOG")
mkdir -p "$LOG_DIR"

# La campagne construit son journal dans un fichier temporaire unique situé
# dans le même répertoire que la destination. Le mv final est donc un rename
# atomique : l'ancien journal complet reste intact pendant toute l'exécution.
TMP_LOG=$(mktemp "${LOG}.tmp.XXXXXX") || {
    printf '[FAIL] impossible de créer le journal temporaire pour : %s\n' "$LOG" >&2
    exit 1
}

cleanup() {
    rm -f -- "$TMP_LOG"
}

on_signal() {
    local status=$1
    trap - EXIT HUP INT TERM
    cleanup
    exit "$status"
}

trap cleanup EXIT
trap 'on_signal 129' HUP
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

run_suite() {
    printf '============================================================\n'
    printf 'Babet WebDriver — campagne complète de tests\n'
    printf '============================================================\n'
    printf 'Date      : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf 'HEADLESS  : %s\n' "$HEADLESS"
    printf 'Install   : %s\n' "$RUN_INSTALL_SMOKE"
    printf 'Journal   : %s\n' "$LOG"
    printf '\n'

    printf '=== Tests environnement + protocole + BiDi + worker ===\n'
    "$ROOT/run_tests.sh" || return $?

    printf '\n=== Smoke direct — Firefox ===\n'
    "$ROOT/run_smoke.sh" firefox || return $?

    printf '\n=== Smoke direct — Chromium ===\n'
    "$ROOT/run_smoke.sh" chromium || return $?

    printf '\n=== Smoke worker — Firefox ===\n'
    "$ROOT/run_worker_smoke.sh" firefox || return $?

    printf '\n=== Smoke worker — Chromium ===\n'
    "$ROOT/run_worker_smoke.sh" chromium || return $?

    if [ "${RUN_INSTALL_SMOKE:-0}" = "1" ]; then
        printf '\n=== Préflight installation fraîche — Firefox ===\n'
        "$ROOT/run_install_smoke.sh" firefox || return $?

        printf '\n=== Préflight installation fraîche — Chromium ===\n'
        "$ROOT/run_install_smoke.sh" chromium || return $?
    fi
}

# tee garde le déroulé visible dans le terminal, mais écrit uniquement dans le
# temporaire privé de cette campagne. PIPESTATUS conserve le vrai statut des
# tests indépendamment de tee.
run_suite 2>&1 | tee "$TMP_LOG"
statuses=("${PIPESTATUS[@]}")
test_status=${statuses[0]:-1}
tee_status=${statuses[1]:-1}

if (( tee_status != 0 )); then
    printf '\n[FAIL] impossible d’écrire complètement le journal temporaire.\n' >&2
    exit "$tee_status"
fi

if (( test_status != 0 )); then
    summary=$(printf '\n============================================================\n[FAIL] campagne interrompue (code %d)\nJournal : %s\n============================================================\n' \
        "$test_status" "$LOG")
else
    summary=$(printf '\n============================================================\n[PASS] campagne complète terminée\nJournal : %s\n============================================================\n' \
        "$LOG")
fi

printf '%s\n' "$summary" | tee -a "$TMP_LOG"
summary_status=${PIPESTATUS[1]:-1}
if (( summary_status != 0 )); then
    printf '\n[FAIL] impossible de finaliser le journal temporaire.\n' >&2
    exit "$summary_status"
fi

# Publication atomique dans le même répertoire. Une campagne terminée en échec
# reste utile pour le diagnostic et remplace donc elle aussi l'ancien journal ;
# une campagne interrompue par signal ne le remplace jamais.
if ! mv -f -- "$TMP_LOG" "$LOG"; then
    printf '\n[FAIL] impossible de publier atomiquement le journal : %s\n' "$LOG" >&2
    exit 1
fi
trap - EXIT HUP INT TERM

exit "$test_status"
