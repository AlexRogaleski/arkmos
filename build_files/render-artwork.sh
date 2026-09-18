#!/usr/bin/env bash
#
# Arte do Arkmos: o splash de boot (Plymouth) e o wallpaper padrão.
#
# Gerada aqui, a partir de fonte, cores e formas, em vez de versionada como
# imagem pronta. O repositório e a imagem publicada são públicos, e arte tirada
# de site de wallpaper não tem autor nem licença identificáveis — o que sai
# deste script é do projeto.
#
# As cores são as que o Tokyo Night e o Dracula têm em comum: fundo índigo
# quase preto e lavanda como destaque (#bb9af7 num, #bd93f9 no outro). O boot e
# o desktop combinam com qualquer um dos dois.
#
# ARTWORK_ROOT renderiza fora da imagem, para conferir o resultado:
#
#   podman run --rm --security-opt label=disable \
#       -v ./build_files/render-artwork.sh:/render.sh:ro \
#       -v ./output/preview:/out -e ARTWORK_ROOT=/out \
#       localhost/arkmos:dev bash /render.sh

set -euo pipefail

ROOT="${ARTWORK_ROOT:-}"
THEME="$ROOT/usr/share/plymouth/themes/arkmos"
BACKGROUNDS="$ROOT/usr/share/backgrounds/arkmos"
SPINNER=/usr/share/plymouth/themes/spinner

FUNDO='#16161e'
FUNDO_ALTO='#1f1d33'
TEXTO='#c0caf5'
DESTAQUE='#bb9af7'

# fc-match nunca falha: sem a fonte pedida, devolve a mais parecida. Conferir o
# arquivo é o que impede um wordmark em Noto Sans de passar despercebido.
FONTE="$(fc-match -f '%{file}' 'JetBrains Mono:light')"
case "$FONTE" in
    */JetBrainsMono-Light.*) ;;
    *) echo "fonte do wordmark não encontrada (fc-match devolveu $FONTE)" >&2; exit 1 ;;
esac

# --- Logo do repositório -------------------------------------------------------

# A mesma fonte e as mesmas cores do splash, num banner para o README. Não vai
# para a imagem: 'just logo' chama este script com ARTWORK_LOGO apontando para
# .github/assets/logo.png, e o arquivo gerado é versionado. Sai daqui, e não de
# um desenho à parte, para o README não divergir do que a máquina mostra no boot.
if [ -n "${ARTWORK_LOGO:-}" ]; then
    # -alpha set na base: sem canal alfa, a máscara dos cantos arredondados não
    # tem onde agir e os cantos saem pretos — quinas escuras no tema claro do
    # GitHub. PNG32 garante a saída em RGBA de 8 bits.
    magick -size 1600x400 gradient:"$FUNDO_ALTO-$FUNDO" -alpha set \
        \( -background none -fill "$TEXTO" -font "$FONTE" \
           -pointsize 170 -kerning 36 label:arkmos -trim +repage \) \
        -gravity center -composite \
        \( -size 1600x400 xc:none -fill white \
           -draw "roundrectangle 0,0,1599,399,40,40" \) \
        -compose DstIn -composite \
        -depth 8 -strip "PNG32:$ARTWORK_LOGO"
    exit 0
fi

install -d "$THEME" "$BACKGROUNDS"

# --- Plymouth ----------------------------------------------------------------

# -strip remove os chunks de data que o ImageMagick grava: sem isso, cada build
# gera um arquivo diferente com o mesmo conteúdo.
magick -background none -fill "$TEXTO" -font "$FONTE" \
    -pointsize 64 -kerning 14 label:arkmos \
    -trim +repage -strip "$THEME/watermark.png"

# A animação e os elementos do diálogo de senha vêm do tema spinner do próprio
# Plymouth. As formas são dele; a cor passa a ser a do Arkmos.
for f in "$SPINNER"/animation-*.png "$SPINNER"/throbber-*.png; do
    # -quiet: os PNGs do spinner trazem o chunk eXIf duplicado, e o aviso
    # sairia uma vez por quadro no log do build.
    magick -quiet "$f" -fill "$DESTAQUE" -colorize 100 -strip "$THEME/${f##*/}"
done
for f in bullet capslock entry keyboard keymap-render lock; do
    install -m 0644 "$SPINNER/$f.png" "$THEME/$f.png"
done

# --- Wallpaper -----------------------------------------------------------------

# Degradê vertical com dois brilhos difusos, lavanda embaixo à esquerda e azul
# em cima à direita. O ruído fino existe contra o banding que um degradê tão
# escuro mostra em painel de 8 bits; a semente fixa mantém o build repetível.
#
# extent=Ellipse faz o brilho chegar a transparente dentro da própria camada.
# No padrão (Diagonal) o raio vai até o canto, a borda da camada ainda tem cor,
# e cada brilho aparece como um retângulo com aresta nítida.
magick -size 3840x2160 gradient:"$FUNDO_ALTO-$FUNDO" \
    -define gradient:extent=Ellipse \
    \( -size 3600x2600 radial-gradient:'rgba(187,154,247,0.26)-rgba(187,154,247,0)' \) \
        -geometry -1100+900 -composite \
    \( -size 3000x2200 radial-gradient:'rgba(122,162,247,0.14)-rgba(122,162,247,0)' \) \
        -geometry +1900-900 -composite \
    -seed 240 -attenuate 0.12 +noise Gaussian \
    -strip -quality 92 -define webp:method=6 "$BACKGROUNDS/arkmos.webp"

# Só para conferência fora da imagem: o splash montado como o two-step o
# posiciona, em 1920x1080.
if [ -n "$ROOT" ]; then
    magick -size 1920x1080 "xc:$FUNDO" \
        "$THEME/watermark.png" -gravity north -geometry +0+$((1080 * 42 / 100 - 20)) -composite \
        "$THEME/throbber-0004.png" -gravity north -geometry +0+$((1080 * 60 / 100)) -composite \
        "$ROOT/preview-plymouth.png"
fi
