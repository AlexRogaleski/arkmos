FROM quay.io/fedora/fedora-bootc:44

RUN dnf -y install \
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
    && dnf clean all

LABEL org.opencontainers.image.title="Arkmos"
LABEL org.opencontainers.image.description="Estação de trabalho pessoal baseada em Fedora bootc"
LABEL org.opencontainers.image.version="0.2.0"
