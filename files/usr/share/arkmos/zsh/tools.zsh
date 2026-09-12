# Integrações com as ferramentas da imagem.

# --- Ambiente --------------------------------------------------------------

# Atribuído direto, e não com ${EDITOR:-...}: o Fedora traz
# /etc/profile.d/nano-default-editor.sh, que define EDITOR=/usr/bin/nano, e o
# /etc/zshrc faz source dos profile.d ANTES desta configuração. Com ':-' o
# nano ganharia sempre, e o neovim que a imagem instala nunca seria usado.
#
# Quem preferir outro editor troca em ~/.config/zsh/local.zsh, carregado
# depois deste arquivo.
export EDITOR=nvim
export VISUAL="$EDITOR"
export PAGER=less

# -R preserva cor, -F sai se couber numa tela, -X não limpa a tela ao sair.
export LESS='-R -F -X'

# --- Prompt ----------------------------------------------------------------

if (( $+commands[starship] )); then
    # Um STARSHIP_CONFIG já definido no ambiente vence o da imagem.
    export STARSHIP_CONFIG="${STARSHIP_CONFIG:-/usr/share/arkmos/starship.toml}"
    eval "$(starship init zsh)"
fi

# --- Navegação -------------------------------------------------------------

# zoxide substitui o cd: continua aceitando caminho normal, e passa a aceitar
# pedaço do nome de um diretório visitado antes.
(( $+commands[zoxide] )) && eval "$(zoxide init --cmd cd zsh)"

# --- fzf -------------------------------------------------------------------

# Ctrl+R no histórico, Ctrl+T em arquivos, Alt+C em diretórios.
[[ -r /usr/share/fzf/shell/key-bindings.zsh ]] \
    && source /usr/share/fzf/shell/key-bindings.zsh

if (( $+commands[fd] )); then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi

export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'
