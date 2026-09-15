# Arkmos

Sistema operacional pessoal e reprodutível baseado em Fedora bootc, desenvolvido para facilitar instalações, reinstalações e manutenção de uma estação de trabalho Linux personalizada.

> **Status:** Em desenvolvimento
> **Versão atual:** 0.8.0
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

Objetivos futuros:

- snapshots;
- rollback de dados (o rollback do sistema já existe, via bootc);
- integração com Snapper;
- recuperação do sistema.

---

# 7. Bootloader

## Estado atual

```text
GRUB
```

O GRUB é utilizado durante o desenvolvimento para reduzir variáveis.

## Objetivo futuro

```text
Limine
```

A mudança deverá ocorrer somente após a estabilização da base.

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
- `Mod+D` abre o Fuzzel;
- `prefer-no-csd` ligado.

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

A paleta é provisória — vem de um tema entregue pelo próprio pacote foot, e sai na definição da identidade visual (seção 26). Um `~/.config/foot/foot.ini` do usuário substitui este arquivo por inteiro; o foot não mescla os dois.

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

## 12.4 Por que um assistente próprio

O Universal Blue **não** cria usuário no primeiro boot. Verificado no Aurora instalado: não há `gnome-initial-setup` nem `initial-setup`; a conta vem do **Anaconda, durante a instalação da ISO**.

Os mecanismos de firstboot presentes na imagem são do systemd e nenhum serve:

```text
systemd-firstboot          locale/keymap/timezone/senha de root — não cria usuário comum
systemd-homed-firstboot    criaria via homectl, mas exige systemd-homed (ausente)
                           e mudaria o modelo de home
```

Para mídia gerada com `bootc-image-builder` e para `bootc install to-disk` não existe caminho pronto. O assistente em TTY é a resposta.

O caminho alternativo, se um dia fizer sentido, é gerar ISO com Anaconda (`--type anaconda-iso`) e deixar o instalador criar a conta.

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

Fonte padrão:

```text
JetBrains Mono Nerd Font 3.5.1
```

O `jetbrains-mono-fonts` do Fedora **não** é a versão patched; o `starship.toml` e o `eza --icons` dependem dos glifos Nerd Font, então a versão patched é baixada no build, com versão e checksum SHA256 fixados em `build_files/install-nerd-font.sh`.

Também instaladas: `google-noto-emoji-fonts`.

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

## Fedora Mobile

Container planejado:

```text
fedora-mobile
```

Responsável por:

- Android Studio;
- Android SDK;
- Android Emulator;
- Flutter;
- Dart;
- FVM;
- JDK;
- Gradle.

## Ubuntu Database

Container planejado:

```text
ubuntu-db
```

Responsável principalmente por:

```text
MySQL Workbench
```

Ambos ainda não estão declarados no repositório — ver seção 36.

---

# 17. Desenvolvimento

Ferramentas na imagem:

```text
Git
Curl / Wget
Neovim / Vim
Zsh
Python
OpenSSH (cliente)
eza / bat / fd / fzf / ripgrep / zoxide
lazygit / lazydocker
VS Code 1.137
```

## 17.1 VS Code na imagem, não em Flatpak

No Flatpak o terminal integrado roda dentro do sandbox e não enxerga o docker do host — o que quebra o Laravel Sail, que é dirigido inteiramente por `docker compose` a partir desse terminal. A extensão Dev Containers também não funciona sob Flatpak.

Manter o VS Code numa imagem que é publicada tem uma questão de licença, tratada na seção 28.4. Os defaults dele são semeados por `/etc/skel` (seção 26.1).

