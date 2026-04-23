function _G.get_oil_winbar()
  local bufnr = vim.api.nvim_win_get_buf(vim.g.statusline_winid)
  local dir = require('oil').get_current_dir(bufnr)
  if dir then
    return vim.fn.fnamemodify(dir, ':~')
  else
    return vim.api.nvim_buf_get_name(0)
  end
end

return {
  'stevearc/oil.nvim',
  dependencies = { 'echasnovski/mini.nvim' },

  config = function()
    local oil = require 'oil'
    local detail = false

    local state = { oil_winid = nil, help_winid = nil, preview_winid = nil }

    local help_lines = {
      '  ─── Oil Keys ─────────────────────────────',
      '  <CR>  open / enter       <C-p>  preview',
      '  -     parent dir         gd     detail view',
      '  _     open cwd           g.     hidden files',
      '  o/O   add line→ create   gs     sort',
      '  dd    del line → delete  gx     open external',
      '  edit name → rename       g?     all keymaps',
      '  :w    apply changes       q     close',
    }

    local function close_help()
      if state.help_winid and vim.api.nvim_win_is_valid(state.help_winid) then
        if #vim.api.nvim_list_wins() > 1 then
          vim.api.nvim_win_close(state.help_winid, true)
        else
          vim.cmd 'quit'
        end
      end
      state.help_winid = nil
    end

    local function open_help(oil_winid)
      if state.help_winid and vim.api.nvim_win_is_valid(state.help_winid) then
        return
      end
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
      vim.bo[buf].modifiable = false

      vim.api.nvim_win_call(oil_winid, function()
        vim.cmd('belowright ' .. #help_lines .. 'split')
        state.help_winid = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(state.help_winid, buf)
        vim.wo[state.help_winid].number = false
        vim.wo[state.help_winid].relativenumber = false
        vim.wo[state.help_winid].signcolumn = 'no'
        vim.wo[state.help_winid].cursorline = false
        vim.wo[state.help_winid].statusline = ' '
        vim.wo[state.help_winid].winhl = 'Normal:NormalFloat,EndOfBuffer:NormalFloat'
      end)
    end

    -- Open preview and record the new window so <CR> can close it cleanly.
    local function open_preview_tracked()
      if not oil.get_cursor_entry() then return end
      local before = {}
      for _, w in ipairs(vim.api.nvim_list_wins()) do before[w] = true end
      oil.open_preview()
      vim.defer_fn(function()
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          if not before[w] and w ~= state.help_winid then
            state.preview_winid = w
            break
          end
        end
      end, 150)
    end

    oil.setup {
      default_file_explorer = true,
      columns = { 'icon' },
      keymaps = {
        ['<C-p>'] = 'actions.preview',
        ['<C-s>'] = false,
        ['<C-h>'] = false,
        ['q'] = 'actions.close',
        ['<CR>'] = {
          desc = 'Open file',
          callback = function()
            local entry = oil.get_cursor_entry()
            if not entry then return end
            -- Close the preview window before opening a file. Without this, oil
            -- promotes the preview window (which holds all previewed files in its
            -- jumplist) as the destination, causing <C-o> to land on previewed files.
            if entry.type ~= 'directory' then
              if state.preview_winid and vim.api.nvim_win_is_valid(state.preview_winid) then
                vim.api.nvim_win_close(state.preview_winid, true)
                state.preview_winid = nil
              end
            end
            oil.select()
          end,
        },
        ['gd'] = {
          desc = 'Toggle file detail view',
          callback = function()
            detail = not detail
            if detail then
              oil.set_columns { 'icon', 'permissions', 'size', 'mtime' }
            else
              oil.set_columns { 'icon' }
            end
          end,
        },
      },
      view_options = { show_hidden = true },
      watch_for_changes = true,
      preview_win = {
        update_on_cursor_moved = true,
        preview_method = 'fast_scratch',
      },
      keymaps_help = { border = 'rounded' },
      win_options = {
        winbar = '%!v:lua.get_oil_winbar()',
      },
    }

    local _oil_entering = false

    vim.api.nvim_create_autocmd('BufEnter', {
      pattern = 'oil://*',
      callback = function()
        if _oil_entering then return end
        _oil_entering = true

        local winid = vim.api.nvim_get_current_win()
        state.oil_winid = winid
        open_help(winid)

        vim.defer_fn(function()
          if vim.api.nvim_win_is_valid(winid) and oil.get_cursor_entry() then
            open_preview_tracked()
          end
          -- Reset only after oil.open_preview's internal focus-restore has fired,
          -- otherwise the restore triggers this callback again and loops.
          vim.defer_fn(function()
            _oil_entering = false
          end, 250)
        end, 100)
      end,
    })

    -- Close help when oil's buffer is replaced in-place by a real file (<CR>).
    -- WinClosed doesn't fire in this case since the window stays open.
    vim.api.nvim_create_autocmd('BufLeave', {
      pattern = 'oil://*',
      callback = function()
        vim.defer_fn(function()
          if state.oil_winid and vim.api.nvim_win_is_valid(state.oil_winid) then
            local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(state.oil_winid))
            if not name:match('^oil://') then
              close_help()
            end
          else
            close_help()
          end
        end, 50)
      end,
    })

    -- Close help when the oil or help window is physically closed (q, :q, etc.)
    vim.api.nvim_create_autocmd('WinClosed', {
      callback = function(ev)
        local closed = tonumber(ev.match)
        if closed == state.oil_winid then
          vim.defer_fn(close_help, 10)
          state.oil_winid = nil
        elseif closed == state.help_winid then
          state.help_winid = nil
        elseif closed == state.preview_winid then
          state.preview_winid = nil
        end
      end,
    })

    vim.keymap.set('n', '-', '<CMD>Oil<CR>', { desc = 'Open parent directory' })
    vim.api.nvim_create_user_command('Ex', function()
      oil.open()
    end, {})
  end,
}
