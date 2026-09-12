# Teclas.
#
# Modo emacs, que é o padrão do zsh. 'bindkey -v' para vi mode fica fora daqui
# de propósito: é escolha de quem usa, não do sistema — o lugar dela é o
# ~/.config/zsh/local.zsh.

bindkey -e

# Busca no histórico pelo que já está escrito na linha: digitar "git pu" e
# apertar ↑ passa só pelos comandos que começam assim, em vez de percorrer o
# histórico inteiro. São widgets que o próprio zsh traz.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search     # ↑
bindkey '^[[B' down-line-or-beginning-search   # ↓
bindkey '^P'   up-line-or-beginning-search     # Ctrl+P
bindkey '^N'   down-line-or-beginning-search   # Ctrl+N

bindkey '^[[1;5C' forward-word         # Ctrl+→
bindkey '^[[1;5D' backward-word        # Ctrl+←
bindkey '^[[H'    beginning-of-line    # Home
bindkey '^[[F'    end-of-line          # End
bindkey '^[[3~'   delete-char          # Delete
bindkey '^H'      backward-kill-word   # Ctrl+Backspace
bindkey '^[[Z'    reverse-menu-complete # Shift+Tab

# Ctrl+X Ctrl+E abre a linha atual no $EDITOR — útil para comando longo ou
# com várias linhas.
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line
