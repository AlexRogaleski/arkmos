#!/usr/bin/env bash
#
# Verificações da imagem do Arkmos.
#
#   ./tests/check-image.sh localhost/arkmos:dev
#
# Um script só, usado pelo 'just check' e pelo CI. Antes as duas listas eram
# mantidas à mão em lugares separados e já divergiam — o que significa que uma
# verificação nova valia num fluxo e não no outro.
#
# O critério para entrar aqui é ser um erro que a imagem consegue esconder:
# algo que constrói, passa no lint e só aparece como falha no boot da máquina.

set -uo pipefail

IMAGE="${1:-localhost/arkmos:dev}"
FAILED=0

# A variante vem do label que o Containerfile grava, e não do nome da imagem:
# o nome é convenção do Justfile e do CI, o label é o que a máquina instalada
# consegue consultar depois.
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
    [[ "$rc" -eq 0 ]] || { echo "$path nao existe na imagem"; return 1; }
    if [[ "$(tr -d '[:space:]' <<< "$content")" != "$expected" ]]; then
        echo "$path contem \"$content\", esperado \"$expected\""
        return 1
    fi
}

check() {
    local desc="$1"; shift
    printf '  %-52s' "$desc"
    local out
    if out="$("$@" 2>&1)"; then
        echo "ok"
    else
        echo "FALHOU"
        [[ -n "$out" ]] && sed 's/^/      /' <<< "$out"
        FAILED=1
    fi
}

# O assistente do primeiro boot roda uma única vez, na instalação: um erro nele
# não aparece em build nem em lint, aparece com a máquina já instalada e sem
# conta para entrar. Aqui ele roda de verdade, num container descartável, com
# as respostas vindas do stdin.
firstboot_e2e() {
    printf 'arkteste\nTeste Arkmos\nsenha-de-teste-longa\nsenha-de-teste-longa\n' \
        | podman run --rm -i "$IMAGE" bash -c '
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

            # /etc/skel só é copiado por useradd --create-home, e só para
            # conta nova. Se o assistente perder essa flag, os defaults de
            # aplicativo somem sem nenhum erro aparecer.
            test -s /var/home/arkteste/.config/Code/User/settings.json \
                || { echo "o /etc/skel não foi copiado para o home"; exit 1; }
            test -s /var/home/arkteste/.config/noctalia/arkmos.toml \
                || { echo "os padrões do Noctalia não chegaram ao home"; exit 1; }
        '
}

echo "Verificando ${IMAGE} (variante: ${VARIANT})"
echo

# --- Estrutura da imagem ---------------------------------------------------

check "bootc container lint" run bootc container lint

# Pega erro de sintaxe e de ordenação nas units do Arkmos, inclusive no
# drop-in que adicionamos ao greetd.
check "systemd-analyze verify (units do Arkmos)" \
    run systemd-analyze verify \
        /usr/lib/systemd/system/arkmos-firstboot.service \
        /usr/lib/systemd/system/arkmos-login-fallback.service \
        /usr/lib/systemd/system/greetd.service

# --- Localização -----------------------------------------------------------

check "locale pt_BR.utf8 presente" \
    run sh -c 'locale -a | grep -qx pt_BR.utf8'

check "timezone America/Sao_Paulo" \
    run sh -c 'readlink /etc/localtime | grep -q "zoneinfo/America/Sao_Paulo$"'

check "teclado ABNT2 (KEYMAP=br)" \
    run sh -c 'grep -qx "KEYMAP=br" /etc/vconsole.conf'

# Sem isto o systemd cai no default e a máquina se apresenta como "fedora".
#
# Lido com 'podman cp' e não com 'podman run': o podman faz bind-mount de
# /etc/hostname no container com o id dele, então dentro de um 'run' o arquivo
# sempre existe e sempre tem conteúdo — a verificação passaria mesmo com a
# imagem sem hostname nenhum, que era exatamente o caso.
check "hostname declarado na imagem" image_file_matches /etc/hostname arkmos

# --- Login -----------------------------------------------------------------

