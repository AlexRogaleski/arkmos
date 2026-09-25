# ---------------------------------------------------------------------------
# Base
#
# Duas variantes; a única diferença é a imagem base (ver PROJECT.md §5.2):
#
#   arkmos          ghcr.io/ublue-os/base-main:44     (padrão)
#   arkmos-nvidia   ghcr.io/ublue-os/base-nvidia:44   driver NVIDIA assinado
#
# ARG antes do FROM não é visível depois dele: a variante viaja separada, no
# ARKMOS_VARIANT do fim do arquivo.
# ---------------------------------------------------------------------------
ARG BASE_IMAGE="ghcr.io/ublue-os/base-main:44"

# ---------------------------------------------------------------------------
# Estágio de compilação: Noctalia Greeter (não empacotado no Fedora; §8.3)
#
# Fixado por commit, e não pela tag: tag pode ser movida.
# v1.5.0 = 5a450b891067c1f0cd7157f4f1091aa0e3014780
#
# O '-march=native' que o meson do upstream força em release é trocado por
# x86-64-v2: compilado no runner do GitHub, o binário morria de SIGILL ao
# autenticar em outro CPU, e o login piscava e voltava. Ver §8.3.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS greeter-builder

ARG NOCTALIA_GREETER_COMMIT="5a450b891067c1f0cd7157f4f1091aa0e3014780"

RUN dnf -y --setopt=install_weak_deps=False install \
        meson gcc-c++ git \
        wayland-devel wayland-protocols-devel wlroots-devel \
        libEGL-devel mesa-libGLES-devel \
        freetype-devel fontconfig-devel \
        cairo-devel pango-devel harfbuzz-devel \
        libxkbcommon-devel glib2-devel \
        tomlplusplus-devel json-devel stb_image_resize2-devel \
        libwebp-devel librsvg2-devel libxml2-devel

# fetch de um commit específico, sem clonar o histórico inteiro.
RUN git init --quiet /tmp/greeter \
    && git -C /tmp/greeter remote add origin \
        https://github.com/noctalia-dev/noctalia-greeter.git \
    && git -C /tmp/greeter fetch --quiet --depth=1 origin "${NOCTALIA_GREETER_COMMIT}" \
    && git -C /tmp/greeter checkout --quiet FETCH_HEAD \
    && cd /tmp/greeter \
    && sed -i "s/'-march=native', '-mtune=native',/'-march=x86-64-v2', '-mtune=generic',/" meson.build \
    && ! grep -q "march=native" meson.build \
    && meson setup build --prefix=/usr --buildtype=release \
    && grep -q -- "-march=x86-64-v2" build/compile_commands.json \
    && ! grep -q -- "-march=native" build/compile_commands.json \
    && meson compile -C build \
    && DESTDIR=/tmp/greeter-root meson install -C build --no-rebuild \
    && test -x /tmp/greeter-root/usr/bin/noctalia-greeter-session

FROM ${BASE_IMAGE}

# Onde as imagens são publicadas, para a política de assinatura. Em
# minúsculas: o GHCR exige.
ARG ARKMOS_REGISTRY="ghcr.io/alexrogaleski"

# ---------------------------------------------------------------------------
# Repositórios de terceiros: antes dos pacotes, com enabled=0, habilitados só
# no install correspondente.
# ---------------------------------------------------------------------------
COPY files/etc/yum.repos.d/ /etc/yum.repos.d/

