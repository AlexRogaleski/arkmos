#!/usr/bin/env bash
#
# Verificações da imagem do Arkmos: ./tests/check-image.sh localhost/arkmos:dev
#
# Usado pelo 'just check' e pelo CI (§28.1). Entra aqui o erro que a imagem
# consegue esconder: constrói, passa no lint e só falha no boot da máquina.

# SC2016: o código vai para DENTRO do container, em aspas simples, de propósito.
# SC2329 (shellcheck 0.11) e SC2317 (0.9, o do runner): as funções de
# verificação são chamadas indiretamente, pelo 'check'.
# shellcheck disable=SC2016,SC2329,SC2317

set -uo pipefail

IMAGE="${1:-localhost/arkmos:dev}"
FAILED=0

# A variante vem do label que o Containerfile grava, não do nome da imagem.
VARIANT="$(podman inspect --format '{{index .Config.Labels "org.arkmos.variant"}}' \
    "$IMAGE" 2>/dev/null)"
VARIANT="${VARIANT:-desconhecida}"

run() { podman run --rm "$IMAGE" "$@"; }

# Lê um arquivo da camada da imagem, sem os bind-mounts que o podman injeta
# em tempo de execução (/etc/hostname, /etc/resolv.conf, /etc/hosts).
image_file_matches() {
    local path="$1" expected="$2" cid content rc=0
    cid="$(podman create "$IMAGE" true)" || return 1
    content="$(podman cp "$cid:$path" - 2>/dev/null | tar -xO 2>/dev/null)" || rc=1
    podman rm "$cid" >/dev/null 2>&1
    [[ "$rc" -eq 0 ]] || {
        echo "$path nao existe na imagem"
        return 1
    }
    if [[ "$(tr -d '[:space:]' <<<"$content")" != "$expected" ]]; then
        echo "$path contem \"$content\", esperado \"$expected\""
        return 1
    fi
}

check() {
    local desc="$1"
    shift
    printf '  %-52s' "$desc"
    local out
    if out="$("$@" 2>&1)"; then
        echo "ok"
    else
        echo "FALHOU"
        # shellcheck disable=SC2001  # indentar cada linha é trabalho de sed
        [[ -n "$out" ]] && sed 's/^/      /' <<<"$out"
        FAILED=1
    fi
}

# O assistente roda de verdade, com as respostas no stdin: um erro nele só
# apareceria com a máquina instalada e sem conta para entrar.
firstboot_e2e() {
    printf 'arkteste\nTeste Arkmos\nsenha-de-teste-longa\nsenha-de-teste-longa\n' |
        podman run --rm -i "$IMAGE" bash -c '
            bash /usr/libexec/arkmos-firstboot >/dev/null 2>&1

            id arkteste >/dev/null 2>&1 \
                || { echo "a conta não foi criada"; exit 1; }
            [ "$(id -u arkteste)" = 1000 ] \
                || { echo "UID é $(id -u arkteste), esperado 1000"; exit 1; }
            [ "$(getent passwd arkteste | cut -d: -f7)" = /usr/bin/zsh ] \
                || { echo "shell não é o zsh"; exit 1; }
            id -nG arkteste | grep -qw wheel \
                || { echo "não entrou no grupo wheel"; exit 1; }
            id -nG arkteste | grep -qw docker \
                || { echo "não entrou no grupo docker"; exit 1; }
            [ "$(passwd -S arkteste | awk "{print \$2}")" = P ] \
                || { echo "a senha não ficou definida"; exit 1; }
            test -f /var/lib/arkmos/initialized \
                || { echo "não gravou a marca de inicializado"; exit 1; }

            # O skel só é copiado por useradd --create-home: sem a flag,
            # os defaults somem sem erro.
            test -s /var/home/arkteste/.config/Code/User/settings.json \
                || { echo "o /etc/skel não foi copiado para o home"; exit 1; }
            test -s /var/home/arkteste/.config/noctalia/arkmos.toml \
                || { echo "os padrões do Noctalia não chegaram ao home"; exit 1; }
        '
}

# Rebase de outro Fedora Atomic, com a conta já existente: o assistente sai
# sozinho e calado, e dá o grupo docker só a quem está no wheel (§12.1).
firstboot_rebase() {
    podman run --rm "$IMAGE" bash -c '
        useradd -u 1000 -m -G wheel ana >/dev/null 2>&1
        echo "ana:senha-de-teste-longa" | chpasswd
        useradd -u 1001 -m beto >/dev/null 2>&1
        echo "beto:senha-de-teste-longa" | chpasswd

        saida=$(timeout 10 bash /usr/libexec/arkmos-firstboot </dev/null 2>&1) \
            || { echo "o assistente não terminou sozinho: $saida"; exit 1; }
        [ -z "$saida" ] \
            || { echo "escreveu no console: $saida"; exit 1; }
        test -f /var/lib/arkmos/initialized \
            || { echo "não gravou a marca de inicializado"; exit 1; }
        id -nG ana | grep -qw docker \
            || { echo "a conta administradora não entrou no grupo docker"; exit 1; }
        if id -nG beto | grep -qw docker; then
            echo "uma conta fora do wheel ganhou o grupo docker"; exit 1
        fi
        [ "$(passwd -S ana | awk "{print \$2}")" = P ] \
            || { echo "a senha da conta existente mudou de estado"; exit 1; }
    '
}

echo "Verificando ${IMAGE} (variante: ${VARIANT})"
echo

# --- Estrutura da imagem ---------------------------------------------------

check "bootc container lint" run bootc container lint

# Sintaxe e ordenação das units do Arkmos, inclusive o drop-in do greetd.
check "systemd-analyze verify (units do Arkmos)" \
    run systemd-analyze verify \
    /usr/lib/systemd/system/arkmos-firstboot.service \
    /usr/lib/systemd/system/arkmos-login-fallback.service \
    /usr/lib/systemd/system/arkmos-flatpak-preinstall.service \
    /usr/lib/systemd/system/greetd.service

# --- Localização -----------------------------------------------------------

check "locale pt_BR.utf8 presente" \
    run sh -c 'locale -a | grep -qx pt_BR.utf8'

check "timezone America/Sao_Paulo" \
    run sh -c 'readlink /etc/localtime | grep -q "zoneinfo/America/Sao_Paulo$"'

check "teclado ABNT2 (KEYMAP=br)" \
    run sh -c 'grep -qx "KEYMAP=br" /etc/vconsole.conf'

# Sem isto a máquina se chama "fedora". Com 'podman cp': num 'run' o podman
# monta um /etc/hostname próprio, e a verificação sempre passaria.
check "hostname declarado na imagem" image_file_matches /etc/hostname arkmos

# --- Login -----------------------------------------------------------------

# A conta do greeter muda de nome entre distribuições, e errá-la não dá erro de
# configuração: o greetd falha cinco vezes, desiste e a vt1 fica preta (§8.3).
check "conta do greeter do greetd existe" \
    run sh -c '
        u=$(sed -n "s/^[[:space:]]*user[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
            /etc/greetd/config.toml | head -1)
        test -n "$u" || { echo "nao achei user= em /etc/greetd/config.toml"; exit 1; }
        getent passwd "$u" >/dev/null || { echo "a conta \"$u\" nao existe na imagem"; exit 1; }
    '

