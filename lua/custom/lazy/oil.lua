-- Declare a global function to retrieve the current directory
function _G.get_oil_winbar()
  local bufnr = vim.api.nvim_win_get_buf(vim.g.statusline_winid)
  local dir = require('oil').get_current_dir(bufnr)
  if dir then
    return vim.fn.fnamemodify(dir, ':~')
  else
    -- If there is no current directory (e.g. over ssh), just show the buffer name
    return vim.api.nvim_buf_get_name(0)
  end
end

return {
  'stevearc/oil.nvim',
  dependencies = { 'echasnovski/mini.nvim' },

  config = function()
    local oil = require 'oil'
    local oil_actions = require 'oil.actions'
    oil.setup {
      default_file_explorer = true,
      columns = { 'icon' },
      keymaps = {
        ['<C-p>'] = 'actions.preview',
        ['<C-s>'] = false, -- disable default horizontal split open
        ['<C-h>'] = false, -- disable default horizontal split open
        ['q'] = 'actions.close',
        ['gd'] = {
          desc = 'Toggle file detail view',
          callback = function()
            detail = not detail
            if detail then
              require('oil').set_columns { 'icon', 'permissions', 'size', 'mtime' }
            else
              require('oil').set_columns { 'icon' }
            end
          end,
        },
      },

      view_options = {
        show_hidden = true,
      },
      float = {
        padding = 2,
        max_width = 80,
        max_height = 40,
      },
      watch_for_changes = true,
      preview = {
        max_width = 0.6,
        min_width = 40,
        max_height = 0.9,
      },
      preview_win = {
        update_on_cursor_moved = true,
        preview_method = 'fast_scratch',
      },
      keymaps_help = {
        border = 'rounded',
      },
      win_options = {
        winbar = '%!v:lua.get_oil_winbar()',
      },
    }

    vim.keymap.set('n', '-', '<CMD>Oil<CR>', { desc = 'Open parent directory' })
    vim.api.nvim_create_user_command('Ex', function()
      require('oil').open()
    end, {})
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'oil',
      callback = function(args)
        vim.api.nvim_create_autocmd('CursorMoved', {
          buffer = args.buf,
          once = true,
          callback = function()
            if oil.get_cursor_entry() then
              oil.open_preview()
            end
          end,
        })
      end,
    })
  end,
}
