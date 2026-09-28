#!/usr/bin/env bash
#
# Plugins do Neovim que a configuração da imagem usa (files/etc/xdg/nvim).
#
# Fixados por commit, como o greeter: tag pode ser movida. Vão para 'opt', e
# não 'start': só carregam pelo packadd do sysinit, que os pula quando a conta
# tem configuração própria (PROJECT.md §9.1).
#
#   tokyonight.nvim  v4.14.1  Apache-2.0
#   mini.nvim        v0.18.0  MIT

set -euo pipefail

DEST="/usr/share/nvim/site/pack/arkmos/opt"

plugin() {
    local nome="$1" repo="$2" commit="$3"
    echo "==> ${nome} ${commit:0:12}"
    git init --quiet "$DEST/$nome"
    git -C "$DEST/$nome" fetch --quiet --depth=1 "https://github.com/$repo.git" "$commit"
    git -C "$DEST/$nome" checkout --quiet FETCH_HEAD
    rm -rf "$DEST/$nome/.git"
    test -f "$DEST/$nome/LICENSE" || test -f "$DEST/$nome/LICENSE.md"
}

mkdir -p "$DEST"
plugin tokyonight.nvim folke/tokyonight.nvim 545d72cde6400835d895160ecb5853874fd5156d
plugin mini.nvim echasnovski/mini.nvim 2df201d9b217bc0ad54e5d077fc4c228e6e4ef96

# Os helptags ficam prontos na imagem: o :help dos plugins funciona sem que o
# Neovim precise escrever em /usr.
nvim --headless -u NONE \
    -c "helptags $DEST/tokyonight.nvim/doc" \
    -c "helptags $DEST/mini.nvim/doc" \
    -c 'qa!'