check "sessão Wayland do Niri registrada" \
    run test -s /usr/share/wayland-sessions/niri.desktop

check "niri validate" \
    run niri validate --config /etc/niri/config.kdl

# --- Primeiro boot ---------------------------------------------------------

check "assistente do primeiro boot cria a conta" firstboot_e2e
check "assistente dispensado em rebase (conta existente)" firstboot_rebase

# --- Sessão: autenticação e localização -------------------------------------

# O PAM do greetd referencia o módulo com '-', que ignora se ele faltar: sem o
# pacote -pam, o chaveiro não abre com o login e a sessão pede a senha de novo.
check "pam_gnome_keyring presente e referenciado" \
    run sh -c 'test -e /usr/lib64/security/pam_gnome_keyring.so \
        || { echo "o módulo não está instalado (falta gnome-keyring-pam)"; exit 1; }
      grep -q pam_gnome_keyring /etc/pam.d/greetd \
        || { echo "o PAM do greetd não referencia o módulo"; exit 1; }'

# O autostart do agente tem OnlyShowIn=MATE e nunca subiria no niri. Sem
# agente, toda autorização falha sem janela nem erro.
check "agente polkit iniciado pelo niri" \
    run sh -c 'grep -q "^spawn-at-startup \"/usr/libexec/polkit-mate-authentication-agent-1\"$" /etc/niri/config.kdl \
        && test -x /usr/libexec/polkit-mate-authentication-agent-1'

# A policy do greeter exige auth_admin em allow_active, o que vira prompt de
# senha logo depois do login — pedindo a senha que acabou de ser digitada.
check "sync do greeter dispensa senha para o wheel" \
    run sh -c 'f=/usr/share/polkit-1/rules.d/50-arkmos-greeter-sync.rules
      grep -q "org.noctalia.greeter.sync-appearance" "$f" \
        || { echo "a regra não cobre a ação do greeter"; exit 1; }
      grep -q "isInGroup(\"wheel\")" "$f" \
        || { echo "a regra não restringe ao grupo wheel"; exit 1; }'

# O systemd --user arranca antes de qualquer login shell e é quem inicia os
# serviços da sessão. /etc/locale.conf não o alcança; environment.d sim.
check "LANG declarado para o systemd --user" \
    run sh -c 'grep -qx "LANG=pt_BR.UTF-8" /usr/lib/environment.d/10-arkmos-locale.conf'

check "arkmos-diag disponível e válido" \
    run sh -c 'test -x /usr/bin/arkmos-diag && bash -n /usr/bin/arkmos-diag'

# --- Aparência -------------------------------------------------------------

# Sem ela cada cliente desenha a própria decoração, e o foot ganha uma barra de
# título branca.
check "niri com prefer-no-csd ativo" \
    run grep -qE '^prefer-no-csd$' /etc/niri/config.kdl

check "foot.ini válido" run foot --check-config

check "foot com titlebar desligada" \
    run sh -c 'grep -qx "preferred=none" /etc/xdg/foot/foot.ini'

# As strings do banco compilado são legíveis: prova que o 'dconf update' rodou
# e que o valor entrou.
check "banco do dconf compilado com tema escuro" \
    run sh -c 'test -s /etc/dconf/db/local &&
               grep -q prefer-dark /etc/dconf/db/local &&
               grep -q adw-gtk3-dark /etc/dconf/db/local'

# Sem o profile, o banco compilado é simplesmente ignorado pelo dconf.
check "profile do dconf inclui o banco do sistema" \
    run sh -c 'grep -qx "system-db:local" /etc/dconf/profile/user'

# Legível, e não só compilado: ilegível é o mesmo que ausente.
check "valores do dconf legíveis" \
    run sh -c 'DCONF_PROFILE=user dconf read /org/gnome/desktop/interface/color-scheme 2>/dev/null | grep -q prefer-dark'

# Firefox e Electron perguntam pelo tema neste backend; no do GNOME, sem sessão
# GNOME, ninguém responde e todos caem no claro.
check "portal de Settings apontado para o backend gtk" \
    run sh -c 'grep -qx "org.freedesktop.impl.portal.Settings=gtk;" /etc/xdg-desktop-portal/niri-portals.conf'

# O tema do VS Code não é alcançado por portal nem variável: o settings.json é
# semeado pelo /etc/skel.
check "defaults do VS Code semeados no /etc/skel" \
    run python3 -c '
import json
c = json.load(open("/etc/skel/.config/Code/User/settings.json"))
assert c.get("window.autoDetectColorScheme") is True, "não segue o tema do sistema"
assert c.get("update.mode") == "none", "auto-update ligado numa imagem read-only"
'

# Caminho sem portal nem D-Bus: se o portal não subir, o GTK3 acha o tema aqui.
check "tema GTK declarado também fora do dconf" \
    run sh -c 'grep -qx "gtk-theme-name=adw-gtk3-dark" /etc/xdg/gtk-3.0/settings.ini && grep -qx "gtk-application-prefer-dark-theme=1" /etc/xdg/gtk-3.0/settings.ini'

# Nome de tema inexistente não dá erro, o GTK cai no fallback. As pastas em
# violeta são symlinks repontados no build.
check "ícones Papirus-Dark, com as pastas em violeta" \
    run sh -c 'test -f /usr/share/icons/Papirus-Dark/index.theme &&
               grep -qx "gtk-icon-theme-name=Papirus-Dark" /etc/xdg/gtk-3.0/settings.ini &&
               grep -qx "gtk-icon-theme-name=Papirus-Dark" /etc/xdg/gtk-4.0/settings.ini &&
               DCONF_PROFILE=user dconf read /org/gnome/desktop/interface/icon-theme | grep -q "Papirus-Dark" &&
               test "$(readlink /usr/share/icons/Papirus/64x64/places/folder.svg)" = folder-violet.svg &&
               test "$(readlink /usr/share/icons/Papirus/48x48/places/user-home.svg)" = user-violet-home.svg'

# Cada lugar alcança uma classe de programa. Nome inexistente não dá erro: o
# programa cai no cursor padrão, e o sistema fica com dois cursores.
check "cursor Bibata-Modern-Ice instalado e declarado nos cinco lugares" \
    run sh -c 'c=Bibata-Modern-Ice
               test -f /usr/share/icons/$c/index.theme && test -e /usr/share/icons/$c/cursors/left_ptr ||
                   { echo "tema $c não instalado"; exit 1; }
               grep -qx "gtk-cursor-theme-name=$c" /etc/xdg/gtk-3.0/settings.ini || { echo "gtk-3.0"; exit 1; }
               grep -qx "gtk-cursor-theme-name=$c" /etc/xdg/gtk-4.0/settings.ini || { echo "gtk-4.0"; exit 1; }
               DCONF_PROFILE=user dconf read /org/gnome/desktop/interface/cursor-theme | grep -qx "'"'"'$c'"'"'" ||
                   { echo "dconf"; exit 1; }
               grep -qx "    xcursor-theme \"$c\"" /etc/niri/config.kdl || { echo "niri"; exit 1; }
               grep -qx "theme = \"$c\"" /usr/share/arkmos/noctalia-greeter.toml || { echo "greeter"; exit 1; }'

