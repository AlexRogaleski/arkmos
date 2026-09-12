# Arkmos — configuração do Zsh.
#
# Vive em /usr, read-only, e é igual para todo usuário: atualiza junto com a
# imagem. O ZDOTDIR que aponta para cá é definido em /etc/zshenv, que é o
# único lugar de onde isso é possível.
#
# Dois pontos de escape, em ordem de precedência:
#
#   1. ~/.config/zsh/.zshrc próprio — assume o controle total, e o
#      /etc/zshenv passa a apontar o ZDOTDIR para lá.
#   2. ~/.config/zsh/local.zsh — carregado por último por este arquivo, com
#      a última palavra sobre tudo o que vem abaixo.
#
# A ordem dos módulos importa: os plugins vêm no fim porque o
# syntax-highlighting embrulha os widgets já definidos e o autosuggestions se
# apoia no histórico já configurado.

# Diretório deste arquivo, sem hardcode: %x é o script em execução, :A
# resolve links e :h corta o nome do arquivo.
ARKMOS_ZSH="${${(%):-%x}:A:h}"

for _module in history completion keybindings aliases tools plugins; do
    [[ -r "$ARKMOS_ZSH/$_module.zsh" ]] && source "$ARKMOS_ZSH/$_module.zsh"
done
unset _module

_arkmos_local="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/local.zsh"
[[ -r "$_arkmos_local" ]] && source "$_arkmos_local"
unset _arkmos_local
