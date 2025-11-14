return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  config = function()
    require('nvim-treesitter.configs').setup {
      ensure_installed = {
        'bash',
        'c',
        'diff',
        'lua',
        'luadoc',
        'markdown',
        'markdown_inline',
        'query',
        'vim',
        'vimdoc',
        'python',
      },
      sync_install = false,
      auto_install = true,
      indent = {
        enable = true,
        disable = { 'python', 'cpp', 'c' },
      },
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = { 'markdown' },
      },
    }
  end,
}
