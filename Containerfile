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

# ---------------------------------------------------------------------------
# Estágio de compilação: Noctalia Greeter
#
# O greeter não é empacotado pelo Fedora, e o único RPM existente é um snapshot
# de git num COPR de terceiro. Compilar aqui mantém a mesma política do resto
# do projeto — versão fixada, nada de snapshot — e o estágio separado existe
# para que os ~40 pacotes -devel da compilação não acabem na imagem final: o
# que atravessa são 5 binários e alguns assets.
#
# Fixado por commit, e não pela tag: tag pode ser movida.
# v1.5.0 = 5a450b891067c1f0cd7157f4f1091aa0e3014780
#
# O '-march=native' do upstream é removido, e isso não é ajuste de otimização:
# em release o meson dele acrescenta '-march=native -mtune=native', sem opção
# para desligar. O binário sai amarrado ao processador de quem compila — e quem
# compila a imagem publicada é o runner do GitHub, não esta máquina. Numa
# máquina com outro CPU o greeter morre de SIGILL na primeira coisa que faz ao
# autenticar (GreetdClient::sendRequest): a senha é aceita, o greetd reinicia e
# a tela de login pisca e volta, sem nada que aponte a causa. Foi exatamente
# assim que a primeira imagem publicada se comportou na VM. Ver PROJECT.md 8.3.
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
#
# 'gnome-keyring-pam' é um pacote separado do 'gnome-keyring' e entrega só o
# pam_gnome_keyring.so. O /etc/pam.d/greetd JÁ o referencia, mas com '-' na
# frente — sintaxe que manda ignorar em silêncio quando o módulo não existe.
# Sem o pacote, portanto, nada falha e nada avisa: o chaveiro simplesmente não
# é destravado com a senha do login, e a sessão abre com um prompt pedindo a
# mesma senha de novo.
#
# 'fuse-libs' é a libfuse.so.2, que a base não traz (traz o fusermount e a
# fuse3). AppImages com o runtime clássico a carregam para se montar, e sem
# ela nem abrem: "dlopen(): error loading libfuse.so.2". Os com runtime novo,
# como o do AppManager, não precisam dela.
#
# Carlito e Caladea têm as mesmas medidas da Calibri e da Cambria, as fontes
# padrão do Word: sem elas um documento aberto aqui troca de fonte e desalinha.
# As da Liberation, que cobrem Arial, Times e Courier, já vêm da base.
#
# O btop substitui o htop que vem da base: mesma função, com gráficos, e com os
# temas Tokyo Night e Dracula embutidos. Nada depende do htop.
#
# 'gh' é o cliente do GitHub: 'gh pr', 'gh run', 'gh auth'. O repositório deste
# projeto vive lá, e o CI é acompanhado por ele.
#
# Sem 'mako': quem implementa o org.freedesktop.Notifications aqui é o próprio
# Noctalia, com daemon ligado por padrão. O mako ficava instalado, desabilitado
# e nunca iniciado — dois daemons para o mesmo barramento, e um deles peso
# morto.
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
    && dnf -y remove htop \
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

# Ícones: Papirus-Dark, com as pastas em violeta.
#
# A Papirus-Dark, e não a Papirus, porque é a variante feita para tema escuro:
# os ícones pequenos de barra e de ferramenta vêm claros. Ela só traz o que
# difere e aponta para a Papirus em todo o resto, por isso os dois pacotes.
# As pastas trocam o azul padrão pelo violeta, o tom de destaque do Arkmos —
# ver o script sobre como, e por que ele falha o build se a troca não pegar.
COPY build_files/papirus-folders.sh /tmp/papirus-folders.sh
RUN bash /tmp/papirus-folders.sh violet && rm -f /tmp/papirus-folders.sh

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