# O parser do greetd recusa o que o tomllib aceita (string multilinha com barra
# no fim, por exemplo), então quem valida é o greetd. Sem VT ele falha ao abrir
# o terminal, e chegar até ali prova que o config foi lido.
check "greetd consegue ler o próprio config" \
    run sh -c '
        saida=$(greetd --config /etc/greetd/config.toml 2>&1)
        case "$saida" in
            *"unable to open"*|*"unable to reset VT"*) exit 0 ;;
            *) echo "$saida" | head -3; exit 1 ;;
        esac
    '

check "script da tela de login é executável" \
    run test -x /usr/libexec/arkmos-greeter

# OnFailure apontando para unit inexistente é aceito em silêncio.
check "fallback de login ligado ao greetd" \
    run sh -c '
        grep -q "^OnFailure=arkmos-login-fallback.service$" \
            /usr/lib/systemd/system/greetd.service.d/50-arkmos-fallback.conf \
            || { echo "o drop-in do greetd não aponta para o fallback"; exit 1; }
        test -e /usr/lib/systemd/system/arkmos-login-fallback.service \
            || { echo "a unit de fallback não existe"; exit 1; }
    '

# Sem tty o tuigreet estoura antes de reclamar da flag, e sai com 0: as flags
# são conferidas contra o --help.
check "opções do tuigreet existem nesta versão" \
    run python3 -c '
import re, subprocess, sys
script = open("/usr/libexec/arkmos-greeter").read()
corpo = script.split("exec tuigreet", 1)[1]   # ignora o cabeçalho de comentários
usadas = set(re.findall(r"(?<!\S)--[a-z][a-z0-9-]*", corpo))
ajuda = subprocess.run(["tuigreet", "--help"], capture_output=True, text=True)
conhecidas = ajuda.stdout + ajuda.stderr
faltando = sorted(f for f in usadas if f not in conhecidas)
if faltando:
    sys.exit("tuigreet nao reconhece: " + ", ".join(faltando))
'

# --- Tela de login gráfica ---------------------------------------------------

check "binários do Noctalia Greeter instalados" \
    run sh -c 'for b in noctalia-greeter noctalia-greeter-session noctalia-greeter-compositor noctalia-greeter-apply-appearance; do
        test -x "/usr/bin/$b" || { echo "falta /usr/bin/$b"; exit 1; }
    done'

# -devel na imagem final é sinal de que o COPY --from virou um dnf install.
check "toolchain de compilação ficou fora da imagem" \
    sh -c '! podman run --rm "'"$IMAGE"'" sh -c "rpm -q meson gcc-c++ wlroots-devel >/dev/null 2>&1"'

check "wlroots de runtime presente" run rpm -q wlroots

# O do upstream usa o usuário 'greeter', que não existe no Fedora: o estado do
# greeter deixaria de ser criado e o login falharia.
check "tmpfiles.d do upstream substituído pelo nosso" \
    run sh -c '
        test ! -e /usr/lib/tmpfiles.d/noctalia-greeter.conf \
            || { echo "o tmpfiles.d do upstream voltou para a imagem"; exit 1; }
        grep -q "d /var/lib/noctalia-greeter 0750 greetd greetd" /usr/lib/tmpfiles.d/arkmos.conf \
            || { echo "a declaração corrigida não está no arkmos.conf"; exit 1; }
    '

check "greeter.toml entregue pelo tmpfiles" \
    run sh -c 'grep -q "^C /var/lib/noctalia-greeter/greeter.toml" /usr/lib/tmpfiles.d/arkmos.conf &&
               test -s /usr/share/arkmos/noctalia-greeter.toml'

# Faltando um papel da paleta, o greeter descarta a semente em silêncio e o
# login volta ao tema embutido (§26.1).
check "aparência inicial do login semeada e completa" \
    run python3 -c '
import os, re, tomllib
assert re.search(r"^C /var/lib/noctalia-greeter/sync.toml .* /usr/share/arkmos/noctalia-greeter-sync.toml$",
                 open("/usr/lib/tmpfiles.d/arkmos.conf").read(), re.M), "sync.toml não é entregue pelo tmpfiles"
a = tomllib.load(open("/usr/share/arkmos/noctalia-greeter-sync.toml", "rb"))["appearance"]
g = tomllib.load(open("/usr/share/arkmos/noctalia-greeter.toml", "rb"))["appearance"]
assert a["scheme"] == g["scheme"] == "Synced", "o login não seleciona a paleta semeada"
papeis = ["on_" + p for p in ("primary", "secondary", "tertiary", "error", "surface", "surface_variant", "hover")] + \
         ["primary", "secondary", "tertiary", "error", "surface", "surface_variant", "hover", "outline", "shadow"]
faltam = [p for p in papeis if not re.fullmatch(r"#[0-9A-Fa-f]{6}", a["palette"].get(p, ""))]
assert not faltam, "paleta incompleta: " + ", ".join(faltam)
assert os.path.isfile(a["wallpaper"]["path"]), "papel de parede do login não existe: " + a["wallpaper"]["path"]
'

# Valor inválido aqui não dá erro. O teclado importa mais: na senha do login
# não há retorno visual do que foi digitado.
check "greeter.toml declara sessão e teclado do Arkmos" \
    run python3 -c '
import tomllib
c = tomllib.load(open("/usr/share/arkmos/noctalia-greeter.toml", "rb"))
assert c["session"]["default"] == "Niri", "sessão padrão não é Niri"
assert c["keyboard"]["layout"] == "br", "teclado do login não é br"
assert c["appearance"]["theme_mode"] == "dark", "login não está em tema escuro"
'

# Sessão sem .desktop vira opção que não abre nada.
check "sessão padrão do greeter existe como .desktop" \
    run python3 -c '
import tomllib, pathlib, re
nome = tomllib.load(open("/usr/share/arkmos/noctalia-greeter.toml", "rb"))["session"]["default"]
nomes = []
for p in pathlib.Path("/usr/share/wayland-sessions").glob("*.desktop"):
    for linha in p.read_text().splitlines():
        if linha.startswith("Name="):
            nomes.append(linha[5:].strip())
assert nome in nomes, f"sessao {nome!r} nao esta em {nomes}"
'

# Recuperação: uma linha no config do greetd devolve o login pelo tuigreet.
check "greeter de console mantido como recuperação" \
    run sh -c 'test -x /usr/libexec/arkmos-greeter && rpm -q tuigreet >/dev/null'

# --- Boot ------------------------------------------------------------------

check "tema padrão do Plymouth é o do Arkmos" \
    run sh -c 't=$(plymouth-set-default-theme); [ "$t" = arkmos ] || { echo "tema padrão é $t"; exit 1; }'

# Render pela metade não quebra nada: o two-step desenha só o fundo.
check "tema do Plymouth completo" \
    run sh -c '
        d=/usr/share/plymouth/themes/arkmos
        grep -qx "ImageDir=$d" "$d/arkmos.plymouth" \
            || { echo "ImageDir não aponta para $d"; exit 1; }
        for f in watermark.png throbber-0001.png animation-0001.png entry.png bullet.png lock.png; do
            test -s "$d/$f" || { echo "falta $d/$f"; exit 1; }
        done
    '