## 17.2 Stack principal

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
```

Objetivos: Ethernet, Wi-Fi, VPN, integração com desktop.

---

# 23. Energia

```text
tuned 2.28
tuned-ppd
```

Objetivos: gerenciamento de performance, perfis de energia, autonomia em notebook.

Os diretórios que o tuned espera em `/var` são declarados em `tmpfiles.d` e não assados na imagem — ver seção 3.4.

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

Lista declarada:

```text
flatpaks.list
```

**Estado:** a lista existe e está versionada, mas nada a aplica ainda, e o conteúdo é a captura crua do Aurora — contém aplicações KDE que vieram do ambiente atual e podem não fazer sentido sob Niri (`kcalc`, `kclock`, `kontact`, `gwenview`, `okular`, `kpat`, `kweather`, `skanpage`…). Precisa de curadoria e de um mecanismo que a reconcilie. Ver seção 36.

AppImages específicas:

- Tolaria;
- Tabularis.

## 25.1 Gerenciador de arquivos: Nautilus, na imagem

O gerenciador de arquivos fica na camada do sistema, não em Flatpak. Ele não é um aplicativo isolado, é integração: montar pendrive (udisks), falar MTP e SMB e ter lixeira (gvfs), e implementar `org.freedesktop.FileManager1` — a interface D-Bus que o "mostrar na pasta" do VS Code e do Firefox chama. No sandbox ele precisaria de `filesystem=host` para ser útil, e ainda assim ficaria sem o resto.

| Opção | Custo na imagem | Observação |
| --- | --- | --- |
| **Nautilus** | 10 pacotes, 22 MiB | GTK4/libadwaita, segue o tema escuro já configurado; traz o gvfs |
| Thunar | 15 pacotes, 35 MiB | puxa `xfce4-panel` e `xfconf`, sem uso sob o Niri |
| Dolphin | 85 pacotes | KDE; Qt coberto só pelo portal |

O seletor de arquivos dos aplicativos continua no backend `gtk` do portal (`niri-portals.conf`). O backend do GNOME delega o seletor ao próprio Nautilus.

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
/etc/xdg-desktop-portal/         backend gtk para a interface Settings
  niri-portals.conf
/etc/greetd/config.toml          tela de login com nome, cores e retorno ao digitar
/usr/share/plymouth/themes/      splash de boot com o nome do sistema
  arkmos
/usr/share/backgrounds/arkmos    wallpaper padrão, gerado no build
/etc/skel/.config/noctalia/      wallpaper padrão e sync da tela de login
  arkmos.toml
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

Isso entra junto com o mecanismo que vai aplicar a `flatpaks.list` (seção 36) — instalar a extensão de tema é parte da mesma tarefa, não uma segunda.

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

### Arte gerada no build

O splash de boot e o wallpaper padrão não são imagens versionadas: saem de `build_files/render-artwork.sh`, a partir de fonte, cores e formas. O repositório e a imagem publicada são públicos, e arte tirada de site de wallpaper não tem autor nem licença identificáveis (seção 28.4).

As cores são as que o Tokyo Night e o Dracula têm em comum — fundo índigo quase preto e lavanda como destaque (`#bb9af7` num, `#bd93f9` no outro) —, para que o boot e o desktop combinem com qualquer um dos dois. Os dois esquemas vêm embutidos no Noctalia.

O Noctalia só lê configuração do home, então o wallpaper padrão chega pelo `/etc/skel` (`.config/noctalia/arkmos.toml`), como os defaults do VS Code. A tela de bloqueio usa o wallpaper do desktop enquanto a dela estiver vazia, que é o padrão.

A tela de login recebe wallpaper e paleta pelo **sync** do Noctalia, ligado no mesmo arquivo (`auto_sync = true`) e liberado sem senha pela regra `50-arkmos-greeter-sync.rules`. O código do greeter impõe duas consequências:

- **Nada de wallpaper ou paleta no `greeter.toml`.** Ele vence o `sync.toml`, e um valor declarado lá impediria para sempre que a escolha feita no desktop chegasse ao login. O `just check` barra isso.
- **Não há semente para o login.** O greeter só usa o `[appearance]` do `sync.toml` com a paleta completa (16 cores): semear só o wallpaper seria ignorado, e semear a paleta seria escolher um esquema. Até a primeira mudança de aparência na sessão, o login usa o tema embutido do greeter.

Um wallpaper pessoal é escolhido na conta, pela interface do Noctalia, e o sync o leva para login e bloqueio. Ele não entra no repositório.

## 26.2 O que falta

A personalização deverá abranger:

- Niri;
- Noctalia;
- GTK (hoje `adw-gtk3-theme`);
- Qt;
- terminal;
- Zsh;
- ícones (hoje `papirus-icon-theme`);
- cursores;
- wallpapers (hoje, o padrão gerado da seção 26.1);
- cores (base comum a Tokyo Night e Dracula; esquema final a escolher);
- tipografia;
- login;
- notificações;
- menus;
- status bar.

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

## 27.4 Ruído conhecido e aceito

Dezenas de `Failed to resolve group 'audio' / 'utmp' / 'tty'…` do `systemd-tmpfiles` no initramfs. Comparado com o Aurora instalado: acontece igual lá (167 ocorrências no boot atual). É comportamento do Fedora no initrd, não do Arkmos, e não vale divergir da base por isso.

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
- **A variante NVIDIA é construída e verificada, mas não publicada.** Ela compartilha a árvore `files/` inteira com a padrão, então o que pode quebrar só nela vem da base — a imagem sair do ar, mudar de nome, deixar de trazer um pacote. Construir a cada push custa tempo de runner, que em repositório público é gratuito. Publicar são ~5 GB por versão de uma imagem que ninguém usa hoje.
- **Sem `schedule` por enquanto.** O cron existe para acompanhar a reconstrução diária da base do Universal Blue — cujas tags, aliás, expiram em 4 semanas — e isso só protege uma imagem que está em uso. Entra quando a publicação virar rotina.
- **Assina com cosign** quando o secret `SIGNING_SECRET` existe.