# Gerenciador de arquivos na imagem, não em Flatpak.
#
# Um gerenciador de arquivos é integração com o sistema, não aplicativo
# isolado: no sandbox ele precisa de filesystem=host para ser útil e mesmo
# assim não monta pendrive, não fala MTP nem SMB e não enxerga a lixeira do
# gvfs. O Nautilus traz o gvfs como dependência e implementa o
# org.freedesktop.FileManager1 — é por essa interface que o "mostrar na pasta"
# do VS Code e do Firefox abre alguma coisa.
#
# Escolhido por ser GTK4/libadwaita, o mesmo tema escuro que o resto já segue
# pelo dconf e pelo portal, e pelo custo: 10 pacotes e 22 MiB. O Thunar custa
# 35 MiB e puxa xfce4-panel; o Dolphin, 85 pacotes de KDE.
#
# O seletor de arquivos continua no backend gtk do portal (niri-portals.conf):
# o do GNOME passaria a abrir o próprio Nautilus como seletor.
#
# xdg-user-dirs cria Documentos, Downloads, Imagens… no login. Sem ele o home
# nasce vazio, e a barra lateral do Nautilus não tem para onde apontar. O
# pacote entrega uma unit de usuário ligada ao início da sessão gráfica, que o
# preset do Fedora já habilita (a entrada de autostart dele vem marcada para o
# systemd pular). Os nomes saem em português porque o LANG do systemd --user
# vem do environment.d do Arkmos.
#
# Discos (gnome-disk-utility) e o gerenciador de compactação (file-roller)
# entram pelo mesmo motivo: são integração com o sistema de arquivos e com o
# hardware, não aplicativo isolado. O Discos traz o montador de imagem que o
# Nautilus usa no clique duplo numa .iso, além de formatar pendrive, gravar
# imagem e mostrar o SMART do disco. O gerenciador abre um arquivo compactado
# para navegar e extrair só parte dele — o "Comprimir" e o "Extrair aqui" do
# Nautilus já funcionavam sozinhos, pelo gnome-autoar. Os formatos vêm da base
# (7zip, zip, xz, zstd, bzip2, libarchive); o 7zip do Fedora não traz o codec
# RAR, por licença, e quem lê RAR é a libarchive. Os dois juntos custam 12 MiB.
#
# Os backends do gvfs que a base não traz: gvfs-mtp faz o celular ligado por
# USB aparecer no Nautilus, gvfs-smb abre pastas compartilhadas na rede, e o
# gvfs-fuse dá a esses locais um caminho de verdade (/run/user/UID/gvfs), sem
# o qual um Flatpak ou o VS Code não conseguem abrir um arquivo que está no
# celular. O sushi é a pré-visualização da tecla Espaço, e o
# papers-thumbnailer gera as miniaturas de PDF: o Papers da lista de Flatpaks
# não exporta o dele para o host.
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

# Impressão: o assistente, e o que ele precisa para funcionar.
#
# A base já traz o obrigatório do grupo 'printing' do Fedora (cups,
# cups-filters, ghostscript) e quase todos os padrões dele — hplip, gutenprint,
# ipp-usb, colord, nss-mdns, samba-client, system-config-printer-udev. Faltava
# a parte que se usa: nenhum programa permitia CADASTRAR uma impressora. O
# system-config-printer é o assistente, e o cups-pk-helper é o que o deixa
# fazer isso sem root, pedindo autorização ao polkit em vez de exigir sudo.
#
# O cups-browsed segue desligado, como no preset do próprio Fedora, que só
# habilita cups.socket e cups.path.
#
# O assistente põe o botão Desbloquear na linha do menu, ocupando a altura
# dela inteira. Sob uma barra de título isso passa despercebido; com o
# prefer-no-csd do niri não há barra, e o botão encosta na borda da janela. As
# duas margens o afastam dela. O sed é conferido: se o pacote mudar a linha, o
# build falha em vez de seguir sem o ajuste. O script roda direto, pelo
# shebang, e nunca é importado; o .pyc que o pacote traz não entra em jogo.
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

# Rede e sessão: o que o dia a dia de uso pede e a base não traz.
#
# tailscale: a VPN em malha usada para chegar às outras máquinas. Vem do
# Fedora; o tailscaled é habilitado adiante, e a máquina entra na rede com
# 'sudo tailscale up' uma vez.
#
# nm-connection-editor: o painel do Noctalia conecta em Wi-Fi e cabo, mas não
# configura IP fixo, hotspot, VPN nem Wi-Fi corporativo. Isso fica aqui.
#
# gcr: o agente SSH do GNOME (gcr-ssh-agent). Guarda a senha da chave no
# chaveiro, que o login já destrava, e define o SSH_AUTH_SOCK para a sessão.
# Sem agente, cada 'git push' pede a senha da chave, e o VS Code, que não tem
# onde perguntar, falha. O gnome-keyring deixou de ser agente SSH; o papel
# passou para o gcr. O socket é habilitado para todo usuário adiante.
#
# xdg-terminal-exec: é por ele que o GLib descobre o terminal para abrir um
# programa de terminal (btop, nvim) pelo Nautilus ou pelo "Abrir com". A
# lista embutida no GLib não conhece o foot, e sem isto a ação simplesmente
# não acontece. O foot é declarado em /etc/xdg/xdg-terminals.list.
RUN dnf -y --setopt=install_weak_deps=False install \
        tailscale \
        nm-connection-editor \
        gcr \
        xdg-terminal-exec \
    && dnf clean all

