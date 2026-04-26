return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    config = function()
      require('copilot').setup {
        copilot_node_command = vim.fn.expand('~/.local/share/mise/installs/node/25.9.0/bin/node'),
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
