#!/usr/bin/env bash
#
# Instala em /usr/bin os binários que o Fedora 44 não empacota.
#
# Cada entrada fixa versão E checksum. Baixar de release upstream direto para
# /usr/bin sem verificar o conteúdo seria confiar em qualquer coisa que
# estivesse naquela URL no momento do build — inclusive numa conta de release
# comprometida.
#
# Para atualizar: trocar a versão e o sha256 correspondente. Os checksums
# oficiais estão publicados junto de cada release:
#
#   starship     <tag>/starship-x86_64-unknown-linux-musl.tar.gz.sha256
#   lazygit      <tag>/checksums.txt
#   lazydocker   <tag>/checksums.txt
#   mise         <tag>/SHASUMS256.txt

set -euo pipefail

STARSHIP_VERSION="1.26.0"
STARSHIP_SHA256="b7c232b0e8249d8e55a40beb79c5c43a7d370f3f9408bd215deb0170daeaadf3"

LAZYGIT_VERSION="0.65.0"
LAZYGIT_SHA256="44d8e7dd1484b4a66e191bd4ab25a71e8b4b3a65ab122f838e65677ef58c5506"

LAZYDOCKER_VERSION="0.25.2"
LAZYDOCKER_SHA256="0d9dbfc26068b218e7ed84b104748cadc6e3cf733c0afd35465306fb39b9523c"

MISE_VERSION="2026.9.10"
MISE_SHA256="cf6c0d4713932cf47da67f4f753348bc1ccf9a22d4d1e3c76d3c23a6187a853c"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() {
    local url="$1" dest="$2" want="$3" got
    echo "    ${url##*/}"
    # Espera de 10s entre tentativas, e não o backoff de 1s do curl: uma
    # indisponibilidade de release do GitHub dura mais que os 8 segundos que
    # três tentativas somam (ver install-nerd-font.sh).
    curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors \
        --connect-timeout 20 -o "$dest" "$url"
    got="$(sha256sum "$dest" | cut -d' ' -f1)"
    if [[ "$got" != "$want" ]]; then
        echo "ERRO: checksum de ${url##*/} não confere." >&2
        echo "  esperado: $want" >&2
        echo "  obtido:   $got" >&2
        echo "Se a versão foi atualizada de propósito, atualize o sha256." >&2
        exit 1
    fi
}

echo "==> starship ${STARSHIP_VERSION}"
fetch "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-x86_64-unknown-linux-musl.tar.gz" \
      "$WORK/starship.tar.gz" "$STARSHIP_SHA256"
tar -xzf "$WORK/starship.tar.gz" -C /usr/bin starship

# Atenção à capitalização: o lazygit publica 'linux' e o lazydocker 'Linux' na
# mesma posição do nome do arquivo. Trocar um pelo outro dá 404 no build.
echo "==> lazygit ${LAZYGIT_VERSION}"
fetch "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_x86_64.tar.gz" \
      "$WORK/lazygit.tar.gz" "$LAZYGIT_SHA256"
tar -xzf "$WORK/lazygit.tar.gz" -C /usr/bin lazygit

echo "==> lazydocker ${LAZYDOCKER_VERSION}"
fetch "https://github.com/jesseduffield/lazydocker/releases/download/v${LAZYDOCKER_VERSION}/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz" \
      "$WORK/lazydocker.tar.gz" "$LAZYDOCKER_SHA256"
tar -xzf "$WORK/lazydocker.tar.gz" -C /usr/bin lazydocker

# mise — gerenciador de versões de linguagens (Go, Node, Python, Ruby...).
#
# Entra na imagem porque é ferramenta de sistema; as versões de linguagem que
# ele instala ficam no $HOME, por projeto. É essa divisão que evita ter de
# reconstruir a imagem para trocar a versão de uma toolchain — e que dispensa
# container para desenvolver numa linguagem que o Fedora não empacota na
# versão desejada.
#
# Artefato gnu, e não musl: o instalador oficial do mise só escolhe o musl
# quando a libc do próprio sistema é musl — ele decide testando
# 'ldd /bin/ls | grep musl'. Numa Fedora, o caminho testado upstream é este.
#
# Único dos quatro tarballs que não traz o binário na raiz: o conteúdo vem
# todo sob 'mise/', daí o --strip-components. E o alvo é o arquivo exato, não
# 'mise/bin': o diretório carrega junto um 'mise.d' de 359 KiB que é o arquivo
# de dependências do build em Rust vazado no release, cheio de caminhos de
# /home/runner e sem uso nenhum aqui.
#
# ~127 MiB instalados, de longe o maior binário da imagem — o mise embute o
# registro de ferramentas que consulta. É o custo de não precisar de container
# para toolchain nenhuma.
echo "==> mise ${MISE_VERSION}"
fetch "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-x64.tar.gz" \
      "$WORK/mise.tar.gz" "$MISE_SHA256"
tar -xzf "$WORK/mise.tar.gz" -C /usr/bin --strip-components=2 mise/bin/mise

chmod 0755 /usr/bin/starship /usr/bin/lazygit /usr/bin/lazydocker /usr/bin/mise

# Executar cada um fecha o que o checksum não cobre: um tarball da arquitetura
# errada extrai sem erro nenhum e só falha na máquina de quem instalou.
echo "==> verificando"
/usr/bin/starship --version   | head -1
/usr/bin/lazygit --version    | head -1
/usr/bin/lazydocker --version | head -1
/usr/bin/mise --version       | head -1