# O aviso de obsolescência que aparecia entre a senha e o desktop.
#
# O 'niri-session' do pacote chama 'systemctl --user import-environment' sem
# lista de variáveis, e o systemd avisa no console. O script explica o resto:
# por que não é só estética, por que LANG e XDG_DATA_DIRS ficam fora da lista,
# e as issues do upstream. Ele falha de propósito quando o pacote vier
# corrigido, e aí o remendo sai.
COPY build_files/patch-niri-session.sh /tmp/patch-niri-session.sh
RUN bash /tmp/patch-niri-session.sh && rm -f /tmp/patch-niri-session.sh

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

# Noctalia Greeter, vindo do estágio de compilação acima.
#
# 'wlroots' é a única dependência de runtime que a base não traz — o greeter
# sobe um compositor wlroots próprio para desenhar a tela de login.
#
# O tmpfiles.d do upstream é descartado de propósito. Ele declara
#
#     d /var/lib/noctalia-greeter 0750 greeter greeter -
#
# com o usuário 'greeter', que no Fedora não existe — a conta é 'greetd'. O
# próprio comentário deles avisa para sobrescrever quando o usuário difere.
# Sem isso o diretório de estado não é criado e o greeter não tem onde gravar:
# é o mesmo erro que a conta errada no config.toml produz, e a mesma falha que
# o Zirconium registrou na issue #68 com o greeter deles. A entrada correta
# está em /usr/lib/tmpfiles.d/arkmos.conf, que o 'just check' valida
# resolvendo usuários de verdade.
RUN dnf -y --setopt=install_weak_deps=False install \
        wlroots \
    && dnf clean all

COPY --from=greeter-builder /tmp/greeter-root/ /
RUN rm -f /usr/lib/tmpfiles.d/noctalia-greeter.conf

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

# Menu de aplicativos: o que aparece e não deveria.
#
# O foot traz três entradas (o terminal, o modo servidor e o cliente dele), e
# só a primeira serve para abrir pelo menu. A do Noctalia inicia o shell, que o
# niri já inicia no login: clicada, não faz nada. No lugar dela entra
# "Configurações do Noctalia" (arkmos-noctalia-settings.desktop), que é o que se
# espera achar ali. NoDisplay tira do menu sem apagar o arquivo, que outros
# programas ainda consultam. Cada troca é conferida: se um pacote renomear o
# arquivo, o build falha em vez de a entrada voltar ao menu sem ninguém notar.
RUN for f in foot-server footclient dev.noctalia.Noctalia; do \
        sed -i '/^\[Desktop Entry\]$/a NoDisplay=true' "/usr/share/applications/$f.desktop" \
        && grep -qx 'NoDisplay=true' "/usr/share/applications/$f.desktop" \
        || exit 1; \
    done \
    && desktop-file-validate /usr/share/applications/arkmos-noctalia-settings.desktop

# Menu do ujust: o mesmo critério, uma camada acima.
#
# O ublue-os-just traz o menu do Universal Blue inteiro, e parte dele aponta
# para fora desta imagem — o 'toggle-nvk' faria rebase para uma variante
# '-nvidia-open' que aqui não existe. As receitas do Arkmos entram pelo gancho
# que o próprio pacote deixa, o 60-custom.just, que vem na árvore files/.
COPY build_files/trim-ujust.sh /tmp/trim-ujust.sh
RUN bash /tmp/trim-ujust.sh && rm -f /tmp/trim-ujust.sh

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
#
# O escopo são os DOIS repositórios do Arkmos, e não o namespace inteiro. O
# ublue pode usar 'ghcr.io/ublue-os' porque tudo que vive lá é deles e é
# assinado; este namespace é uma conta pessoal, que pode publicar qualquer
# outra imagem — e com o escopo no namespace, cada uma dessas passaria a
# precisar da assinatura do Arkmos para ser baixada nesta máquina.
#
# Vale saber o que a política da base já faz: o escopo "" do transporte docker
# é 'insecureAcceptAnything', então imagem de registry não listado continua
# sendo aceita sem verificação. Esta entrada é aditiva e específica; ela não
# torna o sistema restritivo de forma geral.
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

