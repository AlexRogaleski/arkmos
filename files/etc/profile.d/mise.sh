# Arkmos — ativação do mise no bash.
#
# O zsh tem a dele em /usr/share/arkmos/zsh/tools.zsh. Esta é só para o bash,
# que o projeto não configura em nenhum outro lugar.
#
# As duas guardas têm motivo:
#
# - BASH_VERSION, porque este diretório não é exclusivo do bash: o /etc/zshrc
#   do Fedora também faz source de /etc/profile.d/*.sh. Sem a guarda, o zsh
#   avaliaria a ativação em dialeto de bash, com hook de PROMPT_COMMAND que
#   ele não usa — e ainda por cima antes da ativação correta, vinda do
#   tools.zsh.
#
# - shell interativo, porque 'mise activate' instala hook de prompt e mexe no
#   PATH. Fora de shell interativo — script, hook de editor, serviço do
#   systemd --user — o caminho são os shims em ~/.local/share/mise/shims.
#
# Sem 'return' de propósito: o zsh faz o source deste arquivo de dentro de uma
# função, e um return ali interromperia o laço, deixando os demais scripts de
# profile.d sem carregar.
#
# O /etc/bashrc do Fedora carrega este diretório tanto em shell de login como
# em interativo não-login, então este arquivo cobre os dois casos.
if [ -n "${BASH_VERSION:-}" ]; then
    case $- in
        *i*)
            command -v mise >/dev/null 2>&1 && eval "$(mise activate bash)"
            ;;
    esac
fi
