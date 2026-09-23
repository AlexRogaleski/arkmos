# Arkmos — tarefas de build e teste.
#   just            lista as tarefas
#   just build      constrói a imagem local
#   just check      roda as verificações sobre a imagem construída
#   just vm         gera um qcow2 para testar em QEMU
#   just run-vm     sobe o qcow2 no QEMU com aceleração 3D
#   just iso        gera a ISO instalável, para pendrive
#   just run-iso    ensaia a instalação da ISO numa VM
#
# Duas variantes do mesmo sistema. A padrão não tem a pilha NVIDIA e é a que
# se testa em VM; a outra troca só a imagem base:
#
#   just build                  →  localhost/arkmos:dev
#   just variant=nvidia build   →  localhost/arkmos-nvidia:dev
#
# 'variant' vale para qualquer tarefa, e cada variante tem seu próprio
# diretório de saída para que os dois qcow2 possam coexistir.

variant := ""

base := if variant == "nvidia" { "ghcr.io/ublue-os/base-nvidia:44" } else { "ghcr.io/ublue-os/base-main:44" }

suffix := if variant == "nvidia" { "-nvidia" } else { "" }

image := "localhost/arkmos" + suffix
outdir := "output" + suffix
tag := "dev"
builder := "quay.io/centos-bootc/bootc-image-builder:latest"

# A imagem publicada, que é a origem da mídia de instalação — ver a receita
# 'iso'. Não entra no build nem nas verificações, que trabalham na local.
publicado := "ghcr.io/alexrogaleski/arkmos" + suffix + ":44"

default:
    @just --list

[doc("Constrói a imagem local")]
build:
    podman build \
        --build-arg BASE_IMAGE="{{ base }}" \
        --build-arg ARKMOS_VARIANT="{{ if variant == "" { "base" } else { variant } }}" \
        --build-arg ARKMOS_VERSION="dev" \
        --build-arg ARKMOS_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
        -t {{ image }}:{{ tag }} .

# Exatamente as mesmas verificações que o CI roda — os dois chamam este
# script, em vez de manter duas listas que divergem com o tempo.
[doc("Roda as verificações sobre a imagem construída")]
check:
    ./tests/check-image.sh {{ image }}:{{ tag }}

# Constrói e verifica as duas variantes. É o que vale rodar antes de um commit
# que mexa no Containerfile ou em files/: um erro que só aparece numa das duas
# passa despercebido se você testar só a sua.
[doc("Constrói e verifica as duas variantes")]
check-all:
    just build
    just check
    just variant=nvidia build
    just variant=nvidia check

# Gera o qcow2. Substitui o antigo truncate + losetup + bootc install to-disk:
# um comando só, particionamento declarativo e rotulagem SELinux correta.
#
# Pede senha de sudo duas vezes: o bootc-image-builder roda privilegiado e só
# enxerga o storage do root, enquanto 'just build' constrói sem privilégio.
# O 'image scp' transfere a imagem entre os dois storages sem reconstruir.
#
# Sem flag --local: esta versão do builder já lê o storage montado. O
# config.toml também não tem flag — é lido de /config.toml dentro do container.
[doc("Gera um qcow2 para testar em QEMU")]
vm: build
    mkdir -p {{ outdir }}
    podman image scp {{ image }}:{{ tag }} root@localhost::
    sudo podman run --rm -it --privileged --pull=newer \
        --security-opt label=type:unconfined_t \
        -v ./config.toml:/config.toml:ro \
        -v ./{{ outdir }}:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        {{ builder }} \
        build --type qcow2 \
        --chown "$(id -u):$(id -g)" \
        {{ image }}:{{ tag }}
    # As variáveis EFI guardam a entrada de boot que o bootc gravou no disco
    # ANTERIOR. Reaproveitá-las com um disco novo faz o firmware tentar uma
    # entrada que não existe mais, e o sintoma é a VM não dar boot — indistinguível
    # de imagem quebrada. Descartadas aqui, o 'run-vm' recria limpas.
    rm -f {{ outdir }}/OVMF_VARS.fd

