return { -- Autoformat
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format { async = true, lsp_format = 'fallback' }
      end,
      mode = '',
      desc = '[F]ormat buffer',
    },
  },
  opts = {
    notify_on_error = false,
    format_on_save = function(bufnr)
      -- Disable "format_on_save lsp_fallback" for languages that don't
      -- have a well standardized coding style. You can add additional
      -- languages here or re-enable it for the disabled ones.
      --local disable_filetypes = { c = true, cpp = true }
      local disable_filetypes = {}
      if disable_filetypes[vim.bo[bufnr].filetype] then
        return nil
      else
        return {
          timeout_ms = 500,
          lsp_format = 'fallback',
        }
      end
    end,
    formatters_by_ft = {
      lua = { 'stylua' },
      c = { 'clang-format' },
      cpp = { 'clang-format' },
      python = { 'isort', 'black' },
      --cmake = { 'cmake-format' },
      xml = { 'xmlformat' },
      -- Conform can also run multiple formatters sequentially
      -- python = { "isort", "black" },
      --
      -- You can use 'stop_after_first' to run the first available formatter from the list
      -- javascript = { "prettierd", "prettier", stop_after_first = true },
    },
    formatters = {
      ['clang-format'] = {
        prepend_args = { '--style=Google' },
      },
    },
    linters_by_ft = {
      python = { 'ruff' },
      cmake = {
        function()
          return {
            exe = 'cmakelint',
            args = { '--quiet' },
            stdin = false,
          }
        end,
      },
      cpp = {
        function()
          return {
            exe = 'cpplint',
            args = { '--filter=-whitespace/line_length' },
            stdin = false,
          }
        end,
      },
    },
  },
}
