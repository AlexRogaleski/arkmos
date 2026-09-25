# Arkmos — configuração do Zsh.
#
# Vive em /usr, read-only, e é igual para todo usuário: atualiza junto com a
# imagem. Quem a carrega é o /etc/zshrc, numa linha que o Containerfile
# acrescenta ao do Fedora, e o zsh lê o /etc/zshrc ANTES do ~/.zshrc. Por isso
# o ~/.zshrc continua sendo da conta, lido por último, com a última palavra —
# e o que um instalador acrescentar lá (lerd, nvm, rustup) funciona como em
# qualquer outro sistema.
#
# Antes (até 2026-09-25) a configuração era apontada pelo ZDOTDIR, e o zsh
# ignorava o ~/.zshrc e o ~/.zprofile em silêncio. Ver PROJECT.md, seção 13.1.
#
# A ordem dos módulos importa: os plugins vêm no fim porque o
# syntax-highlighting embrulha os widgets já definidos e o autosuggestions se
# apoia no histórico já configurado.

# Diretório deste arquivo, sem hardcode: %x é o script em execução, :A
# resolve links e :h corta o nome do arquivo.
ARKMOS_ZSH="${${(%):-%x}:A:h}"

# /home é link para /var/home, e o kernel só guarda o caminho resolvido. A
# sessão herda PWD=/var/home/<usuário> de quem a sobe, e todo terminal aberto
# dela nascia fora do $HOME aos olhos do shell: o prompt mostrava o caminho
# inteiro no lugar do ~. Mesmo diretório, então basta trocar o prefixo.
if [[ $PWD != $HOME && $PWD != $HOME/* ]]; then
    _arkmos_home="${HOME:A}"
    if [[ $_arkmos_home != $HOME && ($PWD == $_arkmos_home || $PWD == $_arkmos_home/*) ]]; then
        builtin cd -q -- "$HOME${PWD#$_arkmos_home}"
    fi
    unset _arkmos_home
fi

for _module in history completion keybindings aliases tools plugins; do
    [[ -r "$ARKMOS_ZSH/$_module.zsh" ]] && source "$ARKMOS_ZSH/$_module.zsh"
done
unset _module