# A conta do greeter tem nome diferente em cada distribuição, e errá-la não
# produz erro de configuração: o greetd falha 5 vezes, desiste, e como ele
# entra em conflito com getty@tty1 a vt1 fica preta. Foi o que aconteceu na
# primeira VM. Este é o teste que faltava.
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

# --- Sessão: autenticação e localização -------------------------------------

# O /etc/pam.d/greetd já referencia pam_gnome_keyring com '-' na frente, que
# manda ignorar em silêncio quando o módulo não existe. Sem o pacote -pam,
# portanto, nada falha e nada avisa: o chaveiro não é destravado com a senha do
# login, e a sessão abre pedindo a mesma senha outra vez, num prompt sem tema e
# em inglês. Foi o que apareceu no teste em VM.
check "pam_gnome_keyring presente e referenciado" \
    run sh -c 'test -e /usr/lib64/security/pam_gnome_keyring.so \
        || { echo "o módulo não está instalado (falta gnome-keyring-pam)"; exit 1; }
      grep -q pam_gnome_keyring /etc/pam.d/greetd \
        || { echo "o PAM do greetd não referencia o módulo"; exit 1; }'

# O autostart XDG do agente tem OnlyShowIn=MATE, e XDG_CURRENT_DESKTOP=niri não
# casa com isso: ele nunca subiria sozinho. Sem agente, toda autorização falha
# sem mostrar janela nem erro.
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

# É esta opção que faz o compositor desenhar a decoração. Sem ela cada cliente
# desenha a própria, e o foot usa a cor de foreground padrão: uma barra de
# título branca em cima de um terminal escuro.
check "niri com prefer-no-csd ativo" \
    run grep -qE '^prefer-no-csd$' /etc/niri/config.kdl

check "foot.ini válido" run foot --check-config

check "foot com titlebar desligada" \
    run sh -c 'grep -qx "preferred=none" /etc/xdg/foot/foot.ini'

# O banco do dconf é um GVDB binário; as strings ficam legíveis dentro dele, o
# que serve para afirmar que o 'dconf update' rodou E que o valor entrou. Sem
# o update, os arquivos-fonte ficam na imagem sem efeito nenhum.
check "banco do dconf compilado com tema escuro" \
    run sh -c 'test -s /etc/dconf/db/local &&
               grep -q prefer-dark /etc/dconf/db/local &&
               grep -q adw-gtk3-dark /etc/dconf/db/local'

# Sem o profile, o banco compilado é simplesmente ignorado pelo dconf.
check "profile do dconf inclui o banco do sistema" \
    run sh -c 'grep -qx "system-db:local" /etc/dconf/profile/user'

# O dconf precisa estar LEGÍVEL, não só compilado — um banco presente mas
# ilegível é indistinguível de ausente para quem consulta.
check "valores do dconf legíveis" \
    run sh -c 'DCONF_PROFILE=user dconf read /org/gnome/desktop/interface/color-scheme 2>/dev/null | grep -q prefer-dark'

# O dconf pode estar perfeito e o tema ainda sair claro: é por este backend
# que Firefox e aplicativos Electron perguntam se o sistema está no escuro. Se
# a interface Settings cair no backend do GNOME — que pressupõe uma sessão
# GNOME — ninguém responde, e cada um usa o default claro embutido.
check "portal de Settings apontado para o backend gtk" \
    run sh -c 'grep -qx "org.freedesktop.impl.portal.Settings=gtk;" /etc/xdg-desktop-portal/niri-portals.conf'

# Caminho de leitura independente de portal e de D-Bus: se o portal não subir,
# o GTK3 ainda encontra o tema aqui em vez de cair no Adwaita claro.
# O VS Code tem sistema de temas próprio: nenhum portal ou variável alcança o
# 'workbench.colorTheme'. O que alcança é semear o settings.json do usuário
# pelo /etc/skel, que o useradd copia ao criar a conta.
check "defaults do VS Code semeados no /etc/skel" \
    run python3 -c '
import json
c = json.load(open("/etc/skel/.config/Code/User/settings.json"))
assert c.get("window.autoDetectColorScheme") is True, "não segue o tema do sistema"
assert c.get("update.mode") == "none", "auto-update ligado numa imagem read-only"
'

