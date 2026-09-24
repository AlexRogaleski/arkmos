# Arkmos

Sistema operacional pessoal e reprodutível baseado em Fedora bootc, desenvolvido para facilitar instalações, reinstalações e manutenção de uma estação de trabalho Linux personalizada.

> **Status:** Em desenvolvimento
> **Versão atual:** 0.10.0
> **Base:** Universal Blue, Fedora 44 bootc
> **Compositor:** Niri
> **Shell do desktop:** Noctalia
> **Bootloader atual de testes:** GRUB
> **Filesystem:** Btrfs

Este documento registra arquitetura, decisões e estado. Para uso — construir, testar, instalar, atualizar — ver o [README.md](README.md).

---

# 1. Visão do Projeto

O Arkmos é uma imagem de sistema operacional Linux personalizada, baseada no Fedora bootc, criada para uso pessoal.

O objetivo principal não é criar uma distribuição Linux pública, mas manter uma definição declarativa e versionada da estação de trabalho, permitindo reconstruí-la de maneira previsível quando necessário.

A ideia central é:

```text
Código-fonte
     ↓
Containerfile
     ↓
Imagem Arkmos
     ↓
bootc install / bootc upgrade
     ↓
Sistema operacional
     ├── Niri
     ├── Noctalia
     ├── GTK/Qt
     ├── ferramentas de desenvolvimento
     ├── containers
     └── aplicações
```

O sistema deve ser versionado utilizando Git, permitindo acompanhar a evolução da configuração e reproduzir instalações futuras.

---

# 2. Objetivos

## 2.1 Objetivo principal

Criar uma estação de trabalho Linux pessoal baseada em Fedora bootc, com configuração reproduzível e personalizada.

## 2.2 Objetivos específicos

- Utilizar Fedora bootc como base, através das imagens do Universal Blue.
- Utilizar Btrfs como filesystem raiz.
- Utilizar Niri como compositor Wayland.
- Utilizar Noctalia como shell/desktop shell.
- Ter configuração personalizada do ambiente gráfico.
- Utilizar português do Brasil como locale padrão.
- Utilizar teclado brasileiro ABNT2.
- Utilizar `America/Sao_Paulo` como timezone.
- Disponibilizar ferramentas de desenvolvimento.
- Utilizar Podman como infraestrutura de containers.
- Manter Docker real para compatibilidade com Laravel Sail.
- Utilizar Distrobox para ambientes específicos.
- Separar sistema operacional de dados pessoais.
- Permitir reinstalação rápida e previsível.
- Manter a configuração versionada no Git.
- Publicar a imagem em registry, para que a atualização seja `bootc upgrade`.
- Testar as imagens em máquina virtual antes da instalação em hardware real.

---

# 3. Princípios do Projeto

## 3.1 Reprodutibilidade

A configuração do sistema deve estar declarada no código sempre que possível.

Alterações importantes devem ser versionadas através do Git.

## 3.2 Imutabilidade

O sistema operacional deve ser tratado como uma imagem.

Preferência:

```text
Alterar código
      ↓
Construir nova imagem
      ↓
Verificar
      ↓
Testar em VM
      ↓
Instalar/atualizar
```

Em vez de depender de dezenas de alterações manuais após a instalação.

## 3.3 Separação entre sistema e usuário

O sistema operacional pertence à imagem. Os dados pessoais pertencem ao usuário.

```text
Imagem Arkmos
├── Sistema
├── Serviços
├── Niri
├── Shell
└── Ferramentas

/home
├── Projetos
├── Documentos
├── Downloads
└── Configurações do usuário
```

## 3.4 O que está em `/usr`, e o que pode estar em `/etc`

Duas regras estruturais do modelo bootc, que valem para tudo em `files/`:

- **Nada em `/usr/local` nem `/opt`.** Ambos são symlink para `/var` neste tipo de imagem, e o bootc só popula `/var` na primeira instalação. Conteúdo colocado lá nunca mais seria atualizado por `bootc upgrade`.
- **Configuração em `/usr`, não em `/etc`.** `/etc` passa por merge de três vias e, uma vez modificado localmente, deixa de receber atualizações da imagem.

O que está em `/etc` está por exigência de quem lê o arquivo, e não por conveniência:

```text
/etc/locale.conf        locale.conf(5) só lê de /etc
/etc/vconsole.conf      vconsole.conf(5) só lê de /etc
/etc/localtime          localtime(5) só lê de /etc
/etc/hostname           lido pelo systemd em /etc
/etc/greetd/            o greetd procura sua configuração em /etc
/etc/xdg-desktop-portal/ caminho de configuração dos portais
/etc/nvidia/            caminho dos application profiles do driver
```

Conteúdo destinado a `/var` não é assado na imagem: é declarado em `tmpfiles.d` e reconciliado a cada boot.

## 3.5 Testes antes do hardware real

Toda alteração significativa deve ser testada inicialmente em máquina virtual.

Ambiente atual de desenvolvimento/teste:

- Aurora (Universal Blue)
- Podman
- QEMU
- KVM
- OVMF/UEFI

---

# 4. Arquitetura

```text
        ┌─────────────────────────────────┐
        │  Universal Blue / Fedora bootc  │
        └────────────────┬────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │        Btrfs        │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │  Noctalia Greeter   │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │        Niri         │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │      Noctalia       │
              └──────────┬──────────┘
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
         GTK apps    Qt apps     Wayland apps
```

---

# 5. Base do Sistema

## 5.1 Universal Blue

