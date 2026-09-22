#!/usr/bin/env bash
#
# JetBrains Mono Nerd Font.
#
# O 'jetbrains-mono-fonts' do Fedora NÃO é a versão patched: não traz os
# glifos Nerd Font de que o prompt do Starship e o 'eza --icons' dependem.
# Sem eles o terminal mostra caixas vazias no lugar dos ícones.
#
# Checksum oficial em <tag>/SHA-256.txt no release do nerd-fonts.

set -euo pipefail

NERD_FONTS_VERSION="3.5.1"
JETBRAINS_MONO_SHA256="04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf"

DEST="/usr/share/fonts/jetbrains-mono-nerd"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --retry-delay fixa a espera em 10s: o padrão do curl dobra a partir de 1s, e
# três tentativas se esgotam em 8 segundos. O release do GitHub respondeu 500
# por mais tempo que isso em 2026-09-22, e o build falhou no CI por causa disso.
echo "==> JetBrains Mono Nerd Font ${NERD_FONTS_VERSION}"
curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors \
    --connect-timeout 20 -o "$WORK/JetBrainsMono.tar.xz" \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONTS_VERSION}/JetBrainsMono.tar.xz"

got="$(sha256sum "$WORK/JetBrainsMono.tar.xz" | cut -d' ' -f1)"
if [[ "$got" != "$JETBRAINS_MONO_SHA256" ]]; then
    echo "ERRO: checksum da fonte não confere." >&2
    echo "  esperado: $JETBRAINS_MONO_SHA256" >&2
    echo "  obtido:   $got" >&2
    exit 1
fi

mkdir -p "$DEST"
tar -xJf "$WORK/JetBrainsMono.tar.xz" -C "$DEST" \
    --wildcards '*.ttf' --exclude='*Windows*'

fc-cache -f "$DEST" >/dev/null
echo "    $(find "$DEST" -name '*.ttf' | wc -l) arquivos instalados"