check "tema GTK declarado também fora do dconf" \
    run sh -c 'grep -qx "gtk-theme-name=adw-gtk3-dark" /etc/xdg/gtk-3.0/settings.ini && grep -qx "gtk-application-prefer-dark-theme=1" /etc/xdg/gtk-3.0/settings.ini'

# O parser TOML do greetd é mais restrito que o TOML 1.0, e rejeita
# construções que outros parsers aceitam — uma string multi-linha com barra
# invertida no fim da linha, por exemplo. Validar o arquivo com o tomllib do
# Python NÃO pega isso: ele aceita, o greetd aborta, e o sintoma é o mesmo de
# uma conta de greeter inexistente (cinco restarts e desiste). Custou um teste
# em VM. Quem valida o arquivo do greetd é o greetd.
#
# Sem VT, o greetd falha ao abrir o terminal — e é justamente isso que se
# exige aqui: ter chegado até o terminal significa que o config foi lido.
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

# O drop-in e a unit de recuperação só servem juntos: um OnFailure apontando
# para unit inexistente é aceito em silêncio pelo systemd, e a rede de
# segurança simplesmente não existiria.
check "fallback de login ligado ao greetd" \
    run sh -c '
        grep -q "^OnFailure=arkmos-login-fallback.service$" \
            /usr/lib/systemd/system/greetd.service.d/50-arkmos-fallback.conf \
            || { echo "o drop-in do greetd não aponta para o fallback"; exit 1; }
        test -e /usr/lib/systemd/system/arkmos-login-fallback.service \
            || { echo "a unit de fallback não existe"; exit 1; }
    '

# Flag errada aqui produz o mesmo sintoma. Rodar o tuigreet não denuncia:
# sem tty ele estoura no terminal antes de reclamar do argumento, e ainda sai
# com código 0. Então as flags são conferidas contra o --help.
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

# Compilado noutro estágio justamente para o toolchain não vir junto. Se algum
# -devel aparecer na imagem final, o COPY --from virou um dnf install.
check "toolchain de compilação ficou fora da imagem" \
    sh -c '! podman run --rm "'"$IMAGE"'" sh -c "rpm -q meson gcc-c++ wlroots-devel >/dev/null 2>&1"'

check "wlroots de runtime presente" run rpm -q wlroots

# O tmpfiles.d do upstream declara o diretório para o usuário 'greeter', que no
# Fedora não existe. Se ele voltar para a imagem, o estado do greeter deixa de
# ser criado e o login falha — a mesma classe de erro da conta errada no
# config.toml.
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

# Valor inválido aqui não dá erro de sintaxe: o greeter sobe e ignora, ou falha
# ao desenhar. O teclado é o que mais importa — é a única tela do sistema onde
# não há retorno visual do que foi digitado.
check "greeter.toml declara sessão e teclado do Arkmos" \
    run python3 -c '
import tomllib
c = tomllib.load(open("/usr/share/arkmos/noctalia-greeter.toml", "rb"))
assert c["session"]["default"] == "Niri", "sessão padrão não é Niri"
assert c["keyboard"]["layout"] == "br", "teclado do login não é br"
assert c["appearance"]["theme_mode"] == "dark", "login não está em tema escuro"
'

# A sessão apontada tem de existir como .desktop, senão o greeter mostra uma
# opção que não abre nada.
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

# O tuigreet continua instalado como caminho de recuperação: se o greeter
# gráfico não subir, trocar uma linha no config do greetd devolve o login.
check "greeter de console mantido como recuperação" \
    run sh -c 'test -x /usr/libexec/arkmos-greeter && rpm -q tuigreet >/dev/null'

# --- Boot ------------------------------------------------------------------

check "tema padrão do Plymouth é o do Arkmos" \
    run sh -c 't=$(plymouth-set-default-theme); [ "$t" = arkmos ] || { echo "tema padrão é $t"; exit 1; }'