### Por que o repositório é público

Não é só preferência: é o que torna este workflow viável. Em conta gratuita do GitHub, repositório privado tem **500 MB** de cota no GitHub Packages, e as imagens ocupam cerca de 4 GB (padrão) e 5 GB (NVIDIA) comprimidas — a primeira publicação estouraria a cota por uma ordem de grandeza. Repositório público tem Actions ilimitado e registry sem cota.

O projeto já era construído com essa hipótese: nada pessoal é declarado na imagem, e a conta nasce no primeiro boot (seção 12.4).

### Retenção

Cada publicação cria **uma** versão (um digest) carregando três tags: `44.AAAAMMDD.N`, `44` e `latest`. Sem limpeza, nada remove as anteriores e cada uma ocupa ~4 GB. Em repositório público isso não custa cota, mas uma listagem com centenas de versões deixa de ser navegável — e no dia em que o `schedule` for ligado, passa a crescer sozinha.

Dois passos, com critérios diferentes:

- **Versões sem tag são removidas todas.** Mover `44` e `latest` para a versão nova deixa a anterior sem nenhuma tag apontando para ela; não dá para referenciá-la por nome e ela não é alvo de rollback.
- **Cinco publicações de histórico são mantidas.** O rollback do dia a dia é local — `bootc rollback` usa o deployment anterior, que já está no disco e não depende do registry. As cinco servem para o outro caso: reinstalar do zero uma versão que se sabe boa, quando a mais recente não presta.

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

**O driver NVIDIA**, na variante correspondente: `nvidia-driver` e `kmod-nvidia` são "NVIDIA License", proprietária. A variante não é publicada hoje (`publishable: false` no CI), então a questão não se apresenta. Antes de publicá-la, avaliar — o Universal Blue publica `base-nvidia` abertamente, o que é um precedente, mas não foi verificado aqui.

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

# 29. Processo de Build

```bash
just build                  # localhost/arkmos:dev
just variant=nvidia build   # localhost/arkmos-nvidia:dev
just check-all              # constrói e verifica as duas
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

O `bootc container lint` roda como última camada do próprio `Containerfile`, então erros de `/var`, `/opt` e layout de kernel falham o build.

---

# 30. Teste com QEMU

```bash
just vm       # gera output/qcow2/disk.qcow2
just run-vm   # sobe a VM
```

O `just vm` usa o [bootc-image-builder](https://github.com/osbuild/bootc-image-builder), que substituiu o antigo `truncate` + `losetup` + `bootc install to-disk`: um comando só, particionamento declarativo e rotulagem SELinux correta. Ele pede a senha do sudo duas vezes — roda privilegiado e só enxerga o storage do root, enquanto `just build` constrói sem privilégio; o `podman image scp` transfere a imagem entre os dois storages sem reconstruir.

Para o Niri, a VM precisa de aceleração 3D, e mais duas coisas que a experiência impôs:

```text
-device virtio-vga-gl,xres=1920,yres=1080
-display gtk,gl=on,grab-on-hover=on
```

O padrão do `virtio-vga-gl` é 1280x800, e nessa janela o assistente do primeiro boot rola para fora da tela — foi o que fez a pausa final parecer travamento.

O `grab-on-hover` captura o teclado quando o ponteiro está sobre a janela. Sem ele, atalhos com Super/Mod são interpretados pelo compositor do **host** e nunca chegam na VM, o que torna impossível testar os binds do Niri. `Ctrl+Alt+G` libera e recaptura a qualquer momento.

UEFI via `pflash`, não `-bios`: o firmware precisa de uma cópia **gravável** das variáveis EFI para guardar a entrada de boot que o bootc instala. As variáveis são descartadas ao gerar um disco novo — reaproveitá-las faz o firmware tentar uma entrada que não existe mais, e o sintoma é a VM não dar boot, indistinguível de imagem quebrada.

Cada variante tem seu próprio diretório de saída (`output/`, `output-nvidia/`).

---

# 31. Instalação e Atualização

Instalação:

```bash
sudo podman run --rm --privileged --pid=host \
    -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
    --security-opt label=type:unconfined_t \
    ghcr.io/<owner>/arkmos:44 \
    bootc install to-disk --wipe /dev/sdX
