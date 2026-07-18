#!/usr/bin/env bash
set -euo pipefail

# Construit un PDF pour chaque fichier Markdown localisé présent dans docs/.
# Convention reconnue : docs/<nom>.<langue>.md
# Exemples : webdriver.fr.md, webdriver.en.md, webdriver.de.md.

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="${DOCS_DIR:-$PROJECT_ROOT/docs}"
OUTPUT_DIR="${PDF_OUTPUT_DIR:-$DOCS_DIR/pdf}"
PANDOC_BIN="${PANDOC:-pandoc}"

usage() {
    cat <<'USAGE'
Usage : ./build_docs.sh [--clean]

Construit automatiquement tous les fichiers docs/*.*.md en PDF dans docs/pdf/.
Les futures traductions respectant la convention <nom>.<langue>.md sont prises
en charge sans modifier le script.

Variables facultatives :
  PANDOC          commande Pandoc à utiliser (défaut : pandoc)
  PDF_ENGINE      moteur PDF : xelatex ou lualatex
  DOCS_DIR        dossier contenant les Markdown
  PDF_OUTPUT_DIR  dossier de sortie des PDF
USAGE
}

case "${1:-}" in
    "") ;;
    --clean)
        rm -rf -- "$OUTPUT_DIR"
        printf 'PDF générés supprimés : %s\n' "$OUTPUT_DIR"
        exit 0
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        printf 'Option inconnue : %s\n\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac

if ! command -v "$PANDOC_BIN" >/dev/null 2>&1; then
    printf 'Erreur : Pandoc est introuvable (%s).\n' "$PANDOC_BIN" >&2
    exit 1
fi

if [[ -n "${PDF_ENGINE:-}" ]]; then
    ENGINE="$PDF_ENGINE"
    if ! command -v "$ENGINE" >/dev/null 2>&1; then
        printf 'Erreur : le moteur PDF demandé est introuvable : %s\n' "$ENGINE" >&2
        exit 1
    fi
elif command -v xelatex >/dev/null 2>&1; then
    ENGINE="xelatex"
elif command -v lualatex >/dev/null 2>&1; then
    ENGINE="lualatex"
else
    printf 'Erreur : xelatex ou lualatex est nécessaire pour produire les PDF.\n' >&2
    exit 1
fi

if [[ ! -d "$DOCS_DIR" ]]; then
    printf 'Erreur : dossier de documentation introuvable : %s\n' "$DOCS_DIR" >&2
    exit 1
fi

mkdir -p -- "$OUTPUT_DIR"

# find permet de gérer proprement les espaces dans les noms de fichiers.
mapfile -d '' SOURCES < <(
    find "$DOCS_DIR" -maxdepth 1 -type f -name '*.*.md' -print0 | sort -z
)

if (( ${#SOURCES[@]} == 0 )); then
    printf 'Erreur : aucun fichier %s/*.*.md trouvé.\n' "$DOCS_DIR" >&2
    exit 1
fi

printf '== Génération de la documentation PDF ==\n'
printf 'Pandoc      : %s\n' "$PANDOC_BIN"
printf 'Moteur PDF  : %s\n' "$ENGINE"
printf 'Destination : %s\n\n' "$OUTPUT_DIR"

built=0
for source in "${SOURCES[@]}"; do
    filename="$(basename -- "$source")"
    basename="${filename%.md}"
    language="${basename##*.}"
    destination="$OUTPUT_DIR/$basename.pdf"
    temporary="$destination.tmp.pdf"

    # Langue BCP 47 minimale pour Pandoc/LaTeX. Les suffixes comme pt-BR ou
    # zh-CN sont conservés, tandis que les underscores deviennent des tirets.
    language="${language//_/-}"

    printf '  • %s -> %s ... ' "$filename" "$(basename -- "$destination")"

    rm -f -- "$temporary"
    "$PANDOC_BIN" "$source" \
        --from=gfm \
        --standalone \
        --pdf-engine="$ENGINE" \
        --resource-path="$PROJECT_ROOT:$DOCS_DIR" \
        --metadata="lang:$language" \
        --variable=papersize:a4 \
        --variable=geometry:margin=22mm \
        --variable=fontsize:10pt \
        --variable=colorlinks:true \
        --variable=linkcolor:blue \
        --variable=urlcolor:blue \
        --variable=toccolor:blue \
        --variable=mainfont:"DejaVu Serif" \
        --variable=sansfont:"DejaVu Sans" \
        --variable=monofont:"DejaVu Sans Mono" \
        --highlight-style=tango \
        --output="$temporary"

    mv -f -- "$temporary" "$destination"
    printf 'OK\n'
    ((built += 1))
done

printf '\n== %d PDF généré(s) ==\n' "$built"
