<p align="center">
  <img src=".github/assets/logo.png" alt="arkmos" width="560">
</p>

Estação de trabalho Linux pessoal definida como imagem [Fedora bootc](https://docs.fedoraproject.org/en-US/bootc/): o sistema operacional inteiro descrito em código, construído como container e instalado a partir dele.

O objetivo não é publicar uma distribuição. É que a configuração da máquina seja o patrimônio, e não a instalação — o hardware pode mudar, a instalação pode ser destruída, e a imagem é reconstruída a partir do Git.

> **Em desenvolvimento.** As imagens são publicadas e assinadas no GHCR, com instalação, atualização e rollback validados em máquina virtual, e a variante padrão instalada pela ISO no hardware de destino em 2026-09-24.
> Arquitetura e o motivo de cada decisão: [PROJECT.md](PROJECT.md).

---

## O que tem dentro

| Camada | Componentes |
| --- | --- |
| Base | Fedora 44 bootc sobre o [Universal Blue](https://universal-blue.org), Btrfs, SELinux enforcing |
| Desktop | [niri](https://github.com/niri-wm/niri) (compositor), [Noctalia](https://github.com/noctalia-dev/noctalia) (shell), [Noctalia Greeter](https://github.com/noctalia-dev/noctalia-greeter) (login), Nautilus, Discos, gerenciador de compactação |
| Terminal | [foot](https://codeberg.org/dnkl/foot), zsh com configuração própria, [starship](https://starship.rs), JetBrains Mono Nerd Font, btop |
| Desenvolvimento | VS Code, Docker CE + compose, Podman, Distrobox, [mise](https://mise.jdx.dev), Git, GitHub CLI, Neovim, lazygit, lazydocker |
| Aplicativos | Flatpaks do Flathub, instalados sozinhos no primeiro boot e mantidos pela lista da imagem: Chrome, Thunderbird, OnlyOffice, Papers, Loupe, Showtime e outros |
| Sistema | PipeWire, NetworkManager, Tailscale, BlueZ, CUPS com assistente de impressão, TuneD, Flatpak |
| Localização | pt_BR.UTF-8, teclado ABNT2, `America/Sao_Paulo` |

Docker CE e VS Code estão **na imagem**, e não como `podman-docker` e Flatpak, por causa do [Laravel Sail](https://laravel.com/docs/sail): ele é dirigido inteiramente por `docker compose`, e no sandbox do Flatpak o terminal integrado não enxerga o docker do host.

## Variantes

Duas imagens do mesmo sistema; a única diferença é a imagem base.

| Imagem | Base | Para |
| --- | --- | --- |
| `ghcr.io/alexrogaleski/arkmos` | `ublue-os/base-main:44` | padrão |
| `ghcr.io/alexrogaleski/arkmos-nvidia` | `ublue-os/base-nvidia:44` | máquinas com GPU NVIDIA em uso — driver com módulos assinados |

Na variante padrão não há driver NVIDIA nenhum: numa máquina cuja dGPU é ligada pela BIOS, é preciso trocar de variante. Trocar é `bootc switch` e reboot, não reinstalação.

---

## Instalar

### Pela ISO, num pendrive

O caminho para máquina de verdade. A mídia instala a imagem **publicada** no GHCR, e não a local: é essa referência que a máquina passa a seguir nos `bootc upgrade`.

Requer `podman`, `just` e `7z` (`p7zip`), e uns 20 GB livres — o builder descomprime a imagem inteira antes de montar a mídia. A ISO final tem uns 4,5 GB.

```bash
just iso                    # gera output/bootiso/install.iso (pede sudo)
just variant=nvidia iso     # o mesmo, para a variante NVIDIA → output-nvidia/
```

A receita confere o kickstart dentro da ISO antes de terminar — assinatura exigida no `bootc switch`, raiz em Btrfs comprimido, a imagem certa — e para com erro se algo faltar.

Para ensaiar a instalação numa VM antes de ir ao hardware (requer também `qemu` e `edk2-ovmf`):

```bash
just run-iso                # instala num disco virtual novo, de 60G
just run-iso-instalado      # boots seguintes, sem a ISO
```

Para gravar no pendrive, confira o device com `lsblk` — tudo nele é apagado:

```bash
sudo dd if=output/bootiso/install.iso of=/dev/sdX bs=4M status=progress oflag=direct
```

O instalador abre em português e em ABNT2, e pede o disco, a rede e a conta. Ele **não apaga disco nenhum sozinho**: o destino é escolhido na tela. No fim, reinicia direto no sistema instalado.

### Num disco, direto da imagem

A partir da imagem publicada:

```bash
sudo podman run --rm --privileged --pid=host \
    -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
    --security-opt label=type:unconfined_t \
    ghcr.io/alexrogaleski/arkmos:44 \
    bootc install to-disk --wipe /dev/sdX
```

O primeiro boot abre um assistente que cria a conta e define a senha — só isso. Locale, teclado e timezone já vêm na imagem, e nada pessoal fica versionado aqui.

Ou por rebase, a partir de um Fedora Atomic já instalado (Silverblue, Kinoite, Aurora…), mantendo a conta e os arquivos:

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/alexrogaleski/arkmos:44
```

A flag faz toda atualização seguinte exigir a assinatura. A troca em si é verificada pela política do sistema de origem, que ainda não conhece a chave do Arkmos.

## Atualizar e voltar atrás

```bash
sudo bootc upgrade                                         # baixa a versão nova para o próximo boot
sudo bootc rollback                                        # volta para a deployment anterior
sudo bootc status                                          # o que roda e o que está preparado

sudo bootc switch --enforce-container-sigpolicy \
    ghcr.io/alexrogaleski/arkmos-nvidia:44                 # troca de variante
```

As imagens são assinadas com [cosign](https://github.com/sigstore/cosign), e o sistema **recusa** atualização que não venha com assinatura válida. As versões seguem o esquema por data do Fedora (`44.AAAAMMDD.N`), mais as tags `44` e `latest`.

---

## Desenvolver

Requer `podman`, `just`, `qemu` e `edk2-ovmf`.

```bash
just build                  # constrói localhost/arkmos:dev
just check                  # verificações — as mesmas que o CI roda
just vm                     # gera um disco para a VM (pede sudo)
just run-vm                 # sobe a VM; ssh na porta 2222 do host
just variant=nvidia build   # o mesmo, para a variante NVIDIA
```

`just check` existe para pegar o que a imagem consegue esconder: o que constrói, passa no lint e só falharia no boot da máquina. Estrutura do repositório, testes em VM e o processo de publicação estão no [PROJECT.md](PROJECT.md).

## Créditos

O Arkmos parte das imagens do [Universal Blue](https://universal-blue.org), o projeto por trás de Bluefin, Aurora e Bazzite. A parte mais difícil de uma imagem bootc para desktop — a pilha NVIDIA com módulos compilados e assinados, reconstruída a cada kernel — vem pronta de lá. Se este repositório é pequeno, é porque a base não é.

Além deles: [Fedora Project](https://fedoraproject.org), [niri](https://github.com/niri-wm/niri), [Noctalia](https://github.com/noctalia-dev/noctalia), [greetd](https://kl.wtf/projects/greetd), [foot](https://codeberg.org/dnkl/foot), [starship](https://starship.rs), [lazygit e lazydocker](https://github.com/jesseduffield), [mise](https://mise.jdx.dev) e [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts).

Cada componente mantém a licença do seu projeto.