O Arkmos parte das imagens do [Universal Blue](https://universal-blue.org), o projeto por trás de Bluefin, Aurora e Bazzite.

A parte mais cara de uma imagem Fedora bootc para desktop é a pilha de drivers — em especial os módulos NVIDIA compilados e **assinados**, sem os quais não existe Secure Boot com driver proprietário. O Universal Blue mantém essa engrenagem e a entrega pronta. Partir dela é o que torna este projeto viável para uma pessoa só.

Repositório da base: <https://github.com/ublue-os/main>

Os componentes `ublue-os-*` que vêm na imagem estão sob MIT (`akmods-addons`, `nvidia-addons`) e Apache-2.0 (`signing`, `update-services`, `just`, `luks`, `udev-rules`).

## 5.2 Duas variantes

A versão major do Fedora permanece explícita, e a base é parametrizada por `ARG BASE_IMAGE`:

```text
arkmos          ghcr.io/ublue-os/base-main:44      padrão, sem pilha NVIDIA
arkmos-nvidia   ghcr.io/ublue-os/base-nvidia:44    driver NVIDIA assinado
```

A diferença é **apenas** a imagem base: uma árvore `files/` só, um `Containerfile` só. A variante padrão é um subconjunto exato da variante NVIDIA — 79 pacotes a menos, nenhum pacote exclusivo.

```text
arkmos           ~8,8 GB
arkmos-nvidia   ~11,1 GB
```

O Containerfile remove o que não se aplica (`/etc/nvidia`, drop-in do CDI) decidindo a partir do que a base realmente entregou, e não a partir de um build-arg — se a base-main passar a trazer o driver algum dia, a regra continua correta.

## 5.3 Histórico da base

```text
0.1.0 – 0.7.0    quay.io/fedora/fedora-bootc:44
0.8.0 –          ghcr.io/ublue-os/base-main:44 (+ variante nvidia)
```

Motivo da saída do `fedora-bootc`: ele é o tier "standard", voltado a servidor headless — não é uma base mínima nem uma base de desktop, e a pilha gráfica e de drivers teria de ser construída inteira.

---

# 6. Filesystem

Filesystem raiz padrão:

```text
Btrfs
```

Configuração:

```text
files/usr/lib/bootc/install/00-arkmos.toml
```

Conteúdo:

```toml
[install.filesystem.root]
type = "btrfs"
```

## O que o Btrfs acrescenta aqui — e o que não acrescenta

O snapshot, num sistema de pacotes como o Arch, é a única rede de segurança do sistema: uma atualização quebra e você **boota dentro de um snapshot** do subvolume raiz. É o que o Omarchy monta com o Snapper e o bootloader.

Aqui esse papel já está coberto, e por um mecanismo mais forte. Cada `bootc upgrade` cria uma deployment nova e deixa a anterior intacta no disco; `bootc rollback` volta em um reboot. Não é cópia de arquivos, é a própria unidade de instalação — e o `/usr` é read-only com composefs, então não existe o acúmulo de mudança local que o snapshot protege. Bootar dentro de um snapshot não faz sentido no Arkmos: quem manda no boot são as deployments do ostree, não subvolumes.

O que o rollback do bootc **não** cobre é o `/var`, que é compartilhado entre deployments e atravessa o rollback sem mudar. E é ali que ficam os dados: `/var/home`, `/var/lib/flatpak` (aplicativos e o estado deles), `/var/lib/docker` (volumes do Sail), `/var/lib/containers` (Distrobox). Esse é o recorte onde o snapshot ganha valor: uma pasta apagada por engano, um volume corrompido, uma atualização de Flatpak que estraga os dados do aplicativo.

Daí o escopo, nesta ordem de valor:

- **backup do `/var/home` para fora da máquina** — snapshot não sobrevive à morte do SSD, a um `mkfs` errado nem a roubo;
- **snapshots de `/var/home`**, com retenção curta, para desfazer engano em segundos;
- nada de integração snapshot↔bootloader, que é resposta para um problema que este sistema não tem.

A escolha do filesystem é a parte irreversível, e já está feita do lado certo: a imagem instala em Btrfs e traz o `btrfs-progs`. Os snapshots entram depois, na máquina, sem reinstalar.

**O layout, medido na instalação pela ISO em 2026-09-23:** um único subvolume.

```text
$ findmnt -no SOURCE,FSTYPE /sysroot
/dev/vda3[/root] btrfs

$ sudo btrfs subvolume list /sysroot
ID 256 gen 316 top level 5 path root
```

O `autopart --nohome --type=btrfs` do kickstart cria só o `root`, e o `/var/home` mora dentro dele. Um snapshot desse subvolume levaria o `/ostree` inteiro junto — as deployments, e não apenas os dados. Para o recorte da seção anterior (snapshots de `/var/home`), o `/var/home` precisa de subvolume próprio, o que dá para fazer depois movendo o conteúdo, ou no particionamento manual da instalação.

Note o alvo: `/sysroot`. A raiz de um sistema bootc é um overlay do composefs, e `btrfs subvolume list /` responde `not a btrfs filesystem` mesmo num disco Btrfs.

**No hardware, o subvolume se chamou `root00`**, e não `root`. O notebook tem um segundo NVMe com uma instalação Btrfs anterior, e o instalador deu um nome que não colidisse. Nada depende do nome, mas é ele que aparece no `rootflags=` — então não dá para assumir `subvol=root` em comando nenhum.

## Compressão: no `rootflags`, e não no fstab

O Anaconda grava no `/etc/fstab` uma linha para `/` com `subvol=...,compress=zstd:1,ro`. Num sistema bootc isso não funciona: o `/` é o overlay do composefs, o `systemd-remount-fs` tenta remontá-lo com opções de Btrfs, e o overlay recusa:

```text
mount: /: fsconfig() failed: overlay: No changes allowed in reconfigure.
```

A unit falha em todo boot, e o pior não é ela: a compressão só existia nessa linha, e por isso **nunca era aplicada**. O `/sysroot` e o `/var` montavam sem `compress`. Visto na primeira instalação em hardware, em 2026-09-24.

A correção tira a linha de `/` do fstab — o `bootc install to-disk` também não a grava — e leva a opção para o `rootflags=` do kernel, que é com o que o initramfs monta o `/sysroot`. No Btrfs, `compress` vale para o sistema de arquivos inteiro, então cobre o `/var` e o `/var/home` junto. O ostree carrega os argumentos de kernel de uma deployment para a seguinte, e a correção sobrevive ao `bootc upgrade`.

Nas mídias novas, quem faz isso é o `%post` do kickstart (seção 31). Numa máquina já instalada por ISO anterior:

```bash
sudo sed -i '\|^UUID=[^ ]* / btrfs |d' /etc/fstab
sudo rpm-ostree kargs --delete=rootflags=subvol=<subvol> \
    --append=rootflags=subvol=<subvol>,compress=zstd:1
```

com o `<subvol>` que aparece em `cat /proc/cmdline`. O `--replace` não serve aqui: ele aceita a forma `CHAVE=ANTIGO=NOVO`, e o `=` de dentro de `subvol=` faz ele procurar um `rootflags=subvol` que não existe. A compressão vale para o que for escrito depois; o que já está no disco fica como está.

---

# 7. Bootloader

```text
GRUB
```

É o bootloader da base, e é com ele que o bootc se integra: as entradas de deployment, o `bootc upgrade` e o `bootc rollback` passam por ele, e isso já está validado em VM (seção 35.2).

O Limine constou como objetivo futuro até 2026-09-22, quando saiu do plano. Trocar de bootloader num sistema em que o bootc cuida das entradas de boot é risco sem ganho: o GRUB da base vem configurado e testado, inclusive no caminho de rollback, e a única coisa que o Arkmos acrescenta é mascarar a `grub-boot-success`, que não faz sentido aqui (seção 33).

---

# 8. Ambiente Gráfico

## 8.1 Compositor

```text
Niri 26.04
```

Configuração:

```text
files/etc/niri/config.kdl
```

Personalizações em relação à configuração de exemplo:

- `spawn-at-startup "noctalia"` no lugar da Waybar;
- `Mod+T` abre o Foot;
- `Mod+D` e `Mod+Space` abrem o lançador do Noctalia, e `Super+Alt+L` bloqueia a tela pelo Noctalia. A configuração de exemplo apontava para o fuzzel e o swaylock, dois programas à parte, e o lançador do Noctalia ficava sem atalho;
- `Shift+Print` faz captura com anotação (seção 25);
- anel de foco de 3 px, com gradiente do azul ao roxo de destaque do Tokyo Night, e cantos arredondados de 8 px em todas as janelas, com `clip-to-geometry` para o conteúdo ser recortado no mesmo raio — sem ele o arredondamento fica só na moldura e o conteúdo aparece quadrado nos cantos;
- `prefer-no-csd` ligado.

O terminal tem fundo levemente translúcido (`alpha=0.9` em `[colors-dark]`, declarado depois do include do tema para vencê-lo). A seção é `[colors-dark]`, e não `[colors]`: o foot 1.27 depreciou a segunda e abria imprimindo o aviso em cima do prompt; com `initial-color-theme=dark`, é a seção escura que vale. O niri não desfoca o que está atrás, então o que aparece é o papel de parede; o `alpha-mode` fica no padrão, que aplica a translucidez só às células com a cor de fundo padrão, deixando texto selecionado e blocos coloridos sólidos.

O `prefer-no-csd` faz o niri anunciar decoração do lado do servidor e desenhar ele mesmo a borda e o anel de foco. Sem ele, cada aplicativo desenha a própria barra de título com o tema que conseguir adivinhar — ver seção 9.

Validação (roda no `just check` e no CI):

```bash
niri validate --config /etc/niri/config.kdl
```

## 8.2 Shell/Desktop Shell

```text
Noctalia 5.0.1
```

A v5 é reescrita nativa em C++/Wayland: sem Qt, sem Quickshell, sem COPR, tudo em `/usr`. **Não usar a v4** (pacote `noctalia-shell`, baseada em Quickshell), que está sem manutenção upstream.

O pacote não entrega agente polkit próprio, então o `mate-polkit` continua necessário.

Responsável por barra, dock, lançador, central de controle, notificações, wallpaper e tela de bloqueio.

## 8.3 Login

```text
greetd 0.10.3  +  Noctalia Greeter 1.5.0
```

O greetd continua sendo o gerenciador; o que mudou foi o greeter. O Noctalia Greeter é gráfico, sobe um compositor wlroots próprio e foi escrito para acompanhar o Noctalia Shell — a tela de login usa a paleta que o shell publica, em vez de ter identidade própria.

`greetd-selinux` traz a política; sem ela o greetd esbarra no SELinux em modo enforcing.

**A conta do greeter no Fedora chama-se `greetd`, não `greeter`.** Errar esse nome não produz erro de configuração: o greetd sobe, falha ao abrir a sessão, reinicia cinco vezes e termina em `start-limit-hit`. Como a unit tem `Conflicts=getty@tty1.service`, o getty já foi parado nesse ponto, e a vt1 fica preta com o cursor. Esse foi o sintoma que travou o primeiro teste em VM, e hoje existe uma verificação dedicada a ele.

### Por que compilado, e não de pacote

O greeter não é empacotado pelo Fedora. A documentação dele aponta o repositório Terra para Fedora 44, mas **foi verificado que o pacote não está lá** — só o shell. O único RPM existente é um snapshot de git num COPR de terceiro.

Compilar mantém a política da seção 13.3: versão fixada, nada de snapshot. O estágio de compilação é separado justamente para os ~40 pacotes `-devel` não acabarem na imagem final — o que atravessa são 5 binários e alguns assets, **5,5 MB**, mais o `wlroots` de runtime. O commit é fixado, e não a tag, porque tag pode ser movida.

### O `-march=native` do upstream

Em `buildtype=release`, o `meson.build` do greeter acrescenta `-march=native -mtune=native`, e não há opção para desligar. O binário sai amarrado ao processador de quem compila — e quem compila a imagem publicada é o runner do GitHub, não esta máquina.

O sintoma, na primeira imagem publicada testada em VM: a senha é aceita, a tela pisca e volta para o login. O greeter morre de **SIGILL** dentro de `GreetdClient::sendRequest`, na primeira coisa que faz ao autenticar; o greetd reinicia e nada na tela diz o motivo. O log registra `pam_unix(greetd:auth): conversation failed`, que parece senha errada e não é — o SSH autentica a mesma conta com a mesma senha.

O que atrapalhou o diagnóstico: o `build fingerprint` que o greeter imprime é do código, não do binário, então ele é **igual** nas duas imagens; e o diff de pacotes entre as duas deployments mostrava apenas `code`, `ffmpeg`, `libde265` e `unibilium`. Tudo apontava para "a mesma coisa", e a diferença estava no código de máquina.

A instrução que estoura é `vmovw`, de **AVX512-FP16**: 102 ocorrências no binário vindo do runner e nenhuma no compilado aqui. O Xeon do runner tem essa extensão; o i5-11300H (Tiger Lake), não. Os dois binários usam outras instruções de AVX-512 (`vpermi2b`, `vgf2p8affineqb`, `vmovdqa64`), mas essas o Tiger Lake executa — é só a de FP16 que falta.

O build troca os dois flags por `-march=x86-64-v2 -mtune=generic` e confere, no `compile_commands.json`, que o compilador recebeu o flag certo e nenhum `-march=native`. Verificado no binário resultante: zero instruções de AVX-512, e o AVX2 que resta está apenas nas funções `*_x86_avx2` do wuffs, o decodificador de JPEG, que escolhe o caminho conforme o CPU em tempo de execução. Vale lembrar que este é o **único** componente compilado aqui: todo o resto vem de RPM do Fedora, já construído para a linha de base da distribuição.

### A armadilha do usuário, de novo

O `tmpfiles.d` que o upstream instala declara:

```text
d /var/lib/noctalia-greeter 0750 greeter greeter -
```

`greeter` de novo — e o próprio comentário deles avisa para sobrescrever quando o usuário difere. No Fedora isso falha, o diretório de estado não é criado e o greeter não tem onde gravar. O Zirconium registrou exatamente essa falha na issue #68, com outro greeter. O arquivo deles é removido no build e a declaração correta vive em `arkmos.conf`, que o `just check` valida resolvendo usuários de verdade.

### Configuração

```text
/usr/share/arkmos/noctalia-greeter.toml   →   /var/lib/noctalia-greeter/greeter.toml
```

Entregue por `tmpfiles.d` com `C`, que copia só se o destino não existir: a imagem dá o padrão e uma edição feita na máquina sobrevive às atualizações. Em troca, mudança no template não alcança quem já tem o arquivo — para reaplicar, apagar o de `/var/lib` e reiniciar.

O que importa estar ali: `[session] default = "Niri"` (tem de casar com o `Name=` do `.desktop`), `[appearance] scheme = "Synced"` com `theme_mode = "dark"`, e **`[keyboard] layout = "br"`** — sem isso o login nasce em `us`, e é a única tela do sistema onde não há retorno visual do que foi digitado.

### O PAM não precisa de patch aqui

O script de setup do upstream aplica um patch em `/etc/pam.d/greetd` para acrescentar `pam_systemd.so`. **No Fedora é desnecessário**, e o script dá falso positivo porque faz grep literal sem seguir os `include`:

```text
/etc/pam.d/greetd          session include system-auth → tem pam_systemd
/etc/pam.d/greetd-greeter  session optional pam_systemd.so (direto, do pacote)
```

O Fedora já entrega um PAM dedicado ao greeter. Nada a fazer.

### Caminho de recuperação

Se o greeter gráfico falhar, o `OnFailure` entrega um login de texto na vt1. O tuigreet permanece instalado, com os argumentos em `/usr/libexec/arkmos-greeter`: trocar uma linha no `config.toml` devolve um greeter que não depende de GPU nem de compositor.

---

# 9. Terminal

Terminal padrão:

```text
Foot 1.27.0
```

Atalho:

```text
Mod + T
```

Configuração de sistema:

```text
files/etc/xdg/foot/foot.ini
```

Fonte JetBrains Mono Nerd Font, paleta escura e barra de título desligada:

```ini
[csd]
preferred=none
size=0
```

Sem isso, o foot desenha a própria barra de título usando a cor de foreground padrão — **branca**, independentemente do esquema de cores. Era o que aparecia no primeiro teste em VM, e numa janela em tiling essa barra também não serve para nada. A correção principal é o `prefer-no-csd` do niri (seção 8.1); esta é a rede de segurança para o caso de o compositor pedir CSD assim mesmo.

A paleta é a `tokyonight-night`, um tema que o próprio pacote foot entrega, incluída pelo `foot.ini` — o Tokyo Night escolhido como identidade (seção 26.1). As cores do Zsh e do prompt são as cores nomeadas do terminal, então seguem o mesmo esquema sem configuração própria. Um `~/.config/foot/foot.ini` do usuário substitui este arquivo por inteiro; o foot não mescla os dois.

---

# 10. Portais e Secret Service

Componentes:

```text
xdg-desktop-portal
xdg-desktop-portal-gtk
xdg-desktop-portal-gnome
gnome-keyring
mate-polkit
```

Configuração:

```text
files/etc/xdg-desktop-portal/niri-portals.conf
```

Objetivos:

- file chooser;
- clipboard;
- notificações;
- secrets;
- autenticação polkit;
- integração GTK/Wayland.

Os portais seguem listados explicitamente no `Containerfile` mesmo vindo da base: o Niri depende deles, e o Universal Blue vem podando imagens intermediárias. Se a base parar de trazê-los, é melhor o build continuar correto do que a sessão quebrar de forma confusa.

**Agente SSH: o do gcr.** O `gnome-keyring` deixou de ser agente SSH, e o papel passou para o `gcr-ssh-agent`, do pacote `gcr`. O socket é habilitado para todo usuário (`systemctl --global`) e define o `SSH_AUTH_SOCK` no `systemd --user`, de onde o niri e tudo o que ele abre herdam. A senha da chave fica no chaveiro, que o login já destrava. Sem agente nenhum, cada `git push` pedia a senha da chave, e o VS Code, que não tem onde perguntar, falhava.

---

# 11. Localização

Padrões do Arkmos:

```text
Locale:    pt_BR.UTF-8
Teclado:   ABNT2
Timezone:  America/Sao_Paulo
Hostname:  arkmos
```

Declarados **na imagem**, não no primeiro boot:

```text
files/etc/locale.conf      LANG=pt_BR.UTF-8
files/etc/vconsole.conf    KEYMAP=br, XKBLAYOUT=br, XKBMODEL=pc105
files/etc/hostname         arkmos
/etc/localtime             symlink para zoneinfo/America/Sao_Paulo
```

Suporte ao locale:

```text
glibc-langpack-pt
```

**Não chamar `localectl` nem `timedatectl` na máquina.** Gravar esses arquivos em runtime os marca como modificados localmente e os congela contra futuras atualizações da imagem. Foi por isso que essa configuração saiu do firstboot na 0.8.0.

`/etc/localtime` tem de ser symlink: o nome da timezone é extraído do alvo do link.

Validação (no `just check` e no CI):

```bash
locale -a | grep -qx pt_BR.utf8
readlink /etc/localtime
grep -qx KEYMAP=br /etc/vconsole.conf
```

## 11.1 Pastas do usuário

O `xdg-user-dirs` cria as pastas do home no login, com o nome no idioma da sessão:

```text
Área de trabalho  Documentos  Downloads  Imagens  Modelos  Músicas  Público  Vídeos
```

Quem roda é a unit de usuário do pacote, `xdg-user-dirs.service`, ligada ao `graphical-session-pre.target` e habilitada pelo preset do Fedora; a entrada de autostart dele vem marcada para o systemd pular. O português depende do `LANG` do `systemd --user`, que vem de `/usr/lib/environment.d/10-arkmos-locale.conf` — o `/etc/locale.conf` não alcança o gerenciador de usuário.

Conta que já existe ganha as pastas no primeiro login depois da atualização.

## 11.2 O que continua em inglês

- **Overlay de atalhos do niri.** O niri não tem tradução. Cada linha aceita um `hotkey-overlay-title`, e as 19 ações que ele lista têm título em português na `config.kdl` — o `just check` barra ação sem título. O cabeçalho "Important Hotkeys" é fixo no binário. O overlay não abre sozinho no login (`skip-at-startup`); `Mod+Shift+/` o mostra.
- **Noctalia Greeter.** Não tem mecanismo de tradução: "Type password", "Search users…", "Shut down", "Restart", "No users found" e mais uns poucos textos estão fixos no código. O Noctalia Shell, esse sim, tem `pt-BR`. **Decisão (2026-09-15): aceito em inglês.** Traduzir no build seria o primeiro patch em código de terceiro do projeto, a conferir a cada versão, por uns dez textos.

---

# 12. First Boot

Arquivos:

```text
files/usr/libexec/arkmos-firstboot
files/usr/lib/systemd/system/arkmos-firstboot.service
```

## 12.1 Escopo

O assistente faz **apenas o que não pode estar declarado na imagem**:

1. Solicitar nome de usuário e validar.
2. Solicitar nome completo.
3. Criar o usuário com UID/GID 1000 e shell Zsh.
4. Adicionar aos grupos `wheel` e `docker`.
5. Solicitar e confirmar a senha.
6. Marcar a instalação como inicializada.

Locale, teclado, timezone e hostname **não** passam por aqui — ver seção 11.

Estado:

```text
/var/lib/arkmos/initialized
```

O arquivo é gravado somente ao final, depois de conta, grupos e senha confirmados. Qualquer interrupção antes disso faz o assistente rodar de novo no próximo boot e retomar de onde parou: se já existe conta no UID 1000, ele retoma a partir da senha em vez de pedir um nome novo — pedir travaria o assistente para sempre, já que o nome original seria rejeitado por "usuário já existe".

### Rebase: a conta já existe

Quem chega ao Arkmos por `bootc switch` a partir de outro Fedora Atomic (Silverblue, Kinoite, Aurora…) já tem conta: foi criada pelo Anaconda do sistema de origem e atravessa a troca junto com o `/var/home`. Antes deste ajuste, o assistente via essa conta no UID 1000 sem a marca de inicializado, a tratava como cadastro interrompido e exigia uma senha nova antes de liberar a tela de login.

Agora, antes de escrever qualquer coisa no console, ele procura contas humanas (UID entre `UID_MIN` e `UID_MAX` do `login.defs`) com senha definida. Se encontra, alguém já consegue entrar e não há o que perguntar: ele grava a marca e sai em silêncio, registrando no journal.

O que o rebase não traz é o grupo `docker`, que é do Arkmos, e sem ele o Laravel Sail não fala com o daemon. O assistente o acrescenta só às contas que já estão no `wheel`: estar no `docker` equivale a ser root, e uma conta que não administrava o sistema de origem não passa a administrar este.

O cadastro que o próprio assistente interrompeu continua sendo retomado: a conta nasce sem senha, e a senha é o último passo antes da marca. O `just check` cobre os dois caminhos, com uma conta criada pelo assistente e com contas preexistentes, dentro e fora do `wheel`.

## 12.2 Senha

O assistente pede a senha com prompt próprio, e não chamando `passwd`.

O `passwd` fala em inglês no meio de um assistente em português, pede a senha duas vezes sem avisar que vai pedir, e intercala mensagens do pwquality (`BAD PASSWORD: The password is shorter than 8 characters`) que parecem erro grave quando são aviso — como root, ele aceita a senha depois de reclamar. O resultado é um passo confuso justamente onde não se pode errar.

No lugar disso: a regra é dita antes, o retorno é em português, e a senha só é aceita quando as duas digitações batem. A senha vai para o `chpasswd` por stdin — não passa por linha de comando, não aparece em `ps` — e o resultado é confirmado com `passwd -S` em vez de confiar no código de saída.

A conclusão tem prazo:

```text
Indo para a tela de login em 20s — ENTER para ir agora.
```

Sem o prazo, quem não viu a mensagem — porque a janela da VM rolou o texto para fora — fica preso numa tela parada, sem saber o que o sistema espera. O resumo final é curto pelo mesmo motivo, e a instrução é a última linha.

## 12.3 Ordenação e console

A unit é ordenada:

```ini
After=systemd-vconsole-setup.service
After=plymouth-quit-wait.service
Before=greetd.service
Before=getty@tty1.service
```

O `After=plymouth-quit-wait.service` existe por um motivo concreto: sem ele o assistente arrancava junto com o `sysinit.target`, com o splash do plymouth ainda na tela, e o prompt nascia disputando a vt1 — o splash cobria o texto e, ao sair, redesenhava a tela por cima do que já estava escrito.

O script também silencia o status do systemd no console antes de escrever:

```bash
kill -s RTMIN+21 1
```

`SIGRTMIN+21` desliga a impressão de status no console e `SIGRTMIN+20` religa (ver `systemd(1)`). Sem isso, as linhas "Started…", "Listening on…" e "Reached target…" dos serviços que ainda estão subindo caem no meio das perguntas. O estado não é restaurado ao final de propósito: o plymouth manda o mesmo sinal quando sai, então console silencioso já é o normal depois do boot.

### O teclado da sessão gráfica vem do vconsole.conf

Parece faltar declaração, e não falta. O bloco `xkb` do `/etc/niri/config.kdl` está vazio de propósito: nesse caso o niri busca as configurações no `org.freedesktop.locale1`, e o `systemd-localed` responde com o `XKBLAYOUT` e o `XKBMODEL` do `/etc/vconsole.conf` — mesmo sem existir `/etc/X11/xorg.conf.d/00-keyboard.conf`, que é onde a documentação mais antiga manda procurar.

Verificado na VM instalada pela ISO, em 2026-09-23:

```text
$ localectl status
System Locale: LANG=pt_BR.UTF-8
    VC Keymap: br
   X11 Layout: br
    X11 Model: pc105

$ ls /etc/X11/xorg.conf.d
(não existe)
```

E o `ç` e o `ã` funcionam na sessão. A man page do `vconsole.conf` do systemd 259 **não** documenta as variáveis `XKB*`, o que faz parecer que elas são resquício inerte de outro formato — não são. Um arquivo em `xorg.conf.d` seria duplicação, e declarar `layout "br"` no niri seria uma terceira fonte da mesma verdade.

## 12.4 Por que um assistente próprio

O Universal Blue **não** cria usuário no primeiro boot. Verificado no Aurora instalado: não há `gnome-initial-setup` nem `initial-setup`; a conta vem do **Anaconda, durante a instalação da ISO**.

Os mecanismos de firstboot presentes na imagem são do systemd e nenhum serve:

```text
systemd-firstboot          locale/keymap/timezone/senha de root — não cria usuário comum
systemd-homed-firstboot    criaria via homectl, mas exige systemd-homed (ausente)
                           e mudaria o modelo de home
```

Para mídia gerada com `bootc-image-builder` e para `bootc install to-disk` não existe caminho pronto. O assistente em TTY é a resposta.

**Com a ISO instalável (`just iso`, seção 31), a conta vem do Anaconda, como no Universal Blue** — desde que o kickstart passou a ser nosso (abaixo). O assistente continua na imagem, e faz diferença nos dois cenários:

- concede o grupo `docker`, que nenhum instalador concede — o Anaconda, quando cria a conta (como no sistema de origem de um rebase), oferece `wheel` e para aí, e sem `docker` o Laravel Sail não fala com o daemon;
- cobre a instalação em que ninguém criou conta: `bootc install to-disk` não tem instalador, e a tela de conta do Anaconda pode ser pulada. Sem ele, o resultado seria uma máquina sem conta e sem senha de root, ou seja, uma reinstalação.

**Quem cria a conta depende do kickstart, e as duas ISOs ensaiadas em VM mostraram os dois lados:**

- **2026-09-23, kickstart padrão do builder:** o Anaconda não criou conta. O kickstart dele é completo (`clearpart --all` incluído), a instalação corre sem nenhuma tela, e a conta de usuário fica sem perguntar. Quem a criou foi o assistente, no primeiro boot;
- **2026-09-24, kickstart nosso:** sem o `clearpart`, a instalação para nas telas que faltam — disco, rede e **conta**. A conta foi criada no Anaconda, marcada como administradora, e o assistente se dispensou no primeiro boot acrescentando o `docker`: `groups` mostrou `arm wheel docker`.

A ideia de encolher o assistente para só conceder o grupo `docker` continua descartada: ele é o que cria a conta quando ninguém criou, e o custo de mantê-lo é zero quando a conta já existe — no rebase e na ISO. Ao criar a conta no Anaconda, basta marcá-la como administradora: o `docker` vem do assistente, e não precisa ser acrescentado nas opções avançadas.

## 12.5 Segurança

Não armazenar na imagem:

- senhas;
- chaves SSH pessoais;
- tokens;
- credenciais;
- informações pessoais.

O `config.toml` do bootc-image-builder é deliberadamente **sem** bloco `[[customizations.user]]`: definir um usuário ali pularia justamente o fluxo que precisa ser testado.

---

# 13. Shell

Shell padrão:

```text
Zsh 5.9 + Starship
```

## 13.1 Configuração própria

A configuração é do Arkmos e vive versionada no repositório:

```text
files/usr/share/arkmos/zsh/
├── .zshrc           ponto de entrada, carrega os módulos na ordem
├── history.zsh      histórico no state dir do usuário
├── completion.zsh   compinit com cache no cache dir do usuário
├── keybindings.zsh  modo emacs, busca por prefixo no histórico
├── aliases.zsh      eza, git, docker, sail, bootc
├── tools.zsh        starship, zoxide, fzf, EDITOR/PAGER
└── plugins.zsh      carregado por último

files/usr/share/arkmos/starship.toml
```

A ordem importa: `plugins.zsh` vem no fim porque o syntax-highlighting embrulha os widgets já definidos e o autosuggestions se apoia no histórico já configurado.

Tudo vive em `/usr`: read-only, igual para todo usuário, atualizado junto com a imagem. O que é dado de quem usa — histórico, cache do compinit — vai para os diretórios XDG do usuário, porque em `/usr` não poderia ser escrito. O `zsh` não cria o diretório do `HISTFILE` e falha em silêncio sem ele, então a configuração o cria.

`ZDOTDIR` é apontado por `/etc/zshenv`, o único lugar de onde isso é possível. Dois pontos de escape, em ordem de precedência:

1. `~/.config/zsh/.zshrc` próprio assume o controle total, e o `/etc/zshenv` passa a apontar o `ZDOTDIR` para lá.
2. `~/.config/zsh/local.zsh` é carregado por último pelo `.zshrc` da imagem, com a última palavra.

O modo vi fica deliberadamente fora: `bindkey -v` no `local.zsh` resolve, e é escolha de quem usa, não do sistema.

## 13.2 Plugins: RPM, não git clone

```text
zsh-autosuggestions        /usr/share/zsh-autosuggestions/
zsh-syntax-highlighting    /usr/share/zsh-syntax-highlighting/
```

Os dois vêm de RPM do Fedora. O dnf cuida de atualização e de licença, e nada é baixado na primeira abertura do shell — o que numa imagem imutável significaria shell quebrado em máquina recém-instalada e sem rede. Essa propriedade é verificada no CI, com a imagem rodando sem rede.

Busca no histórico por prefixo sai de widgets que o próprio zsh traz (`up-line-or-beginning-search`), e não de plugin.

## 13.3 A política

O que o Fedora empacota vem de RPM. O que não é empacotado vem do release upstream, com versão e checksum SHA256 fixados. Configuração é própria e fica versionada aqui.

Isso vale em especial para configuração de shell, que é tentador importar pronta:

- **Clone em tempo de build é código de terceiro entrando na imagem.** O Arkmos distribui a imagem, não só a constrói — e junto com o código vêm manutenção, licença e crédito.
- **Patch sobre código de outro depende de trechos exatos dele.** Qualquer mudança lá quebra o build ou, pior, aplica metade e produz um shell meio configurado.
- **Nada disso é o trecho difícil deste projeto.** Histórico, completion, teclas, aliases e três integrações: escrever e manter sai mais barato do que sincronizar com o upstream de outra pessoa.

---

# 14. Fontes

Duas fontes, com papéis separados:

```text
Adwaita Sans                  interface: Noctalia, janelas GTK, tela de login
JetBrains Mono Nerd Font 3.5.1  monoespaçada: terminal, editor, prompt, arte
```

A **JetBrains Mono** cobre o que é monoespaçado: terminal e editor, os glifos do prompt e a arte do sistema (a logo do README, o splash do Plymouth e a arte de login, desenhados pelo `render-artwork.sh`).

A **Adwaita Sans** é a fonte da interface, escolhida em 2026-09-24. Antes eram três: o Noctalia usava `sans-serif`, que no Fedora cai na Noto Sans; as janelas GTK, a Cantarell do dconf; e a tela de login, a JetBrains Mono. A Adwaita Sans é a padrão do GNOME desde a versão 48, derivada da Inter, e é com ela que os aplicativos libadwaita da imagem são desenhados. Vem da base (`adwaita-sans-fonts`), sem custo no build. Ela é declarada em cinco lugares — o `font_family` do `arkmos.toml` do skel, o `font-name` e o `document-font-name` do dconf, os dois `settings.ini` e o `greeter.toml` —, e o `just check` confere que os cinco concordam e que o fontconfig resolve o nome para ela mesma, e não para uma substituta.

No login ela é declarada no `greeter.toml`, que vence o sync: trocar a fonte nas configurações do Noctalia não chega à tela de login.

O `jetbrains-mono-fonts` do Fedora **não** é a versão patched; o `starship.toml` e o `eza --icons` dependem dos glifos Nerd Font, então a versão patched é baixada no build, com versão e checksum SHA256 fixados em `build_files/install-nerd-font.sh`.

**As ligaduras de código sobrevivem ao patch.** A família `JetBrainsMono Nerd Font` tem a tabela `calt`, que é como esta fonte implementa `!=` e `=>` — verificado com o fontTools no `.ttf` instalado. O `editor.fontLigatures` do VS Code fica ligado no `/etc/skel` por causa disso. O pacote traz ainda a família `JetBrainsMonoNL Nerd Font`, a mesma fonte **sem** ligaduras, então o nome na configuração importa, e não só a pasta. No `foot` não há ligaduras: o terminal não implementa isso.

A FiraCode foi considerada e descartada: a JetBrains Mono patched já tem as ligaduras, e duas fontes monoespaçadas na imagem seriam redundância.

Também instaladas: `google-noto-emoji-fonts`, e `google-carlito-fonts` e `google-crosextra-caladea-fonts`, que têm as mesmas medidas da Calibri e da Cambria, as fontes padrão do Word. Sem elas, um documento aberto aqui troca de fonte e desalinha. As Liberation, que cobrem Arial, Times e Courier, vêm da base.

---

# 15. Containers

```text
Podman 5.8
Docker CE 29.8 + compose
Distrobox 1.8
```

**Docker CE de verdade, não `podman-docker`.** O `podman-docker` é um shim que faz `docker` invocar o podman; é exatamente a substituição que este projeto proíbe, a origem clássica de atrito com Laravel Sail, e conflitaria com `docker-ce-cli`, já que ambos fornecem `/usr/bin/docker`. Sua ausência é verificada no CI.

O grupo `docker` é declarado em `files/usr/lib/sysusers.d/arkmos-docker.conf`, com GID dinâmico. Fixá-lo foi tentado e colidiu com o greetd, que recebeu o mesmo número por alocação dinâmica ao ser instalado antes; como socket, membros de grupo e permissões resolvem por nome em runtime, fixar o número traz colisão sem trazer benefício.

---

# 16. Ambientes Distrobox

A imagem entrega a ferramenta, e não os ambientes: `distrobox` e `podman`, que vêm da base, e o DistroShelf (Flatpak) para gerenciar os containers pela interface.

Os containers em si **não são declarados neste repositório**. Ficam num repositório privado do usuário, recriados a partir de lá com `distrobox assemble`. Três motivos:

- **São escolhas pessoais.** Quais ferramentas, de qual distribuição, em qual versão: nada disso é o sistema, e o repositório e a imagem são públicos.
- **Um deles guarda software que não pode ser redistribuído.** O Insync tem licença "non-transferable, without the right to sublicense", que proíbe distribuí-lo. Declarar o container publicamente não o redistribuiria, mas misturaria no repositório do sistema algo que só faz sentido na conta de uma pessoa.
- **Não moram na imagem de qualquer forma.** Um container Distrobox vive no storage do usuário, em `~/.local/share/containers`, e sobrevive a `bootc upgrade` e a rollback sem depender da imagem.

A regra vale além do Insync: software proprietário que a licença impede de redistribuir fica fora da imagem, mesmo que seja de uso diário.

## O que a imagem garante para esses ambientes

Os ambientes em uso hoje servem de referência do que a imagem precisa suportar:

| Container | Para |
| --- | --- |
| `fedora-app` | Insync |
| `fedora-mobile` | Android Studio com emulador, SDK, Flutter, Dart, FVM, JDK, Gradle |
| `ubuntu-db` | MySQL Workbench |

E o que eles precisam do sistema, verificado na imagem:

- **Emulador Android:** o `/dev/kvm` é liberado para todos (`MODE="0666"`, na regra padrão do udev do systemd).
- **Celular por USB para o `adb`:** o `70-uaccess.rules` do systemd libera dispositivos ADB e fastboot ao usuário logado. O `adb` de dentro do container enxerga o celular sem regra extra no host.
- **Atalhos no menu:** `distrobox-export --app` põe o aplicativo do container no lançador do Noctalia.

---

# 17. Desenvolvimento

Ferramentas na imagem:

```text
Git
GitHub CLI (gh)
Curl / Wget
Neovim / Vim
Zsh
Python
OpenSSH (cliente)
eza / bat / fd / fzf / ripgrep / zoxide
lazygit / lazydocker
mise 2026.9.10
VS Code 1.139
```

## 17.1 VS Code na imagem, não em Flatpak

No Flatpak o terminal integrado roda dentro do sandbox e não enxerga o docker do host — o que quebra o Laravel Sail, que é dirigido inteiramente por `docker compose` a partir desse terminal. A extensão Dev Containers também não funciona sob Flatpak.

Manter o VS Code numa imagem que é publicada tem uma questão de licença, tratada na seção 28.4. Os defaults dele são semeados por `/etc/skel` (seção 26.1).

## 17.2 Toolchains: mise no sistema, versões no `$HOME`

O `mise` está na imagem; as linguagens que ele gerencia, não.

A imutabilidade trava `/usr`, não o `$HOME` — e toolchain moderna (Go, Node,
Python, Rust) instala inteiramente no home do usuário, sem root. Declarar uma
delas na imagem amarraria a versão ao ciclo de build: trocar a versão do Go
passaria a custar rebuild e reboot. Com o mise, custa um comando, e a versão
fica declarada por projeto, no `.mise.toml` versionado junto do código.

É também o que dispensa container para desenvolver: o container continua
valendo para os **serviços** do projeto (`docker compose`, Sail) e para
ambientes fechados (Distrobox, seção 16), não para a linguagem.

A ativação do zsh fica em `files/usr/share/arkmos/zsh/tools.zsh`, junto das
outras integrações do shell; a do bash, em `files/etc/profile.d/mise.sh`. As
duas valem para shell **interativo**: `mise activate` instala um hook de prompt
que ajusta o PATH ao entrar num diretório com `.mise.toml`. Sem ativação o
binário está na imagem e não serve para nada, então o `just check` exige as
duas.

O arquivo do bash tem duas guardas, e nenhuma é decorativa. A primeira é
`BASH_VERSION`, porque `/etc/profile.d` **não** é exclusivo do bash: o
`/etc/zshrc` do Fedora também carrega esse diretório, e sem a guarda o zsh
receberia a ativação em dialeto de bash — antes da correta, ainda. É por isso
que a verificação do zsh exige `MISE_SHELL=zsh`: é ela que denuncia a guarda
quebrada. A segunda é shell interativo, pelo mesmo motivo da seção acima.

O arquivo também não usa `return`: o zsh faz o source dele de dentro de uma
função, e um `return` ali interromperia o laço, deixando os demais scripts de
`profile.d` sem carregar.

**O mise se atualiza com a imagem, não sozinho.** Ele está em `/usr/bin`,
somente leitura, com a versão fixada em `build_files/install-upstream-bins.sh`.
Do jeito que vem, ele avisava de versão nova e sugeria `mise self-update` — que
falharia ao tentar se substituir, e apontaria para uma atualização fora do
alcance de quem usa. Dois arquivos resolvem:

```text
files/etc/mise/config.toml                            disable_update_warning = true
files/usr/lib/mise/mise-self-update-instructions.toml "atualizado junto com o sistema"
```

O primeiro fica em `/etc` porque é de lá que o mise lê a configuração de
sistema, e desligar o aviso também elimina a consulta periódica ao GitHub. O
segundo é o mecanismo que o mise oferece a empacotadores: com ele presente, o
self-update fica indisponível, e onde o mise orienta a atualizar aparece a
mensagem do Arkmos. O mise procura esse arquivo em `<instalação>/lib/mise/`,
com `<instalação>` sendo o binário canonizado dois níveis acima — `/usr`.

Como o VS Code está na imagem e não em Flatpak (seção 17.1), a extensão da
linguagem enxerga o binário que o mise instalou sem configuração extra.
Atenção a um detalhe: o terminal integrado herda o PATH do zsh, mas o processo
do VS Code herda o de quem o lançou — se a extensão não achar a toolchain que
o terminal acha, o PATH dos shims precisa estar no `environment.d` do usuário,
e não só no shell.

## 17.3 Stack principal

```text
Laravel
PHP
Inertia
React
TypeScript
Vite
ShadCN
Node
Docker
Laravel Sail
PostgreSQL
Redis
```

---

# 18. Python

Python deve ser fornecido pelo Fedora.

Preferência:

```text
Python nativo
```

Projetos devem utilizar ambientes virtuais:

```bash
python -m venv .venv
```

Evitar modificar o Python do sistema com instalações globais via `pip`.

---

# 19. Banco de Dados

Principal:

```text
PostgreSQL
```

Infraestrutura atual/futura:

```text
Supabase
```

---

# 20. Áudio

Stack:

```text
PipeWire 1.6
WirePlumber 0.5
ALSA
PulseAudio compatibility
```

Vem da base. Objetivos: áudio moderno, compatibilidade PulseAudio, gerenciamento de dispositivos, integração Bluetooth.

---

# 21. Bluetooth

```text
BlueZ 5.87
```

---

# 22. Rede

```text
NetworkManager 1.56
tailscale
firewalld, zona FedoraWorkstation
```

Objetivos: Ethernet, Wi-Fi, VPN, integração com desktop.

O painel do Noctalia conecta em Wi-Fi e cabo. O que ele não cobre (IP fixo, hotspot, VPN, Wi-Fi corporativo) fica no `nm-connection-editor`.

**Tailscale** vem do Fedora, com o `tailscaled` habilitado. A máquina entra na rede com `sudo tailscale up`, uma vez.

**Firewall na zona FedoraWorkstation**, a mesma do Fedora Workstation: portas altas liberadas na rede local. A `public`, que vinha da base, bloqueava sem avisar o LocalSend (porta 53317) e um servidor de desenvolvimento acessado pelo celular.

**Servidor SSH desligado.** A base o habilita, e com a zona que o libera, num Wi-Fi público qualquer um tentaria entrar com senha. Desabilitar na imagem não bastava: o `/etc/machine-id` nasce vazio, o systemd trata o primeiro boot como tal e reaplica os presets, e o `90-default.preset` do Fedora o habilitaria de novo. O `10-arkmos.preset` vem antes e vence; o `just check` confere o estado e o preset. A VM de teste o liga pela linha de boot (seção 30).

---

# 23. Energia

```text
tuned 2.28
tuned-ppd
```

Objetivos: gerenciamento de performance, perfis de energia, autonomia em notebook.

Os diretórios que o tuned espera em `/var` são declarados em `tmpfiles.d` e não assados na imagem — ver seção 3.4.

**Bloqueio por inatividade.** O Noctalia vem com toda ação por inatividade desligada: a tela nunca bloqueava nem apagava sozinha. O `arkmos.toml` do skel liga o bloqueio e a tela apagada, com os tempos do próprio Noctalia (10 e 11 minutos). Cada ação é declarada inteira — ação e tempo, não só `enabled` —, porque o Noctalia **substitui** o bloco em vez de mesclá-lo com o padrão: declarar só `enabled = true` deixava a ação vazia e o tempo em zero, ligado e sem efeito, sem erro nenhum. O `just check` confere a configuração efetiva, como o Noctalia a lê, e não o arquivo. A suspensão por inatividade fica desligada, para não interromper um build ou um download longo; fechar a tampa já bloqueia antes de suspender (`lock_before_suspend`, ligado por padrão). Como é skel, vale para conta nova. Os tempos se mudam nas configurações do Noctalia (`noctalia msg settings-open`, seção de inatividade), que gravam em `~/.local/state/noctalia/settings.toml` e vencem o padrão.

---

# 24. NVIDIA

A máquina alvo é um notebook com gráficos Intel integrados e uma **dGPU NVIDIA alternável pela BIOS**, mantida desligada por autonomia de bateria e ligada sob demanda. Com ela desligada, a GPU não aparece no `lspci` — a máquina se apresenta como se fosse só Intel.

É isso que torna os akmods assinados um requisito real, e foi o que decidiu a base (seção 5).

## 24.1 Estratégia

A pilha NVIDIA vive numa **variante** da imagem, não num condicional dentro dela:

```text
arkmos          sem driver
arkmos-nvidia   driver assinado + container toolkit
```

Trocar de variante numa máquina instalada é `bootc switch` e um reboot, não uma reinstalação. A consequência aceita: na variante padrão, ligar a dGPU na BIOS não traz driver nenhum.

## 24.2 Ajustes na variante NVIDIA

```text
files/etc/nvidia/nvidia-application-profiles-rc.d/
    50-limit-free-buffer-pool-in-wayland-compositors.json
files/usr/lib/systemd/system/nvidia-cdi-refresh.service.d/
    50-arkmos-gpu-presente.conf
```

O `nvidia-cdi-refresh.service` vem da base e condiciona a existir `nvidia-smi` e `nvidia-ctk`, que existem sempre. Seu `ExecStart` é

```text
nvidia-smi -L || /usr/sbin/nvidia-smi -L || /usr/lib/wsl/lib/nvidia-smi -L
```

Sem GPU, os dois primeiros falham e o terceiro não existe: a unit morre com 127, reinicia cinco vezes e termina em `failed`. Isso acontece em toda VM de teste e aconteceria nesta máquina sempre que a dGPU estivesse desligada — o Aurora instalado carrega essa mesma falha em todo boot.

O drop-in condiciona ao vendor PCI da NVIDIA:

```ini
[Service]
ExecCondition=/bin/sh -c 'grep -qx 0x10de /sys/bus/pci/devices/*/vendor'
```

Com a GPU ausente, o systemd registra a unit como **pulada** em vez de **falhada**. O problema não é estético: um `systemctl --failed` que nunca está vazio deixa de servir para achar a falha seguinte.

Condicionado ao hardware, e não a `/dev/nvidiactl`, de propósito: esse device pode ser criado sob demanda no primeiro uso do driver, e condicionar a ele arriscaria nunca gerar o CDI numa máquina que tem a GPU ligada.

---

# 25. Aplicações Gráficas

Estratégia por camada:

```text
Sistema base   →  componentes necessários e o que precisa do docker/PATH do host
Flatpak        →  aplicações gráficas
Distrobox      →  ambientes específicos
AppImage       →  aplicações independentes
```

Onde fica cada aplicativo em uso:

| Aplicativo | Camada |
| --- | --- |
| Podman, Distrobox, Docker CE | imagem |
| VS Code | imagem: precisa do docker do host (seção 17.1) |
| Nautilus, Discos, compactação, assistente de impressão | imagem: integração com o sistema (25.1, 25.2) |
| Chrome, Thunderbird, Spotify, Discord, OnlyOffice, Inkscape, Switcheroo, AnyDesk | Flatpak |
| Papers (PDF), Loupe (imagens), Showtime (vídeo), Calculadora | Flatpak |
| Fedora Media Writer, LocalSend, Galaxy Buds Client, Mecalin | Flatpak |
| Monitor de sistema: btop, no lugar do htop da base | imagem |
| Flatseal, Warehouse, Bazaar (loja), Embellish (Nerd Fonts), DistroShelf (Distrobox) | Flatpak |
| Insync, Android Studio com emulador, MySQL Workbench | Distrobox, declarado num repositório privado (seção 16) |
| Tolaria, Tabularis | AppImage, pelo AppManager |
| Captura de tela com anotação | Noctalia, no `Shift+Print` |

Lista declarada de Flatpaks:

```text
files/usr/share/flatpak/preinstall.d/arkmos.preinstall
```

Ela substituiu a `flatpaks.list`, que era a captura crua do Aurora, com aplicações KDE que não faziam sentido sob o niri. A lista nova parte do que de fato é usado; dos extras do Aurora ficaram só os que não são do KDE e têm uso, e o Kontainer deu lugar ao DistroShelf, que faz o mesmo com interface GNOME.

### Como a lista é aplicada

Pelo `flatpak preinstall`, que existe desde o Flatpak 1.16 justamente para isto: o sistema declara os Flatpaks que o acompanham num arquivo em `/usr/share/flatpak/preinstall.d/`, e o comando sincroniza a instalação de sistema com ele. O `arkmos-flatpak-preinstall.service` o roda a cada boot, como o próprio Flatpak recomenda:

- instala o que está na lista e falta;
- desinstala o que saiu da lista numa imagem nova, se tinha sido instalado por ela;
- não reinstala o que a pessoa desinstalou por conta própria.

É o que faz um aplicativo acrescentado aqui chegar à máquina depois do `bootc upgrade`, e um retirado sair dela, sem script de reconciliação próprio.

O arquivo não diz de qual remoto instalar. O `preinstall` resolve pelos remotos ativos, e o único é o Flathub: a base o configura e deixa os repositórios do Fedora desativados. As atualizações também são da base, pelo `flatpak-system-update.timer`, uma vez por dia. O `just check` confere que o Flathub continua configurado, porque sem ele nada seria instalado e nada reclamaria.

O serviço é `Type=exec`, e não `oneshot`. Um oneshot seguraria o `multi-user.target` até o fim da instalação, que no primeiro boot são alguns GB. Assim o boot segue, e a instalação corre em segundo plano com prioridade baixa. Sem rede, ele tenta de novo a cada minuto, por até dez vezes; o que não der fica para o boot seguinte.

A lista também leva a extensão de tema `org.gtk.Gtk3theme.adw-gtk3-dark`, como runtime. O sandbox não vê o `/usr/share/themes` do host, e sem ela um Flatpak GTK3 cai no Adwaita do runtime (seção 26.1).

### Como o Universal Blue faz

Verificado nos repositórios deles, porque a pergunta "estamos fazendo igual?" merece resposta com fonte:

- **Bluefin** declara em `/usr/share/flatpak/preinstall.d/*.preinstall` e habilita um serviço que roda o `flatpak preinstall` — o mesmo mecanismo daqui. Eles ainda mantêm um teste no build para o arquivo não desaparecer da imagem, com a justificativa explícita de que, sem ele, o aplicativo **sai** das máquinas na atualização seguinte. É a confirmação de que a sincronização nos dois sentidos é comportamento esperado, e não efeito colateral.
- **Bazzite** instala por post-script do Anaconda (`install-flatpaks.ks`), no kickstart da ISO. Funciona, mas amarra os aplicativos à mídia: quem chega por rebase não recebe nada, e a lista não se reconcilia depois.

A única diferença em relação ao Bluefin é a unidade: eles habilitam um `flatpak-preinstall.service` que o Fedora 44 não entrega — o `flatpak` 1.18.2 traz o comando, e nenhum pacote do repositório instala essa unidade. Daí o `arkmos-flatpak-preinstall.service`, com a mesma função.

### Aplicativos padrão

`/etc/xdg/mimeapps.list` aponta PDF para o Papers, imagens para o Loupe e vídeo para o Showtime. Sem ele, o clique duplo num PDF abriria o Chrome. Os padrões do Fedora apontam para Evince, Eye of GNOME e Totem, que não existem aqui, e o sistema então escolhe qualquer aplicativo que se declare capaz de abrir o tipo — e o Chrome se declara para PDF e imagens.

Arquivos de texto (`text/plain`, Markdown, JSON, YAML, TOML, scripts) abrem no VS Code. O padrão do Fedora para `text/plain` é o nvim, um programa de terminal: o clique duplo num `.txt` abria um terminal, ou nada.

Os tipos de mídia são os que cada aplicativo declara no próprio `.desktop`. O `just check` confere que todo padrão aponta para um aplicativo da lista de preinstall ou da imagem. O "Abrir com" do Nautilus continua mudando o padrão da conta, porque `~/.config/mimeapps.list` vence o de `/etc/xdg`.

**O id do `.desktop` muda debaixo dos pés.** O pacote da Microsoft renomeou a entrada do VS Code de `code.desktop` para `com.microsoft.VSCode.desktop` na 1.139.0 (setembro de 2026), sem deixar link de compatibilidade — e com ela mudou também o `StartupWMClass`. Um padrão que aponta para um id que não existe não dá erro: o clique duplo simplesmente volta a não abrir nada. Duas defesas:

- no `mimeapps.list`, cada tipo de texto lista **os dois ids**, `com.microsoft.VSCode.desktop;code.desktop;`. O valor é uma lista, e vale o primeiro id instalado, então a imagem funciona antes e depois da renomeação — e funcionaria se a Microsoft voltasse atrás;
- o `just check` confere que **pelo menos um** id de cada tipo existe, e confere também os ícones fixados no dock do Noctalia, que são ids de `.desktop` e onde não cabe listar dois (cada item é um ícone, e o antigo apareceria morto ao lado do novo). Foi essa verificação que pegou a renomeação, no CI, antes de a imagem ser publicada.

### Os Flatpaks precisam estar no XDG_DATA_DIRS da sessão

O Fedora só acrescenta as pastas do Flatpak ao `XDG_DATA_DIRS` pelo `/etc/profile.d/flatpak.sh`, que roda em shell de login. O `systemd --user`, que inicia a sessão gráfica, não passa por lá: o niri e tudo o que ele abre nasciam com `XDG_DATA_DIRS=/usr/local/share:/usr/share`.

A consequência não dá erro em lugar nenhum. O Nautilus não encontra aplicativo capaz de abrir o arquivo, e o clique duplo numa imagem, num PDF ou num vídeo não faz nada — com o Flatpak instalado e o padrão declarado no `mimeapps.list`. O lançador do Noctalia não sofria com isso, porque procura os aplicativos por conta própria; foi assim que o sintoma apareceu como "abre pelo menu, não abre pelo arquivo".

O `files/usr/lib/environment.d/20-arkmos-flatpak.conf` declara a lista completa para o `systemd --user`, na mesma ordem do `flatpak.sh`. O `profile.d` continua valendo para os shells e não duplica o que já estiver lá.

### Menu de aplicativos

Três tipos de entrada apareciam no menu sem servir para nada:
- o modo servidor e o cliente do foot, que o pacote traz junto do terminal;
- a do Noctalia, que inicia um shell que o niri já iniciou no login, e por isso, clicada, não faz nada.

As três recebem `NoDisplay=true` no build, e o build falha se um pacote renomear o arquivo. No lugar da do Noctalia entra **Configurações do Noctalia**, até aqui a única forma de chegar às configurações dele era pela linha de comando.

O **nvtop**, monitor de GPU que vem da base, é um programa de terminal. Sem uma GPU que ele reconheça, como na VM, ele mostra "No GPU to monitor." e fecha na hora, levando a janela do terminal junto, e parece que nada aconteceu. No notebook, com Intel e NVIDIA, funciona. Os programas de terminal abrem pelo lançador do Noctalia, que procura o terminal por conta própria e acha o foot.

### Captura de tela

O niri captura sozinho: `Print` para uma região, `Ctrl+Print` para a tela e `Alt+Print` para a janela. Para anotar, `Shift+Print` chama o `screenshot-annotate` do Noctalia, que congela a tela, deixa desenhar e escrever por cima, e então copia ou salva. É o papel que o Spectacle tinha no KDE; ele não está no Flathub e depende do KWin.

Os dois salvam em `~/Imagens/Capturas de tela`, o nome que o GNOME usa. O padrão do niri era um caminho fixo em inglês, `~/Pictures/Screenshots`, que criaria um `~/Pictures` ao lado do `~/Imagens`; o do Noctalia era a raiz de `~/Imagens`. A pasta do Noctalia vem no `arkmos.toml` do skel, então vale para conta nova.

### AppImage

Tolaria e Tabularis são AppImages, e ficam com quem usa: não entram na imagem nem na lista. Quem os instala e atualiza é o [AppManager](https://github.com/kem-a/AppManager), também um AppImage, que se instala sozinho. Ele tem interface GTK4 e comandos de terminal (`app-manager install`, `app-manager --update-all`).

A imagem traz a `fuse-libs`, que a base não tem. AppImages com o runtime clássico a carregam para se montar, e sem ela nem abrem: `dlopen(): error loading libfuse.so.2`. O AppManager usa um runtime novo e não depende dela.

### AnyDesk sob o niri

Usar esta máquina para controlar outra funciona. Esta máquina ser controlada não: o niri compartilha a tela, mas não implementa o controle remoto de entrada (`org.gnome.Mutter.RemoteDesktop`), e sem ele o outro lado não move mouse nem digita.

## 25.1 Gerenciador de arquivos: Nautilus, na imagem

O gerenciador de arquivos fica na camada do sistema, não em Flatpak. Ele não é um aplicativo isolado, é integração: montar pendrive (udisks), falar MTP e SMB e ter lixeira (gvfs), e implementar `org.freedesktop.FileManager1` — a interface D-Bus que o "mostrar na pasta" do VS Code e do Firefox chama. No sandbox ele precisaria de `filesystem=host` para ser útil, e ainda assim ficaria sem o resto.

| Opção | Custo na imagem | Observação |
| --- | --- | --- |
| **Nautilus** | 10 pacotes, 22 MiB | GTK4/libadwaita, segue o tema escuro já configurado; traz o gvfs |
| Thunar | 15 pacotes, 35 MiB | puxa `xfce4-panel` e `xfconf`, sem uso sob o Niri |
| Dolphin | 85 pacotes | KDE; Qt coberto só pelo portal |

O seletor de arquivos dos aplicativos continua no backend `gtk` do portal (`niri-portals.conf`). O backend do GNOME delega o seletor ao próprio Nautilus.

**Os backends do gvfs que a base não traz** entram junto: `gvfs-mtp` faz o celular ligado por USB aparecer, `gvfs-smb` abre pastas compartilhadas na rede, e `gvfs-fuse` dá a esses locais um caminho de verdade (`/run/user/UID/gvfs`), sem o qual um Flatpak ou o VS Code não abrem um arquivo que está no celular. O `sushi` é a pré-visualização da tecla Espaço, e o `papers-thumbnailer` gera as miniaturas de PDF, porque o Papers da lista de Flatpaks não exporta o dele para o host.

**Programas de terminal abertos pelo Nautilus.** O GLib descobre em qual terminal abrir um programa como o btop ou o nvim por uma lista embutida que não conhece o foot, e a ação simplesmente não acontecia. O `xdg-terminal-exec` resolve, com o foot declarado em `/etc/xdg/xdg-terminals.list`.

**Discos e compactação vão junto**, pelo mesmo motivo: são integração com o sistema de arquivos e com o hardware. O `gnome-disk-utility` traz o montador de imagem que o Nautilus usa no clique duplo numa `.iso`, e o aplicativo Discos — formatar pendrive, gravar imagem, ver o SMART do disco. O `file-roller` abre um arquivo compactado para navegar e extrair só parte dele; o "Comprimir" e o "Extrair aqui" do Nautilus já funcionavam sozinhos, pelo `gnome-autoar`. Os dois custam 12 MiB.

Os formatos vêm da base: `7zip`, `zip`, `xz`, `zstd`, `bzip2` e a `libarchive`. O `7zip` do Fedora não traz o codec RAR, por licença, e quem lê RAR é a `libarchive` — verificado extraindo, na imagem, os arquivos de teste RAR e RAR5 do próprio projeto libarchive. Dois limites ficam: **criar** RAR não é possível (o formato de escrita é proprietário) e RAR **com senha** a `libarchive` não abre; isso exigiria o `unrar`, que só existe no RPM Fusion *nonfree*.

### O indexador, e por que ele não subia

O `localsearch` (antigo `tracker-miners`) vem da base e é o que dá busca por conteúdo e "recentes" ao Nautilus. Ele não subia, e o modo de falhar é o pior possível: a unit traz `ConditionEnvironment=XDG_SESSION_CLASS=user` e o systemd a **pula** — não é falha, é condição não satisfeita. O único sinal é uma linha no journal, mais o Nautilus reclamando no stderr que não conseguiu ativar `org.freedesktop.Tracker3.Miner.Files`.

A condição não está errada sobre esta máquina: a sessão é classe `user` para o logind (`Class=user`, `Service=greetd`). O que falta é a variável no ambiente do `systemd --user` — com greetd e `niri-session`, o `import-environment` traz `XDG_SEAT`, `XDG_VTNR`, `XDG_SESSION_ID` e as demais, mas não `XDG_SESSION_CLASS`.

O drop-in em `files/usr/lib/systemd/user/localsearch-3.service.d/` **zera** a lista de condições, em vez de trocá-la por outra. O propósito dela no upstream — não indexar em sessão de greeter ou de background — segue garantido por quem dispara a unit: o autostart da sessão gráfica e a ativação D-Bus do Nautilus, e a conta do greeter não roda nenhum dos dois. Uma condição nova no lugar (`XDG_CURRENT_DESKTOP=niri`, por exemplo) voltaria a quebrar em silêncio no dia em que esse valor mudasse de forma. O `just check` falha também se o upstream mudar a condição, para o drop-in não envelhecer calado.

### Ruído conhecido: "Invalid service client type"

Ao abrir o Nautilus pelo terminal aparece:

```text
Failed to initialize display server connection: GDBus.Error:
org.freedesktop.DBus.Error.InvalidArgs: Invalid service client type
```

É inofensivo, e não há o que corrigir deste lado. O Nautilus pede ao compositor uma conexão Wayland especial pela interface `org.gnome.Mutter.ServiceChannel`, do compositor do GNOME. O niri implementa essa interface por compatibilidade, mas só para o tipo de cliente que ele atende, e recusa o do Nautilus — as duas pontas estão nos binários: `OpenWaylandServiceConnection` no Nautilus, e a mensagem exata no niri. O Nautilus registra a recusa e segue normalmente. Aqui essa conexão não faz falta: o seletor de arquivos usa o backend `gtk` do portal (`niri-portals.conf`).

## 25.2 Impressão

A base já traz o obrigatório do grupo `printing` do Fedora (`cups`, `cups-filters`, `ghostscript`) e quase todos os padrões dele: `hplip`, `gutenprint`, `ipp-usb`, `colord`, `nss-mdns`, `samba-client`, `system-config-printer-udev`, além do `sane-backends` para scanner. Faltava a parte que se usa — nenhum programa permitia **cadastrar** uma impressora.

Entram o `system-config-printer`, que é o assistente, e o `cups-pk-helper`, que o deixa cadastrar sem root, pedindo autorização ao polkit em vez de exigir `sudo`. O assistente puxa o `dbus-daemon` como dependência; o barramento do sistema continua no `dbus-broker`, e o `just check` afirma isso, porque essa troca não daria erro nenhum.

O `cups-browsed` segue desligado, como no preset do próprio Fedora, que só habilita `cups.socket` e `cups.path`.

O assistente recebe um ajuste no build. Ele põe o botão **Desbloquear** na linha do menu, ocupando a altura dela inteira: sob uma barra de título isso passa despercebido, mas com o `prefer-no-csd` do niri não há barra, e o botão encosta na borda da janela. Um `sed` acrescenta 6 px de margem em cima e embaixo, e o build confere o resultado: se o pacote mudar a linha, ele falha em vez de seguir sem o ajuste.

---

# 26. Identidade Visual

O Arkmos deve possuir identidade visual própria, não derivada de nenhum outro ambiente.

## 26.1 O que já existe

Não é identidade ainda — é o mínimo para o sistema não se apresentar com metade das janelas claras e metade escuras:

```text
prefer-no-csd no niri            decoração desenhada pelo compositor
/etc/xdg/foot/foot.ini           terminal escuro, sem barra de título
/etc/dconf/db/local.d/           tema escuro no GSettings
  10-arkmos-appearance           (color-scheme, gtk-theme, ícones, cursor, fontes)
/etc/xdg/gtk-3.0/settings.ini    o mesmo tema, por um caminho que não depende
/etc/xdg/gtk-4.0/settings.ini    de portal nem de D-Bus
/usr/share/icons/Papirus         ícones Papirus-Dark, pastas em violeta
/etc/xdg-desktop-portal/         backend gtk para a interface Settings
  niri-portals.conf
/etc/greetd/config.toml          tela de login com nome, cores e retorno ao digitar
/usr/share/plymouth/themes/      splash de boot com o nome do sistema
  arkmos
/usr/share/backgrounds/arkmos    papéis de parede do projeto, mais o gerado
                                 no build
/etc/skel/.config/noctalia/      esquema Tokyo Night, papel de parede padrão,
  arkmos.toml                    sync do login, bloqueio por inatividade
```

### Por que três lugares para a mesma coisa

Não é redundância por descuido — são caminhos de leitura diferentes, e cada um cobre a falha do outro:

- **GSettings (dconf)** é onde o tema "oficialmente" mora. Fora de uma sessão GNOME não há daemon de configurações para distribuir esse valor, então quem quiser saber tem de ir buscar.
- **O portal de Settings** é como aplicativos sandboxed e não-GTK perguntam. Ele lê do GSettings e responde a quem perguntar — Firefox e aplicativos Electron perguntam por aqui. O detalhe que custou um teste: a interface Settings não estava declarada no `niri-portals.conf` e caía no `default=gnome;gtk;`, ou seja, no backend do GNOME, que pressupõe componentes de uma sessão GNOME inexistentes aqui. Ninguém respondia, e cada aplicativo usava o próprio default claro.
- **`/etc/xdg/gtk-*/settings.ini`** é lido direto pela biblioteca GTK, sem D-Bus e sem portal. É a rede de segurança: se o portal não subir, o GTK3 ainda encontra o tema aqui em vez de cair no Adwaita claro.

O `user-db` vem antes do `system-db` no profile do dconf, e um `~/.config/gtk-3.0/settings.ini` tem precedência sobre o de `/etc/xdg` — então isso é padrão, não imposição.

### O alcance: por classe, não por programa

Nada disso é configurado aplicativo por aplicativo. Cada camada atende uma forma de descobrir o tema, e um programa instalado depois já nasce escuro se usar uma delas:

| Classe | Como descobre o tema | Situação |
| --- | --- | --- |
| GTK3 nativo (Firefox, GIMP…) | `settings.ini` de `/etc/xdg`, GSettings e portal | coberto pelos três |
| GTK4 / libadwaita | GSettings e portal (`color-scheme`) | coberto |
| Qt 6.5+ | portal (`color-scheme`), nativamente | coberto pelo portal — não há aplicativo Qt na imagem para confirmar aqui |
| Electron / Chromium | portal, para a parte nativa | coberto; o tema interno do aplicativo é dele |
| Flatpak | portal | parcial — ver abaixo |
| Aplicativo com tema próprio | configuração dele | fora de alcance por natureza |

Vale notar que `qgnomeplatform` e `adwaita-qt`, que eram a resposta para Qt, **não existem mais no Fedora 44**. Não é regressão: o Qt passou a ler o portal direto, e o portal é justamente o que foi consertado aqui.

### Flatpak é o caso parcial

Um Flatpak não vê `/etc/xdg/gtk-3.0/settings.ini` nem o banco do dconf do host: o sandbox tem o próprio `/etc`. O que atravessa é o portal, e por isso `color-scheme` funciona — aplicativo moderno, sandboxed, escolhe escuro corretamente.

O que não atravessa é o **tema GTK3 em si**: para um Flatpak aplicar `adw-gtk3-dark`, o tema precisa estar instalado como extensão Flatpak (`org.gtk.Gtk3theme.adw-gtk3-dark`). Sem isso ele usa o Adwaita do runtime, que respeita claro/escuro mas não é o mesmo tema.

A extensão está na lista de preinstall (seção 25) e chega junto com os aplicativos.

### Aplicativo com tema próprio: /etc/skel

O VS Code tem sistema de temas próprio, e o `workbench.colorTheme` vive no `settings.json` do usuário — nenhum portal, variável de ambiente ou configuração de sistema alcança isso.

O que alcança é semear o arquivo:

```text
files/etc/skel/.config/Code/User/settings.json
```

O `useradd --create-home` copia `/etc/skel` para o home ao criar a conta, e o assistente do primeiro boot usa exatamente essa flag. O que fica semeado:

```json
"window.autoDetectColorScheme": true,   segue claro/escuro do sistema
"window.titleBarStyle": "custom",       barra desenhada com o tema do editor
"editor.fontFamily": "JetBrainsMono Nerd Font",
"update.mode": "none",                  ver abaixo
"telemetry.telemetryLevel": "off"
```

`update.mode: none` não é preferência: numa imagem read-only o VS Code não consegue se atualizar, e sem isso ele tenta e falha periodicamente. Atualização vem com a imagem.

Isto é um **default semeado**, não configuração imposta: a partir daí o arquivo é do usuário e nada o sobrescreve. Vale só para conta nova — `/etc/skel` não alcança quem já existe.

O `just check` verifica as duas pontas: que o arquivo está na imagem com os valores que importam, e que o assistente de primeiro boot realmente o entrega no home.

### Esquema de cores: Tokyo Night

Escolhido em 2026-09-21, entre os dois que estavam na mesa. É um dos esquemas embutidos no Noctalia, declarado no `arkmos.toml` do skel:

```toml
[theme]
source = "builtin"
builtin = "Tokyo-Night"
mode = "dark"
```

O identificador é exatamente `Tokyo-Night`, como no código do Noctalia. O validador dele **não** confere nomes de esquema: um nome errado seria ignorado em silêncio e o shell abriria no esquema padrão. Por isso o `just check` compara o nome declarado com a lista de embutidos do próprio binário.

É do esquema que saem as cores do shell — barra, painéis, notificações, tela de bloqueio —, e o sync as leva para a tela de login (seção 8.3). As cores da arte do build (`#16161e` de fundo, `#bb9af7` de destaque) já eram as do Tokyo Night, então splash e login continuam como estão.

Diferente dos blocos de inatividade, blocos normais como `[theme]` e `[wallpaper]` **mesclam** com o padrão do Noctalia: o que não está declarado segue com o valor dele.

### O que segue a paleta, e o que é fixo

O Noctalia tem um sistema de templates: a cada troca de esquema ele reescreve o arquivo de cores de outros programas e avisa cada um. Os ligados no `arkmos.toml` do skel:

| Template | Escreve | Efeito |
| --- | --- | --- |
| `gtk3`, `gtk4` | `~/.config/gtk-{3.0,4.0}/noctalia.css`, importado no `gtk.css` | aplicativos GTK seguem a paleta |
| `btop` | `~/.config/btop/themes/noctalia.theme`, selecionado no `btop.conf` | o monitor segue a paleta |

**Os templates de `foot` e de `niri` ficam de fora de propósito.** O `apply.sh` de cada um cria configuração na conta do usuário quando ela não existe, e esses dois programas leem a do usuário **em vez** da do sistema: o de niri deixaria a sessão com um `~/.config/niri/config.kdl` de uma linha, sem os atalhos, sem o `prefer-no-csd` e sem o `spawn-at-startup "noctalia"` desta imagem. O de `starship` escreve num caminho que a imagem não lê, porque o `STARSHIP_CONFIG` aponta para `/usr/share/arkmos/starship.toml`; o de `qt` escreve para qt5ct e qt6ct, que não estão na imagem.

Então a divisão é esta:

```text
segue a paleta       shell do Noctalia (barra, painéis, notificações, bloqueio)
                     aplicativos GTK 3 e GTK 4
                     btop
                     tela de login, pelo sync
fixo em Tokyo Night  terminal (tema tokyonight-night, do próprio foot)
                     cor de destaque do libadwaita (accent-color='purple')
                     prompt (o starship usa cores nomeadas, que vêm do terminal)
                     anel de foco do niri (#bb9af7)
                     splash de boot, tela de login e wallpaper gerados no build
```

### Flatpak e AppImage

Um **AppImage** não tem sandbox: ele lê o `$HOME` de verdade, então um AppImage GTK pega o `gtk.css` da conta e segue a paleta como qualquer aplicativo da imagem. AppImage Electron ou Qt segue só claro/escuro, pelo portal, porque as cores internas são do próprio aplicativo.

Um **Flatpak** tem o próprio `/etc` e o próprio `XDG_CONFIG_HOME` (`~/.var/app/<id>/config`), e por isso não vê o `gtk.css` da conta. O que atravessa, e o que não:

| | Como | Estado |
| --- | --- | --- |
| Claro/escuro | portal (`color-scheme`) | funciona |
| Tema GTK3 (`adw-gtk3-dark`) | extensão `org.gtk.Gtk3theme.adw-gtk3-dark`, na lista de preinstall | funciona |
| Paleta (o `gtk.css` da conta) | `filesystems=xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro` no override global | funciona |
| Cor de destaque do libadwaita | portal (`accent-color`) | **não** |

O override global vem de `files/usr/share/arkmos/flatpak-overrides/global` e o `tmpfiles.d` o **copia** para `/var/lib/flatpak/overrides/global` — cópia, e não symlink, para que `flatpak override` continue funcionando depois, e só quando o destino não existe, para não desfazer o que a pessoa mudar.

A cor de destaque é a exceção conhecida. O `accent-color='purple'` do dconf vale para os aplicativos libadwaita **da imagem**; um Flatpak pergunta ao portal, e o backend `gtk`, que é o nosso, não implementa essa chave (o do GNOME implementa, mas ele pressupõe uma sessão GNOME — foi por isso que a interface Settings ficou no backend `gtk`, seção 26.1). Então um Flatpak libadwaita fica com o azul padrão dele até o backend `gtk` ganhar a chave.

**Trocar de esquema**, pela interface do Noctalia, muda a primeira lista na hora — inclusive para uma paleta gerada a partir do papel de parede. A segunda lista continua em Tokyo Night até ser editada: são arquivos da imagem, não da conta. O padrão da imagem (`Tokyo-Night`) vale para conta nova; o que se escolhe depois vive em `~/.local/state/noctalia/settings.toml`.

O `just check` confere as duas pontas: que os três templates certos estão ligados e que os de foot e de niri **não** estão.

### Barra, dock e painéis

Vieram de uma sessão de testes na VM: mexer na interface do Noctalia e exportar com `noctalia config export`, que imprime só o que difere do padrão dele. O resultado está no `arkmos.toml` do skel.

O arredondamento da interface do shell está em `corner_radius_scale = 1.25`, escolhido olhando na VM para acompanhar os cantos das janelas. Ele viaja ao login pelo sync, e é por isso que não é declarado no `greeter.toml` (seção 8.3).

A barra leva lançador, captura e papel de parede à esquerda, com espaçadores antes e depois dos workspaces e a janela ativa no fim; relógio e mídia no centro; e à direita o monitor de sistema, RAM, bandeja, notificações, área de transferência, rede, Bluetooth, volume, brilho, bateria, centro de controle, caffeine e sessão. Sem moldura arredondada nem margem nas pontas, com 60% de opacidade. O dock fica oculto e não reserva espaço, com VS Code, Spotify, AnyDesk, Bazaar e Thunderbird fixados.

Três coisas da exportação **não** entraram, e é a regra para as próximas:

- **papel de parede pessoal**, que na VM era uma imagem de site de wallpapers, sem licença clara — arte de terceiro não entra no repositório nem na imagem (seção 28.4);
- **estado de máquina**: último papel de parede usado e o papel por monitor;
- **posição dos widgets da tela de bloqueio**, que grava nome de monitor (`Virtual-1`, da VM) e coordenadas em pixels — no notebook o monitor é outro, e isso viraria lixo.

Os ids dos fixados no dock são de `.desktop`: um id que não esteja instalado vira ícone morto. A exportação vinha com `org.mozilla.thunderbird_esr`, que não é o que a lista instala, e foi corrigido para `org.mozilla.Thunderbird`.

### Notificações

Quem implementa o `org.freedesktop.Notifications` é o próprio Noctalia, com daemon ligado por padrão — por isso a imagem **não** instala mako, que ficava desabilitado e nunca iniciado: dois daemons para o mesmo barramento, um deles peso morto.

Dois padrões do Noctalia significam "sem limite", e são os que o `arkmos.toml` muda:

| | Padrão | Arkmos |
| --- | --- | --- |
| `max_visible` | `0`, enche a tela numa rajada | `4` |
| `history_retention_hours` | `0`, guarda para sempre | `168` (sete dias) |

Há também um filtro para o Spotify, que notifica a cada troca de música: o toast e o histórico saem, porque a barra já tem o widget de mídia mostrando o que toca.

O resto fica como vem do Noctalia: canto superior direito, que acompanha a barra; camada `top`, que mantém o toast fora de aplicativo em tela cheia; borda, opacidade e margens. Som de notificação está desligado (`[audio] enable_sounds = false`), e o Noctalia não traz som próprio.

### Papéis de parede

Nove imagens geradas por IA pelo autor do projeto, em WebP 1920x1081 de ~250 KB cada, mais o `arkmos.webp` que o `render-artwork.sh` desenha com o nome do sistema. Todas em:

```text
files/usr/share/backgrounds/arkmos/
```

O padrão é o `arkmos-default.webp`, e a pasta é declarada no `arkmos.toml` para a lista do Noctalia mostrar todas. O `just check` confere que o padrão existe, que está dentro da pasta declarada e que a pasta não ficou vazia — caminho errado ali não dá erro, o shell só abre com o fundo vazio.

São arte própria, e é isso que as deixa entrar num repositório público: arte de terceiro sem licença clara fica fora do repo e da imagem (seção 28.4).

### Ícones: Papirus-Dark, pastas em violeta

O tema de ícones é a **Papirus-Dark**, a variante da Papirus feita para tema escuro: os ícones pequenos de barra e de ferramenta vêm claros. Ela traz só o que difere e aponta, por symlink, para os diretórios da Papirus em todo o resto, por isso a imagem instala os dois pacotes (`papirus-icon-theme` e `papirus-icon-theme-dark`). Antes a imagem usava a Papirus comum, que é a variante para tema claro.

As pastas trocam o azul padrão pelo violeta, o tom de destaque do Arkmos. A Papirus traz cada pasta em todas as cores, e o nome sem cor é um symlink para a padrão (`folder.svg -> folder-blue.svg`). O `build_files/papirus-folders.sh` reponta esses symlinks, que é o que faz o `papirus-folders` do próprio projeto; o Fedora não o empacota. O script falha o build se trocar menos links do que o esperado, para que uma mudança de estrutura no tema não publique pastas azuis sem aviso.

A escolha saiu de uma comparação lado a lado com Adwaita, Yaru, Breeze, Numix, Pop e Colloid. O Colloid, que tem uma variante Dracula própria, ficou de fora por não estar nos repositórios do Fedora.

### Cursor: Bibata Modern Ice

Escolhido em 2026-09-24, no lugar do Adwaita. A variante Ice é a branca, de pontas arredondadas: é a que mais aparece contra o fundo escuro do Tokyo Night.

O Fedora não empacota o Bibata — os temas de cursor do repositório são Adwaita, Breeze, Oxygen e Bluecurve —, então ele vem do release upstream, como a Nerd Font: `build_files/install-cursor.sh`, versão 2.0.7 fixada, 1,7 MB. O release não publica checksum, e o SHA256 fixado foi calculado no download de 2026-09-24; dali em diante, qualquer mudança no arquivo servido falha o build. A licença é GPL-3.0, redistribuível.

O nome do tema é declarado em cinco lugares, e cada um alcança uma classe de programa:

```text
/etc/dconf/db/local.d/10-arkmos-appearance   GTK4 e libadwaita, pelo GSettings
/etc/xdg/gtk-{3.0,4.0}/settings.ini          GTK sem D-Bus nem portal
/etc/niri/config.kdl (cursor)                o desktop, e XCURSOR_THEME e
                                             XCURSOR_SIZE para Electron, Qt e XWayland
/usr/share/arkmos/noctalia-greeter.toml      a tela de login
```

Nome errado em qualquer um deles não dá erro: aquele programa cai no cursor padrão, e o sistema fica com dois cursores conforme a janela. O `just check` confere que os cinco concordam e que o tema está instalado.

### Arte gerada no build

O splash de boot e o wallpaper padrão não são imagens versionadas: saem de `build_files/render-artwork.sh`, a partir de fonte, cores e formas. O repositório e a imagem publicada são públicos, e arte tirada de site de wallpaper não tem autor nem licença identificáveis (seção 28.4).

A logo do README também sai desse script: `just logo` o roda com `ARTWORK_LOGO` e grava `.github/assets/logo.png` — mesma fonte e mesmas cores do splash, para o repositório não divergir do que a máquina mostra no boot. É o único produto do script que vai para o Git, porque o README precisa de um arquivo.

As cores são as que o Tokyo Night e o Dracula têm em comum — fundo índigo quase preto e lavanda como destaque (`#bb9af7` num, `#bd93f9` no outro) —, para que o boot e o desktop combinem com qualquer um dos dois. Os dois esquemas vêm embutidos no Noctalia.

O Noctalia só lê configuração do home, então o wallpaper padrão chega pelo `/etc/skel` (`.config/noctalia/arkmos.toml`), como os defaults do VS Code. A tela de bloqueio usa o wallpaper do desktop enquanto a dela estiver vazia, que é o padrão.

A tela de login recebe wallpaper e paleta pelo **sync** do Noctalia, ligado no mesmo arquivo (`auto_sync = true`) e com a regra `50-arkmos-greeter-sync.rules` para dispensar a senha. O código do greeter impõe duas consequências:

- **Nada de wallpaper, paleta ou `corner_radius_scale` no `greeter.toml`.** Ele vence o `sync.toml`, e um valor declarado lá impediria para sempre que a escolha feita no desktop chegasse ao login. Os três são sincronizados; o `just check` barra os três.
- **O login precisa de semente.** O sync automático do Noctalia 5.0.1 só dispara quando a aparência **muda** na sessão — tema, papel de parede ou fonte. Na partida, o tema é aplicado antes de o sync passar a observar (`application_services.cpp`, na tag v5.0.1), então numa instalação nova nada chegava ao login, que ficava no tema embutido do greeter até alguém clicar em sincronizar. Por isso a imagem entrega um `sync.toml` inicial (`/usr/share/arkmos/noctalia-greeter-sync.toml`, copiado pelo `tmpfiles.d` só se o destino não existir) com a paleta Tokyo Night e o papel de parede padrão. O greeter só usa o `[appearance]` com a paleta **completa**, os 16 papéis, e o `just check` confere isso. As cores são as do `Tokyo-Night` embutido, iguais no greeter e no shell. O primeiro sync feito depois substitui a semente.

A regra de polkit libera a ação `org.noctalia.greeter.sync-appearance`. Pela leitura do código, no Noctalia 5.0.1 o sync passaria por `run0`/`pkexec` e essa ação só seria usada na versão seguinte — mas na instalação de 2026-09-24 o sync manual, pelas configurações do Noctalia, **não pediu senha**. O comportamento na máquina é o que vale; a leitura do código não se confirmou.

Um wallpaper pessoal é escolhido na conta, pela interface do Noctalia, e o sync o leva para login e bloqueio. Ele não entra no repositório.

O que é **só do greeter**, e por isso fica declarado nele: a sessão padrão, o teclado, o cursor, o watchdog de autenticação e mais três escolhas — a máscara de senha aleatória (`password_style`), que não revela o tamanho da senha; a logo do Noctalia escondida (`hide_logo`), porque a identidade que aparece no boot é a do Arkmos; e o apagamento de tela em 5 minutos (`[idle] timeout`), já que o padrão do greeter é nunca apagar, e um notebook esquecido na tela de login ficaria aceso até a bateria acabar.

O greeter **não tem relógio nem sistema de widgets** — ele é seleção de usuário, senha, sessão e esquema. O relógio da tela de bloqueio é do Noctalia, que roda dentro da sessão; do desktop para o login viajam só wallpaper, paleta, fonte, arredondamento e layout de monitores.

## 26.2 O que falta

Já definidos: o esquema (Tokyo Night), os ícones (Papirus-Dark com pastas em violeta), os papéis de parede e o cursor (Bibata Modern Ice) — todos na seção 26.1 —, e a fonte da interface, Adwaita Sans (seção 14). O Zsh segue o esquema pelas cores do terminal (seção 9).

Também definidos na 0.10.0: barra, dock, painéis, notificações, arredondamento e a tela de login (seção 26.1), e a paleta chegando a GTK 3 e 4, btop, Qt e KDE pelos templates do Noctalia.

Falta:

- **cor de destaque em Flatpak libadwaita**, que depende do portal expor a chave (seção 26.1);
- **layout da tela de bloqueio**, que é estado de máquina, por decisão (seção 34).

Objetivo:

```text
Um ambiente coerente e reconhecível como Arkmos.
```

---

# 27. Boot e Console

O objetivo é um boot limpo, sem esconder erros reais.

## 27.1 Argumentos de kernel

```text
files/usr/lib/bootc/kargs.d/10-arkmos.toml
kargs = ["rhgb", "quiet", "loglevel=3", "rd.udev.log_level=3"]
```

## 27.2 Splash de boot

```text
files/etc/plymouth/plymouthd.conf          Theme=arkmos
files/usr/share/plymouth/themes/arkmos/    o .plymouth do tema
build_files/render-artwork.sh              a arte, gerada no build
```

O padrão do Fedora é o `bgrt`, que desenha o logo gravado no firmware — nesta máquina, o da Lenovo. O tema do Arkmos usa o plugin `two-step`, o mesmo do `spinner`: wordmark `arkmos` em JetBrains Mono Light, a animação do spinner recolorida em lavanda, fundo índigo em degradê. Os títulos dos modos de atualização estão em português.

**O tema só vale dentro do initramfs.** O `plymouthd` arranca do initramfs e continua, depois do switch-root, com o tema que carregou lá. O initramfs da base foi gerado com o `bgrt`: trocar o `plymouthd.conf` sem regerá-lo passa em qualquer verificação que olhe o sistema de arquivos, e o boot continua com o logo do fabricante.

Por isso o `Containerfile` roda o `dracut` com os mesmos argumentos que a base usou (visíveis no `lsinitrd`, linha "Arguments") e com os `dracut.conf.d` que ela instalou — inclusive o `99-nvidia.conf` da variante NVIDIA. Rodando depois de todo o `/etc`, o initramfs também passa a levar o teclado `br`, que é onde uma senha de LUKS seria digitada.

O `just check` confere o initramfs, e não só o `/usr`: tema, `plymouthd.conf`, teclado e o módulo `ostree` — sem ele o deployment não é montado e não há boot.

**Custo medido: 249 MB.** É o tamanho da camada com o initramfs regerado. O arquivo da base continua na camada dela, então é quanto a imagem cresce — e, como o initramfs já sai comprimido com zstd, o download cresce praticamente o mesmo. Comparado ao da base, o initramfs novo tem exatamente os mesmos módulos do dracut e os mesmos arquivos; muda o tema do Plymouth e entra o `vconsole.conf`. A comparação pegou uma diferença, já corrigida: sem `/var/roothome` no container de build — ele só nasce no boot —, o dracut não instalava o `/root`. O diretório é criado só durante o dracut.

## 27.3 Resolvido na 0.8.0

- **Status do systemd por cima do assistente de firstboot** — seção 12.3.
- **`nvidia-cdi-refresh` falhando em todo boot** — seção 24.2.
- **`greetd` em loop de restart** — seção 8.3.
- **Pausa final do assistente sem prazo**, que em janela pequena parecia travamento — seção 12.2.
- **Config do greetd rejeitada pelo parser dele**, e o fallback de vt1 brigando com o `Restart=always` do greetd — seção 8.3. Foram as duas falhas do segundo teste em VM.
- **`grub-boot-success.service` falhando em toda sessão.** O preset do Fedora habilita essa unit de usuário; ela roda `grub2-set-bootflag boot_success` dois minutos depois do login e grava no `grubenv`, e no bootc o `/boot` é somente leitura ("Creating tmpfile failed: Read-only file system"). Ela serve ao menu automático do GRUB, que aqui não se usa — quem cuida das entradas de boot é o bootc. Mascarada no build.

## 27.4 Ruído conhecido e aceito

Dezenas de `Failed to resolve group 'audio' / 'utmp' / 'tty'…` do `systemd-tmpfiles` no initramfs. Comparado com o Aurora instalado: acontece igual lá (167 ocorrências no boot atual). É comportamento do Fedora no initrd, não do Arkmos, e não vale divergir da base por isso.

Duas linhas do `dbus-broker-launch` a cada sessão que sobe, no login e quando a tela de login volta no desligamento:

```text
Policy to allow eavesdropping in /usr/share/dbus-1/session.conf +31:
  Eavesdropping is deprecated and ignored
```

Vêm do `session.conf` do pacote `dbus` do Fedora, que ainda declara a política antiga de *eavesdropping*; o `dbus-broker` a ignora e avisa. É arquivo da distribuição, não do Arkmos, e mexer nele seria divergir da base para calar um aviso sem efeito.

O outro aviso obsoleto, esse **corrigido**, era o `Calling import-environment without a list of variable names is deprecated.`, que aparecia no console entre a senha e o desktop: vinha do `niri-session` do pacote chamando `systemctl --user import-environment` sem lista. O build passa a lista (ver Containerfile), porque a forma sem ela não é só feia — está deprecada, e quando deixar de funcionar a sessão nasceria sem o ambiente do login sem nada avisar.

A lista pede só as variáveis que existem, com `${VAR+VAR}`: a primeira versão listava todas, e o `systemctl` passou a imprimir `Environment variable $DISPLAY not set, ignoring.` uma vez por ausente — no login, `DISPLAY` e `WAYLAND_DISPLAY` ainda não existem, e um aviso virou vários.

É **remendo temporário**, e o problema é conhecido no upstream: a issue [niri-wm/niri#3572](https://github.com/niri-wm/niri/issues/3572) acompanha o aviso, a [#4624](https://github.com/niri-wm/niri/issues/4624) descreve exatamente este sintoma num setup greetd + noctalia-greeter (fechada como duplicata) e a [#3776](https://github.com/niri-wm/niri/pull/3776) é a correção em andamento — ela registra que o import sem lista sobrescreve o que o gerenciador já tem do `environment.d`, e é por isso que `LANG` e `XDG_DATA_DIRS` ficam fora da nossa lista. O `sed` confere a linha original antes de alterá-la: quando o pacote vier corrigido, o build falha de propósito e o remendo sai.

---

# 28. Verificação e CI

## 28.1 Verificações

```text
tests/check-image.sh
```

Um script só, usado pelo `just check` e pelo CI. Antes as duas listas eram mantidas à mão em lugares separados e já divergiam, o que significa que uma verificação nova valia num fluxo e não no outro.

O critério para uma verificação entrar ali é ser **um erro que a imagem consegue esconder**: algo que constrói, passa no lint e só aparece como falha no boot da máquina.

Cobertura atual:

```text
bootc container lint
systemd-analyze verify das units do Arkmos
locale pt_BR.utf8, timezone, KEYMAP=br, hostname
conta do greeter referenciada em greetd/config.toml existe na imagem
sessão Wayland do Niri registrada, niri validate
systemd-tmpfiles --dry-run (resolve usuários e grupos de verdade)
pacotes essenciais e componentes herdados da base
ausência de podman-docker
serviços habilitados, greetd como display-manager
por variante: pilha NVIDIA presente/ausente e limpeza condicional
binários upstream instalados e executáveis, Nerd Font patched presente
config do zsh carregando inteira SEM REDE, com plugins e módulos
starship.toml lido e parseado (e não caindo no default em silêncio)
assistente do primeiro boot rodando de ponta a ponta em container
prefer-no-csd ativo, foot.ini válido, barra de título desligada
banco do dconf compilado e profile apontando para ele
opções do tuigreet conferidas contra o --help
greetd lendo o próprio config (o parser dele, não o do Python)
fallback de vt1 existindo e ligado ao greetd
```

Três desses merecem nota, porque cobrem erro que só apareceria com a máquina instalada:

- **o assistente do primeiro boot roda de verdade**, num container descartável, com as respostas vindas do stdin — ele executa uma única vez na vida de uma instalação, e um erro ali deixa a máquina sem conta para entrar;
- **as flags do tuigreet são conferidas contra o `--help`**, porque uma flag inexistente reproduz exatamente a tela preta da seção 8.3 — e rodar o tuigreet não denuncia isso: sem tty ele estoura no terminal antes de reclamar do argumento, e sai com código 0;
- **o banco do dconf é verificado compilado**, porque sem o `dconf update` os arquivos-fonte ficam na imagem sem efeito nenhum e nada indica o motivo;
- **o config do greetd é validado pelo greetd**, e não por um parser TOML qualquer: o do Python aceita o que o do greetd rejeita, e foi assim que um arquivo inválido chegou à VM.

Dois detalhes que a experiência impôs:

- `/etc/hostname` é lido com `podman cp` de um container criado, não com `podman run`: o podman faz bind-mount desse arquivo com o id do container, então dentro de um `run` ele sempre existe e a verificação passaria com a imagem vazia.
- A variante é lida do label `org.arkmos.variant`, e não do nome da imagem: o nome é convenção do Justfile e do CI, o label é o que a máquina instalada consegue consultar depois.

## 28.2 CI

```text
.github/workflows/build.yml
```

O workflow tem duas funções, e elas entram em momentos diferentes do projeto.

**Verificar** vale agora. Cada push e cada pull request na `main` constrói as duas variantes e roda o mesmo `tests/check-image.sh` que o `just check` roda na máquina. É o que pega regressão enquanto o projeto muda rápido, sem depender de alguém lembrar de verificar antes de commitar.

**Publicar** só vale quando houver máquina instalada para atualizar — é a peça que transforma o Arkmos de "reconstruir e reinstalar" em um sistema atualizável por `bootc upgrade`. Até lá, publicar é encher o registry de versões que ninguém baixa. Fica atrás de um acionamento manual (`workflow_dispatch` com a caixa `publish` marcada), e as tags seguem o esquema por data: `44.AAAAMMDD.N`, mais `44` e `latest`.

Detalhes do desenho:

- **Uma variante por job** (`strategy.matrix`). O runner do GitHub já precisa de limpeza para caber **uma** imagem de ~11 GB; as duas no mesmo job estouram o disco. Em jobs separados também constroem em paralelo.
- **As duas variantes são construídas, verificadas e publicadas.** A NVIDIA passou a publicar depois que o ciclo de publicar, instalar e atualizar foi validado na padrão (seção 35.2); são ~5 GB por versão, e em repositório público não há cota de registry. Ela compartilha a árvore `files/` inteira com a padrão, então o que pode quebrar só nela vem da base — a imagem sair do ar, mudar de nome, deixar de trazer um pacote.
- **Sem `schedule` por enquanto.** O cron existe para acompanhar a reconstrução diária da base do Universal Blue — cujas tags, aliás, expiram em 4 semanas — e isso só protege uma imagem que está em uso. Entra quando a publicação virar rotina.
- **Assina com cosign** quando o secret `SIGNING_SECRET` existe.
- **Nome do registry em minúsculas.** O dono da conta é `AlexRogaleski`, e `github.repository_owner` vem com as maiúsculas; o podman recusa o nome ("repository name must be lowercase"). O workflow monta `ghcr.io/alexrogaleski` num passo de shell e passa o mesmo valor ao build, para a política de assinatura apontar para onde a imagem é publicada.
- **O digest assinado é o publicado.** O push recomprime as camadas, e o manifesto no registry tem outro digest que o da imagem local — que o `podman inspect` continua mostrando mesmo depois do push. O workflow assina o digest do `--digestfile` e para se as três tags saírem com digests diferentes.

- **O cosign faz login próprio.** Ele não lê o arquivo de autenticação do podman, e sim a configuração do Docker: sem `cosign login`, a assinatura falha com `UNAUTHORIZED` depois de o push ter dado certo. Foi assim que a primeira publicação terminou com a imagem no registry e sem assinatura.
- **O formato da assinatura importa.** No cosign 3, `--new-bundle-format` vem ligada: a assinatura vira um bundle Sigstore anexado pela API de referrers, que o GHCR não suporta — e o cosign cai numa tag de índice `sha256-<digest>`. O podman e o bootc leem a *sigstore attachment* clássica, na tag `sha256-<digest>.sig`, que nesse formato não existe. O CI assina **e** verifica com `--new-bundle-format=false` — e, ao assinar, também com `--use-signing-config=false`, que no cosign 3 vem ligada e exige o formato novo: sozinha, a primeira opção é recusada antes de assinar. Sem isso, a imagem é validada pelo cosign e recusada pela máquina.
- **O CI confere a assinatura publicada**, com a mesma chave pública que vai dentro da imagem. É a verificação que a máquina instalada vai exigir no `bootc upgrade`.
- **Um job de `lint` em paralelo**, com shellcheck, actionlint e a sintaxe do Justfile, pelas mesmas receitas que rodam na máquina. Job separado, e não um passo do build: responde em menos de um minuto e não segura a publicação, que leva meia hora.
- **Rechunk antes de verificar e publicar** (seção 28.5).
- **Ferramenta instalada depois da limpeza de disco.** O job de build apaga o `$AGENT_TOOLSDIRECTORY` para caber a imagem, e é justamente ali que a action do `just` guarda o binário. Instalado antes, o `PATH` apontava para um diretório que deixava de existir, e o passo do rechunk morria com `just: command not found` depois de nove minutos de build. Um `just --version` logo após a instalação transforma isso em falha de um segundo.

O digest assinado, o login do cosign e o formato da assinatura só apareceram ao publicar de verdade, porque é o único trecho que um push comum não executa.

### Como publicar

1. Na aba **Actions** do GitHub: workflow **build** → **Run workflow**, branch `main`, caixa **publish** marcada. Pela linha de comando, `gh workflow run build.yml -f publish=true`.
2. **Só na primeira vez:** pacote de conta pessoal nasce **privado**, e o `bootc switch` não baixa imagem privada sem login. Em *Packages → arkmos → Package settings → Change visibility*, marcar **Public**. **Não tem volta** — pacote público não pode voltar a ser privado.
3. Conferir a assinatura: `cosign verify --key files/etc/pki/containers/arkmos.pub ghcr.io/alexrogaleski/arkmos:latest`.

### Por que o repositório é público

Não é só preferência: é o que torna este workflow viável. Em conta gratuita do GitHub, repositório privado tem **500 MB** de cota no GitHub Packages, e as imagens ocupam cerca de 4 GB (padrão) e 5 GB (NVIDIA) comprimidas — a primeira publicação estouraria a cota por uma ordem de grandeza. Repositório público tem Actions ilimitado e registry sem cota.

O projeto já era construído com essa hipótese: nada pessoal é declarado na imagem, e a conta nasce no primeiro boot (seção 12.4).

### Retenção

Cada publicação cria **uma** versão (um digest) carregando três tags: `44.AAAAMMDD.N`, `44` e `latest`. Sem limpeza, nada remove as anteriores e cada uma ocupa ~4 GB. Em repositório público isso não custa cota, mas uma listagem com centenas de versões deixa de ser navegável — e no dia em que o `schedule` for ligado, passa a crescer sozinha.

Dois passos, com critérios diferentes:

- **Versões sem tag são removidas todas.** Mover `44` e `latest` para a versão nova deixa a anterior sem nenhuma tag apontando para ela; não dá para referenciá-la por nome e ela não é alvo de rollback.
- **Doze versões de histórico são mantidas.** E a conta não é uma versão por publicação: cada publicação cria **duas** versões, a imagem e a assinatura do cosign, que no registry é um artefato próprio. Doze são portanto cerca de seis publicações. O valor era 5, o que deixava duas publicações — pouco o bastante para, durante os testes da 0.8.0, apagar no meio do caminho as versões que serviam de teste negativo. Isto é histórico de imagem, para reinstalar do zero uma versão que se sabe boa; o rollback do dia a dia é local e não depende do registry.

## 28.3 Assinatura

A imagem verifica a própria procedência quando existe um par de chaves cosign configurado. Enquanto não existe, o build segue e a imagem funciona — apenas sem verificar de onde veio.

### Como configurar

**Já configurado.** O par foi gerado com cosign v3.1.3 e a chave privada está cifrada com scrypt.

```text
~/.local/share/arkmos-signing/   (modo 700)
├── cosign.key        privada, cifrada          → secret SIGNING_SECRET
├── cosign.password   senha da chave            → secret COSIGN_PASSWORD
└── cosign.pub        pública                   → files/etc/pki/containers/arkmos.pub
```

Esse diretório é o único lugar onde a chave privada e a senha existem fora dos secrets do GitHub: **perder os dois significa não poder mais assinar com essa identidade**, e a saída seria gerar um par novo e atualizar a chave pública na imagem — o que invalida as assinaturas antigas.

O `.gitignore` bloqueia `cosign.key`, `cosign.password` e `*.key` como rede de segurança contra cópia acidental para dentro do repositório.

Para gerar de novo, se algum dia for preciso:

```bash
cosign generate-key-pair            # o cosign não é empacotado pelo Fedora
gh secret set SIGNING_SECRET  < cosign.key
gh secret set COSIGN_PASSWORD < cosign.password
cp cosign.pub files/etc/pki/containers/arkmos.pub
```

O `cosign` não é empacotado pelo Fedora; o binário vem do release upstream, como starship e lazygit.

`COSIGN_PASSWORD` não é opcional por capricho: sem a variável, o cosign tenta **pedir** a senha, e num runner sem terminal isso trava o job até o timeout. Vazia funciona para chave gerada sem senha.

### O que a imagem faz com a chave

```text
files/etc/pki/containers/arkmos.pub            chave pública (versionada)
files/etc/containers/registries.d/arkmos.yaml  onde procurar a assinatura
/etc/containers/policy.json                    entradas inseridas no build
```

A entrada é **inserida** na política que a base já traz, e não substitui por uma nossa. O `policy.json` do `ublue-os-signing` já confia nos registries do Fedora, da Red Hat e do Universal Blue — reescrever o arquivo significaria manter essa lista à mão e sair de sincronia com a base.

O escopo são os **dois repositórios** do Arkmos, não o namespace inteiro. O ublue pode usar `ghcr.io/ublue-os` porque tudo que vive lá é deles e é assinado; este namespace é uma conta pessoal, que pode publicar qualquer outra imagem — e com o escopo no namespace, cada uma delas passaria a precisar da assinatura do Arkmos para ser baixada nesta máquina.

Vale saber o que a política da base já faz, para não confundir o alcance disto:

```text
"default":  reject
docker "":  insecureAcceptAnything
```

O escopo vazio do transporte docker aceita qualquer coisa, então imagem de registry não listado continua sendo baixada sem verificação. A entrada do Arkmos é **aditiva e específica** — ela garante que uma imagem do Arkmos venha assinada, e não torna o sistema restritivo de forma geral.

O `registries.d` é necessário porque o cosign anexa a assinatura ao próprio registry, ligada ao digest ("sigstore attachment"), em vez de publicá-la num servidor separado. Sem essa declaração, o podman procura no lugar errado e a verificação falha mesmo com a assinatura presente.

`signedIdentity` é `matchRepository`, não `matchExact`: as tags `44` e `latest` se movem entre digests.

**A exigência fica gravada na deployment.** Depois de um `bootc switch --enforce-container-sigpolicy`, o `bootc status` mostra `signature: containerPolicy` na imagem — não é efeito momentâneo do comando. Um `bootc upgrade` seguinte continua verificando a assinatura sem repetir a flag.

O `just check` afirma a coerência das duas peças, que só funcionam juntas — chave sem entrada na política não verifica nada, e entrada apontando para chave ausente faz **todo** pull do Arkmos falhar.

---

## 28.4 Licenças e redistribuição

Publicar a imagem é **redistribuir** software de terceiros. O repositório é outra coisa: ele contém apenas configuração própria — nenhuma linha de código de terceiro é versionada aqui —, então a questão se aplica só à imagem.

### O levantamento

As licenças de todos os pacotes da variante padrão, por frequência:

```text
195  GPL-2.0-or-later        56  BSD-3-Clause
124  LGPL-2.1-or-later       50  GPL-3.0-or-later
119  MIT                     41  Apache-2.0
 67  OFL-1.1                 33  GPL-2.0-only
```

Todas permitem redistribuição. Dois grupos merecem nota:

**21 pacotes de firmware** sob `LicenseRef-Callaway-Redistributable-no-modification-permitted` (`linux-firmware`, `iwlwifi-*`, `intel-gpu-firmware`, `amd-*`, `atheros-firmware`…). Redistribuição é permitida; modificação, não — e nada aqui os modifica. São os mesmos que qualquer distribuição Linux redistribui.

**O driver NVIDIA**, na variante correspondente: `nvidia-driver` e `kmod-nvidia` são "NVIDIA License", proprietária. **Decisão: publicar a variante**, porque a licença permite e as condições dela são cumpridas.

O texto que está dentro da imagem (`/usr/share/licenses/nvidia-driver/LICENSE`) concede, em 1.1(d):

```text
Distribute the SOFTWARE provided for use with operating system kernels
distributed under the terms of an OSI-approved open source license [...]
provided that (i) the binary files thereof are not modified in any way
(except for uncompressing of compressed files) and (ii) this Agreement is
provided to each SOFTWARE recipient.
```

E 2.7 fecha o resto: fora do que é expressamente concedido, não há distribuição. As três coisas que isso exige, no nosso caso:

- **kernel sob licença OSI** — Linux, GPL-2.0;
- **binários não modificados** — o driver vem inteiro da `base-nvidia` do Universal Blue; esta imagem só acrescenta configuração (`nvidia-cdi-refresh` e o perfil de buffer para compositores Wayland), sem tocar em binário do driver;
- **o acordo entregue a cada destinatário** — o `LICENSE` viaja dentro da imagem, no caminho acima, que é como quem faz `bootc switch` o recebe.

Vale lembrar que 2.8 limita o **uso** do software GeForce/Titan ao hardware que o usuário possui. É limitação para quem usa, não para quem distribui, e não muda a decisão.

### O caso do VS Code

É o único componente cuja licença trata de distribuição em termos restritivos. O EULA embarcado na própria imagem (`/usr/share/code/resources/app/LICENSE.rtf`) diz:

```text
SCOPE OF LICENSE
  You may not · share, publish, rent or lease the software,
  or provide the software as a stand-alone offering for others to use.
```

E, sobre o que é permitido:

```text
INSTALLATION AND USE RIGHTS
  You may use any number of copies of the software to develop and test
  your applications, including deployment within your internal
  corporate network.
```

**Decisão: manter o VS Code na imagem e publicar, seguindo o Universal Blue.**

O que sustenta a decisão:

- O `bluefin-dx` instala o VS Code na imagem — `dnf -y install --enablerepo=code code`, do repositório que a própria Microsoft mantém — e publica essas imagens abertamente no GHCR. Verificado no código deles e confirmado numa instalação de `aurora-dx-nvidia-open`, onde o `code` vem da imagem e não de pacote em camada.
- É prática estabelecida, em escala e visível, de um projeto com patrocínio institucional, usando o canal de distribuição oficial da Microsoft para Linux.
- Uma leitura possível é que o alvo da cláusula é oferecer o VS Code **isoladamente** — "as a stand-alone offering" — e não incluí-lo como uma ferramenta entre centenas num sistema operacional.

O que a decisão **não** é: um parecer de que a cláusula não se aplica. Ela diz o que diz, a leitura acima não foi confirmada por ninguém com competência para isso, e o risco é assumido conscientemente.

Se houver objeção algum dia, a correção é pequena e localizada — uma camada do Containerfile:

- trocar por **VSCodium** ou **code-oss**, que são MIT e redistribuíveis (custo: o marketplace da Microsoft não é acessível a eles, e a extensão Dev Containers não está no Open VSX);
- ou publicar a imagem sem o VS Code e derivá-la localmente com três linhas, que é o padrão para software não-redistribuível.

### Arte

A arte do Arkmos — splash de boot e wallpaper padrão — é gerada no build (seção 26.1) e pertence ao projeto. As formas da animação do splash vêm do tema `spinner` do próprio Plymouth (GPL-2.0-or-later), recoloridas; a fonte do wordmark é a JetBrains Mono (OFL-1.1).

**Imagem de terceiros não entra no repositório nem na imagem.** Sites de wallpaper republicam arte sem autor nem licença identificáveis, e publicar a imagem seria redistribuí-la. Um wallpaper pessoal fica na conta do usuário.

Um wallpaper definitivo gerado por IA é aceitável, com dois cuidados: registrar a ferramenta e conferir se os termos dela permitem redistribuir o resultado; e gerar a partir de descrição de estilo, sem usar como entrada as imagens de terceiros que serviram de referência — um resultado muito próximo delas continua sendo cópia.

### Marca

A imagem deriva do Fedora, mas não se chama Fedora nem usa a marca — que é o que as diretrizes de marca pedem de um derivado.

---

## 28.5 Rechunk: camadas por conteúdo

O CI reorganiza as camadas da imagem antes de publicar, com `just ostree-rechunk`. É o passo que Bluefin, Aurora e Bazzite dão, e que o `image-template` do Universal Blue traz com esse nome; por baixo é o `rpm-ostree compose build-chunked-oci`, que recebe o sistema de arquivos pronto e o reescreve em até 127 camadas decididas por **conteúdo**, e não pela ordem dos comandos do Containerfile.

Medido nesta imagem, em 2026-09-23:

| | Antes | Depois |
| --- | --- | --- |
| Camadas | 289 | 128 |
| Tamanho | 9,88 GB | 8,02 GB |

O 1,9 GB a menos vem dos objetos duplicados que o `rpm-ostree` unifica (11.363 nesta imagem). As 289 camadas também eram um problema por si: o próprio `rpm-ostree` avisa que runtimes mais antigos engasgam acima de 200.

As mesmas 289 camadas viram as mesmas 128 no runner do GitHub, nas duas variantes, com 11.469 e 11.580 objetos duplicados unificados. O custo é tempo: **6min06** na padrão e **6min37** na NVIDIA, sobre oito a nove minutos de build — mas execuções anteriores do mesmo passo levaram de 5min30 a 19min, porque o disco do runner é compartilhado e o gargalo é I/O. Na máquina, a padrão levou doze minutos. Hoje o rechunk roda em todo push, e não só ao publicar, porque o que a verificação examina tem de ser a imagem que iria ao registry.

O ganho maior, porém, é no `bootc upgrade` de quem usa. Camadas decididas por conteúdo são estáveis entre publicações: sem rechunk, um `dnf install` no começo do Containerfile invalida tudo o que vem depois e cada publicação obriga a baixar gigabytes.

### O delta, medido

Não precisa de máquina instalada para medir: o que um `bootc upgrade` baixa são exatamente as camadas que a versão nova tem e a antiga não, e isso sai dos manifests no registry.

| Atualização | Camadas | Download |
| --- | --- | --- |
| `.48 → .57`, as duas sem rechunk | 287 → 288 | 2.635 MB — 58% da imagem |
| `.57 → .69`, a primeira reorganizada | 288 → 128 | 3.459 MB — 100%, o plano inteiro muda |
| **`.69 → .75`, as duas reorganizadas** | 128 → 128, 5 novas | **559 MB — 16%** |
| `.69 → .75` na variante NVIDIA | 128 → 128, 5 novas | 668 MB — 15% |

De **2,6 GB para 559 MB** por atualização, e a publicação medida não era pequena: trocou o id de `.desktop` do VS Code, recortou o menu do ujust, acrescentou receitas e mexeu no `mimeapps.list`.

A linha do meio é o preço de entrada, e cobra uma vez: a primeira publicação reorganizada não compartilha camada nenhuma com a anterior. A partir dela, cada publicação herda o plano da última — é o `--previous-build`, e o log diz `plano de camadas herdado de ... (128 camadas)` quando ele entra.

Quatro detalhes que o caminho ensinou:

- **Os labels não sobrevivem sozinhos.** O `build-chunked-oci` monta uma imagem nova a partir do sistema de arquivos e não herda a configuração: dos 16 labels sobravam 3, e com eles iam a variante (que o `just check` lê) e a versão (que o `bootc status` mostra). A receita os repassa um a um, lidos da imagem de origem, então um label novo no Containerfile viaja sem ninguém editar o `Justfile`. A receita do image-template não faz isso, e por isso não serviu como está.
- **O `--from` não substitui o `--rootfs` aqui.** Ele espera a imagem no storage do próprio container, e o nosso está montado do host; a sintaxe de storage explícita, que o `--output` aceita, ele recusa. Ficaram perdidos `ENV` e `CMD`, que nesta imagem são o `PATH` padrão e `/usr/bin/bash` — os dois só afetam `podman run`, e o podman injeta o mesmo `PATH` quando não há nenhum.
- **`--previous-build` entra condicionado.** Ele mantém o plano de camadas da publicação anterior, e só faz sentido quando a imagem publicada já é reorganizada. Quem diz isso é a **contagem de camadas**, e não o label `ostree.final-diffid`: esse label vem da base do Universal Blue e é herdado por toda imagem derivada, então está presente também numa publicação de 288 camadas — o CI anunciou "plano herdado" para uma imagem que não tinha plano nenhum antes de o critério ser trocado.
- **O nome curto grava no lugar errado.** `podman build --tag arkmos:latest` cria `localhost/arkmos:latest`; o transporte `containers-storage` normaliza o mesmo nome curto para `docker.io/library/arkmos:latest`. Com o nome sem qualificação, o `rpm-ostree` gravava uma imagem nova sob o Docker Hub, imprimia `Pushed digest`, saía com zero — e a tag do build continuava apontando para a imagem de 289 camadas. O CI ficou verde duas vezes tendo verificado a imagem **não** reorganizada. A receita qualifica o alvo com `localhost/` quando ele vem sem registry, lê o driver do `podman info` em vez de fixar `overlay`, e no fim confere a contagem de camadas: mais de 128 na tag depois do rechunk é erro, não aviso.

A verificação roda **depois** do rechunk, de propósito: o que o `just check` examina é exatamente a imagem que vai ao registry. E o rechunk grava só na tag que recebeu, então as outras duas são reapontadas em seguida — sem isso, `44` e a versão do dia continuariam na imagem antiga.

---

# 29. Processo de Build

```bash
just build                  # localhost/arkmos:dev
just variant=nvidia build   # localhost/arkmos-nvidia:dev
just check-all              # constrói e verifica as duas
just logo                   # logo do README, a partir da arte do boot
```

```bash
just lint                   # shellcheck, actionlint e a sintaxe do Justfile
just format                 # shfmt nos scripts, e o formatador do just
just ostree-rechunk         # reorganiza as camadas (seção 28.5)
```

Por baixo:

```bash
podman build \
    --build-arg BASE_IMAGE=... \
    --build-arg ARKMOS_VARIANT=... \
    --build-arg ARKMOS_VERSION=... \
    --build-arg ARKMOS_COMMIT=... \
    -t localhost/arkmos:dev .
```

**Os ARGs voláteis ficam no fim do Containerfile.** Um build-arg diferente invalida o cache de tudo o que vem depois dele, e `ARKMOS_VERSION` e `ARKMOS_COMMIT` mudam a cada commit: declarados no topo, cada build local refazia o `dnf install` e as camadas seguintes. Declarados junto dos labels, que é o único lugar onde são usados, um commit novo invalida só a camada de label. A ideia vem do `finpilot`, o template novo do projectbluefin, que documenta exatamente esse motivo.

**O `.containerignore` mantém o contexto limpo.** O `podman build .` passa o diretório inteiro como contexto, e aqui dentro há discos de VM de vários GB em `output/`. Nada os copia para a imagem hoje, mas fora do contexto eles não podem ser arrastados por um `COPY` futuro.

**Lint e formatação seguem as convenções do Universal Blue**: `lint` com shellcheck, `format` com shfmt, mais o actionlint do `finpilot` e a checagem de sintaxe do Justfile pelo próprio `just`. Duas adaptações: no template deles `check` é a sintaxe do Justfile, e aqui `check` já são as verificações da imagem, então a sintaxe entrou no `lint`; e o escopo do shellcheck sai do `git`, filtrado por shebang, porque metade dos nossos scripts não tem extensão `.sh`. O `.editorconfig` existe para o shfmt: sem ele, o padrão dele é tabulação, e ele reescreveria os nove scripts do projeto.

O `bootc container lint` roda como última camada do próprio `Containerfile`, então erros de `/var`, `/opt` e layout de kernel falham o build.

---

## 29.1 Trabalhar em outra máquina

Tudo o que o projeto é está versionado: 84 arquivos, 4,6 MB de repositório, incluindo os papéis de parede. Um `git clone` basta, e nada precisa ser copiado à mão de uma máquina para outra.

```bash
git clone https://github.com/AlexRogaleski/arkmos
cd arkmos
```

O que **não** atravessa, e não precisa: o par de chaves cosign (`~/.local/share/arkmos-signing/`). Quem assina é o CI, com os secrets do GitHub; localmente as chaves só serviriam para assinar à mão, o que o fluxo não faz. A chave **pública** está no repositório, porque é ela que vai dentro da imagem.

### O que instalar

| Para | Pacotes |
| --- | --- |
| construir, verificar, rechunk, lint | `podman` |
| gerar mídia (`just iso`, `just vm`) | `podman`, `sudo`, `p7zip` |
| subir VM pelo terminal (`just run-vm`, `just run-iso`) | `qemu-kvm`, `edk2-ovmf` |
| consultar o registry e o CI | `skopeo`, `jq`, `gh` |
| as receitas em si | `just` |

Em Fedora Workstation:

```bash
sudo dnf install just podman qemu-kvm edk2-ovmf p7zip skopeo jq git gh
```

Numa base atômica do Universal Blue, `podman`, `skopeo`, `jq`, `git` e `just` já vêm; o que falta (`qemu-kvm`, `edk2-ovmf`, `p7zip`) entra por `rpm-ostree install` ou, se preferir não empilhar pacote, pelo virt-manager em vez das receitas de QEMU.

O `just lint` não exige shellcheck, shfmt nem actionlint instalados: com `ARKMOS_LINT_CONTAINER=1` ele usa as versões fixadas em container, que é como o CI roda.

### Três fluxos, e o que cada um exige

- **gerar mídia de instalação** — `just iso`. Não constrói nada: baixa a imagem publicada do GHCR e monta a ISO. Precisa de ~20 GB livres e de uns 15 minutos. É o caminho para instalar numa máquina nova sem passar por build;
- **desenvolver** — `just build` e `just check`, ou `just check-all` para as duas variantes. O primeiro build baixa a base do Universal Blue (~3 GB) e leva uns dez minutos; os seguintes aproveitam o cache (seção 29);
- **ensaiar a instalação** — `just run-iso` para o disco vazio com a ISO, ou o virt-manager com UEFI, Video Virtio com 3D e Display Spice com OpenGL (seção 30).

### Este documento é o ponto de retomada

O histórico de uma conversa não atravessa de máquina para máquina, e nem deve: o que precisa sobreviver está aqui. As decisões e o porquê de cada uma, o que já foi validado (seção 35), o que falta (seção 36) e as armadilhas que custaram tempo para achar — o `/etc` que congela, o nome curto de imagem que grava no lugar errado, o kickstart que apaga o primeiro disco. É por isso que este arquivo é longo: ele é o projeto, e o repositório é a sua execução.

# 30. Teste com QEMU

```bash
just vm       # gera output/qcow2/disk.qcow2
just run-vm   # sobe a VM
```

O `just vm` usa o [bootc-image-builder](https://github.com/osbuild/bootc-image-builder), que substituiu o antigo `truncate` + `losetup` + `bootc install to-disk`: um comando só, particionamento declarativo e rotulagem SELinux correta. Ele pede a senha do sudo duas vezes — roda privilegiado e só enxerga o storage do root, enquanto `just build` constrói sem privilégio; o `podman image scp` transfere a imagem entre os dois storages sem reconstruir.

**O builder roda com `--network=host`.** Ele resolve pacotes do Fedora durante a geração, e na rede bridge do podman rootful o DNS não sai quando o Docker está rodando: o Docker põe a chain `FORWARD` em `DROP`. Apareceu ao gerar a ISO no desktop, em 2026-09-24: o pull da imagem funcionava, porque é do host, e o builder falhava em `Could not resolve host: mirrors.fedoraproject.org`. O mesmo `getent hosts` falhava num container rootful pela bridge e resolvia no mesmo container com `--network=host`, e também num rootless. Como o Arkmos traz o Docker ligado, toda máquina Arkmos cairia nisso. O container já é `--privileged`, então a rede do host não abre nada novo.

Para o Niri, a VM precisa de aceleração 3D, e mais duas coisas que a experiência impôs:

```text
-device virtio-vga-gl,xres=1920,yres=1080
-display gtk,gl=on,grab-on-hover=on
```

O padrão do `virtio-vga-gl` é 1280x800, e nessa janela o assistente do primeiro boot rola para fora da tela — foi o que fez a pausa final parecer travamento.

O `grab-on-hover` captura o teclado quando o ponteiro está sobre a janela. Sem ele, atalhos com Super/Mod são interpretados pelo compositor do **host** e nunca chegam na VM, o que torna impossível testar os binds do Niri. `Ctrl+Alt+G` libera e recaptura a qualquer momento.

UEFI via `pflash`, não `-bios`: o firmware precisa de uma cópia **gravável** das variáveis EFI para guardar a entrada de boot que o bootc instala. As variáveis são descartadas ao gerar um disco novo — reaproveitá-las faz o firmware tentar uma entrada que não existe mais, e o sintoma é a VM não dar boot, indistinguível de imagem quebrada.

Cada variante tem seu próprio diretório de saída (`output/`, `output-nvidia/`).

**Para ensaiar a instalação pela ISO**, e não o sistema já instalado:

```bash
just iso                  # gera output/bootiso/install.iso
just run-iso              # disco vazio de 60G + a ISO no cdrom
just run-iso-instalado    # o mesmo disco depois, sem a mídia
```

O Anaconda que roda aí é o mesmo que vai rodar no hardware, com as telas de disco, cifragem e conta — é o ensaio que responde se a conta nasce no instalador ou no assistente (seção 12.4) e que layout de subvolumes o Btrfs recebe (seção 6). Três diferenças em relação ao `run-vm`: o disco nasce vazio (criado pelo `qemu-img`, não pelo bootc-image-builder), a ISO entra com `bootindex=0` porque o firmware tentaria o disco vazio primeiro, e a VM sobe com 8 GB de RAM, porque o instalador roda a partir de um squashfs em memória. Depois de instalar, é preciso sair da mídia: com a ISO ainda no cdrom, o firmware volta para o instalador — daí a segunda receita.

**A VM nasce seguindo a imagem local.** O disco é gerado a partir de `localhost/arkmos:dev`, e é isso que fica gravado na deployment: um `bootc upgrade` ali tenta buscar em `localhost/v2/` e falha. Para a VM passar a seguir a imagem publicada, uma vez:

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/<owner>/arkmos:44
```

Depois disso o `bootc upgrade` funciona, com a assinatura verificada, e o `/var` não é tocado — os Flatpaks instalados e a conta continuam lá.

**Mudança em `/etc/skel` não chega a quem já tem conta.** O skel é copiado no momento em que a conta nasce, e nem `bootc upgrade` nem `bootc switch` tocam no `$HOME`. Ao testar um padrão semeado (Noctalia, VS Code, btop), a conta que já existe na VM continua com a versão antiga do arquivo — foi o que fez o bloqueio por inatividade continuar sem funcionar depois de um upgrade que trazia a correção. Para testar: copiar o arquivo (`cp /etc/skel/.config/... ~/.config/...`) ou gerar uma VM nova, com conta nova.

**A linha de boot da VM não é a da imagem.** O bootc-image-builder acrescenta `console=tty0 console=ttyS0` no qcow2; isso não vem do `kargs.d`. Com console serial o Plymouth alterna entre o splash e o modo texto de reserva (três pontos), e o que aparece muda de um boot para outro. Por isso o `config.toml` acrescenta `plymouth.ignore-serial-consoles` na mídia de teste: o Plymouth ignora o serial e desenha o splash na tela, como numa máquina real. É configuração da mídia, não da imagem publicada.

O mesmo `config.toml` acrescenta `systemd.wants=sshd.service`, que liga o servidor SSH só na VM: a imagem o deixa desligado (seção 22), e é por ele que o ssh na porta 2222 do host funciona.

O mesmo console serial é útil quando a tela congela: na janela do QEMU, **View → serial0** mostra o console do sistema, e um `arkmos login:` ali significa que o sistema subiu e o problema é só a exibição.

---

# 31. Instalação e Atualização

Há três caminhos de instalação, e os três terminam no mesmo sistema.

**ISO instalável** — é o caminho para máquina de verdade:

```bash
just iso    # gera output/bootiso/install.iso
```

A ISO leva o Anaconda, em português e em ABNT2: escolha do disco, particionamento, cifragem se quiser, e a criação da conta, que o assistente do primeiro boot completa com o grupo `docker` (seção 12.4). Ela embute a imagem **comprimida** mais o ambiente do instalador: a gerada em 2026-09-23 ficou em 4,5 GB, abaixo das ISOs do Universal Blue (6 a 7 GB) — um pendrive de 8 GB serve. No host, reserve uns 20 GB: o osbuild descomprime a imagem em árvore intermediária antes de montar a mídia.

Para dimensionar, os tamanhos comprimidos no registry em 2026-09-23:

| Imagem | Comprimida |
| --- | --- |
| `base-main:44` (nossa base) | 3,12 GB |
| **`arkmos:44`** | **3,46 GB** |
| `arkmos-nvidia:44` | 4,37 GB |
| `bluefin:latest` | 3,32 GB |
| `bluefin-dx:latest` | 5,27 GB |
| `aurora-dx:latest` | 5,51 GB |

O Arkmos já traz VS Code e Docker, que no Universal Blue são o que separa a imagem básica da `-dx` — e mesmo assim fica 1,8 GB abaixo da `bluefin-dx`. O que mais ocupa, descomprimido: `code` 997 MB, `firefox` 289 MB (da base), `glibc-all-langpacks` 227 MB, `mesa-vulkan-drivers` 174 MB, `ibus` 149 MB, `cosign` 135 MB.

A origem é a imagem **publicada**, e não a local: a referência usada na geração é a que fica gravada na deployment, e uma instalação feita a partir de `localhost/arkmos:dev` nasce seguindo um registry que não existe (seção 30). Por isso a receita não depende do `just build`.

### O kickstart é nosso, e por dois motivos

O builder gera um kickstart próprio, e o README descreve o tipo `anaconda-iso` como *"an **unattended** Anaconda installer that installs to the **first disk found**"*. Com o `clearpart --all` que ele inclui, é exatamente isso: a mídia apaga o primeiro disco que encontrar, sem perguntar. Numa VM de teste é o comportamento desejado; num computador com mais de um disco é destruição silenciosa.

O segundo motivo é a assinatura. O `%post` dele aponta a deployment para o registry com `bootc switch --mutate-in-place --transport registry <imagem>`, **sem** `--enforce-container-sigpolicy` — e sem essa flag nenhum `bootc upgrade` posterior verifica assinatura (seção 28.3). Como o `--mutate-in-place` só grava a origin, a flag não custa download nenhum: é uma palavra no lugar certo.

Daí o `iso-config.toml`, versionado, que passa o kickstart inteiro:

```text
rootpw --lock / lang pt_BR.UTF-8 / keyboard br / timezone America/Sao_Paulo
autopart --nohome --type=btrfs          ← esquema nosso, disco escolhido na tela
network --device=link --bootproto=dhcp --onboot=on --activate
%post: devolve locale.conf e vconsole.conf de /usr/etc (seção 35.2.2)
       tira a linha de / do fstab, compress=zstd:1 no rootflags (seção 6)
       bootc switch --mutate-in-place --transport registry \
           --enforce-container-sigpolicy <imagem>
```

Ao receber um kickstart próprio, o builder deixa de gerar particionamento e rede, mas **não** se ausenta do `%post`. Conferido na ISO de 2026-09-24: ele grava um `osbuild-base.ks` com a linha `ostreecontainer` e um `%post` próprio, com o `bootc switch` **sem** a flag, e o nosso `osbuild.ks` o inclui na primeira linha. O Anaconda roda os `%post` na ordem em que aparecem, então os dois switches rodam, o dele primeiro, e o nosso, por ser o último a gravar a origin, é o que vale.

Por isso a receita `just iso` termina extraindo os kickstarts da ISO pronta (com o `7z`), montando o conteúdo na ordem de execução e conferindo: que o `%include` do builder está no topo, que o **último** `bootc switch` exige a assinatura, o `--type=btrfs`, a correção do fstab e da compressão, a linha `ostreecontainer` e uma única linha de `autopart`. Procurar a flag em qualquer lugar não bastaria: com a ordem invertida, ela estaria no kickstart e a deployment nasceria sem ela. É a única parte da instalação que o `just check` não alcança, e um erro aqui só apareceria com o disco da máquina já apagado.

O `autopart` fica, e o `clearpart` sai: sem ele o spoke de destino fica incompleto e o Anaconda para na tela de seleção de disco, que é onde essa decisão pertence — mantendo o esquema (Btrfs, sem `/home` separado) declarado por nós.

### O que a instalação de 2026-09-23 mostrou

Com a mídia anterior, ainda com o kickstart padrão do builder:

- **o Btrfs é respeitado.** O builder lê o `[install.filesystem.root]` da imagem e o traduz para o `autopart`. O `--nohome` é o certo num sistema ostree, onde `/home` é link para `/var/home`. Para conferir depois, o alvo é `/sysroot`, e não `/`: a raiz de um sistema bootc é um overlay do composefs, e `btrfs subvolume list /` responde "not a btrfs filesystem" mesmo num disco Btrfs;
- **o `%post` já aponta a deployment para o registry**, o que faz o `bootc upgrade` funcionar sem nenhum passo extra — mas a instalação daquele dia saiu sem a exigência de assinatura, e o `bootc status` sem campo nenhum de assinatura. Numa máquina já instalada assim, o conserto é um `sudo bootc switch --enforce-container-sigpolicy ghcr.io/<dono>/arkmos:44`; nas mídias geradas a partir do `iso-config.toml` a flag já vai no kickstart;
- **o digest instalado não é o do registry.** A imagem viaja na ISO como OCI layout, e a conversão muda o digest do manifest: a máquina instalada mostrou `sha256:493bd810…` para a mesma `44.20260923.75` que no registry é `sha256:3d5fc5fc…`. Mesmo conteúdo, formato diferente — o primeiro `bootc upgrade` depois de instalar pela ISO pode, por isso, baixar mais do que o delta normal entre publicações (seção 28.5).

**Instalação direta**, num disco, a partir de qualquer Linux com podman (um pendrive live, por exemplo):

```bash
sudo podman run --rm --privileged --pid=host \
    -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
    --security-opt label=type:unconfined_t \
    ghcr.io/<owner>/arkmos:44 \
    bootc install to-disk --wipe /dev/sdX
```

A imagem não tem conta nenhuma, e é o assistente do primeiro boot que a cria (seção 12). É o caminho que torna a imagem autossuficiente, e o que o `just vm` usa.

**Rebase**, a partir de um Fedora Atomic já instalado (Silverblue, Kinoite, Aurora…):

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/<owner>/arkmos:44
```

A conta e o `/var/home` vêm do sistema de origem, e o assistente se dispensa sozinho (seção 12.1).

**O que o rebase não traz é o `$HOME`.** Todo o resto chega igual, porque está declarado fora dele: pacotes, serviços habilitados, greetd, niri, Noctalia, firewall, docker, fontes, o tema do sistema (o dconf é banco de sistema), o `mimeapps.list` de `/etc/xdg` e os Flatpaks da lista, que são instalados por serviço de sistema. Fica de fora o que o `/etc/skel` semeia numa conta que já existia: a configuração do Noctalia (barra, dock, paleta do shell), o zsh e o starship, o `settings.json` do VS Code e o tema do btop. Um `cp -rn /etc/skel/. ~/` cobre isso. Nos caminhos de instalação do zero o problema não existe: a conta nasce depois da imagem, e o `useradd` — do Anaconda ou do assistente — copia o skel.

**O assistente do primeiro boot continua necessário nos três caminhos.** Quando o instalador já cria a conta, ele se dispensa em silêncio e faz só o que falta, o grupo `docker` (seção 12.1). Quando não cria — o `install to-disk` não tem instalador nenhum, e uma tela de conta pode ser pulada — ele é o que faz a máquina nascer usável em vez de inacessível. Removê-lo amarraria o projeto a um instalador específico.

A flag é o que faz as atualizações seguintes serem verificadas: ela grava na deployment que o pull obedece à política de assinatura (`signature: containerPolicy` no `bootc status`). Sem ela, nenhum `bootc upgrade` posterior checaria nada.

Esse primeiro switch, porém, não verifica a assinatura do Arkmos. Quem decide é a política do sistema de origem, que não conhece a chave, e nela uma imagem sem regra própria cai no `insecureAcceptAnything`. A política do Arkmos chega com a nova deployment e vale a partir do upgrade seguinte, desde que o `/etc/containers/policy.json` do sistema de origem não tenha sido editado: arquivo alterado localmente em `/etc` prevalece sobre o da imagem. Para conferir antes da troca, o `cosign verify` com a chave pública do repositório (seção 28).

## 31.1 Atualização

Na mão:

```bash
sudo bootc upgrade     # busca e encena a imagem nova
bootc status           # o que está rodando, o que está encenado
sudo bootc rollback    # volta para a deployment anterior
```

O número da versão não é a rede de segurança — `bootc rollback` é.

**E já existe atualização automática, herdada da base do Universal Blue.** Ela não foi escolhida aqui, veio com a base, e é melhor saber disso do que descobrir num boot:

| Unidade | Estado | O que faz |
| --- | --- | --- |
| `rpm-ostreed-automatic.timer` | ligada | 1h depois do boot e a cada 24h: baixa a imagem nova e a **encena**, com `AutomaticUpdatePolicy=stage` em `/etc/rpm-ostreed.conf`. Um drop-in exige rede não tarifada. |
| `flatpak-system-update.timer` | ligada | atualiza os Flatpaks da instalação de sistema, às 4h com jitter de 10min |
| `bootc-fetch-apply-updates.timer` | **desligada** | este aplicaria e reiniciaria sozinho |

O desenho é o certo para uma máquina de trabalho: o download acontece sozinho, a imagem nova fica pronta no disco, e **reiniciar continua sendo decisão de quem usa** — nada troca debaixo de uma sessão aberta. O `just check` passou a afirmar esse estado, porque uma reconstrução da base pode mudá-lo em silêncio nos dois sentidos: máquina que deixa de receber imagem nova, ou máquina que passa a reiniciar em imagem que ninguém olhou.

A base também traz o `ujust`, do pacote `ublue-os-just`, com as receitas do Universal Blue:

```bash
ujust update           # rpm-ostree update + flatpak update + distrobox upgrade
ujust toggle-updates   # liga/desliga a atualização automática
ujust changelogs       # rpm-ostree db diff --changelogs
ujust update-firmware  # fwupdmgr
```

**O que o Arkmos não tem é o `uupd`**, o daemon de atualização do Universal Blue. O Bluefin o instala, desabilita o `rpm-ostreed-automatic.timer` e deixa o `uupd` coordenar sistema, Flatpaks e Distrobox num só lugar — o `ujust update` inclusive detecta se ele está ligado e delega. Aqui o ganho seria coordenação e log num lugar só, ao custo de uma dependência a mais fora do Fedora; com o `flatpak preinstall` já reconciliando a lista e o timer do Flatpak já atualizando versões, a conta não fechou. Fica registrado como alternativa, não como pendência.

## 31.2 O menu do ujust

O menu vem do pacote `ublue-os-just`, e o justfile dele termina com

```text
import? "/usr/share/ublue-os/just/60-custom.just"
```

A interrogação quer dizer opcional: é o gancho que o Universal Blue deixa para a imagem derivada acrescentar receitas sem tocar no justfile do pacote. As três do Arkmos entram por ali (`files/usr/share/ublue-os/just/60-custom.just`):

| Receita | O que faz |
| --- | --- |
| `ujust arkmos-variant base\|nvidia` | o `bootc switch` para a variante irmã, com a flag de assinatura. A imagem sai da própria deployment, então quem instalou de outro registry continua trocando dentro dele; imagem local é recusada com a instrução do switch. |
| `ujust arkmos-apply-defaults` | copia o `/etc/skel` para a conta, com `cp -rn` — nunca sobrescreve o que a pessoa editou. É a resposta ao caso do rebase e ao "atualizei a imagem e meu home continuou com o padrão antigo" (seção 30). |
| `ujust arkmos-diag` | o `arkmos-diag` que já existia, agora visível no menu. |

E quatro receitas do Universal Blue **saem** do menu, pelo `build_files/trim-ujust.sh`:

```text
toggle-nvk             faz rebase para '<imagem>-nvidia-open', que aqui não
                       existe: as variantes são 'arkmos' e 'arkmos-nvidia'
install-resolve        DaVinci Resolve num Distrobox dedicado
configure-broadcom-wl  Wi-Fi Broadcom
setup-distrobox-app    containers de aplicativo do Bluefin
```

O recorte é dentro dos arquivos, e não apagando cada um: os `.just` do pacote misturam receitas úteis com essas, e o justfile principal importa todos sem interrogação — arquivo ausente quebraria o menu. Os `alias` que apontavam para uma receita removida saem junto, senão o justfile fica com sintaxe inválida. Se o pacote renomear alguma delas, o script falha de propósito; e no fim ele monta o menu com o `just --list` e confere as duas listas, o que sai e o que tem de ficar.

O que fica é o que serve aqui, com destaque para três:

- `ujust bios` reinicia direto na UEFI — é onde a dGPU é ligada e desligada nesta máquina (seção 24);
- `ujust check-local-overrides` faz diff do `/etc` contra o `/usr/etc` da imagem: é o comando que mostra o que ficou congelado localmente contra as atualizações (seção 11);
- `ujust setup-luks-tpm-unlock` destrava o disco cifrado pelo TPM, se a instalação pela ISO for com cifragem.

Duas ressalvas sobre receitas que ficaram, porque o comportamento não é óbvio pelo nome:

- `ujust clean-system` roda `podman image prune -af`: remove **toda** imagem sem container associado, o que inclui as do Laravel Sail se nenhum container estiver criado naquele momento. Não toca em containers nem volumes, então o custo é re-download;
- `ujust enroll-secure-boot-key` só importa com Secure Boot ligado e a variante NVIDIA; a senha `universalblue` que ele pede é legítima, porque os akmods vêm assinados pelo Universal Blue (seção 5).

---

# 32. Git

O projeto é versionado em Git, com mensagens em inglês no formato convencional (`feat:`, `fix:`, `chore:`, `docs:`).

O que **não** entra no repositório:

```text
*.qcow2
*.raw
*.img
*.iso
*.log
result/
output/
output-nvidia/
```

Decisões arquiteturais devem vir acompanhadas de justificativa — no commit quando é pontual, neste documento quando muda o desenho.

---

# 33. Estrutura do Projeto

```text
arkmos/
├── Containerfile                  a imagem: base, pacotes, configuração
├── Justfile                       build, verificação, VM, lint, rechunk
├── .containerignore               o que não vai no contexto do build
├── .editorconfig                  estilo dos arquivos (o shfmt o lê)
├── config.toml                    bootc-image-builder (a MÍDIA, não a imagem)
├── iso-config.toml                kickstart da ISO: disco escolhido, assinatura
├── README.md                      uso
├── PROJECT.md                     arquitetura e decisões
├── .gitignore
│
├── .github/
│   ├── workflows/build.yml        build, verificação, publicação, assinatura
│   └── assets/logo.png            logo do README, gerada por 'just logo'
│
├── tests/
│   └── check-image.sh             verificações, compartilhadas com o CI
│
├── build_files/                   rodam no build e NÃO ficam na imagem
│   ├── install-upstream-bins.sh   starship, lazygit, lazydocker (sha256)
│   ├── install-nerd-font.sh       JetBrains Mono patched (sha256)
│   ├── install-cursor.sh          cursor Bibata Modern Ice (sha256)
│   ├── papirus-folders.sh         pastas do Papirus em violeta
│   ├── patch-niri-session.sh      lista de variáveis no import-environment
│   ├── trim-ujust.sh              recorta o menu do ujust
│   └── render-artwork.sh          splash de boot e wallpaper padrão
│
└── files/                         copiado para dentro da imagem
    ├── etc/
    │   ├── greetd/config.toml
    │   ├── hostname
    │   ├── locale.conf
    │   ├── vconsole.conf
    │   ├── niri/config.kdl
    │   ├── nvidia/…
    │   ├── plymouth/plymouthd.conf
    │   ├── profile.d/mise.sh      ativação do mise no bash
    │   ├── skel/                  defaults de VS Code, Noctalia e btop
    │   ├── xdg/mimeapps.list      aplicativos padrão por tipo de arquivo
    │   ├── xdg/xdg-terminals.list terminal padrão (foot)
    │   ├── xdg-desktop-portal/niri-portals.conf
    │   ├── yum.repos.d/           docker-ce e vscode, enabled=0
    │   └── zshenv
    └── usr/
        ├── lib/
        │   ├── bootc/install/     filesystem raiz
        │   ├── environment.d/     locale e XDG_DATA_DIRS do systemd --user
        │   ├── bootc/kargs.d/     argumentos de kernel
        │   ├── systemd/system/    firstboot, preinstall de Flatpaks, drop-ins
        │   ├── systemd/system-preset/  sshd desligado, tailscaled ligado
        │   ├── sysusers.d/        grupo docker
        │   └── tmpfiles.d/        conteúdo de /var
        ├── libexec/
        │   ├── arkmos-firstboot
        │   └── arkmos-greeter
        ├── share/ublue-os/just/     60-custom.just, receitas do ujust
        ├── share/flatpak/preinstall.d/
        │   └── arkmos.preinstall  Flatpaks que acompanham o sistema
        ├── share/arkmos/
        │   ├── noctalia-greeter*.toml  tela de login e sua aparência inicial
        │   ├── starship.toml      prompt
        │   └── zsh/               configuração do shell, em módulos
        └── share/plymouth/themes/arkmos/
                                   tema do splash (arte gerada no build)
```

Os repositórios de terceiros ficam com `enabled=0` e são habilitados pontualmente no `install` correspondente, para que o sistema em execução nunca dependa deles.

A configuração é copiada **depois** dos pacotes, de propósito: se vier antes, o RPM encontra o arquivo ocupado e grava o dele como `.rpmnew`, deixando qual das duas versões vale dependente da ordem de instalação.

---

# 34. Estratégia de Versionamento

## 0.1.0

Base Fedora bootc.

## 0.2.0

Infraestrutura: NetworkManager, Bluetooth, PipeWire, WirePlumber, TuneD, Podman, Docker compatibility, Distrobox.

## 0.3.0

Filesystem Btrfs e configuração declarativa do bootc.

## 0.4.0

Base gráfica: Niri, XWayland Satellite, Foot, XDG Desktop Portal, GNOME Keyring.

## 0.5.0

Configuração personalizada do Niri: remoção da dependência de Waybar, Foot como terminal, ajustes de atalhos, configuração versionada.

## 0.6.0

Configuração regional e firstboot: pt_BR, ABNT2, `America/Sao_Paulo`, cadastro inicial.

## 0.6.1

Correção do suporte ao locale português (`glibc-langpack-pt`).

## 0.7.0

Desktop completo e ferramentas:

- Noctalia Shell 5;
- login gráfico com greetd + tuigreet;
- ambiente de terminal (Zsh + Starship + Nerd Font);
- Docker CE real e VS Code na imagem;
- localização movida do firstboot para a imagem.

Primeiro teste em VM: firstboot completo, mas sessão não abriu — `user = "greeter"` inexistente no `greetd/config.toml`.

## 0.8.0

Base, distribuição e robustez:

- migração para as imagens do Universal Blue;
- duas variantes (`arkmos`, `arkmos-nvidia`) parametrizadas por `ARG BASE_IMAGE`;
- CI com publicação no GHCR e assinatura cosign;
- verificações unificadas em `tests/check-image.sh`, incluindo a que reproduz o bug do greeter;
- configuração própria do Zsh, substituindo a config de terceiro clonada no build (seção 13.3); plugins passam a vir de RPM;
- lazygit e lazydocker, com checksum SHA256 fixado, como todo download de build;
- primeira aparência coerente: `prefer-no-csd`, terminal escuro, tema GTK escuro por dconf, tela de login com nome e retorno ao digitar (seção 26.1);
- splash de boot próprio — tema `arkmos` do Plymouth, com o initramfs regerado — e wallpaper padrão, os dois gerados no build a partir de fonte e cores (seções 26.1 e 27.2);
- Nautilus como gerenciador de arquivos, na imagem (seção 25.1), e as pastas do usuário criadas em português (seção 11.1);
- títulos do overlay de atalhos do niri em português (seção 11.2);
- primeira imagem publicada no GHCR, assinada e com a assinatura verificada de ponta a ponta — inclusive a recusa de imagem sem assinatura (seções 28.2 e 28.3);
- greeter compilado para uma linha de base portátil: o `-march=native` do upstream deixava toda imagem publicada inutilizável fora do runner do CI (seção 8.3);
- correções: conta do greeter, ordenação do firstboot e ruído no console, hostname, `nvidia-cdi-refresh`, fallback de getty, cache do tuigreet, variáveis EFI da VM, prompt de senha do assistente, resolução e captura de teclado da VM;
- documentação: README e este documento.

## 0.9.0

Aplicações declaradas e identidade visual:

- lista de Flatpaks declarada na imagem e aplicada pelo `flatpak preinstall`, com um serviço que instala o que falta a cada boot e remove o que sair da lista (seção 25);
- atualização automática no modo encenado, com o timer do bootc que reiniciaria sozinho desligado (seção 31.1);
- menu do ujust sem as receitas que apontam para fora desta imagem e com as três do Arkmos (seção 31.2);
- aplicativos padrão por tipo de arquivo, com PDF, imagem e vídeo nos visualizadores do GNOME e texto no VS Code, mais o `XDG_DATA_DIRS` da sessão, sem o qual o clique duplo não abria nada (seções 25 e 26.1);
- o que o uso diário pedia e a base não trazia: celular e rede no Nautilus, miniaturas de PDF, terminal padrão para programas de terminal, Tailscale, agente SSH, firewall na zona do Fedora Workstation, servidor SSH desligado, btop no lugar do htop (seções 22 e 25);
- esquema **Tokyo Night** como identidade, com nove papéis de parede próprios, ícones Papirus-Dark com pastas em violeta e o anel de foco do niri no roxo do esquema (seção 26.1);
- a paleta seguida por GTK 3 e 4, btop, Qt e KDE — inclusive em Flatpak, pelo override que dá acesso ao tema da conta (seção 26.1);
- bloqueio de tela por inatividade, que o Noctalia não liga por padrão (seção 23);
- assistente de primeiro boot que se dispensa quando a conta já existe, para o caminho de rebase (seção 12.1);
- atalhos do Noctalia para lançador e bloqueio, menu sem as entradas que não abrem nada, e captura com anotação (seções 8.1 e 25).

## 0.10.0

Noctalia configurado e o ferramental alinhado ao Universal Blue:

- barra, dock e painéis declarados a partir de uma sessão de testes exportada com `noctalia config export`, com o que é específico de máquina deixado de fora (seção 26.1);
- notificações: limite de toasts na tela, retenção de histórico de sete dias e filtro para o Spotify; o mako saiu da imagem, porque quem implementa o barramento de notificações é o Noctalia (seção 26.1);
- arredondamento da interface em 1.25, que o sync leva ao login;
- tela de login com apagamento por inatividade, máscara de senha aleatória e sem a logo do Noctalia (seção 8.3);
- terminal com fundo translúcido e ligaduras da JetBrains Mono no VS Code (seções 9 e 14);
- `just lint` e `just format` nas convenções do `image-template`, com `.editorconfig` e `.containerignore`, e um job de lint no CI (seções 28.2 e 29);
- rechunk antes de publicar: 289 camadas e 9,88 GB viraram 128 e 8,02 GB, e o `bootc upgrade` passa a baixar só o que mudou (seção 28.5);
- ARGs voláteis no fim do Containerfile, devolvendo o cache aos builds locais (seção 29);
- remendo no `niri-session` para o aviso de obsolescência que aparecia entre a senha e o desktop (seção 27.4);
- Limine fora do plano: o bootc se integra ao GRUB da base, e trocar de bootloader seria risco sem ganho (seção 7).

**O layout da tela de bloqueio ficou fora da imagem, por decisão.** O identificador de cada widget carrega o nome do monitor (`lockscreen-login-box@eDP-1`), e a posição é em pixels: declarar isso na imagem produziria configuração morta em qualquer máquina com outro monitor. É estado de máquina, posicionado uma vez em cada instalação.

---

# 35. Estado Atual

Versão:

```text
0.10.0
```

## 35.1 Validado em container (`just check-all`, as duas variantes)

```text
bootc container lint
units do Arkmos (systemd-analyze verify)
locale pt_BR, ABNT2, timezone, hostname
conta do greeter, display-manager, sessão do Niri, niri validate
tmpfiles.d resolvendo usuários e grupos
pacotes do Arkmos e componentes herdados da base
ausência de podman-docker
pilha NVIDIA presente/ausente conforme a variante
zsh funcionando sem rede
tema do Plymouth e conteúdo do initramfs (tema, ostree, ABNT2, /root)
wallpaper padrão e config do Noctalia semeados, sem avisos do validador
Nautilus atendendo org.freedesktop.FileManager1
pastas do usuário em português e overlay do niri com títulos traduzidos
Discos, gerenciador de compactação e assistente de impressão; barramento do
  sistema ainda no dbus-broker
ícones Papirus-Dark nos três caminhos de leitura, pastas em violeta
esquema Tokyo-Night declarado e existente na lista do Noctalia; templates de
  paleta certos ligados e os de foot e niri fora; anel de foco no roxo do
  esquema; cor de destaque roxa no dconf; override que deixa o Flatpak ler o
  tema da conta; papel de parede
  padrão dentro da pasta declarada, com as outras imagens ao lado
Flatpaks declarados legíveis pelo flatpak preinstall, padrões de aplicativo
  apontando para eles, libfuse.so.2 para AppImage, capturas em pt-BR
componentes de uso diário (gvfs-mtp/smb/fuse, sushi, miniaturas de PDF,
  Tailscale, gcr-ssh-agent, xdg-terminal-exec, btop, Carlito e Caladea)
sshd desligado também no preset, firewall na zona FedoraWorkstation
lançador e bloqueio do Noctalia nos atalhos, bloqueio por inatividade ligado
menu sem as entradas que não abrem nada, com as configurações do Noctalia
```

## 35.2 Validado em VM

```text
boot em UEFI/OVMF com Btrfs
assistente de firstboot completo: usuário, grupos wheel e docker, senha
/var/lib/arkmos/initialized gravado
login pelo Noctalia Greeter
sessão Niri + Noctalia subindo depois do login
splash de boot do Arkmos numa instalação completa (mídia com
  plymouth.ignore-serial-consoles; seção 30)
pastas do usuário criadas em português no login
overlay de atalhos do niri: não abre sozinho, títulos em português
teclado ABNT2 na sessão gráfica
clipboard entre terminal e VS Code, nos dois sentidos
wallpaper padrão aplicado no desktop
wallpaper escolhido na sessão levado às telas de bloqueio e de login (sync)
bootc switch para a imagem publicada no GHCR, com --enforce-container-sigpolicy
recusa de imagem sem assinatura: "A signature was required, but no signature
  exists", antes de baixar camada nenhuma
login e sessão a partir da imagem publicada, com o greeter compilado para
  linha de base portátil (seção 8.3)
bootc rollback devolvendo a deployment anterior: os papéis booted e rollback
  aparecem trocados no bootc status
bootc upgrade para uma versão publicada depois da instalada, verificando a
  assinatura sem repetir a flag (signature: containerPolicy na deployment)
portais, notificações e seletor de arquivos na sessão: arkmos-diag sem
  pendência, notify-send aparecendo, xdg-open abrindo o Nautilus e o "salvar
  como" do Firefox abrindo o seletor
mise ativado no zsh e no bash interativo (MISE_SHELL=zsh, MISE_SHELL=bash)
nenhuma unit de usuário falhada na sessão (grub-boot-success mascarada)
indexador do Nautilus (localsearch-3) ativo ao abrir o Nautilus
Nautilus em uso: busca, lixeira, "mostrar na pasta", e ISO montada pelo Discos
  no clique duplo
extração de RAR4 e RAR5 pelo gerenciador de compactação
assistente de impressão abrindo, com o Desbloquear afastado da borda
mise sem oferecer atualização que não consegue fazer
ícones Papirus-Dark com pastas violeta, e ícones de ferramenta claros
avatar trocado pelo Centro de controle do Noctalia
instalação dos 22 Flatpaks pelo preinstall no primeiro boot (o Papers exigiu o
  runtime GNOME 51, publicado no mesmo dia, e só abriu depois dele)
aplicativos padrão no clique duplo: imagem, PDF e vídeo, depois do
  XDG_DATA_DIRS da sessão
bloqueio de tela por inatividade, com o arkmos.toml atualizado na conta
atalhos do Noctalia: lançador no Mod+D, bloqueio no Super+Alt+L
menu sem as entradas que não abrem nada, com Configurações do Noctalia, e btop
  abrindo pelo menu (terminal padrão pelo xdg-terminal-exec)
Distrobox criando, entrando e removendo container; docker run sem sudo
firewall na zona FedoraWorkstation; sshd ativo só pela linha de boot da VM
  (enabled-runtime); SSH_AUTH_SOCK do gcr na sessão; tailscale instalado
bootc switch da imagem local (localhost/arkmos:dev) para a publicada
identidade visual em conta nova (useradd -m, que copia o /etc/skel): papel de
  parede padrão, barra e painéis do Noctalia no Tokyo Night, anel de foco
  roxo, Nautilus com pastas violeta e destaque roxo, btop nas cores do
  esquema, e um Flatpak Qt (Fedora Media Writer) seguindo a paleta
```

## 35.2.1 Instalação pela ISO, em VM (2026-09-23)

Ensaio do caminho que vai ao hardware, com a ISO de 4,5 GB gerada pelo `just iso` a partir da `44.20260923.75` e instalada numa VM do virt-manager (UEFI, Video Virtio com 3D, Display Spice com OpenGL).

```text
deployment seguindo ghcr.io/alexrogaleski/arkmos:44, versão 44.20260923.75
raiz em Btrfs (/dev/vda3[/root]), subvolume único 'root'
conta criada pelo assistente do primeiro boot, com wheel E docker
38 refs de Flatpak instaladas pelo preinstall, incluindo todos os declarados
greetd, docker, tailscaled e o preinstall habilitados; sshd desligado
rpm-ostreed-automatic e flatpak-system-update ligados, bootc-fetch desligado,
  AutomaticUpdatePolicy=stage
LANG=pt_BR.UTF-8, VC Keymap br, X11 Layout br (sem xorg.conf.d)
menu do ujust com as três receitas do Arkmos
/etc alterado localmente: só o inevitável — chaves de host do ssh, machine-id,
  passwd/shadow, fstab, crypttab, conexão do NetworkManager, estado do tuned e
  resíduos do Anaconda. Nada declarado pela imagem ficou congelado.
```

Duas coisas que o ensaio mostrou e que não são defeito:

- **a tela de login nasce com o tema padrão do Noctalia.** A aparência do greeter chega pelo sync a partir da conta (`[shell.greeter_sync] auto_sync = true`), e antes do primeiro login não existe conta de onde sincronizar. Corrigido com a semente do `sync.toml` (seção 26.1);
- **a área de transferência do SPICE não funciona na sessão.** O socket, o daemon e o `spice-vdagent.service` do usuário estavam todos ativos — o agente é que roda em modo X11 (`spice-vdagent -x`), e no niri, Wayland puro, não há ponte de área de transferência com o X11 como o mutter faz no GNOME. Para trazer saídas de dentro da VM, o caminho é o ssh: `sudo systemctl start sshd` na VM (a imagem o mantém desligado) e `ssh -t usuario@IP 'comando' | tee arquivo` no host.

## 35.2.2 Instalação pela ISO com o kickstart próprio, em VM (2026-09-24)

No desktop, com a ISO gerada a partir da mesma `44.20260923.75` e instalada pelo `just run-iso`.

```text
Anaconda em português, teclado ABNT2 (módulo de localização ligado)
disco, rede e conta escolhidos nas telas; root bloqueado
reboot do fim da instalação direto no sistema instalado
conta criada no Anaconda; groups: arm wheel docker
```

O que o ensaio mostrou, e já foi corrigido para a próxima ISO:

- **o módulo de localização reescreve o `/etc`.** O `ostree admin config-diff` mostrou `locale.conf` e `vconsole.conf` modificados, com os mesmos valores entre aspas, e um `/etc/X11/xorg.conf.d/00-keyboard.conf` novo, para onde o `systemd-localed` moveu o `XKBLAYOUT` e o `XKBMODEL`. O `%post` do kickstart passou a devolver os dois arquivos de `/usr/etc` e a apagar o do X11 — ensaiado na segunda instalação, abaixo;
- **o aviso `deprecated: foot: [colors]`** vem da imagem publicada, anterior à correção do `[colors-dark]` (seção 8.1): a ISO sai da imagem publicada, e não da local.

Segunda instalação no mesmo dia, com a ISO de 4,4 GB gerada da **`44.20260924.83`** (commit `a3844b4`), num disco novo:

```text
/etc sem locale.conf, vconsole.conf nem xorg.conf.d no config-diff: a
  restauração do %post funcionou, e o instalador continua em português
tela de login no Tokyo Night desde o primeiro boot, sem clique (semente do
  sync.toml, seção 26.1)
cursor Bibata Modern Ice no desktop e no login
Adwaita Sans na barra, nas janelas e no login
terminal sem o aviso de [colors] do foot
```

## 35.2.3 Primeira instalação em hardware real (2026-09-24)

O notebook alvo — i5-11300H (Tiger Lake) com Iris Xe, dGPU NVIDIA desligada na BIOS —, com a variante padrão instalada pela ISO da `44.20260924.83` no NVMe secundário (NXM-512). O outro NVMe, com a instalação anterior, não foi tocado: é a primeira vez que o kickstart sem `clearpart` protege um disco que existe de verdade.

```text
deployment ostree-image-signed:docker://ghcr.io/alexrogaleski/arkmos:44
login pelo Noctalia Greeter e sessão niri em Wayland
conta criada no Anaconda; groups: arm wheel docker
LANG=pt_BR.UTF-8, VC Keymap br, X11 Layout br
22 Flatpaks instalados pelo preinstall no primeiro boot, em 4min19s
AutomaticUpdatePolicy=stage
```

E o que o hardware mostrou que a VM não tinha mostrado — ou que ninguém tinha olhado:

- **`systemd-remount-fs` falhando, e o Btrfs sem compressão.** A linha de `/` do fstab do Anaconda. Corrigido na máquina, com a linha de boot, e no kickstart para as próximas mídias (seção 6). Depois do reboot: `compress=zstd:1` no `/sysroot` e no `/var`, e `systemctl --failed` vazio. As instalações por ISO na VM saíram do mesmo Anaconda e provavelmente tinham a mesma falha, mas isso não foi conferido;
- **subvolume `root00`**, por causa do Btrfs do outro disco (seção 6);
- **`rhgb quiet` duas vezes na linha do kernel**, uma dos `kargs.d` da imagem e outra do Anaconda. Só estética;
- no journal, só ruído que não é do Arkmos: o grupo `plugdev` das regras de U2F, o `docker-forwarding` já existente no firewalld e o HID de um dispositivo Bluetooth.

## 35.3 Não validado ainda

```text
Laravel Sail em uso real
ISO com a correção do fstab e da compressão no %post (seção 6): o kickstart
  foi conferido fora do Anaconda, mas a instalação não foi ensaiada
a variante NVIDIA no hardware, com a dGPU ligada
o primeiro 'bootc upgrade' de uma máquina instalada pela ISO — o digest local é
  o da conversão OCI da mídia, então o download pode ser maior que o delta
  medido entre publicações (seções 28.5 e 31)
cadastro de uma impressora de verdade
remoção de um Flatpak retirado da lista depois de um bootc upgrade
celular por USB no Nautilus, agente SSH num git push, tailscale up,
  LocalSend recebendo
travamento antes do assistente no primeiro boot em VM — visto uma vez em
  2026-09-15, com a janela GTK/GL; não reproduzido no boot seguinte
```

---

# 36. Próximos Passos

## Curto prazo

1. Se o travamento antes do assistente voltar num primeiro boot em VM, abrir **View → serial0** antes de fechar a janela (seção 30).
2. Gerar uma ISO nova e ensaiar em VM a correção do fstab e da compressão: depois de instalar, `findmnt -M /sysroot` com `compress=zstd:1` e `systemctl --failed` vazio.

## Médio prazo

3. Registrar em uso real, agora no hardware, quanto o `bootc upgrade` baixa de fato, para comparar com os 559 MB medidos no registry (seção 28.5).
4. Validar a variante NVIDIA no hardware: `ujust arkmos-variant nvidia` com a dGPU ligada na BIOS.

## Longo prazo

5. Snapshots do `/var/home` e backup para fora da máquina — o rollback do sistema já vem do bootc (seção 6).
6. Documentar recuperação.
7. Revisar a política de atualização depois de um mês de uso real — hoje é o encenado automático herdado da base, documentado e verificado (seção 31.1).
8. Estabilizar a versão 1.0.0.

---

# 37. Critério para 1.0.0

O Arkmos somente deve ser considerado `1.0.0` quando:

- instalação for reproduzível;
- boot for confiável;
- firstboot estiver estável;
- usuário for criado corretamente;
- locale, teclado e timezone estiverem corretos;
- Niri estiver estável;
- Noctalia estiver integrado;
- aplicações essenciais estiverem definidas e declaradas;
- atualização via `bootc upgrade` estiver validada;
- rollback estiver validado;
- assinatura estiver verificada na instalação;
- Btrfs estiver funcionando corretamente;
- recuperação estiver documentada;
- instalação em hardware real tiver sido validada.

---

# 38. Decisões Arquiteturais

```text
Universal Blue como base        akmods NVIDIA assinados prontos (seção 5)
Duas variantes de imagem        dGPU alternável pela BIOS (seção 24)
Fedora bootc                    sistema como imagem, atualizável e reversível
Btrfs                           snapshots do /var, que o bootc não cobre
Niri                            compositor
Noctalia                        shell do desktop
greetd + Noctalia Greeter       login; tuigreet de recuperação (seção 8.3)
Docker CE real                  Laravel Sail (seção 15)
VS Code na imagem               terminal integrado precisa do docker do host;
                                redistribuição assumida conscientemente (seção 28.4)
Podman + Distrobox              containers e ambientes
PipeWire / NetworkManager       vêm da base
GTK como preferência visual
JetBrains Mono Nerd Font
Zsh + Starship                  configuração própria, plugins de RPM (seção 13)
mise na imagem                  toolchain de linguagem no $HOME, por projeto,
                                fora do ciclo de build (seção 17.2)
Locale na imagem                não em runtime (seção 11)
Verificações compartilhadas     um script para just e CI (seção 28)
```

Alterações nessas decisões devem ser feitas conscientemente e, quando relevante, acompanhadas de justificativa no Git e aqui.

---

# 39. Créditos

O Arkmos é, em volume, quase inteiramente trabalho de outras pessoas. Ver a seção de créditos do [README.md](README.md).

Destaque para o [Universal Blue](https://universal-blue.org): sem a base que eles mantêm — e sobretudo sem os akmods NVIDIA assinados — este projeto não caberia numa pessoa só.

---

# 40. Filosofia do Arkmos

O Arkmos não pretende ser uma nova distribuição Linux tradicional.

É uma definição versionada de uma estação de trabalho pessoal.

A máquina física é substituível.

A instalação é descartável.

A configuração é o patrimônio.

```text
Hardware
    ↓
pode mudar

Sistema instalado
    ↓
pode ser destruído

Imagem Arkmos
    ↓
pode ser reconstruída

Git
    ↓
guarda a definição
```

O objetivo final é poder reinstalar o ambiente pessoal com o mínimo possível de configuração manual.

---

# Status

**Arkmos 0.10.0 — em desenvolvimento**

Marcos:

```text
0.8.0  → fechado: imagem publicada, assinada, instalável e atualizável
0.9.0  → fechado: aplicações declaradas e identidade visual
0.10.0 → fechado: Noctalia configurado e ferramental alinhado ao ublue
1.0.0  → instalado no hardware em 2026-09-24; falta uso real (seção 37)
```
