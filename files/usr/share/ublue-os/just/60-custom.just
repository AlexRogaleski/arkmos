# vim: set ft=make :
#
# Arkmos — receitas próprias no menu do ujust.
#
# O justfile do ublue-os-just termina com
#
#     import? "/usr/share/ublue-os/just/60-custom.just"
#
# e é este o arquivo. A interrogação quer dizer opcional: é o gancho que eles
# deixaram para a imagem derivada acrescentar suas receitas sem tocar no
# justfile do pacote, e é por isso que o nome não é '60-arkmos.just'.
#
# Nomes em inglês, como as receitas do ublue ao lado; as descrições, que são o
# que aparece no menu, em português, como o resto do que o sistema fala.

# Mostra variante, imagem, deployment e serviços do Arkmos
arkmos-diag:
    /usr/bin/arkmos-diag

# Copia para esta conta os padrões da imagem, sem sobrescrever o que você editou
arkmos-apply-defaults:
    #!/usr/bin/bash
    set -euo pipefail
    # O /etc/skel é copiado no instante em que a conta nasce, e nem
    # 'bootc upgrade' nem 'bootc switch' tocam no home. Então uma conta criada
    # antes de um padrão novo — ou vinda de outro sistema, por rebase — não
    # recebe esse padrão sozinha.
    #
    # O -n é o ponto: nunca sobrescreve arquivo que já existe. Quem mexeu na
    # configuração do Noctalia ou no .zshrc continua com a sua versão.
    cp -rn /etc/skel/. "$HOME"/ 2>/dev/null || true
    echo "Padrões da imagem copiados para $HOME."
    echo "O que você já tinha editado ficou como estava."
    echo "Saia da sessão e entre de novo para o shell reler a configuração."

# Troca entre a variante padrão e a NVIDIA (pede reinício depois)
arkmos-variant ALVO="prompt":
    #!/usr/bin/bash
    set -euo pipefail

    ALVO="{{ ALVO }}"

    # O argumento é conferido ANTES de consultar o sistema: um erro de digitação
    # tem de sair como "use base ou nvidia", e não como a mensagem crua de
    # alguma ferramenta que nem precisava ter sido chamada.
    case "$ALVO" in
        base | nvidia | prompt | "") ;;
        *)
            echo "Alvo desconhecido: $ALVO (use 'base' ou 'nvidia')" >&2
            exit 1
            ;;
    esac

    # A imagem sai da própria deployment, e não de um nome fixo aqui: quem
    # instalou de um registry diferente continua trocando de variante dentro
    # do registry dele. O campo vem com o transporte na frente
    # ('ostree-image-signed:docker://ghcr.io/...'), que os dois sed removem.
    referencia="$(rpm-ostree status -b --json 2>/dev/null \
        | jq -r '.deployments[0]."container-image-reference" // empty')" || true

    if [[ -z "$referencia" ]]; then
        echo "Não foi possível ler a imagem desta deployment." >&2
        echo "Veja 'bootc status' — talvez o sistema não tenha vindo de uma imagem." >&2
        exit 1
    fi

    imagem="$(sed -E 's|^ostree-[a-z-]+:||; s|^docker://||' <<<"$referencia")"

    # Imagem local não tem variante irmã para trocar: a VM de teste nasce
    # seguindo 'containers-storage:localhost/arkmos:dev' até o primeiro
    # 'bootc switch' para o registry.
    case "$imagem" in
        containers-storage:* | localhost/*)
            echo "Esta máquina segue uma imagem local: ${imagem}"
            echo "Troque primeiro para a publicada, com:"
            echo "  sudo bootc switch --enforce-container-sigpolicy ghcr.io/<dono>/arkmos:44"
            exit 1
            ;;
    esac

    repositorio="${imagem%:*}"
    etiqueta="${imagem##*:}"
    padrao="${repositorio%-nvidia}"

    if [[ "$repositorio" == *-nvidia ]]; then
        atual="nvidia"
    else
        atual="padrão"
    fi

    if [[ "$ALVO" == prompt || -z "$ALVO" ]]; then
        echo "Variante atual: ${atual}  (${imagem})"
        echo
        echo "  ujust arkmos-variant base      → sem a pilha NVIDIA"
        echo "  ujust arkmos-variant nvidia    → com o driver proprietário"
        echo
        echo "A dGPU desligada na BIOS não precisa da variante NVIDIA."
        exit 0
    fi

    case "$ALVO" in
        base) destino="${padrao}:${etiqueta}" ;;
        nvidia) destino="${padrao}-nvidia:${etiqueta}" ;;
    esac

    if [[ "$destino" == "$imagem" ]]; then
        echo "Já está na variante ${ALVO}: ${imagem}"
        exit 0
    fi

    echo "${imagem}  →  ${destino}"
    echo
    # A flag grava na deployment que o pull obedece à política de assinatura;
    # sem ela, nenhum 'bootc upgrade' posterior verificaria nada.
    sudo bootc switch --enforce-container-sigpolicy "$destino"
    echo
    echo "Reinicie para entrar na variante nova. 'sudo bootc rollback' volta."
