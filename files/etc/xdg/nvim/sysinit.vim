" Arkmos: padrões do Neovim. Lido sempre, antes do ~/.config/nvim da conta,
" que vence. Ver /usr/share/nvim/site/lua/arkmos.lua e PROJECT.md §9.1.
"
" O Neovim lê só o primeiro sysinit.vim que acha, e este esconderia o do
" pacote do Fedora: ele é carregado aqui antes.
if filereadable($VIM . "/sysinit.vim")
    source $VIM/sysinit.vim
endif
lua require("arkmos")
