# ---------------------------------------------------------------------------
# Base
#
# Duas variantes do mesmo sistema, com a única diferença sendo a imagem base:
#
#   arkmos          ghcr.io/ublue-os/base-main:44     (padrão)
#   arkmos-nvidia   ghcr.io/ublue-os/base-nvidia:44   driver NVIDIA assinado
#
# A base-nvidia é a base-main mais a pilha NVIDIA — mesma origem, mesmo
# kernel, ~0,9 GB comprimido a mais. Construir a pilha assinada do zero é o
# trecho mais caro do projeto, e é por isso que ela vem pronta da base.
#
# Trocar de variante na máquina instalada é 'bootc switch' e um reboot, não
# uma reinstalação — o que importa numa máquina cuja dGPU é ligada e desligada
# pela BIOS: sem a variante NVIDIA, ligá-la na BIOS não traz driver nenhum.
#
# 'ARG' antes do 'FROM' é o único lugar de onde a base pode ser parametrizada,
# e ele não fica visível para as camadas seguintes — é por isso que a variante
# viaja separada, no ARKMOS_VARIANT declarado depois do FROM, em vez de ser
# derivada daqui.
# ---------------------------------------------------------------------------
ARG BASE_IMAGE="ghcr.io/ublue-os/base-main:44"
FROM ${BASE_IMAGE}

# Versão da imagem. O CI injeta o esquema por data (44.AAAAMMDD.N);
# builds locais ficam como "dev".
ARG ARKMOS_VERSION="dev"
ARG ARKMOS_COMMIT="unknown"
ARG ARKMOS_VARIANT="base"

# Onde as imagens são publicadas. Usado pela política de verificação de
# assinatura, mais abaixo. Em minúsculas: o GHCR exige.
ARG ARKMOS_REGISTRY="ghcr.io/alexrogaleski"

# ---------------------------------------------------------------------------
# Repositórios de terceiros
#
# Copiados antes dos pacotes porque o dnf precisa deles. Vêm com enabled=0 e
# só são habilitados pontualmente no install correspondente, para que o
# sistema em execução nunca dependa deles.
# ---------------------------------------------------------------------------
COPY files/etc/yum.repos.d/ /etc/yum.repos.d/

# ---------------------------------------------------------------------------
# Pacotes
#
# A base já entrega podman, distrobox, NetworkManager, pipewire, wireplumber,
# bluez, just, wl-clipboard, curl, vim-enhanced e os portais GTK.
#
# Os portais seguem listados de propósito: o Niri depende deles e o ublue vem
# podando imagens intermediárias — se a base parar de trazê-los, é melhor o
# build continuar correto do que a sessão quebrar de forma confusa.
# ---------------------------------------------------------------------------
RUN dnf -y --setopt=install_weak_deps=False install \
        git \
        wget \
        zsh \
        zsh-autosuggestions \
        zsh-syntax-highlighting \
        python3-pip \
        python3-devel \
        glibc-langpack-pt \
        openssh-clients \
        tuned \
        tuned-ppd \
        niri \
        xwayland-satellite \
        foot \
        xdg-desktop-portal \
        xdg-desktop-portal-gtk \
        xdg-desktop-portal-gnome \
        gnome-keyring \
        mate-polkit \
        mako \
        fuzzel \
        brightnessctl \
        playerctl \
        cliphist \
        jetbrains-mono-fonts \
        google-noto-emoji-fonts \
        papirus-icon-theme \
        adw-gtk3-theme \
        neovim \
        eza \
        bat \
        fd-find \
        fzf \
        ripgrep \
        zoxide \
    && dnf clean all

