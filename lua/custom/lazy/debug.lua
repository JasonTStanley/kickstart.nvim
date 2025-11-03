return {
  {
    'mfussenegger/nvim-dap',
    config = function()
      require('dap').set_log_level 'TRACE'
      vim.fn.sign_define('DapBreakpoint', { text = '🛑', texthl = '', linehl = '', numhl = '' })
      vim.g.dap_virtual_text = true

      local dap = require 'dap'

      dap.adapters.codelldb = {
        type = 'server',
        port = '${port}',
        executable = {
          command = vim.fn.stdpath 'data' .. '/mason/bin/codelldb',
          args = { '--port', '${port}' },
        },
      }
      dap.configurations.cpp = {
        {
          name = 'Launch file',
          type = 'codelldb',
          request = 'launch',
          program = function()
            -- check if a build folder exists, and if it does append it to the cwd
            local dir = vim.fn.getcwd()
            if vim.fn.isdirectory(dir .. '/build') == 1 then
              dir = dir .. '/build'
            end
            return vim.fn.input('Path to executable: ', dir .. '/', 'file')
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},
        },
      }
      dap.configurations.c = dap.configurations.cpp
    end,
  },
  {
    'jay-babu/mason-nvim-dap.nvim',
    dependencies = { 'williamboman/mason.nvim' },
    config = function()
      require('mason-nvim-dap').setup {
        ensure_installed = { 'codelldb' },
        automatic_installation = true,
      }
    end,
  },
  {
    'rcarriga/nvim-dap-ui',
    dependencies = { 'mfussenegger/nvim-dap', 'nvim-neotest/nvim-nio' },
    config = function()
      local dap, dapui = require 'dap', require 'dapui'
      dapui.setup()

      dap.listeners.before.attach.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.launch.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated.dapui_config = function()
        dapui.close()
      end
      dap.listeners.before.event_exited.dapui_config = function()
        dapui.close()
      end
    end,
  },
}
