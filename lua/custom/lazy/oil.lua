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

    local open_external_exts = {
      pdf = true,
      png = true, jpg = true, jpeg = true, gif = true, webp = true, svg = true,
      mp4 = true, mov = true, mkv = true, avi = true,
      mp3 = true, flac = true, wav = true,
    }

    local help_lines = {
      '  ─── Oil Keys ───────────',
      '  <C-p>  toggle preview',
      '  gd     detail view',
      '  g.     hidden files',
      '  gs     sort',
      '  gx     open external',
      '  g?     all keymaps',
      '  q      close',
    }

    local function close_help()
      if state.help_winid and vim.api.nvim_win_is_valid(state.help_winid) then
        vim.api.nvim_win_close(state.help_winid, true)
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

      local float_w = 0
      for _, line in ipairs(help_lines) do
        float_w = math.max(float_w, vim.fn.strdisplaywidth(line))
      end
      local float_h = #help_lines
      local oil_h = vim.api.nvim_win_get_height(oil_winid)

      state.help_winid = vim.api.nvim_open_win(buf, false, {
        relative = 'win',
        win = oil_winid,
        anchor = 'NW',
        row = math.max(0, oil_h - float_h),
        col = 0,
        width = float_w,
        height = float_h,
        style = 'minimal',
        border = 'rounded',
        focusable = false,
        zindex = 50,
      })
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
        ['<C-p>'] = {
          desc = 'Toggle preview',
          callback = function()
            if state.preview_winid and vim.api.nvim_win_is_valid(state.preview_winid) then
              require('oil.actions').preview.callback()
              state.preview_winid = nil
            else
              open_preview_tracked()
            end
          end,
        },
        ['<C-s>'] = false,
        ['<C-h>'] = false,
        ['q'] = {
          desc = 'Close oil',
          callback = function()
            if state.preview_winid and vim.api.nvim_win_is_valid(state.preview_winid) then
              vim.api.nvim_win_close(state.preview_winid, true)
              state.preview_winid = nil
            end
            close_help()
            oil.close()
          end,
        },
        ['<CR>'] = {
          desc = 'Open file',
          callback = function()
            local entry = oil.get_cursor_entry()
            if not entry then return end
            if entry.type ~= 'directory' then
              local ext = entry.name:match('%.([^.]+)$')
              if ext and open_external_exts[ext:lower()] then
                require('oil.actions').open_external.callback()
                return
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
      view_options = { show_hidden = false },
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

    vim.api.nvim_create_autocmd('BufEnter', {
      pattern = 'oil://*',
      callback = function()
        local winid = vim.api.nvim_get_current_win()
        state.oil_winid = winid
        open_help(winid)
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
          state.oil_winid = nil
          if state.preview_winid and vim.api.nvim_win_is_valid(state.preview_winid) then
            vim.api.nvim_win_close(state.preview_winid, true)
            state.preview_winid = nil
          end
          vim.defer_fn(close_help, 10)
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
