#!/usr/bin/env bash
#
# Cursores Bibata Modern: Ice (branco, o padrão) e Classic (preto).
#
# O Fedora não empacota o Bibata. Vem do release upstream, GPL-3.0, com versão
# e checksum fixados. O release não publica checksum: os valores abaixo foram
# calculados no download (Ice em 2026-09-24, Classic em 2026-09-28), e uma
# mudança no arquivo servido falha o build. A troca por conta é o
# 'ujust arkmos-cursor' (PROJECT.md §26.1).

set -euo pipefail

BIBATA_VERSION="2.0.7"
declare -A BIBATA_SHA256=(
    [Bibata-Modern-Ice]="a68cae60c4dc706350e194ebc91c5fe48bc7bc9d59e119555834a2a7ee5078ef"
    [Bibata-Modern-Classic]="7d3495864e5bbef02f5e77de760b2905903b63c71495a78ef6306d19a3b556d8"
)

DEST="/usr/share/icons"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for THEME in Bibata-Modern-Ice Bibata-Modern-Classic; do
    # Retry generoso: o release do GitHub já respondeu 500 por mais tempo que
    # as três tentativas padrão do curl.
    echo "==> Cursor ${THEME} ${BIBATA_VERSION}"
    curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors \
        --connect-timeout 20 -o "$WORK/${THEME}.tar.xz" \
        "https://github.com/ful1e5/Bibata_Cursor/releases/download/v${BIBATA_VERSION}/${THEME}.tar.xz"

    got="$(sha256sum "$WORK/${THEME}.tar.xz" | cut -d' ' -f1)"
    if [[ "$got" != "${BIBATA_SHA256[$THEME]}" ]]; then
        echo "ERRO: checksum do cursor ${THEME} não confere." >&2
        echo "  esperado: ${BIBATA_SHA256[$THEME]}" >&2
        echo "  obtido:   $got" >&2
        exit 1
    fi

    tar -xJf "$WORK/${THEME}.tar.xz" -C "$DEST" "${THEME}/"
    test -f "$DEST/${THEME}/index.theme"
    test -e "$DEST/${THEME}/cursors/left_ptr"
    echo "    $(find "$DEST/${THEME}/cursors" -mindepth 1 | wc -l) cursores instalados"
done
