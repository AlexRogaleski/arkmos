-- Arkmos: Neovim agradável para uso geral (PROJECT.md §9.1).
--
-- As opções valem sempre, e a configuração da conta, lida depois, as
-- sobrescreve. Plugins, atalhos e tema só entram quando a conta NÃO tem
-- ~/.config/nvim/init.lua (ou init.vim): uma configuração própria, como o
-- LazyVim, traz os dela, e os da imagem brigariam com eles.

local opt = vim.opt

opt.number = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.scrolloff = 8
opt.mouse = "a"
opt.clipboard = "unnamedplus" -- a área de transferência do sistema (wl-clipboard)
opt.undofile = true -- desfazer sobrevive a fechar o arquivo
opt.ignorecase = true
opt.smartcase = true
opt.confirm = true -- :q com alteração pergunta se salva, em vez de dar erro
opt.splitright = true
opt.splitbelow = true
opt.linebreak = true -- quebra longa de linha entre palavras
opt.breakindent = true
opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.updatetime = 250

local config = vim.fn.stdpath("config")
if vim.uv.fs_stat(config .. "/init.lua") or vim.uv.fs_stat(config .. "/init.vim") then
    return
end

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Mesmo esquema do terminal (foot) e do resto do sistema.
vim.cmd.packadd("tokyonight.nvim")
require("tokyonight").setup({ style = "night" })
vim.cmd.colorscheme("tokyonight-night")

vim.cmd.packadd("mini.nvim")
require("mini.icons").setup()
MiniIcons.mock_nvim_web_devicons()
require("mini.statusline").setup()
require("mini.files").setup()
require("mini.pick").setup()
require("mini.extra").setup()
require("mini.completion").setup()
require("mini.pairs").setup()

-- Um painel com as teclas possíveis aparece logo depois de <leader>, g, z, [,
-- ], aspas e Ctrl+W: é o que torna os atalhos descobríveis.
local clue = require("mini.clue")
clue.setup({
    triggers = {
        { mode = "n", keys = "<Leader>" },
        { mode = "x", keys = "<Leader>" },
        { mode = "n", keys = "g" },
        { mode = "x", keys = "g" },
        { mode = "n", keys = "z" },
        { mode = "x", keys = "z" },
        { mode = "n", keys = "[" },
        { mode = "n", keys = "]" },
        { mode = "n", keys = "'" },
        { mode = "n", keys = "`" },
        { mode = "n", keys = '"' },
        { mode = "x", keys = '"' },
        { mode = "i", keys = "<C-r>" },
        { mode = "c", keys = "<C-r>" },
        { mode = "n", keys = "<C-w>" },
    },
    clues = {
        clue.gen_clues.builtin_completion(),
        clue.gen_clues.g(),
        clue.gen_clues.marks(),
        clue.gen_clues.registers(),
        clue.gen_clues.windows(),
        clue.gen_clues.z(),
    },
    window = { delay = 300 },
})

local map = vim.keymap.set
map({ "n", "i", "x" }, "<C-s>", "<Cmd>write<CR><Esc>", { desc = "Salvar" })
map("n", "<Leader>w", "<Cmd>write<CR>", { desc = "Salvar" })
map("n", "<Leader>q", "<Cmd>quit<CR>", { desc = "Fechar" })
map("n", "<Leader>e", function()
    -- Arquivo novo ainda não existe no disco: abre na pasta atual.
    local nome = vim.api.nvim_buf_get_name(0)
    MiniFiles.open(vim.uv.fs_stat(nome) and nome or nil)
end, { desc = "Explorar arquivos" })
map("n", "<Leader>f", "<Cmd>Pick files<CR>", { desc = "Buscar arquivo" })
map("n", "<Leader>/", "<Cmd>Pick grep_live<CR>", { desc = "Buscar texto" })
map("n", "<Leader>b", "<Cmd>Pick buffers<CR>", { desc = "Arquivos abertos" })
map("n", "<Leader>r", "<Cmd>Pick oldfiles<CR>", { desc = "Recentes" })
map("n", "<Leader>h", "<Cmd>Pick help<CR>", { desc = "Ajuda" })
map("n", "<Esc>", "<Cmd>nohlsearch<CR>", { desc = "Limpar destaque da busca" })
