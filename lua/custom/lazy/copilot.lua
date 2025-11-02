return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    config = function()
      require('copilot').setup {
        suggestion = { enabled = false }, -- disable inline suggestions
        panel = { enabled = false }, -- disable side panel
        filetypes = {
          markdown = true,
          help = false,
          cpp = true,
          c = true,
          python = true,
          lua = true,
        },
      }
    end,
  },

  {
    'jvune0/copilot-cmp',
    dependencies = { 'zbirenbaum/copilot.lua' },
    config = function()
      require('copilot_cmp').setup()
    end,
  },
}
