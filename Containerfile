FROM quay.io/fedora/fedora-bootc:44

RUN mkdir -p /usr/lib/bootc/install \
    && printf '%s\n' \
        '[install.filesystem.root]' \
        'type = "btrfs"' \
        > /usr/lib/bootc/install/00-arkmos.toml

RUN dnf -y --setopt=install_weak_deps=False install \
        git \
        curl \
        wget \
        vim-enhanced \
        zsh \
        python3 \
        python3-pip \
        python3-devel \
        openssh-clients \
        NetworkManager \
        bluez \
        bluez-tools \
        pipewire \
        pipewire-alsa \
        pipewire-pulseaudio \
        wireplumber \
        tuned \
        tuned-ppd \
        podman \
        podman-docker \
        distrobox \
        niri \
        xwayland-satellite \
        foot \
        xdg-desktop-portal \
        xdg-desktop-portal-gtk \
        gnome-keyring \
    && dnf clean all

COPY files/usr/local/libexec/arkmos-firstboot /usr/local/libexec/arkmos-firstboot
COPY files/etc/systemd/system/arkmos-firstboot.service /etc/systemd/system/arkmos-firstboot.service
COPY files/etc/niri/config.kdl /etc/niri/config.kdl

RUN chmod +x /usr/local/libexec/arkmos-firstboot \
    && systemctl enable arkmos-firstboot.service

LABEL org.opencontainers.image.title="Arkmos"
LABEL org.opencontainers.image.description="Estação de trabalho pessoal baseada em Fedora bootc"
LABEL org.opencontainers.image.version="0.5.0"