# Gera a ISO instalável, para gravar num pendrive e instalar em máquina de
# verdade: o Anaconda escolhe o disco, particiona e pede a conta. O qcow2 do
# 'just vm' é mídia de teste; esta é mídia de instalação.
#
# A origem é a imagem PUBLICADA, não a local. O que fica gravado na deployment
# é a referência usada aqui: instalada a partir de 'localhost/arkmos:dev', a
# máquina nasce seguindo um registry que não existe e o 'bootc upgrade' falha
# procurando em localhost/v2/ (seção 30). Por isso esta receita não depende do
# 'build' — ela não usa a imagem local em momento nenhum.
#
# Sem o config.toml: aquele arquivo descreve a mídia de TESTE (console serial do
# QEMU, sshd ligado, disco declarado em 40 GiB). Numa instalação real quem
# particiona é o Anaconda, e ligar o sshd sem ninguém pedir seria o oposto do
# que a seção 22 decidiu.
#
# Reserve espaço no host: o osbuild descomprime a imagem inteira em árvore
# intermediária antes de montar a mídia, então conte uns 20 GB livres. A ISO em
# si embute a imagem comprimida (3,46 GB na publicação de 2026-09-23) mais o
# ambiente do Anaconda — as ISOs equivalentes do Universal Blue ficam entre 6 e
# 7 GB.
[doc("Gera a ISO instalável a partir da imagem publicada")]
iso origem=publicado:
    mkdir -p {{ outdir }}
    # O builder roda como root e só enxerga o storage do root; o pull explícito
    # aqui deixa claro no terminal o que está sendo baixado, e de onde.
    sudo podman pull {{ origem }}
    sudo podman run --rm -it --privileged --pull=newer \
        --security-opt label=type:unconfined_t \
        -v ./{{ outdir }}:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        {{ builder }} \
        build --type anaconda-iso \
        --chown "$(id -u):$(id -g)" \
        {{ origem }}
    @echo
    @ls -lh {{ outdir }}/bootiso/*.iso
    @echo
    @echo "Para gravar: confira o device com 'lsblk' e use"
    @echo "  sudo dd if={{ outdir }}/bootiso/install.iso of=/dev/sdX bs=4M status=progress oflag=direct"

# Sobe o qcow2 no QEMU.
#
# virtio-vga-gl + gl=on são necessários para o Niri renderizar.
#
# xres/yres explícitos porque o padrão do virtio-vga-gl é 1280x800, e numa
# janela desse tamanho o assistente do primeiro boot rola para fora da tela.
#
# grab-on-hover captura o teclado quando o ponteiro está sobre a janela. Sem
# isso, atalhos com Super/Mod são interpretados pelo compositor do HOST e nunca
# chegam na VM, o que torna impossível testar os binds do Niri. Ctrl+Alt+G
# libera e recaptura o teclado a qualquer momento.
#
# A porta 2222 do host cai no ssh da VM (hostfwd). A janela do QEMU não tem
# clipboard compartilhado, então copiar log de dentro dela é sofrido; com isto,
# 'ssh -p 2222 usuario@127.0.0.1' roda o comando de fora e a saída fica no host,
# em arquivo. O sshd já vem habilitado pela base. Só escuta em 127.0.0.1.
#
# Cada qcow2 novo tem chaves de host próprias, então o known_hosts do host
# acumula conflito nessa porta e o ssh chega a bloquear até a senha. Usar:
#
#   ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
#       usuario@127.0.0.1 'comando'
#
# UEFI via pflash, não '-bios': o firmware precisa de uma cópia GRAVÁVEL das
# variáveis EFI para guardar a entrada de boot que o bootc instala. Com
# '-bios' as variáveis são descartadas e o disco pode não dar boot.
[doc("Sobe o qcow2 no QEMU com aceleração 3D")]
run-vm:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f {{ outdir }}/qcow2/disk.qcow2 || { echo "Rode 'just{{ if variant == "" { "" } else { " variant=" + variant } }} vm' antes."; exit 1; }
    if [ ! -f {{ outdir }}/OVMF_VARS.fd ]; then
        cp /usr/share/edk2/ovmf/OVMF_VARS.fd {{ outdir }}/OVMF_VARS.fd
        chmod u+w {{ outdir }}/OVMF_VARS.fd
    fi
    qemu-system-x86_64 \
        -machine q35,accel=kvm -cpu host \
        -m 4096 -smp 4 \
        -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
        -drive if=pflash,format=raw,unit=1,file={{ outdir }}/OVMF_VARS.fd \
        -drive file={{ outdir }}/qcow2/disk.qcow2,if=virtio,format=qcow2 \
        -device virtio-vga-gl,xres=1920,yres=1080 \
        -display gtk,gl=on,grab-on-hover=on \
        -device virtio-net,netdev=n0 -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 \
        -usb -device usb-tablet

# Sobe a ISO instalável numa VM, com um disco vazio para instalar em cima.
#
# É o ensaio da instalação em hardware: o Anaconda que roda aqui é o mesmo que
# vai rodar lá, com as mesmas telas de disco, cifragem e conta. O que se
# aprende aqui — se ele pede usuário, que layout de subvolumes ele cria — é o
# que decide as duas pendências da seção 12.4 e da seção 6.
#
# Diferenças em relação ao 'run-vm', que sobe um disco já instalado:
#
#   - o disco nasce vazio, criado aqui e não pelo bootc-image-builder;
#   - a ISO entra como cdrom, e o menu de boot do firmware tenta o disco vazio
#     primeiro, então 'bootindex' põe o cdrom na frente;
#   - 8 GB de RAM, e não 4: o instalador roda a partir de um squashfs em
#     memória e o Anaconda gráfico é pesado.
#
# Depois de instalar, desligue a VM e use o 'run-iso-instalado', que sobe o
# mesmo disco sem a ISO — com a ISO ainda no cdrom, o firmware volta para o
# instalador.
[doc("Sobe a ISO instalável numa VM, para ensaiar a instalação")]
run-iso tamanho="60G":
    #!/usr/bin/env bash
    set -euo pipefail
    iso={{ outdir }}/bootiso/install.iso
    test -f "$iso" || { echo "Rode 'just{{ if variant == "" { "" } else { " variant=" + variant } }} iso' antes."; exit 1; }

    disco={{ outdir }}/iso-test/disk.qcow2
    mkdir -p "$(dirname "$disco")"
    if [ ! -f "$disco" ]; then
        qemu-img create -f qcow2 "$disco" {{ tamanho }}
        echo "disco novo: $disco ({{ tamanho }}, esparso)"
    else
        echo "disco existente: $disco — apague o arquivo para instalar do zero"
    fi

    vars={{ outdir }}/iso-test/OVMF_VARS.fd
    if [ ! -f "$vars" ]; then
        cp /usr/share/edk2/ovmf/OVMF_VARS.fd "$vars"
        chmod u+w "$vars"
    fi

    qemu-system-x86_64 \
        -machine q35,accel=kvm -cpu host \
        -m 8192 -smp 4 \
        -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
        -drive if=pflash,format=raw,unit=1,file="$vars" \
        -drive file="$disco",if=virtio,format=qcow2 \
        -drive id=iso,file="$iso",if=none,media=cdrom,readonly=on \
        -device virtio-blk-pci,drive=iso,bootindex=0 \
        -device virtio-vga-gl,xres=1920,yres=1080 \
        -display gtk,gl=on,grab-on-hover=on \
        -device virtio-net,netdev=n0 -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 \
        -usb -device usb-tablet

# O mesmo disco do 'run-iso', já instalado, sem a ISO no cdrom.
[doc("Sobe o disco instalado pela ISO, sem a mídia")]
run-iso-instalado:
    #!/usr/bin/env bash
    set -euo pipefail
    disco={{ outdir }}/iso-test/disk.qcow2
    test -f "$disco" || { echo "Não há disco instalado em $disco."; exit 1; }
    qemu-system-x86_64 \
        -machine q35,accel=kvm -cpu host \
        -m 4096 -smp 4 \
        -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
        -drive if=pflash,format=raw,unit=1,file={{ outdir }}/iso-test/OVMF_VARS.fd \
        -drive file="$disco",if=virtio,format=qcow2 \
        -device virtio-vga-gl,xres=1920,yres=1080 \
        -display gtk,gl=on,grab-on-hover=on \
        -device virtio-net,netdev=n0 -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 \
        -usb -device usb-tablet

# A logo do README sai do mesmo script que desenha o splash de boot — mesma
# fonte, mesmas cores —, para o repositório não divergir do que a máquina mostra
# ao ligar. Precisa de uma imagem construída: a fonte vem de dentro dela.
[doc("Gera a logo do README a partir da arte do boot")]
logo:
    mkdir -p .github/assets
    podman run --rm --security-opt label=disable \
        -v ./build_files/render-artwork.sh:/render.sh:ro \
        -v ./.github/assets:/out \
        -e ARTWORK_LOGO=/out/logo.png \
        {{ image }}:{{ tag }} bash /render.sh

[doc("Remove os diretórios de saída das duas variantes")]
clean:
    rm -rf output output-nvidia

# Lint e formatação seguem as convenções do image-template do Universal Blue:
# 'lint' com shellcheck, 'format' com shfmt, e a sintaxe do Justfile conferida
# pelo próprio just. O actionlint no workflow vem do finpilot.
#
# Uma diferença de nome, de propósito: no template deles 'check' é a sintaxe do
# Justfile, e aqui 'check' já significa as verificações da imagem, que é o nome
# que o CI e o PROJECT.md usam desde o começo. A sintaxe do Justfile entrou no
# 'lint'.
#
# As ferramentas não estão no host de desenvolvimento (Aurora é imutável), então
# cada receita usa o binário local quando existe e cai num container com versão
# fixada quando não existe. Na imagem do Arkmos os binários existem, e é o
# caminho local que roda.
#
# ARKMOS_LINT_CONTAINER=1 ignora o binário local e força o container. É o que o
# CI usa: o runner do GitHub traz shellcheck 0.9.0, e a nossa imagem fixada é a
# 0.11.0 — versões diferentes acusam coisas diferentes, e o lint passava aqui e
# falhava lá. Com o container, o CI e a máquina rodam a mesma versão.
# O 'label=disable' em lugar do ':Z' nos mounts: o ':Z' relabela o diretório
# inteiro para o container, e falha no que pertence a outro usuário — a ISO que
# o bootc-image-builder gera fica como 'qemu', e o lint parava com
# "lsetxattr ... operation not permitted". As ferramentas só leem o repositório.
shellcheck_image := "docker.io/koalaman/shellcheck:v0.11.0"
shfmt_image := "docker.io/mvdan/shfmt:v3.12.0"
actionlint_image := "docker.io/rhysd/actionlint:1.7.7"

# O git é a fonte da verdade do escopo, como no finpilot. O critério é o
# shebang, e não a extensão: os scripts de /usr/libexec e /usr/bin não têm '.sh'.
# Os arquivos .zsh ficam fora porque o shellcheck não analisa zsh.
[doc("Lista os scripts de shell versionados")]
shell-sources:
    #!/usr/bin/env bash
    set -euo pipefail
    git ls-files -z | while IFS= read -r -d '' f; do
        [[ -f "$f" && "$f" != *.zsh ]] || continue
        head -1 "$f" | grep -qE '^#!.*(bash|/sh|env sh)' && printf '%s\n' "$f"
    done

[doc("shellcheck nos scripts, actionlint no workflow, sintaxe do Justfile")]
lint:
    #!/usr/bin/env bash
    set -euo pipefail

    mapfile -t fontes < <(just shell-sources)
    if (( ${#fontes[@]} == 0 )); then
        echo "nenhum script de shell versionado encontrado" >&2
        exit 1
    fi
    printf 'shellcheck em %d scripts:\n' "${#fontes[@]}"
    printf '  %s\n' "${fontes[@]}"
    if [[ -z "${ARKMOS_LINT_CONTAINER:-}" ]] && command -v shellcheck >/dev/null; then
        shellcheck "${fontes[@]}"
    else
        podman run --rm --security-opt label=disable \
            -v "$PWD:/mnt:ro" -w /mnt {{ shellcheck_image }} "${fontes[@]}"
    fi

    echo 'actionlint nos workflows:'
    if [[ -z "${ARKMOS_LINT_CONTAINER:-}" ]] && command -v actionlint >/dev/null; then
        actionlint
    else
        podman run --rm --security-opt label=disable \
            -v "$PWD:/repo:ro" -w /repo {{ actionlint_image }}
    fi

    echo 'sintaxe do Justfile:'
    just --unstable --fmt --check -f Justfile

[doc("Formata os scripts com shfmt e o Justfile com o just")]
format:
    #!/usr/bin/env bash
    set -euo pipefail

    mapfile -t fontes < <(just shell-sources)
    if [[ -z "${ARKMOS_LINT_CONTAINER:-}" ]] && command -v shfmt >/dev/null; then
        shfmt --write "${fontes[@]}"
    else
        podman run --rm --security-opt label=disable \
            -v "$PWD:/mnt" -w /mnt {{ shfmt_image }} --write "${fontes[@]}"
    fi
    just --unstable --fmt -f Justfile

# Rechunk: reorganiza as camadas da imagem antes de publicar.
#
# É o passo que Bluefin, Aurora e Bazzite dão, e que o image-template do
# Universal Blue traz como 'ostree-rechunk'. O 'rpm-ostree compose
# build-chunked-oci' recebe o sistema de arquivos pronto e o reescreve em até
# 127 camadas decididas por conteúdo, e não pela ordem dos comandos do
# Containerfile.
#
# O que isso muda na prática: hoje, um 'dnf install' no começo do Containerfile
# invalida todas as camadas seguintes, e cada publicação obriga quem atualiza a
# baixar gigabytes. Com as camadas por conteúdo, duas publicações seguidas
# compartilham quase tudo, e o 'bootc upgrade' baixa só o que mudou de fato.
#
# Roda com o rpm-ostree de DENTRO da própria imagem (ela é derivada do ublue, que
# o traz), então não há ferramenta extra para instalar. Precisa de --privileged e
# do storage do podman montado, porque a saída é gravada direto lá.
[doc("Reorganiza as camadas da imagem para o upgrade baixar menos")]
ostree-rechunk alvo=(image + ":" + tag) anterior="":
    #!/usr/bin/env bash
    set -euo pipefail

    # O nome da imagem é qualificado antes de qualquer outra coisa.
    #
    # 'podman build --tag arkmos:latest' cria 'localhost/arkmos:latest', e o
    # transporte containers-storage normaliza o MESMO nome curto para
    # 'docker.io/library/arkmos:latest'. Com o nome curto, o rechunk gravava
    # numa imagem nova sob o Docker Hub, a tag do build continuava apontando
    # para a imagem antiga, e o CI verificava e publicaria a imagem NÃO
    # reorganizada — dizendo no log que tinha reorganizado.
    alvo="{{ alvo }}"
    case "${alvo%%:*}" in
        */*) ;;
        *) alvo="localhost/${alvo}" ;;
    esac

    graphroot="$(podman info --format '{{ '{{.Store.GraphRoot}}' }}')"

    # O driver vem do podman em vez de fixo em 'overlay': a referência de
    # storage carrega o nome do driver, e escrever com um driver diferente do
    # que o storage usa põe a imagem onde o podman não vai procurar.
    driver="$(podman info --format '{{ '{{.Store.GraphDriverName}}' }}')"

    # Os labels são repassados um a um, lidos da imagem de origem. O
    # build-chunked-oci monta uma imagem NOVA a partir do sistema de arquivos e
    # não herda a configuração: sem isto, a variante, a versão e o commit
    # desapareceriam — o 'bootc status' mostra a versão a partir desse label, e
    # o 'just check' usa o da variante. Não há como repassar ENV e CMD, que só
    # afetam 'podman run' nesta imagem, e ficam perdidos.
    mapfile -t rotulos < <(podman inspect \
        --format '{{ '{{ range $k, $v := .Config.Labels }}{{ $k }}={{ $v }}{{ "\n" }}{{ end }}' }}' "$alvo")
    anterior="{{ anterior }}"

    argumentos=()
    for rotulo in "${rotulos[@]}"; do
        [[ -n "$rotulo" ]] && argumentos+=(--label "$rotulo")
    done

    camadas() { podman inspect --format '{{ '{{len .RootFS.Layers}}' }}' "$alvo"; }

    antes="$(camadas)"
    echo "antes:  ${antes} camadas, $((${#argumentos[@]} / 2)) labels"

    podman run --rm --pull=never --privileged \
        --mount=type=image,src="$alvo",target=/rpm-ostree \
        --mount=type=bind,src="$graphroot",target=/run/host-container-storage,rw \
        --mount=type=tmpfs,target=/run/rpm-ostree-storage \
        --entrypoint /usr/bin/rpm-ostree \
        "$alvo" \
        compose build-chunked-oci \
        --max-layers 127 \
        --format-version=2 \
        --bootc \
        --rootfs /rpm-ostree \
        "${argumentos[@]}" \
        ${anterior:+--previous-build "$anterior"} \
        --output "containers-storage:[${driver}@/run/host-container-storage+/run/rpm-ostree-storage]${alvo}"

    depois="$(camadas)"
    echo "depois: ${depois} camadas"

    # O rpm-ostree imprime "Pushed digest" e sai com zero mesmo quando a
    # imagem foi para um nome que o podman não resolve de volta. Sem esta
    # conferência o passo fica verde e o que segue para a verificação e para o
    # registry é a imagem antiga, intacta.
    #
    # O limite é 128 porque é onde a imagem reorganizada cabe: 127 camadas de
    # conteúdo mais a final. Rodar de novo sobre uma imagem já reorganizada
    # continua passando, que é o que se espera de uma receita idempotente.
    if ((depois > 128)); then
        echo "ERRO: a tag ${alvo} não recebeu a imagem reorganizada." >&2
        echo "      ${antes} camadas antes, ${depois} depois." >&2
        exit 1
    fi