# ---------------------------------------------------------------------------
# Pacotes (o porquê de cada um: §10, §14, §25, §26.1)
#
# A base já entrega podman, distrobox, NetworkManager, pipewire, bluez, just,
# wl-clipboard e os portais GTK. Os portais seguem listados de propósito:
# o niri depende deles, e a base vem sendo podada.
#
# 'gnome-keyring-pam': o /etc/pam.d/greetd o referencia com '-', que ignora em
# silêncio o módulo ausente — sem o pacote, o chaveiro não destrava no login.
#
# O papel de parede da versão tem o número do Fedora no nome do pacote, que
# por isso sai do 'rpm -E %fedora'.
# ---------------------------------------------------------------------------
RUN dnf -y --setopt=install_weak_deps=False install \
        git \
        gh \
        wget \
        zsh \
        zsh-autosuggestions \
        zsh-syntax-highlighting \
        python3-pip \
        python3-devel \
        glibc-langpack-pt \
        fuse-libs \
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
        gnome-keyring-pam \
        mate-polkit \
        brightnessctl \
        playerctl \
        cliphist \
        jetbrains-mono-fonts \
        google-noto-emoji-fonts \
        google-carlito-fonts \
        google-crosextra-caladea-fonts \
        papirus-icon-theme \
        papirus-icon-theme-dark \
        adw-gtk3-theme \
        neovim \
        eza \
        bat \
        fd-find \
        fzf \
        ripgrep \
        zoxide \
        btop \
        fedora-workstation-backgrounds \
        "f$(rpm -E %fedora)-backgrounds-base" \
    && dnf -y remove htop \
    && dnf clean all

# Ambiente de terminal: só o que o Fedora não empacota (starship, lazygit,
# lazydocker, Nerd Font, cursor), com versão e checksum fixados. Os scripts são
# removidos na mesma camada.
COPY build_files/ /tmp/build_files/
RUN /tmp/build_files/install-upstream-bins.sh \
    && /tmp/build_files/install-nerd-font.sh \
    && /tmp/build_files/install-cursor.sh \
    && rm -rf /tmp/build_files

# Ícones Papirus-Dark com pastas em violeta (§26.1). O script falha o build
# se a troca não pegar.
COPY build_files/papirus-folders.sh /tmp/papirus-folders.sh
RUN bash /tmp/papirus-folders.sh violet && rm -f /tmp/papirus-folders.sh

# Noctalia v5, o shell do desktop (§8.2). Não usar a v4 ('noctalia-shell').
# Ele não traz agente polkit: o mate-polkit acima continua necessário.
RUN dnf -y --setopt=install_weak_deps=False install \
        noctalia \
    && dnf clean all

# VS Code na imagem, não em Flatpak: o terminal dele precisa do docker do
# host para o Laravel Sail (§17.1).
RUN dnf -y --setopt=install_weak_deps=False --enablerepo=code install \
        code \
    && dnf clean all

# Nautilus e companhia na imagem, não em Flatpak: são integração com o
# sistema — pendrive, MTP, SMB, lixeira, FileManager1 (§25.1). O seletor de
# arquivos fica no backend gtk do portal, senão abriria o próprio Nautilus.
RUN dnf -y --setopt=install_weak_deps=False install \
        nautilus \
        xdg-user-dirs \
        gnome-disk-utility \
        file-roller \
        gvfs-mtp \
        gvfs-smb \
        gvfs-fuse \
        sushi \
        papers-thumbnailer \
    && dnf clean all

# Impressão: o assistente e o cups-pk-helper, que o deixa cadastrar
# impressora sem root (§25.2). O sed afasta o botão Desbloquear da borda da
# janela sem CSD; é conferido, e o build falha se o pacote mudar a linha.
RUN dnf -y --setopt=install_weak_deps=False install \
        system-config-printer \
        cups-pk-helper \
    && dnf clean all \
    && sed -i 's/^\( *\)self\.hboxMenuBar\.pack_start (self\.unlock_button, False, False, 12)$/&\n\1self.unlock_button.set_margin_top (6)\n\1self.unlock_button.set_margin_bottom (6)/' \
        /usr/share/system-config-printer/system-config-printer.py \
    && test "$(grep -c '^ *self\.unlock_button\.set_margin_\(top\|bottom\) (6)$' \
        /usr/share/system-config-printer/system-config-printer.py)" = 2 \
    && python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' \
        /usr/share/system-config-printer/system-config-printer.py

# Rede e sessão (§10, §22): tailscale, nm-connection-editor (o que o painel
# do Noctalia não configura), gcr (agente SSH) e xdg-terminal-exec (sem ele o
# GLib não acha o foot para abrir programas de terminal).
RUN dnf -y --setopt=install_weak_deps=False install \
        tailscale \
        nm-connection-editor \
        gcr \
        xdg-terminal-exec \
    && dnf clean all

