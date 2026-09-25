# Arkmos — tarefas de build e teste. 'just' lista todas.
#
# 'variant' vale para qualquer tarefa, com diretório de saída próprio:
#   just build                  →  localhost/arkmos:dev
#   just variant=nvidia build   →  localhost/arkmos-nvidia:dev

variant := ""

base := if variant == "nvidia" { "ghcr.io/ublue-os/base-nvidia:44" } else { "ghcr.io/ublue-os/base-main:44" }

suffix := if variant == "nvidia" { "-nvidia" } else { "" }

image := "localhost/arkmos" + suffix
outdir := "output" + suffix
tag := "dev"
builder := "quay.io/centos-bootc/bootc-image-builder:latest"

# Origem da mídia de instalação ('iso'); build e verificações usam a local.
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

# As mesmas verificações do CI: os dois chamam este script.
[doc("Roda as verificações sobre a imagem construída")]
check:
    ./tests/check-image.sh {{ image }}:{{ tag }}

# Antes de um commit que mexa no Containerfile ou em files/.
[doc("Constrói e verifica as duas variantes")]
check-all:
    just build
    just check
    just variant=nvidia build
    just variant=nvidia check

# O builder roda como root e só enxerga o storage dele: o 'image scp' leva a
# imagem para lá. --network=host porque, com o Docker ligado, o DNS não sai
# pela bridge do podman rootful (PROJECT.md §30).
[doc("Gera um qcow2 para testar em QEMU")]
vm: build
    mkdir -p {{ outdir }}
    podman image scp {{ image }}:{{ tag }} root@localhost::
    sudo podman run --rm -it --privileged --pull=newer --network=host \
        --security-opt label=type:unconfined_t \
        -v ./config.toml:/config.toml:ro \
        -v ./{{ outdir }}:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        {{ builder }} \
        build --type qcow2 \
        --chown "$(id -u):$(id -g)" \
        {{ image }}:{{ tag }}
    # Variáveis EFI do disco anterior não dão boot no novo (§30).
    rm -f {{ outdir }}/OVMF_VARS.fd

# Mídia de instalação para máquina de verdade (PROJECT.md §31). A origem é a
# imagem PUBLICADA: a referência usada aqui é a que a deployment segue, e a
# local não existe fora desta máquina. Sem o config.toml, que é da mídia de
# teste. Precisa de uns 20 GB livres no host.
[doc("Gera a ISO instalável a partir da imagem publicada")]
iso origem=publicado:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v 7z >/dev/null || { echo "precisa do 7z (p7zip) para conferir a ISO no fim"; exit 1; }
    mkdir -p {{ outdir }}

    # Só a referência da imagem muda, para cada variante apontar para a sua.
    config={{ outdir }}/iso-config.gerado.toml
    sed 's|@IMAGEM@|{{ origem }}|g' iso-config.toml > "$config"

    # Pull explícito, para o terminal mostrar o que é baixado e de onde.
    sudo podman pull {{ origem }}
    sudo podman run --rm -it --privileged --pull=newer --network=host \
        --security-opt label=type:unconfined_t \
        -v "./$config":/config.toml:ro \
        -v ./{{ outdir }}:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        {{ builder }} \
        build --type anaconda-iso \
        --chown "$(id -u):$(id -g)" \
        {{ origem }}

    # Confere o kickstart que a mídia carrega: é a única parte da instalação
    # fora do 'just check', e um erro aqui só apareceria com o disco apagado.
    iso={{ outdir }}/bootiso/install.iso
    ks="$(mktemp -d)"
    trap 'rm -rf "$ks"' EXIT
    7z e -o"$ks" "$iso" 'osbuild*.ks' >/dev/null

    # Montado na ordem de execução: o %post do builder (switch sem assinatura)
    # roda antes, e o último switch, o que vale, tem de ser o nosso (§31).
    [[ "$(head -n1 "$ks/osbuild.ks")" == "%include /run/install/repo/osbuild-base.ks" ]] ||
        { echo "ERRO: o osbuild.ks não começa pelo %include do builder; reveja a ordem dos %post." >&2; exit 1; }
    conteudo="$(cat "$ks/osbuild-base.ks"; tail -n +2 "$ks/osbuild.ks")"

    falta() { echo "ERRO: a ISO não carrega $1" >&2; exit 1; }
    grep "bootc switch" <<<"$conteudo" | tail -n1 | grep -q -- "--enforce-container-sigpolicy" ||
        falta "a exigência de assinatura no último 'bootc switch'"
    grep -q -- "--type=btrfs" <<<"$conteudo" || falta "o autopart em Btrfs"
    grep -q "^cp -a /usr/etc/vconsole.conf /etc/vconsole.conf" <<<"$conteudo" || falta "a restauração do /etc que o Anaconda reescreve"
    grep -q "btrfs\[\[:space:\]\]|d' /etc/fstab" <<<"$conteudo" || falta "a remoção da linha de / do fstab"
    grep -q "rootflags=.*compress=zstd:1" <<<"$conteudo" || falta "a compressão no rootflags da entrada de boot"
    grep -q "ostreecontainer" <<<"$conteudo" || falta "a linha ostreecontainer do builder"
    grep -q "{{ origem }}" <<<"$conteudo" || falta "a referência {{ origem }}"
    if [[ "$(grep -c "^autopart" <<<"$conteudo")" != 1 ]]; then
        echo "ERRO: a ISO tem $(grep -c "^autopart" <<<"$conteudo") linhas de autopart." >&2
        echo "      O builder mudou a composição do kickstart; reveja iso-config.toml." >&2
        exit 1
    fi
    echo "kickstart conferido: Btrfs comprimido, assinatura exigida, {{ origem }}"

    echo
    ls -lh "$iso"
    echo
    echo "Para gravar: confira o device com 'lsblk' e use"
    echo "  sudo dd if=$iso of=/dev/sdX bs=4M status=progress oflag=direct"

