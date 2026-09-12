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

set -euo pipefail

STARSHIP_VERSION="1.26.0"
STARSHIP_SHA256="b7c232b0e8249d8e55a40beb79c5c43a7d370f3f9408bd215deb0170daeaadf3"

LAZYGIT_VERSION="0.65.0"
LAZYGIT_SHA256="44d8e7dd1484b4a66e191bd4ab25a71e8b4b3a65ab122f838e65677ef58c5506"

LAZYDOCKER_VERSION="0.25.2"
LAZYDOCKER_SHA256="0d9dbfc26068b218e7ed84b104748cadc6e3cf733c0afd35465306fb39b9523c"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() {
    local url="$1" dest="$2" want="$3" got
    echo "    ${url##*/}"
    curl -fsSL --retry 3 -o "$dest" "$url"
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

chmod 0755 /usr/bin/starship /usr/bin/lazygit /usr/bin/lazydocker

# Executar cada um fecha o que o checksum não cobre: um tarball da arquitetura
# errada extrai sem erro nenhum e só falha na máquina de quem instalou.
echo "==> verificando"
/usr/bin/starship --version   | head -1
/usr/bin/lazygit --version    | head -1
/usr/bin/lazydocker --version | head -1