# Lista de variáveis no import-environment do niri-session (§27.4). O script
# falha de propósito quando o pacote vier corrigido, e aí o remendo sai.
COPY build_files/patch-niri-session.sh /tmp/patch-niri-session.sh
RUN bash /tmp/patch-niri-session.sh && rm -f /tmp/patch-niri-session.sh

# Login: greetd + greetd-selinux (a política; sem ela o SELinux barra). No
# Fedora a conta do greeter é 'greetd', não 'greeter' — ver
# files/etc/greetd/config.toml.
RUN dnf -y --setopt=install_weak_deps=False install \
        greetd \
        greetd-selinux \
        tuigreet \
    && dnf clean all

# Noctalia Greeter, do estágio de compilação; 'wlroots' é a dependência de
# runtime que falta na base. O tmpfiles.d do upstream usa o usuário 'greeter',
# que no Fedora não existe: é descartado, e a entrada certa está em
# /usr/lib/tmpfiles.d/arkmos.conf (§8.3).
RUN dnf -y --setopt=install_weak_deps=False install \
        wlroots \
    && dnf clean all

COPY --from=greeter-builder /tmp/greeter-root/ /
RUN rm -f /usr/lib/tmpfiles.d/noctalia-greeter.conf

# Docker CE de verdade, não podman-docker (§15). O grupo docker vem de
# /usr/lib/sysusers.d/arkmos-docker.conf, com GID dinâmico.
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
# DEPOIS dos pacotes: antes, o RPM gravaria a versão dele como .rpmnew. Nada
# em /usr/local nem /opt, que apontam para /var (§3.4).
# ---------------------------------------------------------------------------
COPY files/ /

# Localização na imagem (§11). Não usar localectl/timedatectl na máquina:
# congela os arquivos contra atualizações da imagem.
RUN ln -sf ../usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# zsh: a config do Arkmos entra pelo /etc/zshrc, antes do ~/.zshrc da conta
# (§13.1). Acrescentada ao arquivo do Fedora, em vez de substituí-lo.
RUN printf '\n%s\n%s\n' \
        '# Arkmos: configuração do zsh da imagem, antes do ~/.zshrc da conta.' \
        '[[ -r /usr/share/arkmos/zsh/arkmos.zsh ]] && source /usr/share/arkmos/zsh/arkmos.zsh' \
        >> /etc/zshrc \
    && grep -qx '.*source /usr/share/arkmos/zsh/arkmos.zsh' /etc/zshrc

# Tira do menu as entradas que não servem (§25). O build falha se um pacote
# renomear o arquivo.
RUN for f in foot-server footclient dev.noctalia.Noctalia; do \
        sed -i '/^\[Desktop Entry\]$/a NoDisplay=true' "/usr/share/applications/$f.desktop" \
        && grep -qx 'NoDisplay=true' "/usr/share/applications/$f.desktop" \
        || exit 1; \
    done \
    && desktop-file-validate /usr/share/applications/arkmos-noctalia-settings.desktop

# Menu do ujust sem as receitas que não se aplicam aqui (§31.2).
COPY build_files/trim-ujust.sh /tmp/trim-ujust.sh
RUN bash /tmp/trim-ujust.sh && rm -f /tmp/trim-ujust.sh

# Compila o banco do dconf; sem isto, os arquivos de local.d não têm efeito.
RUN dconf update

# Verificação de assinatura da própria imagem (§28.3), só com a chave pública
# em files/etc/pki/containers/arkmos.pub. A entrada é INSERIDA na política da
# base, e cobre os dois repositórios do Arkmos, não o namespace da conta.
RUN if [ -f /etc/pki/containers/arkmos.pub ]; then \
        python3 -c 'import json, sys; \
p = "/etc/containers/policy.json"; \
d = json.load(open(p)); \
regra = [{"type": "sigstoreSigned", "keyPath": "/etc/pki/containers/arkmos.pub", "signedIdentity": {"type": "matchRepository"}}]; \
d["transports"]["docker"].update({f"{sys.argv[1]}/arkmos": regra, f"{sys.argv[1]}/arkmos-nvidia": regra}); \
json.dump(d, open(p, "w"), indent=4)' "$ARKMOS_REGISTRY" \
        && echo "verificação de assinatura ativada para $ARKMOS_REGISTRY/arkmos{,-nvidia}"; \
    else \
        echo "sem chave pública: a imagem não verificará a própria assinatura"; \
        rm -f /etc/containers/registries.d/arkmos.yaml; \
    fi

