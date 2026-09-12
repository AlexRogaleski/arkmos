# Plugins.
#
# Vêm de RPM do Fedora, e não de git clone fixado em commit: o dnf cuida de
# atualização e de licença, e nada é baixado na primeira abertura do shell —
# o que numa imagem imutável significaria shell quebrado sem rede.
#
# Este módulo é o último carregado. O syntax-highlighting embrulha os widgets
# já definidos, então precisa ver keybindings.zsh pronto; o autosuggestions
# lê o histórico, então precisa ver history.zsh pronto.

# Variáveis antes do source: os dois plugins leem a configuração ao carregar.

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
[[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
    && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh

ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
[[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
    && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
