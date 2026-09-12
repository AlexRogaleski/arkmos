# Arkmos

Estação de trabalho Linux pessoal definida como imagem [Fedora bootc](https://docs.fedoraproject.org/en-US/bootc/): o sistema operacional inteiro descrito em código, construído como container e instalado a partir dele.

O objetivo não é publicar uma distribuição. É que a configuração da máquina seja o patrimônio, e não a instalação — o hardware pode mudar, a instalação pode ser destruída, a imagem pode ser reconstruída, e o Git guarda a definição.

> **Em desenvolvimento.** Testado em máquina virtual, ainda não validado em hardware real.
> Detalhes de arquitetura e decisões em [PROJECT.md](PROJECT.md).

---

## Construído sobre o Universal Blue

O Arkmos **não** constrói sua base do zero: ele parte das imagens do [Universal Blue](https://universal-blue.org), o projeto responsável por Bluefin, Aurora e Bazzite.

Isso não é um detalhe de implementação. A parte mais difícil de uma imagem Fedora bootc para desktop é a pilha de drivers — em especial os módulos NVIDIA compilados e **assinados**, sem os quais não há Secure Boot com driver proprietário. O Universal Blue mantém essa engrenagem (akmods, chaves, reconstrução diária acompanhando o kernel) e a entrega pronta. Reproduzir isso sozinho seria, de longe, o trecho mais caro do projeto.

O que vem deles:

| Origem | Uso no Arkmos |
| --- | --- |
| [`ghcr.io/ublue-os/base-main`](https://github.com/ublue-os/main) | imagem base da variante padrão |
| [`ghcr.io/ublue-os/base-nvidia`](https://github.com/ublue-os/main) | imagem base da variante NVIDIA, com akmods assinados |
| `ublue-os-akmods-addons`, `ublue-os-nvidia-addons` | integração dos módulos de kernel (MIT) |
| `ublue-os-signing`, `ublue-os-update-services`, `ublue-os-just`, `ublue-os-luks`, `ublue-os-udev-rules` | assinatura, atualização automática, regras de udev (Apache-2.0) |

Obrigado ao projeto e a quem o mantém. Se este repositório é pequeno, é porque a base não é.

---

## Variantes

Duas imagens do mesmo sistema. A única diferença é a imagem base — a árvore de configuração é uma só.

| | `arkmos` | `arkmos-nvidia` |
| --- | --- | --- |
| Base | `ghcr.io/ublue-os/base-main:44` | `ghcr.io/ublue-os/base-nvidia:44` |
| Pilha NVIDIA | não | driver assinado + container toolkit |
| Tamanho | ~8,8 GB | ~11,1 GB |
| Uso | padrão, e a que se testa em VM | máquinas com GPU NVIDIA em uso |

Trocar de variante numa máquina já instalada é `bootc switch` e um reboot — não uma reinstalação:

```bash
sudo bootc switch ghcr.io/alexrogaleski/arkmos-nvidia:44
sudo systemctl reboot
```

Vale saber: na variante padrão não há driver NVIDIA nenhum. Numa máquina cuja dGPU é ligada e desligada pela BIOS, ligá-la na BIOS sem trocar de variante não serve para nada.

---

## O que tem dentro

| Camada | Componentes |
| --- | --- |
| Base | Fedora 44 bootc, kernel 7.2, Btrfs, SELinux enforcing |
| Gráfico | [niri](https://github.com/niri-wm/niri) 26.04 (compositor scrollable-tiling), [Noctalia](https://github.com/noctalia-dev/noctalia) 5.0.1 (shell), xwayland-satellite |
| Login | [greetd](https://kl.wtf/projects/greetd) 0.10.3 + [tuigreet](https://github.com/apognu/tuigreet) 0.9.1 |
| Terminal | [foot](https://codeberg.org/dnkl/foot) 1.27.0, zsh 5.9 com configuração própria + starship, JetBrains Mono Nerd Font |
| Containers | Podman 5.8, Docker CE 29.8 (+ compose), Distrobox 1.8 |
| Desenvolvimento | VS Code 1.137, Git, Python, Neovim, lazygit, lazydocker, eza/bat/fd/fzf/ripgrep/zoxide |
| Sistema | PipeWire, NetworkManager, BlueZ, TuneD, Flatpak |
| Aparência | tema escuro padrão (GTK via dconf e portal), decoração pelo compositor, Papirus, cursor Adwaita |
| Localização | pt_BR.UTF-8, teclado ABNT2, `America/Sao_Paulo` |

**Docker CE, e não `podman-docker`.** O `podman-docker` é um shim que faz `docker` invocar o podman — e o [Laravel Sail](https://laravel.com/docs/sail), que é o fluxo de trabalho central desta máquina, é dirigido inteiramente por `docker compose`. Pelo mesmo motivo o VS Code está na imagem em vez de em Flatpak: sob o sandbox, o terminal integrado não enxerga o docker do host.

---

## Terminal

A configuração do Zsh é do Arkmos e vive em [`files/usr/share/arkmos/zsh/`](files/usr/share/arkmos/zsh/), versionada aqui — nada é clonado em tempo de build. Está dividida em módulos (`history`, `completion`, `keybindings`, `aliases`, `tools`, `plugins`) carregados nessa ordem pelo `.zshrc`.

Os plugins vêm de **RPM do Fedora** (`zsh-autosuggestions`, `zsh-syntax-highlighting`): o dnf cuida de atualização e de licença, e o shell não busca nada na primeira abertura — um plugin baixado sob demanda daria shell quebrado numa máquina recém-instalada e sem rede. Busca no histórico por prefixo sai de widgets que o próprio zsh traz, sem plugin.

Só o que o Fedora não empacota é baixado no build, com **versão e checksum SHA256 fixados** ([`build_files/`](build_files/)): starship, lazygit, lazydocker e a Nerd Font patched — o `jetbrains-mono-fonts` do Fedora não tem os glifos que o prompt e o `eza --icons` usam.

A configuração vive em `/usr`, read-only, igual para todo usuário. Dois pontos de escape:

- `~/.config/zsh/local.zsh` — carregado por último, com a última palavra.
- `~/.config/zsh/.zshrc` — assume o controle total; o `/etc/zshenv` passa a apontar o `ZDOTDIR` para lá.

O modo vi fica de fora por escolha: `bindkey -v` no seu `local.zsh` resolve, e essa é uma decisão de quem usa, não do sistema.

O terminal é o **foot**, configurado em [`files/etc/xdg/foot/foot.ini`](files/etc/xdg/foot/foot.ini): fonte Nerd Font, paleta escura e barra de título desligada. Quem desenha a decoração é o compositor, via `prefer-no-csd` no niri — sem isso cada aplicativo desenha a própria, e o foot usa a cor de foreground padrão, que é branca.

---

## Construir e testar

Requer `podman`, `just`, `qemu` e `edk2-ovmf`.

```bash
just                        # lista as tarefas
just build                  # constrói localhost/arkmos:dev
just check                  # roda as verificações sobre a imagem
just vm                     # gera output/qcow2/disk.qcow2
just run-vm                 # sobe a VM no QEMU com aceleração 3D

just variant=nvidia build   # o mesmo, para a variante NVIDIA
just check-all              # constrói e verifica as duas variantes
```

`just check` executa [`tests/check-image.sh`](tests/check-image.sh), exatamente o mesmo script que o CI roda. O critério para uma verificação entrar ali é ser **um erro que a imagem consegue esconder**: algo que constrói, passa no lint e só aparece como falha no boot da máquina. Por exemplo, a conta do greeter referenciada em `/etc/greetd/config.toml` precisa existir de fato na imagem — errar esse nome não produz erro de configuração, produz uma tela preta.

`just vm` pede a senha do sudo duas vezes: o [bootc-image-builder](https://github.com/osbuild/bootc-image-builder) roda privilegiado e só enxerga o storage do root, enquanto `just build` constrói sem privilégio.

Dentro da VM, o teclado é capturado quando o ponteiro está sobre a janela (`grab-on-hover`) — sem isso, atalhos com Super/Mod são interpretados pelo compositor do **host** e nunca chegam na máquina virtual. **`Ctrl+Alt+G`** libera e recaptura o teclado a qualquer momento.

---

## Instalar

O primeiro boot abre um assistente na console que cria a conta do usuário e define a senha. Só isso — locale, teclado e timezone já vêm declarados na imagem, e nada pessoal fica versionado aqui.

Do disco gerado por `just vm`, ou direto de uma imagem publicada:

```bash
sudo podman run --rm --privileged --pid=host \
    -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
    --security-opt label=type:unconfined_t \
    ghcr.io/alexrogaleski/arkmos:44 \
    bootc install to-disk --wipe /dev/sdX
```

## Atualizar

```bash
sudo bootc upgrade      # busca a imagem nova e a prepara para o próximo boot
bootc status            # o que está rodando e o que está preparado
sudo bootc rollback     # volta para o deployment anterior
```

O número de versão não é a rede de segurança — `bootc rollback` é. As imagens usam o esquema por data do Fedora e do Universal Blue (`44.AAAAMMDD.N`), mais as tags `44` e `latest`.

**Ainda não há imagem publicada.** O CI constrói e verifica as duas variantes a cada push, mas a publicação no GHCR fica atrás de um acionamento manual (`workflow_dispatch` com a caixa `publish` marcada) — enquanto não há máquina instalada para atualizar, publicar só encheria o registry. Até então, o caminho é `just vm` e instalar do disco gerado.

---

## Estrutura

```text
Containerfile              a imagem: base, pacotes, configuração
Justfile                   build, verificação, VM
config.toml                bootc-image-builder (descreve a MÍDIA, não a imagem)
flatpaks.list              aplicações gráficas declaradas
tests/check-image.sh       verificações, compartilhadas com o CI
build_files/               scripts que rodam no build e não ficam na imagem
files/                     árvore copiada para dentro da imagem
  etc/                     só o que precisa estar em /etc por design
  usr/lib/bootc/           filesystem raiz e argumentos de kernel
  usr/lib/systemd/system/  unit do firstboot e drop-ins
  usr/lib/tmpfiles.d/      conteúdo de /var, reconciliado a cada boot
  usr/libexec/             assistente do primeiro boot
  usr/share/arkmos/        configuração do zsh e do prompt
  etc/dconf/               tema escuro padrão para aplicativos GTK
  etc/skel/                defaults semeados no home ao criar a conta
.github/workflows/         build, verificação, publicação e assinatura
```

Duas regras que valem para tudo em `files/`:

- **Nada em `/usr/local` nem `/opt`.** Ambos são symlink para `/var` neste tipo de imagem, e o bootc só popula `/var` na primeira instalação — conteúdo colocado lá nunca mais seria atualizado por `bootc upgrade`.
- **Configuração em `/usr`, não em `/etc`.** `/etc` passa por merge de três vias e, uma vez modificado localmente, deixa de receber atualizações da imagem. O que está em `/etc` aqui está por exigência de quem lê o arquivo (`locale.conf`, `vconsole.conf`, `localtime`, `greetd`), não por conveniência.

---

## Assinatura das imagens

O CI assina a imagem publicada com [cosign](https://github.com/sigstore/cosign) quando os secrets existem, e a imagem passa a verificar a própria procedência quando a chave pública está nela. Sem isso, tudo funciona — apenas sem verificação.

```bash
cosign generate-key-pair
```

| Arquivo | Onde vai |
| --- | --- |
| `cosign.key` | secret `SIGNING_SECRET` do repositório — **nunca** versionar |
| a senha da chave | secret `COSIGN_PASSWORD` (se a chave tiver senha) |
| `cosign.pub` | `files/etc/pki/containers/arkmos.pub`, versionado |

A chave pública na imagem é o que liga as duas pontas: o build insere a entrada correspondente no `policy.json` que a base já traz, e a partir daí o `bootc upgrade` recusa uma imagem que não venha assinada pela chave correspondente. Enquanto o arquivo não existir, o build avisa e segue.

Verificação manual, a qualquer momento:

```bash
cosign verify --key cosign.pub ghcr.io/alexrogaleski/arkmos:44
```

## Créditos

Além do [Universal Blue](https://universal-blue.org), o Arkmos é quase inteiramente trabalho de outras pessoas:

- [Fedora Project](https://fedoraproject.org) — a distribuição e o modelo bootc
- [niri](https://github.com/niri-wm/niri) — compositor Wayland
- [Noctalia](https://github.com/noctalia-dev/noctalia) — shell do desktop
- [greetd](https://kl.wtf/projects/greetd) e [tuigreet](https://github.com/apognu/tuigreet) — login
- [foot](https://codeberg.org/dnkl/foot) — terminal
- [starship](https://starship.rs) — prompt
- [lazygit e lazydocker](https://github.com/jesseduffield) — interfaces de terminal para Git e Docker
- [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts) — JetBrains Mono patched

Cada componente mantém a licença do seu projeto de origem. O que este repositório acrescenta é a definição que os costura: `Containerfile`, `files/`, `build_files/`, `tests/` e o CI.
