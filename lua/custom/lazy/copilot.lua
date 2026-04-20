return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    config = function()
      require('copilot').setup {
        copilot_node_command = '/home/jason/.config/nvm/versions/node/v22.21.1/bin/node',
        suggestion = { enabled = false }, -- disable inline suggestions
        panel = { enabled = false }, -- disable side panel
        filetypes = {
          markdown = true,
          help = false,
          cpp = true,
          c = true,
          python = true,
          lua = true,
          js = true,
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
