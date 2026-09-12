# Atalhos.
#
# Cada bloco é guardado por '$+commands[...]': a configuração é a mesma nas
# duas variantes da imagem e precisa continuar carregando limpa se algum
# desses pacotes sair da lista.

# --- Listagem --------------------------------------------------------------

if (( $+commands[eza] )); then
    alias ls='eza --group-directories-first --icons=auto'
    alias ll='eza -l  --group-directories-first --icons=auto --git'
    alias la='eza -la --group-directories-first --icons=auto --git'
    alias lt='eza --tree --level=2 --icons=auto'
fi

# 'cat' NÃO é substituído de propósito: pipes e scripts contam com a saída
# exata dele. O bat fica disponível pelo próprio nome, e 'batp' para paginar.
(( $+commands[bat] )) && alias batp='bat --paging=always'

# --- Git -------------------------------------------------------------------

alias g='git'
alias gs='git status --short --branch'
alias ga='git add'
alias gc='git commit'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'
alias gp='git push'
alias gpl='git pull'
alias gco='git checkout'
alias gb='git branch'
(( $+commands[lazygit] )) && alias lg='lazygit'

# --- Containers ------------------------------------------------------------

alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
(( $+commands[lazydocker] )) && alias lzd='lazydocker'

# --- Laravel ---------------------------------------------------------------

# O alias da documentação oficial do Sail: usa o script da raiz do projeto se
# existir, e o de vendor/bin caso contrário.
alias sail='[ -f sail ] && sh sail || sh vendor/bin/sail'

# Artisan pelo Sail, porque o PHP roda no container e não na imagem.
alias art='sail artisan'

# --- Sistema ---------------------------------------------------------------

alias os-status='bootc status'
alias os-update='sudo bootc upgrade'
alias os-rollback='sudo bootc rollback'

# --- Geral -----------------------------------------------------------------

alias ..='cd ..'
alias ...='cd ../..'
alias mkdir='mkdir -p'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ip='ip -color=auto'