# A arte é gerada no build. Se o render falhar pela metade, o two-step sobe sem
# a imagem que falta e desenha só o fundo — nada quebra, e nada avisa.
check "tema do Plymouth completo" \
    run sh -c '
        d=/usr/share/plymouth/themes/arkmos
        grep -qx "ImageDir=$d" "$d/arkmos.plymouth" \
            || { echo "ImageDir não aponta para $d"; exit 1; }
        for f in watermark.png throbber-0001.png animation-0001.png entry.png bullet.png lock.png; do
            test -s "$d/$f" || { echo "falta $d/$f"; exit 1; }
        done
    '

# O plymouthd arranca de dentro do initramfs e continua com o tema que carregou
# lá, então o que vale é o conteúdo do initramfs, não o de /usr. Configurar o
# tema e esquecer de regerar passa em qualquer verificação que olhe o sistema
# de arquivos — e o boot segue com o logo do fabricante.
#
# Regerar também troca um arquivo que a base gerou, e o erro possível ali não
# aparece em lint: aparece como máquina que não monta a raiz. O módulo ostree é
# o que monta o deployment; sem ele não há boot.
#
# O /root do initramfs aponta para var/roothome, que no build só existe se o
# Containerfile o criar para o dracut — ver o comentário lá.
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

# O Noctalia só lê configuração do home, então o padrão chega pelo /etc/skel.
# Caminho errado ali não dá erro: o shell sobe com o fundo vazio.
check "wallpaper padrão semeado para o Noctalia" \
    run python3 -c '
import tomllib, os
c = tomllib.load(open("/etc/skel/.config/noctalia/arkmos.toml", "rb"))
p = c["wallpaper"]["default"]["path"]
assert os.path.getsize(p) > 0, f"{p} vazio"
assert c["shell"]["greeter_sync"]["auto_sync"] is True, "auto-sync do greeter desligado"
'

# O validate sai com 0 mesmo quando encontra chave desconhecida — e chave com
# nome errado é justamente o erro provável, porque o Noctalia a ignora e segue.
# Por isso o que decide é a saída, não o código de retorno.
check "config semeada do Noctalia é válida e sem avisos" \
    run sh -c '
        saida=$(HOME=/tmp noctalia config validate /etc/skel/.config/noctalia/arkmos.toml 2>&1 | grep -v dconf)
        case "$saida" in
            *WARN*|*ERROR*|*"warning(s)"*) echo "$saida"; exit 1 ;;
            *"Config is valid"*) exit 0 ;;
            *) echo "$saida"; exit 1 ;;
        esac
    '

# A tela de login recebe wallpaper e paleta pelo sync da sessão, gravado no
# sync.toml. O greeter.toml vence o sync.toml, então wallpaper ou paleta
# declarados lá impediriam para sempre que a escolha feita no desktop chegasse
# ao login — sem erro, só com a tela de login parada no valor antigo.
check "greeter.toml não bloqueia o sync da aparência" \
    run python3 -c '
import tomllib
a = tomllib.load(open("/usr/share/arkmos/noctalia-greeter.toml", "rb")).get("appearance", {})
bloqueiam = sorted(k for k in ("wallpaper", "wallpapers", "palette") if k in a)
assert not bloqueiam, "declarado no greeter.toml: " + ", ".join(bloqueiam)
'

# --- Arquivos ----------------------------------------------------------------

# "Mostrar na pasta" do VS Code e do Firefox chama org.freedesktop.FileManager1
# por D-Bus. Sem quem implemente a interface, o clique não faz nada e não dá erro.
check "gerenciador de arquivos atende FileManager1" \
    run sh -c 'rpm -q nautilus gvfs >/dev/null && grep -rqx "Name=org.freedesktop.FileManager1" /usr/share/dbus-1/services/'

# O indexador do Nautilus não subia: a unit do localsearch trazia
# ConditionEnvironment=XDG_SESSION_CLASS=user e era PULADA, porque essa
# variável não chega ao systemd --user numa sessão greetd + niri. Não é falha,
# é condição não satisfeita — o único sinal é uma linha no journal e a busca
# por conteúdo não funcionar. O drop-in zera a condição; ver o comentário nele.
#
# A segunda parte da verificação é contra o drop-in envelhecer em silêncio: se
# o upstream mudar ou remover essa condição, zerar a lista poderia passar a
# apagar uma condição legítima, e é melhor falhar aqui e revisar.
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

