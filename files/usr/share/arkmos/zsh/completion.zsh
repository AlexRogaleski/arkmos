# Completion.

fpath=(/usr/share/zsh/site-functions $fpath)

autoload -Uz compinit

# O cache vai para o cache do usuário: em /usr ele não poderia ser escrito, e
# um compdump que não grava faz o zsh refazer todo o trabalho a cada abertura.
_arkmos_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-${ZSH_VERSION}"

# Mesmo cuidado com $HOME explicado em history.zsh.
if [[ -d "$HOME" && ! -d "${_arkmos_zcompdump:h}" ]]; then
    mkdir -p "${_arkmos_zcompdump:h}"
fi

# -C pula a verificação de permissão dos diretórios do fpath, que é o passo
# mais lento da inicialização. Aqui o fpath vem todo de /usr, entregue pela
# imagem e read-only — não há o que verificar.
compinit -C -d "$_arkmos_zcompdump"
unset _arkmos_zcompdump

zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{cyan}%d%f'
zstyle ':completion:*:warnings' format '%F{red}sem correspondência%f'

# Case-insensitive, e aceita completar no meio da palavra: 'ca-sen' encontra
# 'case-sensitive'.
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'

zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"

setopt AUTO_MENU             # Tab de novo abre o menu de opções
setopt COMPLETE_IN_WORD      # completa com o cursor no meio da palavra
setopt ALWAYS_TO_END         # ao completar, cursor vai para o fim
setopt AUTO_CD               # um caminho sozinho na linha equivale a cd
setopt AUTO_PUSHD            # cd empilha, então 'cd -' tem histórico
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt INTERACTIVE_COMMENTS  # '#' vale como comentário na linha de comando
unsetopt FLOW_CONTROL        # libera Ctrl+S e Ctrl+Q para outros usos