# O servidor SSH fica desligado. A base o habilita, e com a zona de firewall
# que o libera, numa rede Wi-Fi pública qualquer um tentaria entrar com senha.
# Desabilitar aqui não basta: o /etc/machine-id nasce vazio, o systemd trata o
# primeiro boot como tal e reaplica os presets, e o 90-default.preset do Fedora
# o habilitaria de novo. O 10-arkmos.preset vem antes e vence. A VM de teste o
# liga pela linha de boot (config.toml), sem mudar a imagem.
#
# A zona padrão do firewall é a FedoraWorkstation, a do Fedora Workstation:
# portas altas liberadas na rede local, o que o LocalSend (53317) e um servidor
# de desenvolvimento acessado pelo celular precisam. A 'public', que vinha da
# base, bloqueia os dois sem avisar.
#
# O agente SSH do gcr é habilitado para todo usuário, com --global: o socket
# nasce com a sessão e define o SSH_AUTH_SOCK no systemd --user, de onde o niri
# e tudo o que ele abre herdam.
#
# A grub-boot-success é mascarada, e não é frescura: o preset do Fedora a
# habilita para todo usuário, ela roda 'grub2-set-bootflag boot_success' dois
# minutos depois do login, e num sistema bootc o /boot é somente leitura —
# "Creating tmpfile failed: Read-only file system", unit falhada em toda
# sessão. Ela existe para alimentar o menu automático do GRUB gravando no
# grubenv, coisa que aqui não acontece: quem cuida das entradas de boot é o
# bootc. Mascarar é dizer isso de forma explícita, em vez de conviver com uma
# unit vermelha no 'systemctl --user' de todo boot.
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

# Arte do Arkmos: splash de boot e wallpaper padrão.
#
# Gerada por build_files/render-artwork.sh a partir de fonte e cores — ver o
# cabeçalho do script sobre por que não há imagem pronta versionada. Roda
# depois do COPY files/, que traz o plymouthd.conf e o .plymouth do tema.
COPY build_files/render-artwork.sh /tmp/render-artwork.sh
RUN bash /tmp/render-artwork.sh && rm -f /tmp/render-artwork.sh

# Initramfs regerado, porque o tema do Plymouth só vale lá dentro.
#
# O plymouthd arranca do initramfs e continua, depois do switch-root, com o
# tema que carregou nele. O initramfs da base foi gerado com o bgrt: sem
# regerar, o boot continua mostrando o logo do fabricante, com o plymouthd.conf
# da imagem dizendo outra coisa.
#
# Os argumentos são os mesmos que a base usou ('lsinitrd', linha "Arguments"),
# e a configuração vem dos dracut.conf.d que a própria base instalou — inclusive
# o 99-nvidia.conf da variante NVIDIA. Rodar depois de todo o /etc também leva
# o teclado br do vconsole.conf para o initramfs, que é onde uma senha de LUKS
# seria digitada.
#
# /var/roothome existe só enquanto o dracut roda. O /root da imagem é symlink
# para ele, mas o diretório só nasce no boot, pelo tmpfiles do rpm-ostree. Sem
# ele o dracut não instala o /root ("dracut-install: ERROR: installing '/root'"
# no log) e o initramfs sai sem o home do shell de emergência — diferente do
# initramfs da base, que tem. Removido em seguida: /var não sai do build com
# conteúdo.
RUN kver="$(ls /usr/lib/modules)"; \
    [ "$(printf '%s\n' "$kver" | wc -l)" -eq 1 ] \
        || { echo "esperado um único kernel em /usr/lib/modules: $kver"; exit 1; }; \
    criado=; [ -d /var/roothome ] || { mkdir -m 0700 /var/roothome; criado=1; }; \
    DRACUT_NO_XATTR=1 dracut --no-hostonly --kver "$kver" --reproducible \
        --add ostree -f "/usr/lib/modules/$kver/initramfs.img" || exit 1; \
    [ -z "$criado" ] || rmdir /var/roothome

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

# Metadados da imagem.
#
# Os três ARGs voláteis são declarados AQUI, e não no topo, porque um
# build-arg diferente invalida o cache de tudo o que vem depois dele: com a
# versão e o commit lá em cima, cada commit novo refazia o 'dnf install' e as
# camadas seguintes num build local. Declarados junto dos labels, um commit
# novo invalida só a camada de label. O CI injeta o esquema por data
# (44.AAAAMMDD.N); build local fica como "dev".
#
# A ideia vem do finpilot, o template novo do projectbluefin, que documenta
# exatamente esse motivo.
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