# Habilitada pelo preset do Fedora, escreve no grubenv, e o /boot do bootc é
# somente leitura: falhava em toda sessão. Ver o comentário no Containerfile.
check "grub-boot-success mascarada" \
    run sh -c '
        for u in grub-boot-success.timer grub-boot-success.service; do
            [ "$(readlink /etc/systemd/user/$u)" = /dev/null ] \
                || { echo "$u não está mascarada"; exit 1; }
        done
    '

# Sem o xdg-user-dirs-update na sessão, o home nasce sem Documentos, Downloads,
# Imagens… A unit de usuário do pacote cuida disso, mas só se estiver
# habilitada — e os nomes só saem em português com o LANG certo.
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

# --- tmpfiles --------------------------------------------------------------

# O dry-run resolve usuários e grupos de verdade, então uma entrada apontando
# para conta inexistente falha aqui em vez de falhar calada no boot.
check "tmpfiles.d do Arkmos resolve usuários e grupos" \
    run systemd-tmpfiles --dry-run --create /usr/lib/tmpfiles.d/arkmos.conf

# --- Pacotes ---------------------------------------------------------------

check "pacotes essenciais instalados" \
    run rpm -q docker-ce docker-compose-plugin niri noctalia greetd tuigreet code zsh

# Estes o Arkmos não instala: assume que vêm da base, e o Containerfile diz
# isso em comentário. O ublue vem podando as imagens intermediárias, então a
# suposição precisa ser afirmada em algum lugar — senão o dia em que a base
# deixar de trazer o podman ou o portal, o sintoma aparece como sessão gráfica
# quebrada na máquina, não como build vermelho.
check "componentes herdados da base presentes" \
    run rpm -q podman distrobox NetworkManager pipewire wireplumber bluez \
        flatpak plymouth wl-clipboard

# podman-docker é um shim que faz 'docker' chamar o podman — a substituição
# que o PROJECT.md proíbe, e conflito direto com docker-ce-cli.
check "podman-docker ausente" \
    sh -c '! podman run --rm "'"$IMAGE"'" rpm -q podman-docker >/dev/null 2>&1'

# --- Serviços --------------------------------------------------------------

check "serviços habilitados" \
    run sh -c '
        for u in arkmos-firstboot.service docker.service greetd.service; do
            state=$(systemctl is-enabled "$u" 2>&1)
            [ "$state" = enabled ] || { echo "$u esta \"$state\""; exit 1; }
        done
    '

# A política de assinatura é opcional (depende da chave pública existir), mas
# as duas peças só funcionam juntas: chave sem entrada na política não verifica
# nada, e entrada apontando para chave ausente faz TODO pull falhar.
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

check "greetd é o display-manager" \
    run sh -c 'readlink /etc/systemd/system/display-manager.service | grep -q greetd'

# --- Variante --------------------------------------------------------------
#
# As duas variantes diferem só na imagem base, e é justamente por isso que vale
# afirmar a diferença: um erro no build-arg produziria duas imagens iguais com
# nomes diferentes, e nada mais no conjunto de verificações notaria.

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

        # O Containerfile remove estes na variante sem driver; se sobrarem, é
        # sinal de que a limpeza condicional deixou de rodar.
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

# O 'mise' avisa no stderr que não conseguiu gravar em ~/.local/share quando
# roda como root num container descartável. É ruído esperado aqui e não diz
# nada sobre a imagem, daí o 2>/dev/null só nele.
check "binários upstream instalados e executáveis" \
    run sh -c 'starship --version >/dev/null &&
               lazygit --version >/dev/null &&
               lazydocker --version >/dev/null &&
               mise --version >/dev/null 2>/dev/null'

check "Nerd Font patched presente" \
    run sh -c 'fc-list | grep -qi "JetBrainsMono Nerd Font"'

# --network=none é o ponto da verificação, não um detalhe: a configuração tem
# de carregar inteira sem buscar nada. Plugin baixado na primeira abertura do
# shell daria um shell quebrado em máquina recém-instalada e sem rede.
#
# 'zsh -i' aqui roda sem tty, então zle não existe e o syntax-highlighting não
# instala os widgets — checar a variável dele, e não a função, é o que
# distingue "não carregou" de "carregou sem terminal".
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

