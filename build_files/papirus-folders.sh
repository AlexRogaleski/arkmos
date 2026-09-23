#!/usr/bin/env bash
# Arkmos — troca a cor padrão das pastas do Papirus.
#
# O Papirus traz cada pasta em todas as cores (folder-violet.svg,
# folder-violet-download.svg, user-violet-home.svg...), e o nome sem cor é um
# symlink para a cor padrão, o azul: folder.svg -> folder-blue.svg. Trocar a cor
# é repontar esses symlinks. É o que faz o papirus-folders, do próprio projeto
# Papirus; o Fedora não o empacota, e o que ele faz cabe aqui.
#
# Só são tocados os links cujo nome é o alvo sem o "-blue", que são os que
# definem a cor padrão. Os links entre variantes de uma mesma cor
# (folder-blue-desktop.svg -> user-blue-desktop.svg) ficam como estão.
#
# O Papirus-Dark não tem pastas coloridas próprias: os diretórios dele apontam,
# por symlink, para os do Papirus. A troca feita aqui vale para os dois.
set -euo pipefail

cor="${1:?uso: papirus-folders.sh <cor>}"
tema=/usr/share/icons/Papirus

trocados=0
while IFS= read -r -d '' link; do
    alvo="$(readlink "$link")"
    [[ $alvo =~ ^(folder|user)-blue(-.+)?\.svg$ ]] || continue
    [[ "$(basename "$link")" == "${alvo/-blue/}" ]] || continue

    novo="${alvo/-blue/-$cor}"
    if [[ ! -e "$(dirname "$link")/$novo" ]]; then
        echo "papirus-folders: $(dirname "$link")/$novo não existe" >&2
        exit 1
    fi
    ln -sfn "$novo" "$link"
    trocados=$((trocados + 1))
done < <(find "$tema" -type l -path '*/places/*' -print0)

# O Papirus 20250501 tem 385 desses links. Um número muito menor quer dizer que
# a estrutura do tema mudou e a troca não pegou: melhor o build falhar do que a
# imagem sair com as pastas azuis sem ninguém notar.
if ((trocados < 300)); then
    echo "papirus-folders: só $trocados links trocados; o Papirus mudou?" >&2
    exit 1
fi

# O cache guarda nomes de ícone e diretórios, não destinos de symlink, mas é
# regerado para não ficar mais velho que os diretórios que descreve.
gtk-update-icon-cache --quiet --force "$tema"

echo "papirus-folders: $trocados links apontam para $cor"