# Ambiente de terminal.
#
# A configuração do Zsh é do Arkmos e vive em files/usr/share/arkmos/zsh,
# versionada aqui: nada é clonado em tempo de build. Os plugins vêm de RPM
# (acima), então o dnf cuida de atualização e de licença, e o shell não
# depende de rede na primeira abertura.
#
# Aqui só entra o que o Fedora 44 não empacota — starship, lazygit,
# lazydocker e a Nerd Font patched — com versão e checksum fixados.
#
# Os scripts de build não ficam na imagem: são copiados, executados e
# removidos na mesma camada.
COPY build_files/ /tmp/build_files/
RUN /tmp/build_files/install-upstream-bins.sh \
    && /tmp/build_files/install-nerd-font.sh \
    && rm -rf /tmp/build_files

# Noctalia v5 — shell do desktop.
#
# A v5 é reescrita nativa em C++/Wayland: sem Qt, sem Quickshell, sem COPR,
# tudo em /usr. Não usar a v4 (pacote 'noctalia-shell', baseada em
# Quickshell), que está sem manutenção upstream.
#
# Verificado: o pacote não entrega agente polkit próprio, então o
# mate-polkit instalado acima continua necessário.
RUN dnf -y --setopt=install_weak_deps=False install \
        noctalia \
    && dnf clean all

# VS Code na imagem, não em Flatpak.
#
# No Flatpak o terminal integrado roda dentro do sandbox e não enxerga o
# docker do host — o que quebra o Laravel Sail, que é dirigido inteiramente
# por 'docker compose' a partir desse terminal. A extensão Dev Containers
# também não funciona sob Flatpak.
RUN dnf -y --setopt=install_weak_deps=False --enablerepo=code install \
        code \
    && dnf clean all

# Login: greetd + tuigreet, só repositórios Fedora.
#
# greetd-selinux traz a política; sem ela o greetd esbarra no SELinux em modo
# enforcing. A conta do greeter nasce sozinha pelo sysusers.d que o próprio
# pacote entrega — encaixe exato no modelo bootc.
#
# Atenção ao nome dessa conta: no Fedora ela é 'greetd', não 'greeter' como na
# maioria dos tutoriais. Ver o comentário em files/etc/greetd/config.toml.
RUN dnf -y --setopt=install_weak_deps=False install \
        greetd \
        greetd-selinux \
        tuigreet \
    && dnf clean all

# Docker CE de verdade — não podman-docker.
#
# podman-docker é um shim que faz 'docker' invocar o podman; é exatamente a
# substituição que o PROJECT.md §15 proíbe, e a origem clássica de atrito com
# Laravel Sail. Também conflitaria com docker-ce-cli, já que ambos fornecem
# /usr/bin/docker.
#
# O grupo docker é declarado em /usr/lib/sysusers.d/arkmos-docker.conf, com
# GID dinâmico — ver o comentário lá sobre por que não vale fixar o número.
RUN dnf -y --setopt=install_weak_deps=False --enablerepo=docker-ce-stable install \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
    && dnf clean all

# ---------------------------------------------------------------------------
# Configuração do Arkmos
#
# Copiada DEPOIS dos pacotes, de propósito: se vier antes, o RPM encontra o
# arquivo ocupado e grava o dele como .rpmnew, deixando qual das duas versões
# vale dependente da ordem de instalação.
#
# Nada vai para /usr/local nem /opt: ambos são symlink para /var neste tipo de
# imagem, e o bootc só popula /var na primeira instalação — conteúdo colocado
# lá nunca mais seria atualizado por 'bootc upgrade'.
# ---------------------------------------------------------------------------
COPY files/ /

# Localização declarada na imagem, não no primeiro boot.
#
# locale.conf(5), vconsole.conf(5) e localtime(5) só leem de /etc, então estes
# são exceção legítima à preferência por /usr. /etc/localtime tem que ser
# symlink: o nome da timezone é extraído do alvo do link.
#
# Não chamar localectl/timedatectl na máquina depois disso — gravar esses
# arquivos em runtime os marca como modificados localmente e os congela contra
# futuras atualizações da imagem.
RUN ln -sf ../usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# O banco de sistema do dconf é um binário compilado a partir dos arquivos em
# /etc/dconf/db/local.d. Sem este passo, os arquivos ficam na imagem e não têm
# efeito nenhum — o tema continuaria claro e nada indicaria o motivo.
RUN dconf update