# A ativação do mise é o que troca o PATH ao entrar num projeto com
# .mise.toml. Sem ela o binário está na imagem e não serve para nada — e é uma
# linha só no tools.zsh, fácil de perder num refactor do shell.
#
# HOME=/tmp porque o /root da imagem é symlink para var/roothome, que só nasce
# no boot: sem HOME gravável o mise apenas reclama, e a verificação passaria a
# medir o container descartável em vez da imagem.
check "zsh ativa o mise" \
    sh -c 'podman run --rm --network=none -e HOME=/tmp "'"$IMAGE"'" zsh -ic "
        [[ \$MISE_SHELL == zsh ]]             || { print -u2 \"MISE_SHELL=\$MISE_SHELL, esperado zsh\"; exit 1; }
        (( \$+functions[mise] ))              || { print -u2 \"a função mise não foi definida\"; exit 1; }
        (( \$+functions[_mise_hook_precmd] )) || { print -u2 \"hook de precmd do mise ausente\"; exit 1; }
        [[ \$PATH == *mise/shims* ]]          || { print -u2 \"shims do mise fora do PATH\"; exit 1; }
    " 2>&1'

# O bash tem a ativação dele em /etc/profile.d/mise.sh, e esse diretório não é
# exclusivo do bash: o /etc/zshrc do Fedora também o carrega. Por isso a
# verificação do zsh acima exige MISE_SHELL=zsh — se a guarda do arquivo
# quebrar, o zsh passa a receber a ativação em dialeto de bash e aquela linha
# falha. Esta aqui é a outra ponta: o bash precisa de fato ativar.
#
# Com -l, porque no Fedora o bash interativo NÃO-login não lê /etc/bashrc por
# conta própria: quem faz essa ponte é o ~/.bashrc do /etc/skel, e é ele que
# acaba carregando o profile.d. Em shell de login o /etc/profile carrega o
# diretório direto, o que prova o nosso arquivo sem depender de home nenhum; a
# ponte do skel é afirmada na verificação seguinte.
check "bash ativa o mise" \
    sh -c 'podman run --rm --network=none -e HOME=/tmp "'"$IMAGE"'" bash -lic "
        [[ \$MISE_SHELL == bash ]] || { echo \"MISE_SHELL=\$MISE_SHELL, esperado bash\" >&2; exit 1; }
        declare -F mise >/dev/null || { echo \"a função mise não foi definida\" >&2; exit 1; }
        [[ \$(declare -p PROMPT_COMMAND 2>/dev/null) == *_mise_hook* ]] \
            || { echo \"hook do mise fora do PROMPT_COMMAND\" >&2; exit 1; }
    " 2>&1'

# A ponte do caso não-login: sem esta linha no .bashrc que o assistente copia
# do /etc/skel, um 'bash' aberto dentro do terminal não carrega profile.d, e o
# mise fica sem ativação sem que nada reclame.
check "skel liga o bash ao profile.d" \
    run sh -c 'grep -q "\. /etc/bashrc" /etc/skel/.bashrc'

check "ZDOTDIR aponta para a config da imagem" \
    run sh -c 'test -r /usr/share/arkmos/zsh/.zshrc &&
               grep -q /usr/share/arkmos/zsh /etc/zshenv'

# 'print-config' imprime a configuração efetiva. Procurar por uma linha que só
# existe no nosso arquivo prova as duas coisas de uma vez: que o starship achou
# o arquivo e que o TOML é válido — com TOML inválido ele cai no default em
# silêncio, e o prompt fica certo o suficiente para ninguém notar.
#
# (Não usar 'starship config': esse abre o $EDITOR e pendura o build.)
check "starship.toml da imagem é lido e parseado" \
    run sh -c "STARSHIP_CONFIG=/usr/share/arkmos/starship.toml starship print-config 2>/dev/null | grep -qF '\$directory\$git_branch\$git_state\$git_status'"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "Todas as verificações passaram."
else
    echo "Há verificações falhando." >&2
fi
exit "$FAILED"
