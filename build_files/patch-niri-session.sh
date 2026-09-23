#!/usr/bin/env bash
#
# Arkmos — a lista de variáveis que o systemd pede no niri-session.
#
# O 'niri-session' do pacote chama:
#
#     systemctl --user import-environment
#
# sem lista de variáveis, e o systemd responde no console: "Calling
# import-environment without a list of variable names is deprecated." A linha
# roda antes do niri tomar a tela, então o aviso sai na VT, entre a senha e o
# desktop, e não chega ao jornal.
#
# Não é só estética: a forma sem lista está deprecada e um dia deixa de
# funcionar, e aí a sessão nasceria sem o ambiente do login sem nada avisar.
#
# A lista usa '${VAR+VAR}', que expande para o NOME apenas quando a variável
# existe. Sem isso o systemctl imprime "Environment variable $X not set,
# ignoring." para cada ausente — e no login DISPLAY, WAYLAND_DISPLAY e outras
# ainda não existem, o que trocava um aviso por vários.
#
# LANG e XDG_DATA_DIRS ficam DE FORA de propósito: quem manda neles é o
# /usr/lib/environment.d do Arkmos, e importá-los do shell sobrescreveria
# aquele valor pelo que o shell tivesse na hora — foi justamente um
# XDG_DATA_DIRS sem as pastas do Flatpak que deixou o clique duplo sem abrir
# nada.
#
# Conhecido no upstream desde 2024: niri-wm/niri#254, com a correção proposta
# na #255, as duas abertas; a #4624 descreve este sintoma exato num setup
# greetd + noctalia-greeter. Quando o pacote vier corrigido, este script falha
# de propósito e o remendo sai.

set -euo pipefail

ALVO=/usr/bin/niri-session
ORIGINAL='    systemctl --user import-environment'

if ! grep -qx "$ORIGINAL" "$ALVO"; then
    echo "ERRO: $ALVO não tem mais a linha que este remendo corrige." >&2
    echo "      Se o pacote passou a listar as variáveis, remova este script" >&2
    echo "      e a etapa correspondente do Containerfile." >&2
    exit 1
fi

python3 - "$ALVO" <<'PY'
import sys

caminho = sys.argv[1]
original = "    systemctl --user import-environment\n"
novo = """    # Arkmos: a lista que o systemd pede, e só com as variáveis definidas.
    systemctl --user import-environment \\
        ${PATH+PATH} ${DBUS_SESSION_BUS_ADDRESS+DBUS_SESSION_BUS_ADDRESS} \\
        ${DISPLAY+DISPLAY} ${WAYLAND_DISPLAY+WAYLAND_DISPLAY} \\
        ${XDG_CURRENT_DESKTOP+XDG_CURRENT_DESKTOP} \\
        ${XDG_SESSION_DESKTOP+XDG_SESSION_DESKTOP} \\
        ${XDG_SESSION_TYPE+XDG_SESSION_TYPE} ${XDG_SESSION_ID+XDG_SESSION_ID} \\
        ${XDG_SESSION_CLASS+XDG_SESSION_CLASS} ${XDG_SEAT+XDG_SEAT} \\
        ${XDG_VTNR+XDG_VTNR} ${SSH_AUTH_SOCK+SSH_AUTH_SOCK}

"""

conteudo = open(caminho).read()
if conteudo.count(original) != 1:
    raise SystemExit("esperava a linha uma vez, achei %d" % conteudo.count(original))
open(caminho, "w").write(conteudo.replace(original, novo))
PY

sh -n "$ALVO"
# shellcheck disable=SC2016  # o nome da variável é literal, não expansão
grep -q '${XDG_VTNR+XDG_VTNR}' "$ALVO"
if grep -qx "$ORIGINAL" "$ALVO"; then
    echo "ERRO: a linha original continua no arquivo." >&2
    exit 1
fi

echo "niri-session: import-environment com lista de variáveis"
