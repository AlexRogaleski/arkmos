#!/usr/bin/env bash
#
# Arkmos — tira do menu do ujust as receitas que não se aplicam a esta imagem.
#
# O ublue-os-just traz o menu do Universal Blue inteiro, e parte dele aponta
# para fora do Arkmos ou para hardware que ele não tem:
#
#   toggle-nvk             faz rebase para '<imagem>-nvidia-open', que no
#                          Arkmos não existe: as variantes são 'arkmos' e
#                          'arkmos-nvidia'. Quem troca de variante aqui é o
#                          'ujust arkmos-variant'.
#   install-resolve        DaVinci Resolve num Distrobox dedicado
#   configure-broadcom-wl  Wi-Fi Broadcom
#   setup-distrobox-app    containers de aplicativo do Bluefin (brew e afins)
#
# O que fica: bios, changelogs, check-local-overrides, clean-system,
# device-info, distrobox-*, enroll-secure-boot-key, logs-*, *-luks-tpm-unlock,
# toggle-updates, update, update-firmware.
#
# Recortar em vez de apagar o arquivo inteiro: cada .just do pacote mistura
# receitas úteis com as que saem, e o justfile principal importa todos eles com
# 'import' sem interrogação — arquivo ausente quebraria o menu.
#
# Se o pacote renomear ou remover uma dessas receitas, este script falha de
# propósito: é o sinal de que a lista aqui precisa ser revista.

set -euo pipefail

DIR=/usr/share/ublue-os/just
REMOVER=(toggle-nvk install-resolve configure-broadcom-wl setup-distrobox-app)

for receita in "${REMOVER[@]}"; do
    grep -rqE "^${receita}( |:)" "$DIR" || {
        echo "ERRO: a receita '${receita}' não está mais no ublue-os-just." >&2
        echo "      Revise a lista em build_files/trim-ujust.sh." >&2
        exit 1
    }
done

python3 - "$DIR" "${REMOVER[@]}" <<'PY'
import pathlib
import sys

diretorio = pathlib.Path(sys.argv[1])
remover = set(sys.argv[2:])

for arquivo in sorted(diretorio.glob("*.just")):
    linhas = arquivo.read_text().split("\n")
    saida = []
    i = 0
    mudou = False

    while i < len(linhas):
        linha = linhas[i]

        # 'alias x := receita-removida' sai junto: alias órfão é erro de sintaxe.
        if linha.startswith("alias ") and linha.split(":=")[-1].strip() in remover:
            i += 1
            mudou = True
            continue

        nome = linha.split(":")[0].split(" ")[0]
        if linha[:1].strip() and nome in remover:
            # O comentário imediatamente acima é a descrição que o menu mostra.
            while saida and saida[-1].startswith("#"):
                saida.pop()
            i += 1
            # O corpo é tudo o que está indentado, mais as linhas vazias dentro.
            while i < len(linhas) and (linhas[i][:1] in (" ", "\t") or linhas[i] == ""):
                i += 1
            mudou = True
            continue

        saida.append(linha)
        i += 1

    if mudou:
        arquivo.write_text("\n".join(saida))
        print(f"    {arquivo.name} recortado")
PY

# O menu tem de continuar montando: o 'just' recusa um justfile com sintaxe
# quebrada, e é aqui que um recorte malfeito aparece.
menu="$(JUST_JUSTFILE=/usr/share/ublue-os/justfile just --list)"

for receita in "${REMOVER[@]}"; do
    if grep -qE "^ *${receita}( |$)" <<<"$menu"; then
        echo "ERRO: '${receita}' continua no menu." >&2
        exit 1
    fi
done

for receita in update bios check-local-overrides distrobox-new toggle-updates; do
    grep -qE "^ *${receita}( |$)" <<<"$menu" || {
        echo "ERRO: o recorte levou '${receita}' junto." >&2
        exit 1
    }
done

echo "ujust: menu com $(grep -cE '^ +[a-z]' <<<"$menu") receitas"
