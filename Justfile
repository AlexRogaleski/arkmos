# Arkmos — tarefas de build e teste.
#   just            lista as tarefas
#   just build      constrói a imagem local
#   just check      roda as verificações sobre a imagem construída
#   just vm         gera um qcow2 para testar em QEMU
#   just run-vm     sobe o qcow2 no QEMU com aceleração 3D
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

base := if variant == "nvidia" {
    "ghcr.io/ublue-os/base-nvidia:44"
} else {
    "ghcr.io/ublue-os/base-main:44"
}

suffix := if variant == "nvidia" { "-nvidia" } else { "" }

image := "localhost/arkmos" + suffix
outdir := "output" + suffix
tag := "dev"
builder := "quay.io/centos-bootc/bootc-image-builder:latest"

default:
    @just --list

[doc("Constrói a imagem local")]
build:
    podman build \
        --build-arg BASE_IMAGE="{{base}}" \
        --build-arg ARKMOS_VARIANT="{{ if variant == "" { "base" } else { variant } }}" \
        --build-arg ARKMOS_VERSION="dev" \
        --build-arg ARKMOS_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
        -t {{image}}:{{tag}} .

# Exatamente as mesmas verificações que o CI roda — os dois chamam este
# script, em vez de manter duas listas que divergem com o tempo.
[doc("Roda as verificações sobre a imagem construída")]
check:
    ./tests/check-image.sh {{image}}:{{tag}}

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
    mkdir -p {{outdir}}
    podman image scp {{image}}:{{tag}} root@localhost::
    sudo podman run --rm -it --privileged --pull=newer \
        --security-opt label=type:unconfined_t \
        -v ./config.toml:/config.toml:ro \
        -v ./{{outdir}}:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        {{builder}} \
        build --type qcow2 \
        --chown "$(id -u):$(id -g)" \
        {{image}}:{{tag}}
    # As variáveis EFI guardam a entrada de boot que o bootc gravou no disco
    # ANTERIOR. Reaproveitá-las com um disco novo faz o firmware tentar uma
    # entrada que não existe mais, e o sintoma é a VM não dar boot — indistinguível
    # de imagem quebrada. Descartadas aqui, o 'run-vm' recria limpas.
    rm -f {{outdir}}/OVMF_VARS.fd

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
# UEFI via pflash, não '-bios': o firmware precisa de uma cópia GRAVÁVEL das
# variáveis EFI para guardar a entrada de boot que o bootc instala. Com
# '-bios' as variáveis são descartadas e o disco pode não dar boot.
[doc("Sobe o qcow2 no QEMU com aceleração 3D")]
run-vm:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f {{outdir}}/qcow2/disk.qcow2 || { echo "Rode 'just{{ if variant == "" { "" } else { " variant=" + variant } }} vm' antes."; exit 1; }
    if [ ! -f {{outdir}}/OVMF_VARS.fd ]; then
        cp /usr/share/edk2/ovmf/OVMF_VARS.fd {{outdir}}/OVMF_VARS.fd
        chmod u+w {{outdir}}/OVMF_VARS.fd
    fi
    qemu-system-x86_64 \
        -machine q35,accel=kvm -cpu host \
        -m 4096 -smp 4 \
        -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
        -drive if=pflash,format=raw,unit=1,file={{outdir}}/OVMF_VARS.fd \
        -drive file={{outdir}}/qcow2/disk.qcow2,if=virtio,format=qcow2 \
        -device virtio-vga-gl,xres=1920,yres=1080 \
        -display gtk,gl=on,grab-on-hover=on \
        -device virtio-net,netdev=n0 -netdev user,id=n0 \
        -usb -device usb-tablet

[doc("Remove os diretórios de saída das duas variantes")]
clean:
    rm -rf output output-nvidia