```

Atualização:

```bash
sudo bootc upgrade
bootc status
sudo bootc rollback
```

O número da versão não é a rede de segurança — `bootc rollback` é.

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
├── Justfile                       build, verificação, VM
├── config.toml                    bootc-image-builder (a MÍDIA, não a imagem)
├── flatpaks.list                  aplicações gráficas declaradas
├── README.md                      uso
├── PROJECT.md                     arquitetura e decisões
├── .gitignore
│
├── .github/workflows/
│   └── build.yml                  build, verificação, publicação, assinatura
│
├── tests/
│   └── check-image.sh             verificações, compartilhadas com o CI
│
├── build_files/                   rodam no build e NÃO ficam na imagem
│   ├── install-upstream-bins.sh   starship, lazygit, lazydocker (sha256)
│   ├── install-nerd-font.sh       JetBrains Mono patched (sha256)
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
    │   ├── skel/                  defaults de VS Code e Noctalia
    │   ├── xdg-desktop-portal/niri-portals.conf
    │   ├── yum.repos.d/           docker-ce e vscode, enabled=0
    │   └── zshenv
    └── usr/
        ├── lib/
        │   ├── bootc/install/     filesystem raiz
        │   ├── bootc/kargs.d/     argumentos de kernel
        │   ├── systemd/system/    firstboot + drop-ins de greetd e nvidia
        │   ├── sysusers.d/        grupo docker
        │   └── tmpfiles.d/        conteúdo de /var
        ├── libexec/
        │   ├── arkmos-firstboot
        │   └── arkmos-greeter
        ├── share/arkmos/
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
- Nautilus como gerenciador de arquivos, na imagem (seção 25.1);
- correções: conta do greeter, ordenação do firstboot e ruído no console, hostname, `nvidia-cdi-refresh`, fallback de getty, cache do tuigreet, variáveis EFI da VM, prompt de senha do assistente, resolução e captura de teclado da VM;
- documentação: README e este documento.

---

# 35. Estado Atual

Versão:

```text
0.8.0
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
```

## 35.2 Validado em VM

```text
boot em UEFI/OVMF com Btrfs
assistente de firstboot completo: usuário, grupos wheel e docker, senha
/var/lib/arkmos/initialized gravado
login pelo tuigreet
sessão gráfica subindo depois do login
splash de boot do Arkmos em UEFI — boot só de kernel + initramfs, sem disco
```

## 35.3 Não validado ainda

```text
aparência corrigida (prefer-no-csd, tema escuro, tela de login) — a
  primeira VM foi testada antes dessas mudanças
Noctalia em uso
docker em uso real / Laravel Sail
bootc upgrade a partir do GHCR
rollback
instalação em hardware real
splash de boot numa instalação completa
wallpaper padrão e sync para a tela de login
Nautilus em uso: montagem, lixeira, "mostrar na pasta"
```

---

# 36. Próximos Passos

## Curto prazo

1. Testar a 0.8.0 em QEMU: assistente limpo, tuigreet, sessão Niri + Noctalia.
2. Confirmar teclado ABNT2 na sessão gráfica.
3. Confirmar portais, clipboard e notificações.
4. Commitar o trabalho da 0.7.0/0.8.0.
5. Primeiro build no CI e publicação no GHCR.
6. Fechar a assinatura (chave pública + `policy.json`).

## Médio prazo

7. Curar a `flatpaks.list` e criar o mecanismo que a aplica — incluindo a extensão de tema `org.gtk.Gtk3theme.adw-gtk3-dark`, sem a qual Flatpaks GTK3 não usam o tema do sistema (seção 26.1).
8. Definir a identidade visual (seção 26): escolher o esquema — Tokyo Night ou Dracula, os dois embutidos no Noctalia — e o wallpaper definitivo.
9. Configurar Noctalia: barra, dock, notificações, wallpaper, lock.
10. Avaliar o Noctalia Greeter, mantendo greetd/tuigreet como fallback.
11. Validar `bootc upgrade` e `bootc rollback` de ponta a ponta.
12. Declarar os containers Distrobox (`fedora-mobile`, `ubuntu-db`).

## Longo prazo

13. Snapper/Btrfs snapshots.
14. Avaliar Limine.
15. Validar instalação em hardware real.
16. Documentar recuperação.
17. Definir política de atualização/rollback.
18. Estabilizar a versão 1.0.0.

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
Btrfs                           snapshots e rollback de dados no futuro
Niri                            compositor
Noctalia                        shell do desktop
greetd + tuigreet               login, com fallback de texto
Docker CE real                  Laravel Sail (seção 15)
VS Code na imagem               terminal integrado precisa do docker do host;
                                redistribuição assumida conscientemente (seção 28.4)
Podman + Distrobox              containers e ambientes
PipeWire / NetworkManager       vêm da base
GTK como preferência visual
JetBrains Mono Nerd Font
Zsh + Starship                  configuração própria, plugins de RPM (seção 13)
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

**Arkmos 0.8.0 — em desenvolvimento**

Próximo marco:

```text
0.8.0 → validar a sessão gráfica em VM e publicar no GHCR
0.9.0 → aplicações declaradas e identidade visual
```
