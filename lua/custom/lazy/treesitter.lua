return {
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  build = ':TSUpdate',
  config = function()
    require('nvim-treesitter').setup()

    require('nvim-treesitter').install {
      'bash',
      'c',
      'diff',
      'lua',
      'cue',
      'luadoc',
      'markdown',
      'markdown_inline',
      'query',
      'vim',
      'vimdoc',
      'python',
      'xml',
      'javascript',
      'typescript',
      'json',
      'html',
      'css',
    }

    -- Auto-install parser when opening an unrecognised filetype
    vim.api.nvim_create_autocmd('FileType', {
      callback = function()
        local lang = vim.treesitter.language.get_lang(vim.bo.filetype)
        if lang then
          pcall(require('nvim-treesitter').install, { lang })
        end
      end,
    })

    -- Treesitter indent (skip filetypes where it is unreliable)
    local indent_disabled = { python = true, cpp = true, c = true }
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(args)
        if not indent_disabled[vim.bo[args.buf].filetype] then
          vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end,
    })

    -- Keep vim regex highlighting alongside treesitter for markdown
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'markdown',
      callback = function(args)
        vim.bo[args.buf].syntax = 'ON'
      end,
    })
  end,
}