# O plymouthd usa o tema do initramfs, não o de /usr (§27.2). Regerar troca um
# arquivo da base: sem o módulo ostree não há boot, e o /root precisa do
# var/roothome que o Containerfile cria para o dracut.
check "initramfs regerado com o tema, o ostree e o ABNT2" \
    run sh -c '
        img=$(ls /usr/lib/modules/*/initramfs.img)
        lista=$(lsinitrd "$img" 2>/dev/null)
        printf "%s\n" "$lista" | grep -q "usr/share/plymouth/themes/arkmos/watermark.png$" \
            || { echo "tema do Arkmos fora do initramfs"; exit 1; }
        printf "%s\n" "$lista" | grep -q " var/roothome$" \
            || { echo "o /root do initramfs ficou sem destino (var/roothome)"; exit 1; }
        lsinitrd -f etc/plymouth/plymouthd.conf "$img" 2>/dev/null | grep -qx "Theme=arkmos" \
            || { echo "o plymouthd.conf do initramfs não aponta para o arkmos"; exit 1; }
        lsinitrd -m "$img" 2>/dev/null | grep -qx ostree \
            || { echo "módulo ostree ausente do initramfs"; exit 1; }
        lsinitrd -f etc/vconsole.conf "$img" 2>/dev/null | grep -q "^KEYMAP=br" \
            || { echo "teclado do initramfs não é br"; exit 1; }
    '

# --- Wallpaper ---------------------------------------------------------------

# O Noctalia só lê config do home, e caminho errado não dá erro: o fundo sobe
# vazio.
check "wallpaper padrão semeado para o Noctalia" \
    run python3 -c '
import tomllib, os
c = tomllib.load(open("/etc/skel/.config/noctalia/arkmos.toml", "rb"))
p = c["wallpaper"]["default"]["path"]
assert os.path.getsize(p) > 0, f"{p} vazio"
assert c["shell"]["greeter_sync"]["auto_sync"] is True, "auto-sync do greeter desligado"

# A lista entra nas subpastas; extensões as do directory_scanner.cpp do
# Noctalia (o papel do Fedora vem em .jxl).
d = c["wallpaper"]["directory"].rstrip("/")
assert os.path.isdir(d), f"{d} não existe"
assert p.startswith(d + "/"), f"o padrão {p} está fora de {d}"
ext = (".jpg", ".jpeg", ".png", ".webp", ".jxl", ".bmp", ".gif")
def imagens(sub):
    return [f for _, _, fs in os.walk(os.path.join(d, sub)) for f in fs if f.lower().endswith(ext)]
versao = "f" + open("/etc/os-release").read().split("VERSION_ID=")[1].split()[0].strip("\"")
for sub, minimo in (("arkmos", 2), ("fedora-workstation", 2), (versao, 1)):
    n = len(imagens(sub))
    assert n >= minimo, f"só {n} imagem(ns) em {d}/{sub}"

# O validador do Noctalia aceita qualquer nome de esquema.
t = c["theme"]
assert t["source"] == "builtin", "fonte da paleta: " + str(t["source"])
assert t["builtin"] == "Tokyo-Night", "esquema: " + str(t["builtin"])
assert t["mode"] == "dark", "modo: " + str(t["mode"])

# Zero deixa a interface quadrada e o login desalinhado do desktop.
assert c["shell"]["corner_radius_scale"] > 0, "arredondamento do shell zerado"

# Notificações: os dois padrões do Noctalia que significam "sem limite".
n = c["notification"]
assert n["max_visible"] > 0, "toasts sem limite na tela"
assert n["history_retention_hours"] > 0, "histórico de notificações guardado para sempre"
assert n["filter"]["spotify"]["show_toast"] is False, "o Spotify volta a notificar cada música"
'

# O Noctalia é o daemon de notificações; o mako seria um segundo, parado.
check "um só daemon de notificações" \
    run sh -c '
        grep -q -a org.freedesktop.Notifications /usr/bin/noctalia \
            || { echo "o Noctalia não implementa mais o barramento de notificações"; exit 1; }
        ! rpm -q mako >/dev/null 2>&1 || { echo "o mako voltou para a imagem"; exit 1; }
    '

# Nome de esquema desconhecido cai no padrão sem aviso.
check "esquema Tokyo-Night existe no Noctalia" \
    run sh -c 'grep -q -a Tokyo-Night /usr/bin/noctalia'

# Sem a permissão o sandbox não vê o gtk.css da conta, e o Flatpak fica com as
# cores do runtime.
check "Flatpaks podem ler o tema da conta" \
    run sh -c '
        grep -q "^filesystems=.*xdg-config/gtk-3.0:ro" /usr/share/arkmos/flatpak-overrides/global \
            && grep -q "^filesystems=.*xdg-config/gtk-4.0:ro" /usr/share/arkmos/flatpak-overrides/global \
            && grep -q "^filesystems=.*xdg-config/kdeglobals:ro" /usr/share/arkmos/flatpak-overrides/global \
            || { echo "override sem acesso a gtk-3.0, gtk-4.0 ou kdeglobals"; exit 1; }
        grep -q "^C /var/lib/flatpak/overrides/global .* /usr/share/arkmos/flatpak-overrides/global$" \
            /usr/lib/tmpfiles.d/arkmos.conf \
            || { echo "o tmpfiles não copia o override para /var"; exit 1; }
    '

# Sem ela os aplicativos libadwaita ficam no azul padrão.
check "cor de destaque roxa no dconf" \
    run sh -c 'grep -q "purple" /etc/dconf/db/local && DCONF_PROFILE=user dconf read /org/gnome/desktop/interface/accent-color | grep -q purple'

# Os templates de foot e niri criam config na conta, que esses programas leem
# NO LUGAR da do sistema — o de niri apagaria os atalhos desta imagem.
check "templates de paleta: certos ligados, perigosos fora" \
    run python3 -c '
import tomllib
c = tomllib.load(open("/etc/skel/.config/noctalia/arkmos.toml", "rb"))
ids = set(c["theme"]["templates"]["builtin_ids"])
esperados = {"gtk3", "gtk4", "btop", "kcolorscheme"}
assert esperados <= ids, "faltando: " + str(esperados - ids)
proibidos = ids & {"foot", "niri"}
assert not proibidos, "template que sobrescreve config do sistema: " + ", ".join(sorted(proibidos))
'

# O padrão do niri é um azul claro de esquema nenhum.
check "anel de foco do niri no roxo do Tokyo Night" \
    run sh -c '
        grep -q "^ *active-gradient .*to=\"#bb9af7\"" /etc/niri/config.kdl \
            || { echo "o gradiente do anel de foco não termina no roxo do esquema"; exit 1; }
        grep -q "^ *active-color \"#bb9af7\"" /etc/niri/config.kdl \
            || { echo "sem a cor de reserva do anel de foco"; exit 1; }
    '

# O clip-to-geometry é o par do geometry-corner-radius: sem ele o arredondamento
# fica só na moldura, e o conteúdo da janela aparece quadrado nos cantos.
check "cantos arredondados com recorte" \
    run sh -c '
        grep -q "^ *geometry-corner-radius " /etc/niri/config.kdl \
            || { echo "sem geometry-corner-radius"; exit 1; }
        grep -q "^ *clip-to-geometry true" /etc/niri/config.kdl \
            || { echo "sem clip-to-geometry"; exit 1; }
    '

# O validate sai com 0 mesmo com chave desconhecida, que o Noctalia ignora:
# decide a saída, não o código de retorno.
check "config semeada do Noctalia é válida e sem avisos" \
    run sh -c '
        saida=$(HOME=/tmp noctalia config validate /etc/skel/.config/noctalia/arkmos.toml 2>&1 | grep -v dconf)
        case "$saida" in
            *WARN*|*ERROR*|*"warning(s)"*) echo "$saida"; exit 1 ;;
            *"Config is valid"*) exit 0 ;;
            *) echo "$saida"; exit 1 ;;
        esac
    '

# O greeter.toml vence o sync.toml: wallpaper ou paleta declarados nele
# congelariam o login no valor antigo, sem erro.
check "greeter.toml não bloqueia o sync da aparência" \
    run python3 -c '
import tomllib
a = tomllib.load(open("/usr/share/arkmos/noctalia-greeter.toml", "rb")).get("appearance", {})
bloqueiam = sorted(k for k in ("wallpaper", "wallpapers", "palette", "corner_radius_scale") if k in a)
assert not bloqueiam, "declarado no greeter.toml: " + ", ".join(bloqueiam)

# Do greeter, e não do sync: sem idle a tela de login nunca apaga.
g = tomllib.load(open("/usr/share/arkmos/noctalia-greeter.toml", "rb"))
assert 0 < g["idle"]["timeout"] <= 86400, "apagamento de tela no login desligado"
assert a.get("password_style") == "random", "máscara de senha não é a aleatória"
assert a.get("hide_logo") is True, "a logo do Noctalia continua na tela de login"
'

# --- Arquivos ----------------------------------------------------------------

# "Mostrar na pasta" do VS Code e do Firefox chama org.freedesktop.FileManager1
# por D-Bus. Sem quem implemente a interface, o clique não faz nada e não dá erro.
check "gerenciador de arquivos atende FileManager1" \
    run sh -c 'rpm -q nautilus gvfs >/dev/null && grep -rqx "Name=org.freedesktop.FileManager1" /usr/share/dbus-1/services/'

# A condição de classe de sessão fazia o systemd PULAR o indexador, e o drop-in
# a zera (§25.1). A segunda parte falha se o upstream mudar a condição, para o
# drop-in não passar a apagar uma legítima.
check "indexador do Nautilus livre da condição de classe" \
    run sh -c '
        f=/usr/lib/systemd/user/localsearch-3.service.d/50-arkmos-classe-de-sessao.conf
        test -e "$f" || { echo "drop-in ausente: $f"; exit 1; }
        grep -qx "ConditionEnvironment=" "$f" \
            || { echo "o drop-in não zera a condição"; exit 1; }
        grep -qx "ConditionEnvironment=XDG_SESSION_CLASS=user" \
            /usr/lib/systemd/user/localsearch-3.service \
            || { echo "o upstream mudou a condição da unit: revisar o drop-in"; exit 1; }
    '

# Escreve no grubenv, e o /boot do bootc é somente leitura: falhava em toda
# sessão.
check "grub-boot-success mascarada" \
    run sh -c '
        for u in grub-boot-success.timer grub-boot-success.service; do
            [ "$(readlink /etc/systemd/user/$u)" = /dev/null ] \
                || { echo "$u não está mascarada"; exit 1; }
        done
    '

# Montar .iso no clique duplo e navegar dentro de um arquivo compactado.
check "Discos e gerenciador de compactação" \
    run sh -c '
        for f in gnome-disk-image-mounter org.gnome.DiskUtility org.gnome.FileRoller; do
            test -e "/usr/share/applications/$f.desktop" || { echo "falta $f.desktop"; exit 1; }
        done
    '

# Sem o cups-pk-helper o assistente abre, mas não cadastra impressora sem root.
check "impressão: assistente, cups-pk-helper e CUPS" \
    run sh -c '
        rpm -q system-config-printer cups-pk-helper >/dev/null \
            || { echo "assistente ou cups-pk-helper ausente"; exit 1; }
        [ "$(systemctl is-enabled cups.socket 2>&1)" = enabled ] \
            || { echo "cups.socket não está habilitado"; exit 1; }
    '

# O assistente de impressão puxa o dbus-daemon, e a troca de barramento não
# daria erro nenhum (§25.2).
check "barramento D-Bus continua no dbus-broker" \
    run sh -c 'readlink -f /etc/systemd/system/dbus.service | grep -q "/dbus-broker.service$" \
        || { echo "dbus.service aponta para $(readlink -f /etc/systemd/system/dbus.service)"; exit 1; }'

# Documentos, Downloads, Imagens… só nascem com a unit habilitada, e em
# português só com o LANG certo.
check "pastas do usuário criadas em português" \
    run sh -c '
        [ "$(systemctl --global is-enabled xdg-user-dirs.service 2>&1)" = enabled ] \
            || { echo "xdg-user-dirs.service não está habilitada para as sessões"; exit 1; }
        mkdir -p /tmp/h
        HOME=/tmp/h LANG=pt_BR.UTF-8 xdg-user-dirs-update \
            && test -d /tmp/h/Documentos && test -d /tmp/h/Imagens \
            || { echo "pastas criadas:"; ls /tmp/h; exit 1; }
    '

# O niri não tem tradução, mas cada linha do overlay de atalhos aceita um
# título próprio. Um bind novo sem título volta a aparecer em inglês.
check "títulos do overlay do niri em português" \
    run python3 -c '
import re
t = open("/etc/niri/config.kdl").read()
acoes = ["show-hotkey-overlay", "quit", "close-window", "focus-column-left", "focus-column-right",
         "move-column-left", "move-column-right", "focus-workspace-down", "focus-workspace-up",
         "move-column-to-workspace-down", "move-column-to-workspace-up", "switch-preset-column-width",
         "maximize-column", "consume-or-expel-window-left", "consume-or-expel-window-right",
         "toggle-window-floating", "switch-focus-between-floating-and-tiling", "toggle-overview", "screenshot"]
binds = [l for l in t.splitlines() if not l.strip().startswith("//")]
faltando = [a for a in acoes if not any(re.search(r"hotkey-overlay-title=\"[^\"]+\".*\{ *" + re.escape(a) + r";", l) for l in binds)]
assert not faltando, "sem título: " + ", ".join(faltando)
'

# --- Aplicativos -----------------------------------------------------------

# O preinstall ignora em silêncio grupo que não entende, e só instala do
# Flathub que a base configura. Cada padrão do mimeapps.list tem de apontar
# para um aplicativo que existe.
check "Flatpaks declarados e padrões coerentes" \
    run python3 -c '
import configparser, os
p = configparser.ConfigParser(interpolation=None)
p.read("/usr/share/flatpak/preinstall.d/arkmos.preinstall")
apps = {}
for s in p.sections():
    assert s.startswith("Flatpak Preinstall "), "grupo inesperado: " + s
    assert p[s].get("branch"), "sem Branch: " + s
    apps[s.split(" ", 2)[2]] = p[s]
assert len(apps) >= 10, "lista curta demais: %d" % len(apps)
tema = apps.get("org.gtk.Gtk3theme.adw-gtk3-dark")
assert tema and tema.get("isruntime") == "true", "sem a extensão de tema GTK3 como runtime"
assert os.path.exists("/etc/flatpak/remotes.d/flathub.flatpakrepo"), "Flathub não configurado pela base"
m = configparser.ConfigParser(interpolation=None, delimiters=("=",))
m.read("/etc/xdg/mimeapps.list")
def existe(a):
    return a in apps or os.path.exists("/usr/share/applications/%s.desktop" % a)
fora = set()
for tipo, valor in m["Default Applications"].items():
    ids = [i.removesuffix(".desktop") for i in valor.split(";") if i]
    assert ids, "tipo sem padrão: " + tipo
    if not any(existe(i) for i in ids):
        fora.add(tipo + "=" + valor)
assert not fora, "padrão que não está nem na lista nem na imagem: " + ", ".join(sorted(fora))
'

# O Noctalia não avisa quando um id fixado no dock não existe: o ícone some.
check "dock fixa só apps que existem" \
    run python3 -c '
import configparser, os, tomllib
p = configparser.ConfigParser(interpolation=None)
p.read("/usr/share/flatpak/preinstall.d/arkmos.preinstall")
apps = {s.split(" ", 2)[2] for s in p.sections()}
with open("/etc/skel/.config/noctalia/arkmos.toml", "rb") as f:
    fixados = tomllib.load(f)["dock"]["pinned"]
assert fixados, "dock sem nada fixado"
fora = [a for a in fixados
        if a not in apps and not os.path.exists("/usr/share/applications/%s.desktop" % a)]
assert not fora, "dock fixa app que não existe: " + ", ".join(fora)
'

# A libfuse.so.2 não vem da base. Sem ela, um AppImage de runtime clássico
# morre com "dlopen(): error loading libfuse.so.2" antes de abrir.
check "AppImage: libfuse.so.2 presente" \
    run sh -c 'test -e /usr/lib64/libfuse.so.2'

# Com os padrões de cada um, as capturas se dividiriam em duas pastas.
check "capturas de tela na mesma pasta, em português" \
    run sh -c '
        grep -q "^screenshot-path \"~/Imagens/Capturas de tela/" /etc/niri/config.kdl \
            || { echo "screenshot-path do niri fora de ~/Imagens/Capturas de tela"; exit 1; }
        grep -qx "directory = \"~/Imagens/Capturas de tela\"" /etc/skel/.config/noctalia/arkmos.toml \
            || { echo "pasta de capturas do Noctalia diferente da do niri"; exit 1; }
        grep -q "Shift+Print .*screenshot-annotate" /etc/niri/config.kdl \
            || { echo "sem atalho para captura com anotação"; exit 1; }
    '

# O que o uso diário pede e a base não traz (§22, §25); cada falta passa em
# silêncio.
check "componentes de uso diário presentes" \
    run sh -c '
        rpm -q gvfs-mtp gvfs-smb gvfs-fuse sushi papers-thumbnailer tailscale \
               nm-connection-editor gcr xdg-terminal-exec btop \
               google-carlito-fonts google-crosextra-caladea-fonts >/dev/null \
            || { rpm -q gvfs-mtp gvfs-smb gvfs-fuse sushi papers-thumbnailer tailscale \
                        nm-connection-editor gcr xdg-terminal-exec btop \
                        google-carlito-fonts google-crosextra-caladea-fonts | grep "not installed"; exit 1; }
        ! rpm -q htop >/dev/null 2>&1 || { echo "o htop deveria ter saído"; exit 1; }
        grep -qx foot.desktop /etc/xdg/xdg-terminals.list || { echo "foot não é o terminal padrão"; exit 1; }
    '

# A config de exemplo do niri apontava para fuzzel e swaylock.
check "lançador e bloqueio nos atalhos do Noctalia" \
    run sh -c '
        grep -q "^ *Mod+D .*spawn \"noctalia\" \"msg\" \"panel-toggle\" \"launcher\"" /etc/niri/config.kdl \
            || { echo "Mod+D não abre o lançador do Noctalia"; exit 1; }
        grep -q "^ *Super+Alt+L .*\"session\" \"lock\"" /etc/niri/config.kdl \
            || { echo "sem atalho de bloqueio"; exit 1; }
        ! grep -q "^ *[^/]*spawn \"fuzzel\"" /etc/niri/config.kdl || { echo "ainda há atalho para o fuzzel"; exit 1; }
    '

# Servidor e cliente do foot, e o Noctalia, que clicado não faz nada.
check "menu sem entradas que não abrem nada" \
    run sh -c '
        for f in foot-server footclient dev.noctalia.Noctalia; do
            grep -qx "NoDisplay=true" "/usr/share/applications/$f.desktop" \
                || { echo "$f.desktop continua no menu"; exit 1; }
        done
        grep -q "^Exec=.*noctalia msg settings-open" /usr/share/applications/arkmos-noctalia-settings.desktop \
            || { echo "sem a entrada das configurações do Noctalia"; exit 1; }
    '

# A sessão não lê o /etc/profile.d: sem isto o clique duplo num arquivo aberto
# por Flatpak não faz nada (§25).
check "sessão enxerga os Flatpaks (XDG_DATA_DIRS)" \
    run sh -c '
        v=$(sed -n "s/^XDG_DATA_DIRS=//p" /usr/lib/environment.d/20-arkmos-flatpak.conf)
        case "$v" in
            *"/var/lib/flatpak/exports/share"*) ;;
            *) echo "sem a instalação de sistema do Flatpak: $v"; exit 1 ;;
        esac
        case "$v" in
            *"flatpak/exports/share:"*"/usr/share") ;;
            *) echo "XDG_DATA_DIRS não termina nos diretórios padrão: $v"; exit 1 ;;
        esac
    '

# O Noctalia SUBSTITUI o bloco de cada ação em vez de mesclar: conferida a
# config efetiva, e não o arquivo.
check "bloqueio por inatividade ligado para conta nova" \
    run sh -c '
        mkdir -p /tmp/h/.config && cp -r /etc/skel/.config/noctalia /tmp/h/.config/
        HOME=/tmp/h noctalia config export full 2>/dev/null > /tmp/efetivo.toml
        python3 /dev/stdin <<PY
import tomllib
c = tomllib.load(open("/tmp/efetivo.toml", "rb"))
b = c["idle"]["behavior"]
for nome, acao in (("lock", "lock"), ("screen-off", "screen_off")):
    assert b[nome]["enabled"] is True, nome + ": desligado"
    assert b[nome]["action"] == acao, nome + ": ação " + repr(b[nome]["action"])
    assert b[nome]["timeout"] > 0, nome + ": tempo zerado"
PY
    '

# --- tmpfiles --------------------------------------------------------------

# O dry-run resolve usuários e grupos de verdade.
check "tmpfiles.d do Arkmos resolve usuários e grupos" \
    run systemd-tmpfiles --dry-run --create /usr/lib/tmpfiles.d/arkmos.conf

# --- Pacotes ---------------------------------------------------------------

check "pacotes essenciais instalados" \
    run rpm -q docker-ce docker-compose-plugin niri noctalia greetd tuigreet code zsh gh

# Vêm da base, que o ublue vem podando: afirmar aqui faz a falta virar build
# vermelho, e não sessão quebrada na máquina.
check "componentes herdados da base presentes" \
    run rpm -q podman distrobox NetworkManager pipewire wireplumber bluez \
    flatpak plymouth wl-clipboard

# Shim de 'docker' para o podman: proibido (§15).
check "podman-docker ausente" \
    sh -c '! podman run --rm "'"$IMAGE"'" rpm -q podman-docker >/dev/null 2>&1'

# --- Serviços --------------------------------------------------------------

check "serviços habilitados" \
    run sh -c '
        for u in arkmos-firstboot.service arkmos-flatpak-preinstall.service tailscaled.service docker.service greetd.service; do
            state=$(systemctl is-enabled "$u" 2>&1)
            [ "$state" = enabled ] || { echo "$u esta \"$state\""; exit 1; }
        done
    '

# Um aviso de depreciação sai em cima do prompt de todo terminal, e o
# --check-config sai com 0 mesmo avisando: reprova a saída. O de locale é do
# container.
check "configuração do foot sem avisos" \
    run sh -c '
        saida=$(foot --check-config -c /etc/xdg/foot/foot.ini 2>&1 | grep -v "is not a UTF-8 locale")
        if [ -n "$saida" ]; then
            echo "$saida"
            exit 1
        fi
    '

# Receita que aponta para fora desta imagem não dá erro de build, dá erro na mão
# de quem usa (§31.2).
check "menu do ujust recortado e com as receitas do Arkmos" \
    run sh -c '
        menu=$(JUST_JUSTFILE=/usr/share/ublue-os/justfile just --list)
        for r in arkmos-diag arkmos-apply-defaults arkmos-variant; do
            echo "$menu" | grep -qE "^ *$r( |$)" \
                || { echo "$r não está no menu"; exit 1; }
        done
        for r in toggle-nvk install-resolve configure-broadcom-wl setup-distrobox-app; do
            if echo "$menu" | grep -qE "^ *$r( |$)"; then
                echo "$r continua no menu"; exit 1
            fi
        done
        for r in update bios check-local-overrides enroll-secure-boot-key; do
            echo "$menu" | grep -qE "^ *$r( |$)" \
                || { echo "o recorte levou $r junto"; exit 1; }
        done
    '

# Vem da base, não do Arkmos (§31.1): uma reconstrução dela poderia parar as
# atualizações, ou passar a reiniciar sozinha (bootc-fetch-apply).
check "atualização automática no modo encenado" \
    run sh -c '
        grep -qx "AutomaticUpdatePolicy=stage" /etc/rpm-ostreed.conf \
            || { echo "política de atualização não é \"stage\":"; \
                 grep -v "^#" /etc/rpm-ostreed.conf; exit 1; }
        for u in rpm-ostreed-automatic.timer flatpak-system-update.timer; do
            state=$(systemctl is-enabled "$u" 2>&1)
            [ "$state" = enabled ] || { echo "$u esta \"$state\""; exit 1; }
        done
        state=$(systemctl is-enabled bootc-fetch-apply-updates.timer 2>&1)
        [ "$state" = disabled ] \
            || { echo "bootc-fetch-apply-updates.timer esta \"$state\": reiniciaria sozinho"; exit 1; }
    '

# Chave sem entrada na política não verifica nada; entrada sem chave faz TODO
# pull falhar.
check "política de assinatura coerente" \
    run sh -c '
        if [ -f /etc/pki/containers/arkmos.pub ]; then
            grep -q arkmos.pub /etc/containers/policy.json \
                || { echo "chave presente, mas sem entrada na política"; exit 1; }
            test -f /etc/containers/registries.d/arkmos.yaml \
                || { echo "chave presente, mas sem registries.d"; exit 1; }
        else
            grep -q arkmos.pub /etc/containers/policy.json \
                && { echo "política aponta para uma chave que não existe"; exit 1; }
            test ! -e /etc/containers/registries.d/arkmos.yaml \
                || { echo "registries.d sobrou sem chave"; exit 1; }
        fi
        exit 0
    '

# O primeiro boot reaplica os presets: a coluna PRESET é o que vale (§22).
check "servidor SSH desligado, também no preset" \
    run sh -c '
        estado=$(systemctl list-unit-files --no-legend sshd.service | awk "{print \$2, \$3}")
        [ "$estado" = "disabled disabled" ] || { echo "sshd.service: estado e preset = $estado"; exit 1; }
    '

# A 'public' da base bloqueia o LocalSend e servidor de dev, sem avisar.
check "firewall na zona FedoraWorkstation" \
    run sh -c '[ "$(firewall-offline-cmd --get-default-zone 2>/dev/null)" = FedoraWorkstation ]'

# Sem agente SSH, cada 'git push' pede a senha da chave e o VS Code falha.
check "agente SSH do gcr habilitado para as sessões" \
    run sh -c '[ "$(systemctl --global is-enabled gcr-ssh-agent.socket 2>&1)" = enabled ]'

check "greetd é o display-manager" \
    run sh -c 'readlink /etc/systemd/system/display-manager.service | grep -q greetd'

# --- Variante --------------------------------------------------------------
#
# Um build-arg errado daria duas imagens iguais, e nada mais aqui notaria.

case "$VARIANT" in
nvidia)
    check "pilha NVIDIA presente" \
        run rpm -q kmod-nvidia nvidia-driver nvidia-container-toolkit

    check "drop-in do CDI aplicado" \
        run test -e /usr/lib/systemd/system/nvidia-cdi-refresh.service.d/50-arkmos-gpu-presente.conf

    check "perfil NVIDIA para compositores Wayland" \
        run test -e /etc/nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json
    ;;
base)
    check "sem pilha NVIDIA" \
        sh -c '! podman run --rm "'"$IMAGE"'" rpm -q kmod-nvidia >/dev/null 2>&1'

    # Se sobrarem, a limpeza condicional do Containerfile deixou de rodar.
    check "configuração do driver removida" \
        run sh -c '
                for p in /usr/lib/systemd/system/nvidia-cdi-refresh.service.d /etc/nvidia; do
                    [ ! -e "$p" ] || { echo "$p ficou na imagem"; exit 1; }
                done
            '
    ;;
*)
    echo "  AVISO: imagem sem label org.arkmos.variant; verificações"
    echo "         específicas de variante não foram executadas."
    FAILED=1
    ;;
esac

# --- Terminal --------------------------------------------------------------

# O stderr do mise é aviso de home não gravável, do container.
check "binários upstream instalados e executáveis" \
    run sh -c 'starship --version >/dev/null &&
               lazygit --version >/dev/null &&
               lazydocker --version >/dev/null &&
               mise --version >/dev/null 2>/dev/null'

# O mise atualiza com a imagem (§17.2): sem aviso de versão nova nem
# self-update, que falharia em /usr.
check "mise sem self-update nem aviso de versão nova" \
    run sh -c '
        export HOME=/tmp
        [ "$(mise settings get disable_update_warning 2>/dev/null)" = true ] \
            || { echo "o aviso de versão nova continua ligado"; exit 1; }
        mise self-update --yes 2>&1 | grep -q "package manager, cannot update" \
            || { echo "o self-update continua disponível"; exit 1; }
    '

# Nome inexistente não dá erro: o fontconfig troca em silêncio, e cada parte
# fica com uma fonte (§14).
check "fonte da interface Adwaita Sans, instalada e declarada nos cinco lugares" \
    run sh -c 'f="Adwaita Sans"
               fc-match "$f" | grep -q "\"$f\"" || { echo "$f não está instalada"; exit 1; }
               grep -qx "gtk-font-name=$f 11" /etc/xdg/gtk-3.0/settings.ini || { echo "gtk-3.0"; exit 1; }
               grep -qx "gtk-font-name=$f 11" /etc/xdg/gtk-4.0/settings.ini || { echo "gtk-4.0"; exit 1; }
               DCONF_PROFILE=user dconf read /org/gnome/desktop/interface/font-name | grep -qx "'"'"'$f 11'"'"'" ||
                   { echo "dconf"; exit 1; }
               grep -qx "font_family = \"$f\"" /etc/skel/.config/noctalia/arkmos.toml || { echo "noctalia"; exit 1; }
               grep -qx "font_family = \"$f\"" /usr/share/arkmos/noctalia-greeter.toml || { echo "greeter"; exit 1; }'

check "Nerd Font patched presente" \
    run sh -c '
        fc-list | grep -q "JetBrainsMono Nerd Font" \
            || { echo "JetBrainsMono Nerd Font ausente"; exit 1; }
        grep -qx "font=JetBrainsMono Nerd Font:size=11" /etc/xdg/foot/foot.ini \
            || { echo "o terminal não está na JetBrainsMono Nerd Font"; exit 1; }
        grep -qx "alpha=0.9" /etc/xdg/foot/foot.ini \
            || { echo "o terminal perdeu a translucidez"; exit 1; }
        grep -q "JetBrainsMono Nerd Font" /etc/dconf/db/local \
            || { echo "monospace-font-name não chegou ao banco do dconf"; exit 1; }
        python3 -c "
import json
c = json.load(open(\"/etc/skel/.config/Code/User/settings.json\"))
assert c[\"editor.fontLigatures\"] is True, \"ligaduras desligadas no VS Code\"
assert \"JetBrainsMonoNL\" not in c[\"editor.fontFamily\"], \"a família NL não tem ligaduras\"
"
    '

# Sem rede de propósito (§13.2). Sem tty não há zle, e o syntax-highlighting é
# conferido pela variável, não pelos widgets.
check "config do zsh carrega inteira sem rede" \
    sh -c 'podman run --rm --network=none "'"$IMAGE"'" zsh -ic "
        (( \$+functions[_zsh_autosuggest_start] )) || { print -u2 \"zsh-autosuggestions não carregou\"; exit 1; }
        [[ -n \$ZSH_HIGHLIGHT_HIGHLIGHTERS ]]      || { print -u2 \"zsh-syntax-highlighting não carregou\"; exit 1; }
        alias ll >/dev/null                        || { print -u2 \"aliases.zsh não carregou\"; exit 1; }
        (( \$+functions[compdef] ))                || { print -u2 \"completion.zsh não carregou\"; exit 1; }
        [[ -n \$STARSHIP_CONFIG ]]                 || { print -u2 \"tools.zsh não carregou\"; exit 1; }
        [[ \$HISTSIZE -ge 10000 ]]                 || { print -u2 \"history.zsh não carregou\"; exit 1; }
        [[ \$EDITOR == *nvim ]]                     || { print -u2 \"EDITOR é \$EDITOR, esperado nvim\"; exit 1; }
    " 2>&1'

# No zsh o Fedora só põe ~/.local/bin no PATH pelo ~/.zprofile, que o foot não
# lê (§13.1).
check "zsh põe ~/.local/bin no PATH" \
    sh -c 'podman run --rm --network=none -e HOME=/tmp "'"$IMAGE"'" zsh -ic "
        [[ \":\$PATH:\" == *:/tmp/.local/bin:* ]] || { print -u2 \"sem ~/.local/bin: \$PATH\"; exit 1; }
    " 2>&1'

# Uma linha só no tools.zsh, fácil de perder. HOME=/tmp porque o /root da
# imagem só nasce no boot.
check "zsh ativa o mise" \
    sh -c 'podman run --rm --network=none -e HOME=/tmp "'"$IMAGE"'" zsh -ic "
        [[ \$MISE_SHELL == zsh ]]             || { print -u2 \"MISE_SHELL=\$MISE_SHELL, esperado zsh\"; exit 1; }
        (( \$+functions[mise] ))              || { print -u2 \"a função mise não foi definida\"; exit 1; }
        (( \$+functions[_mise_hook_precmd] )) || { print -u2 \"hook de precmd do mise ausente\"; exit 1; }
        [[ \$PATH == *mise/shims* ]]          || { print -u2 \"shims do mise fora do PATH\"; exit 1; }
    " 2>&1'

# A outra ponta do MISE_SHELL=zsh acima (§17.2). Com -l: o bash não-login só
# chega ao profile.d pelo ~/.bashrc do skel, afirmado a seguir.
check "bash ativa o mise" \
    sh -c 'podman run --rm --network=none -e HOME=/tmp "'"$IMAGE"'" bash -lic "
        [[ \$MISE_SHELL == bash ]] || { echo \"MISE_SHELL=\$MISE_SHELL, esperado bash\" >&2; exit 1; }
        declare -F mise >/dev/null || { echo \"a função mise não foi definida\" >&2; exit 1; }
        [[ \$(declare -p PROMPT_COMMAND 2>/dev/null) == *_mise_hook* ]] \
            || { echo \"hook do mise fora do PROMPT_COMMAND\" >&2; exit 1; }
    " 2>&1'

# Sem esta linha, um bash aberto no terminal fica sem o mise.
check "skel liga o bash ao profile.d" \
    run sh -c 'grep -q "\. /etc/bashrc" /etc/skel/.bashrc'

# A conta do Anaconda não passa --shell e cai neste padrão.
check "useradd sem --shell cria a conta no zsh" \
    run sh -c 'useradd -D | grep -qx SHELL=/usr/bin/zsh'

# O ~/.zshrc da conta é lido depois da config da imagem, e vence (§13.1).
zsh_zshrc_da_conta() {
    podman run --rm -i --network=none -e HOME=/tmp "$IMAGE" sh -s <<'SCRIPT'
if grep -q ZDOTDIR /etc/zshenv; then echo "/etc/zshenv ainda define ZDOTDIR"; exit 1; fi
cp /etc/skel/.zshrc /tmp/.zshrc
echo 'alias ll="echo da-conta"' >> /tmp/.zshrc
cd /tmp
zsh -ic '
    (( $+functions[_zsh_autosuggest_start] )) || { print -u2 "a config da imagem não carregou"; exit 1; }
    [[ $(ll) == da-conta ]]                   || { print -u2 "o ~/.zshrc da conta não venceu"; exit 1; }
'
SCRIPT
}
check "zsh lê a config da imagem e depois o ~/.zshrc" zsh_zshrc_da_conta

# Prova que o starship achou o arquivo e que o TOML é válido: inválido, ele cai
# no default em silêncio. ('starship config' abre o $EDITOR e pendura.)
check "starship.toml da imagem é lido e parseado" \
    run sh -c "STARSHIP_CONFIG=/usr/share/arkmos/starship.toml starship print-config 2>/dev/null | grep -qF '\$directory\$git_branch\$git_state\$git_status'"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "Todas as verificações passaram."
else
    echo "Há verificações falhando." >&2
fi
exit "$FAILED"