# Serviços (§7, §22): sshd desligado (o 10-arkmos.preset impede que o preset
# do Fedora o religue no primeiro boot), firewall na zona FedoraWorkstation,
# agente SSH do gcr para todo usuário, e grub-boot-success mascarada — ela
# escreveria no /boot, que aqui é somente leitura.
RUN chmod 0755 /usr/libexec/arkmos-firstboot /usr/libexec/arkmos-greeter \
                /usr/bin/arkmos-diag \
    && systemctl enable arkmos-firstboot.service \
    && systemctl enable arkmos-flatpak-preinstall.service \
    && systemctl enable tailscaled.service \
    && systemctl disable sshd.service \
    && systemctl --global enable gcr-ssh-agent.socket \
    && firewall-offline-cmd --set-default-zone=FedoraWorkstation \
    && systemctl enable docker.service \
    && systemctl enable greetd.service \
    && systemctl --global mask grub-boot-success.timer grub-boot-success.service

# A variante sem NVIDIA remove a configuração do driver, decidindo pelo que a
# base entregou e não por build-arg (§24.2).
RUN if [ ! -e /usr/lib/systemd/system/nvidia-cdi-refresh.service ]; then \
        echo "variante sem NVIDIA: removendo configuração específica do driver"; \
        rm -rf /usr/lib/systemd/system/nvidia-cdi-refresh.service.d \
               /etc/nvidia; \
    fi

# Splash de boot e wallpaper padrão, gerados no build (§27.2). Depois do
# COPY files/, que traz o tema do Plymouth.
COPY build_files/render-artwork.sh /tmp/render-artwork.sh
RUN bash /tmp/render-artwork.sh && rm -f /tmp/render-artwork.sh

# Initramfs regerado, porque o tema do Plymouth só vale lá dentro (§27.2).
# Mesmos argumentos da base (lsinitrd). O /var/roothome existe só durante o
# dracut, que sem ele não instala o /root no initramfs.
RUN kver="$(ls /usr/lib/modules)"; \
    [ "$(printf '%s\n' "$kver" | wc -l)" -eq 1 ] \
        || { echo "esperado um único kernel em /usr/lib/modules: $kver"; exit 1; }; \
    criado=; [ -d /var/roothome ] || { mkdir -m 0700 /var/roothome; criado=1; }; \
    DRACUT_NO_XATTR=1 dracut --no-hostonly --kver "$kver" --reproducible \
        --add ostree -f "/usr/lib/modules/$kver/initramfs.img" || exit 1; \
    [ -z "$criado" ] || rmdir /var/roothome

# /var só é populado na primeira instalação: cache e log do build ficariam
# congelados. Caminhos um a um porque /run/secrets e /run/systemd estão
# montados durante o build.
RUN rm -rf /var/cache/libdnf5 /var/cache/dnf /var/lib/dnf \
           /var/lib/tuned /var/log/tuned \
           /run/dnf /run/tuned /run/selinux-policy /tmp/* \
    && find /var/log -type f -delete \
    && rm -f /var/cache/ldconfig/aux-cache

# Metadados. Os ARGs voláteis ficam aqui, e não no topo, para um commit novo
# não invalidar o cache das camadas de pacotes (§29).
ARG ARKMOS_VERSION="dev"
ARG ARKMOS_COMMIT="unknown"
ARG ARKMOS_VARIANT="base"

LABEL org.opencontainers.image.title="Arkmos"
LABEL org.opencontainers.image.description="Estação de trabalho pessoal baseada em Fedora bootc"
LABEL org.opencontainers.image.source="https://github.com/AlexRogaleski/arkmos"
LABEL org.opencontainers.image.version="${ARKMOS_VERSION}"
LABEL org.opencontainers.image.revision="${ARKMOS_COMMIT}"
LABEL org.arkmos.variant="${ARKMOS_VARIANT}"

# Pega erros de /var, /opt e layout de kernel em tempo de build.
RUN ["bootc", "container", "lint"]
