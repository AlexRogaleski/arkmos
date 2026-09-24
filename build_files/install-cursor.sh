#!/usr/bin/env bash
#
# Cursor Bibata Modern Ice.
#
# O Fedora não empacota o Bibata: os temas de cursor do repositório são
# Adwaita, Breeze, Oxygen e Bluecurve. Vem do release upstream, GPL-3.0, com
# versão e checksum fixados como a Nerd Font.
#
# A variante Ice é a branca, de pontas arredondadas: é a que mais aparece
# contra o fundo escuro do Tokyo Night. O nome do tema, Bibata-Modern-Ice, é o
# que dconf, GTK 3 e 4, niri e a tela de login declaram — o 'just check'
# confere que os cinco concordam e que o tema existe.
#
# O release v2.0.7 não publica checksum. O valor abaixo foi calculado no
# download de 2026-09-24; a partir daí, qualquer mudança no arquivo servido
# falha o build.

set -euo pipefail

BIBATA_VERSION="2.0.7"
BIBATA_SHA256="a68cae60c4dc706350e194ebc91c5fe48bc7bc9d59e119555834a2a7ee5078ef"
THEME="Bibata-Modern-Ice"

DEST="/usr/share/icons"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Mesma política de retry da Nerd Font: o release do GitHub já respondeu 500
# por mais tempo que as três tentativas padrão do curl.
echo "==> Cursor ${THEME} ${BIBATA_VERSION}"
curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors \
    --connect-timeout 20 -o "$WORK/${THEME}.tar.xz" \
    "https://github.com/ful1e5/Bibata_Cursor/releases/download/v${BIBATA_VERSION}/${THEME}.tar.xz"

got="$(sha256sum "$WORK/${THEME}.tar.xz" | cut -d' ' -f1)"
if [[ "$got" != "$BIBATA_SHA256" ]]; then
    echo "ERRO: checksum do cursor não confere." >&2
    echo "  esperado: $BIBATA_SHA256" >&2
    echo "  obtido:   $got" >&2
    exit 1
fi

# O tarball traz a pasta do tema na raiz. Os links simbólicos entre cursores
# (nomes alternativos para a mesma imagem) são preservados pelo tar.
tar -xJf "$WORK/${THEME}.tar.xz" -C "$DEST" "${THEME}/"
test -f "$DEST/${THEME}/index.theme"
test -e "$DEST/${THEME}/cursors/left_ptr"
echo "    $(find "$DEST/${THEME}/cursors" -mindepth 1 | wc -l) cursores instalados"