# Verificação de assinatura da própria imagem.
#
# Só entra em vigor quando a chave pública existir em
# files/etc/pki/containers/arkmos.pub — ver README. Sem ela, o build segue e a
# imagem continua funcionando, apenas sem verificar a própria procedência; com
# ela, 'bootc upgrade' passa a recusar uma imagem que não venha assinada pela
# chave correspondente.
#
# A entrada é INSERIDA na política que a base já traz, em vez de substituí-la
# por uma nossa: o policy.json do ublue-os-signing já recusa tudo por padrão e
# confia nos registries do Fedora, Red Hat e Universal Blue. Reescrever o
# arquivo significaria manter essa lista à mão e sair de sincronia com a base.
#
# 'matchRepository' e não 'matchExact': as tags 44 e latest se movem entre
# digests, e matchExact exigiria que a assinatura fosse feita para o nome
# completo com a tag.
RUN if [ -f /etc/pki/containers/arkmos.pub ]; then \
        python3 -c 'import json, sys; \
p = "/etc/containers/policy.json"; \
d = json.load(open(p)); \
d["transports"]["docker"][sys.argv[1]] = [{"type": "sigstoreSigned", "keyPath": "/etc/pki/containers/arkmos.pub", "signedIdentity": {"type": "matchRepository"}}]; \
json.dump(d, open(p, "w"), indent=4)' "$ARKMOS_REGISTRY" \
        && echo "verificação de assinatura ativada para $ARKMOS_REGISTRY"; \
    else \
        echo "sem chave pública: a imagem não verificará a própria assinatura"; \
        rm -f /etc/containers/registries.d/arkmos.yaml; \
    fi

RUN chmod 0755 /usr/libexec/arkmos-firstboot /usr/libexec/arkmos-greeter \
    && systemctl enable arkmos-firstboot.service \
    && systemctl enable docker.service \
    && systemctl enable greetd.service

# O que só faz sentido com a pilha NVIDIA sai da variante que não a tem.
#
# files/ é comum às duas variantes de propósito — uma árvore só, sem cópia
# condicional para sair de sincronia. A decisão de manter ou remover é tomada
# aqui, a partir do que a base realmente entregou, e não de um build-arg: se a
# base-main passar a trazer o driver algum dia, isto continua correto.
RUN if [ ! -e /usr/lib/systemd/system/nvidia-cdi-refresh.service ]; then \
        echo "variante sem NVIDIA: removendo configuração específica do driver"; \
        rm -rf /usr/lib/systemd/system/nvidia-cdi-refresh.service.d \
               /etc/nvidia; \
    fi

# /var só é populado na primeira instalação, então cache e log deixados aqui
# pelo build ficariam congelados na imagem para sempre. /run e /tmp são
# efêmeros e não devem carregar conteúdo vindo do build.
#
# Caminhos alvejados um a um de propósito: o podman mantém /run/secrets e
# /run/systemd montados durante o build, então um 'rm -rf /run/*' falha.
RUN rm -rf /var/cache/libdnf5 /var/cache/dnf /var/lib/dnf \
           /var/lib/tuned /var/log/tuned \
           /run/dnf /run/tuned /run/selinux-policy /tmp/* \
    && find /var/log -type f -delete \
    && rm -f /var/cache/ldconfig/aux-cache

LABEL org.opencontainers.image.title="Arkmos"
LABEL org.opencontainers.image.description="Estação de trabalho pessoal baseada em Fedora bootc"
LABEL org.opencontainers.image.source="https://github.com/AlexRogaleski/arkmos"
LABEL org.opencontainers.image.version="${ARKMOS_VERSION}"
LABEL org.opencontainers.image.revision="${ARKMOS_COMMIT}"
LABEL org.arkmos.variant="${ARKMOS_VARIANT}"

# Pega erros de /var, /opt e layout de kernel em tempo de build.
RUN ["bootc", "container", "lint"]