# virtio-vga-gl para o niri renderizar, 1920x1080 para o assistente caber,
# grab-on-hover para os atalhos Super chegarem na VM e pflash para as variáveis
# EFI serem graváveis (PROJECT.md §30). ssh na porta 2222 do host:
#
#   ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
#       usuario@127.0.0.1 'comando'
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

# Ensaio da instalação em hardware, num disco vazio (PROJECT.md §30). O disco
# vem antes da ISO na ordem de boot: vazio, o firmware passa para a ISO, e
# depois de instalado é ele que sobe. 8 GB porque o instalador roda da memória.
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
        -drive id=disco,file="$disco",if=none,format=qcow2 \
        -device virtio-blk-pci,drive=disco,bootindex=0 \
        -drive id=iso,file="$iso",if=none,media=cdrom,readonly=on \
        -device virtio-blk-pci,drive=iso,bootindex=1 \
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

# Mesmo script do splash de boot (§26.1). Precisa da imagem construída.
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

# Lint e formatação nas convenções do Universal Blue (PROJECT.md §29). Binário
# local quando existe, senão container com versão fixada; o CI força o
# container com ARKMOS_LINT_CONTAINER=1, para rodar a mesma versão da máquina.
# 'label=disable', e não ':Z': o relabel falha em arquivo de outro usuário,
# como a ISO gerada.
shellcheck_image := "docker.io/koalaman/shellcheck:v0.11.0"
shfmt_image := "docker.io/mvdan/shfmt:v3.12.0"
actionlint_image := "docker.io/rhysd/actionlint:1.7.7"

# Escopo pelo git e pelo shebang (há scripts sem '.sh'); .zsh fica fora,
# porque o shellcheck não analisa zsh.
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

# Reescreve a imagem em até 127 camadas por conteúdo, para o 'bootc upgrade'
# baixar só o que mudou (PROJECT.md §28.5). Usa o rpm-ostree da própria imagem.
[doc("Reorganiza as camadas da imagem para o upgrade baixar menos")]
ostree-rechunk alvo=(image + ":" + tag) anterior="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Nome qualificado: curto, o containers-storage o lê como docker.io/library
    # e o resultado vai para outra imagem (§28.5).
    alvo="{{ alvo }}"
    case "${alvo%%:*}" in
        */*) ;;
        *) alvo="localhost/${alvo}" ;;
    esac

    graphroot="$(podman info --format '{{ '{{.Store.GraphRoot}}' }}')"

    # Driver lido do podman: com outro, a imagem vai para onde ele não procura.
    driver="$(podman info --format '{{ '{{.Store.GraphDriverName}}' }}')"

    # O build-chunked-oci não herda os labels; são repassados um a um.
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

    # O rpm-ostree sai com zero mesmo gravando no lugar errado. Reorganizada, a
    # imagem tem no máximo 128 camadas (127 de conteúdo mais a final).
    if ((depois > 128)); then
        echo "ERRO: a tag ${alvo} não recebeu a imagem reorganizada." >&2
        echo "      ${antes} camadas antes, ${depois} depois." >&2
        exit 1
    fi
