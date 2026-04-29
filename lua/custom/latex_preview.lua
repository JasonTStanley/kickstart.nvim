local M = {}

local tmp_dir = vim.fn.stdpath 'cache' .. '/tex_preview'
vim.fn.mkdir(tmp_dir, 'p')
local tmp_tex = tmp_dir .. '/preview.tex'

-- Read pixel dimensions from a PNG file's IHDR chunk (bytes 16-23).
local function png_dimensions(path)
  local f = io.open(path, 'rb')
  if not f then
    return nil, nil
  end
  f:seek('set', 16)
  local data = f:read(8)
  f:close()
  if not data or #data < 8 then
    return nil, nil
  end
  local b = { data:byte(1, 8) }
  local w = b[1] * 16777216 + b[2] * 65536 + b[3] * 256 + b[4]
  local h = b[5] * 16777216 + b[6] * 65536 + b[7] * 256 + b[8]
  return w, h
end

local function new_state()
  return {
    current_image = nil,
    panel_win = nil,
    panel_buf = nil,
    last_content = nil,
    render_generation = 0,
    render_job = nil,
    auto_enabled = false,
  }
end

local function find_root_file(bufnr)
  local vimtex = vim.b[bufnr] and vim.b[bufnr].vimtex
  if vimtex and type(vimtex) == 'table' and vimtex.tex and vimtex.tex ~= '' then
    return vimtex.tex
  end
  return vim.api.nvim_buf_get_name(bufnr)
end

-- Extract everything before \begin{document} from the root file, replacing
-- \documentclass with standalone and absolutifying \input{} paths so they
-- resolve correctly when compiled from tmp_dir.
local function extract_preamble_from_file(root_file)
  local root_dir = vim.fn.fnamemodify(root_file, ':h')
  local f = io.open(root_file, 'r')
  if not f then
    return nil
  end
  local lines = {}
  local found_class = false
  for line in f:lines() do
    if line:match '\\begin{document}' then
      break
    end
    if line:match '^%s*\\documentclass' then
      lines[#lines + 1] = '\\documentclass[preview,border=3pt]{standalone}'
      -- Load amsmath immediately so \DeclareMathOperator exists when we patch it,
      -- then redefine it to silently skip if the command is already defined.
      lines[#lines + 1] = '\\RequirePackage{amsmath}'
      lines[#lines + 1] = '\\makeatletter'
      lines[#lines + 1] = '\\let\\@lp@dmo\\DeclareMathOperator'
      lines[#lines + 1] = '\\def\\DeclareMathOperator{\\@ifstar\\@lp@dmoS\\@lp@dmoN}'
      lines[#lines + 1] = '\\def\\@lp@dmoN#1#2{\\@ifundefined{\\expandafter\\@gobble\\string#1}{\\@lp@dmo{#1}{#2}}{}}'
      lines[#lines + 1] = '\\def\\@lp@dmoS#1#2{\\@ifundefined{\\expandafter\\@gobble\\string#1}{\\@lp@dmo*{#1}{#2}}{}}'
      lines[#lines + 1] = '\\makeatother'
      found_class = true
    else
      line = line:gsub('\\input{([^}]+)}', function(path)
        if path:sub(1, 1) ~= '/' then
          path = root_dir .. '/' .. path
        end
        return '\\input{' .. path .. '}'
      end)
      lines[#lines + 1] = line
    end
  end
  f:close()
  return found_class and table.concat(lines, '\n') or nil
end

-- Uses the root file's preamble when available so custom commands (\sys, \bfx,
-- etc.) are defined. Falls back to lightweight standalone if the root can't be
-- read. sym.tex is appended as a user override layer in either case.
local function build_preamble(bufnr)
  local root = find_root_file(bufnr)
  local preamble = root and extract_preamble_from_file(root)
  if preamble then
    return preamble
  end
  -- Fallback: lightweight standalone + sym.tex user macros.
  local macro_block = ''
  local sf = io.open(vim.fn.expand '~/.config/tex/sym.tex', 'r')
  if sf then
    macro_block = sf:read '*a'
    sf:close()
  end
  return table.concat({
    '\\documentclass[preview,border=3pt]{standalone}',
    '\\usepackage{xcolor}',
    '\\usepackage{amsmath,amssymb,amsfonts}',
    '\\usepackage{graphicx}',
    macro_block,
  }, '\n')
end

local function build_tex(content, bufnr)
  content = content:gsub('\\label{[^}]*}', '')
  local tex_src = table.concat({
    build_preamble(bufnr),
    '\\begin{document}',
    '\\pagecolor[HTML]{1e1e2e}',
    '{\\color{white}',
    content,
    '}',
    '\\end{document}',
  }, '\n')
  local wf = io.open(tmp_tex, 'w')
  if not wf then
    return false
  end
  wf:write(tex_src)
  wf:close()
  return true
end

local render_async -- forward declaration (defined after refresh_image)

-- Core block-extraction logic operating on a raw lines table (1-indexed).
-- Returns content of the outermost \begin{}\end{} containing lnum, or the
-- line itself as a fallback. Returns nil for blank lines.
local function get_outermost_block_from_lines(lines, lnum)
  local total = #lines

  local skip_stack = {}
  local candidates = {}

  for i = lnum, 1, -1 do
    local line = lines[i]

    local end_env = line:match '\\end{([^}]+)}'
    if end_env then
      table.insert(skip_stack, end_env)
    end

    local begin_env = line:match '\\begin{([^}]+)}'
    if begin_env then
      if #skip_stack > 0 and skip_stack[#skip_stack] == begin_env then
        table.remove(skip_stack)
      elseif begin_env ~= 'document' then
        table.insert(candidates, { env = begin_env, lnum = i })
      end
    end
  end

  if #candidates == 0 then
    local line_content = vim.trim(lines[lnum])
    return line_content ~= '' and line_content or nil
  end

  local outermost = candidates[#candidates]
  local outer_env = outermost.env
  local outer_start = outermost.lnum
  local depth = 1
  local outer_end = nil
  local pat_begin = '\\begin{' .. vim.pesc(outer_env) .. '}'
  local pat_end = '\\end{' .. vim.pesc(outer_env) .. '}'

  for i = outer_start + 1, total do
    local line = lines[i]
    if line:match(pat_begin) then
      depth = depth + 1
    end
    if line:match(pat_end) then
      depth = depth - 1
      if depth == 0 then
        outer_end = i
        break
      end
    end
  end

  if not outer_end then
    local line_content = vim.trim(lines[lnum])
    return line_content ~= '' and line_content or nil
  end

  local block_lines = {}
  for i = outer_start, outer_end do
    block_lines[#block_lines + 1] = lines[i]
  end
  local content = table.concat(block_lines, '\n'):gsub('\\label{[^}]*}', '')
  return vim.trim(content)
end

local function get_outermost_block(bufnr)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return get_outermost_block_from_lines(lines, lnum)
end

-- Returns the label argument if the cursor sits inside a \ref/\eqref/\cref{}
-- call on the current line, nil otherwise.
local ref_preview_cmds = { ref = true, eqref = true, cref = true, Cref = true, autoref = true }

local function get_ref_label_at_cursor()
  local line = vim.fn.getline '.'
  local col = vim.fn.col '.'
  local s = 1
  while s <= #line do
    local cs, ce, cmd, label = line:find('\\([%a@]+)%{([^}]*)%}', s)
    if not cs then
      break
    end
    if ref_preview_cmds[cmd] and col >= cs and col <= ce then
      return label
    end
    s = ce + 1
  end
  return nil
end

-- Finds \label{label} in the current buffer or project and renders its block.
local function preview_label_async(state, label, bufnr)
  local pattern = '\\label{' .. label .. '}'

  -- Search current buffer first.
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:find(pattern, 1, true) then
      local content = get_outermost_block_from_lines(lines, i)
      if content and content ~= '' then
        render_async(state, content, bufnr)
      end
      return
    end
  end

  -- Fall back to ripgrep across the project.
  local file_dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':h')
  local git_root = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(file_dir) .. ' rev-parse --show-toplevel')[1]
  local dir = (git_root and git_root ~= '') and git_root or file_dir
  vim.fn.jobstart({ 'rg', '-F', '--with-filename', '--line-number', '--no-heading', pattern, '--glob', '*.tex', dir }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      vim.schedule(function()
        for _, result in ipairs(data) do
          local file, lnum_str = result:match '^(.+):(%d+):'
          if file and lnum_str then
            local f = io.open(file, 'r')
            if f then
              local file_lines = {}
              for fl in f:lines() do
                file_lines[#file_lines + 1] = fl
              end
              f:close()
              local content = get_outermost_block_from_lines(file_lines, tonumber(lnum_str))
              if content and content ~= '' then
                render_async(state, content, bufnr)
              end
            end
            return
          end
        end
        vim.notify('LaTeX preview: label not found: ' .. label, vim.log.levels.WARN)
      end)
    end,
  })
end

local function get_panel_dims(height)
  local width = vim.o.columns - 2
  local row = vim.o.lines - vim.o.cmdheight - 1
  local col = 0
  return width, height, row, col
end

local function ensure_panel(state, height)
  height = math.max(height or 15, 4)
  local width, h, row, col = get_panel_dims(height)
  if state.panel_win and vim.api.nvim_win_is_valid(state.panel_win) then
    vim.api.nvim_win_set_config(state.panel_win, {
      relative = 'editor',
      anchor = 'SW',
      row = row,
      col = col,
      width = width,
      height = h,
    })
    return state.panel_win, state.panel_buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    anchor = 'SW',
    row = row,
    col = col,
    width = width,
    height = h,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
    zindex = 50,
  })
  vim.wo[win].winhighlight = 'Normal:NormalFloat'
  state.panel_win = win
  state.panel_buf = buf
  return win, buf
end

local function close_panel(state)
  state.render_generation = state.render_generation + 1
  if state.render_job then
    pcall(vim.fn.jobstop, state.render_job)
    state.render_job = nil
  end
  if state.current_image then
    pcall(function()
      state.current_image:clear()
    end)
    state.current_image = nil
  end
  if state.panel_win and vim.api.nvim_win_is_valid(state.panel_win) then
    pcall(vim.api.nvim_win_close, state.panel_win, true)
  end
  if state.panel_buf and vim.api.nvim_buf_is_valid(state.panel_buf) then
    pcall(vim.api.nvim_buf_delete, state.panel_buf, { force = true })
  end
  state.panel_win = nil
  state.panel_buf = nil
  state.last_content = nil
end

local function refresh_image(state, png_path)
  local ok, image_api = pcall(require, 'image')
  if not ok then
    vim.notify('LaTeX preview: image.nvim not loaded', vim.log.levels.WARN)
    return
  end

  -- Compute panel height from PNG aspect ratio.
  -- Use the image's natural cell width (px_w / ~8px per cell) rather than the
  -- full panel width, so narrow equations don't produce an oversized panel.
  local panel_height = 10
  local px_w, px_h = png_dimensions(png_path)
  if px_w and px_h and px_w > 0 then
    local max_h = math.min(20, math.floor(vim.o.lines - vim.o.cmdheight - 3))
    local cell_w = vim.o.columns - 4
    local nat_w = math.ceil(px_w / 8) -- natural width in cells (≈8 px/cell)
    local eff_w = math.min(cell_w, nat_w)
    panel_height = math.max(4, math.min(max_h, math.ceil(eff_w * px_h / px_w / 2)))
  end

  if state.current_image then
    pcall(function()
      state.current_image:clear()
    end)
    state.current_image = nil
  end
  local win, buf = ensure_panel(state, panel_height)
  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)
  vim.defer_fn(function()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
    local img = image_api.from_file(png_path, {
      window = win,
      buffer = buf,
      with_virtual_padding = false,
      inline = true,
    })
    if img then
      img:render { width = width, height = height, x = 0, y = 0 }
      state.current_image = img
    end
  end, 80)
end

render_async = function(state, content, bufnr)
  state.render_generation = state.render_generation + 1
  local my_gen = state.render_generation

  if state.render_job then
    pcall(vim.fn.jobstop, state.render_job)
    state.render_job = nil
  end

  if not build_tex(content, bufnr) then
    vim.notify('LaTeX preview: failed to write .tex file', vim.log.levels.ERROR)
    return
  end

  local png_base = 'preview_' .. my_gen
  local png_path = tmp_dir .. '/' .. png_base .. '.png'

  state.render_job = vim.fn.jobstart({
    'sh',
    '-c',
    string.format(
      'cd %s && pdflatex -interaction=nonstopmode -halt-on-error preview.tex > /dev/null' .. ' && pdftoppm -r 400 -png -singlefile preview.pdf %s',
      vim.fn.shellescape(tmp_dir),
      png_base
    ),
  }, {
    on_exit = function(_, code)
      state.render_job = nil
      vim.schedule(function()
        if my_gen ~= state.render_generation then
          return
        end
        if code == 0 then
          state.last_content = content
          refresh_image(state, png_path)
        else
          -- pdflatex writes errors to its .log file, not stderr.
          -- Extract lines starting with ! (errors) and l. (line refs).
          local errors = {}
          local log = io.open(tmp_dir .. '/preview.log', 'r')
          if log then
            for line in log:lines() do
              if line:match '^!' or line:match '^l%.' then
                table.insert(errors, line)
              end
            end
            log:close()
          end
          local msg = #errors > 0 and table.concat(errors, '\n') or ('pdflatex exited with code ' .. code)
          vim.notify('LaTeX preview failed:\n' .. msg, vim.log.levels.WARN)
        end
      end)
    end,
  })
end

function M.attach(bufnr)
  local state = new_state()
  local aug = vim.api.nvim_create_augroup('LatexPreview_buf' .. bufnr, { clear = true })

  -- Auto-render on CursorHold when enabled.
  vim.api.nvim_create_autocmd('CursorHold', {
    buffer = bufnr,
    group = aug,
    callback = function()
      if not state.auto_enabled then
        return
      end
      -- If cursor is on a \ref/\eqref, preview the referenced equation.
      local ref_label = get_ref_label_at_cursor()
      if ref_label then
        if ref_label ~= state.last_content then
          state.last_content = ref_label
          preview_label_async(state, ref_label, bufnr)
        end
        return
      end
      local content = get_outermost_block(bufnr)
      if not content or content == '' then
        return
      end
      if content == state.last_content and state.panel_win and vim.api.nvim_win_is_valid(state.panel_win) then
        return
      end
      render_async(state, content, bufnr)
    end,
  })

  -- Close panel when leaving the buffer.
  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = bufnr,
    group = aug,
    callback = function()
      close_panel(state)
    end,
  })

  -- Reposition and resize panel when the terminal resizes.
  vim.api.nvim_create_autocmd('VimResized', {
    buffer = bufnr,
    group = aug,
    callback = function()
      if not (state.panel_win and vim.api.nvim_win_is_valid(state.panel_win)) then
        return
      end
      local cur_h = vim.api.nvim_win_get_height(state.panel_win)
      local width, height, row, col = get_panel_dims(cur_h)
      vim.api.nvim_win_set_config(state.panel_win, {
        relative = 'editor',
        anchor = 'SW',
        row = row,
        col = col,
        width = width,
        height = height,
      })
      if state.current_image then
        pcall(function()
          state.current_image:clear()
          state.current_image:render { width = width, height = height, x = 0, y = 0 }
        end)
      end
    end,
  })

  -- Clean up state if panel window is closed by other means.
  vim.api.nvim_create_autocmd('WinClosed', {
    group = aug,
    callback = function(ev)
      if tonumber(ev.match) == state.panel_win then
        if state.current_image then
          pcall(function()
            state.current_image:clear()
          end)
          state.current_image = nil
        end
        state.panel_win = nil
        state.panel_buf = nil
      end
    end,
  })

  -- Toggle auto-preview; disabling cancels in-flight render but leaves panel open.
  vim.keymap.set('n', '<leader>lp', function()
    state.auto_enabled = not state.auto_enabled
    if not state.auto_enabled and state.render_job then
      pcall(vim.fn.jobstop, state.render_job)
      state.render_job = nil
    end
    vim.notify('LaTeX auto-preview ' .. (state.auto_enabled and 'enabled' or 'disabled'), vim.log.levels.INFO)
  end, { buffer = bufnr, desc = '[L]atex [P]review auto toggle' })

  -- Manual render at cursor (always fires regardless of auto_enabled).
  vim.keymap.set('n', '<leader>lv', function()
    local content = get_outermost_block(bufnr)
    if not content or content == '' then
      vim.notify('LaTeX preview: nothing found at cursor', vim.log.levels.WARN)
      return
    end
    render_async(state, content, bufnr)
  end, { buffer = bufnr, desc = '[L]atex [V]iew block' })

  -- Explicitly close the panel.
  vim.keymap.set('n', '<leader>lc', function()
    close_panel(state)
  end, { buffer = bufnr, desc = '[L]atex preview [C]lose' })

  -- Preview the equation referenced by \ref/\eqref/\cref at cursor.
  vim.keymap.set('n', '<leader>lr', function()
    local label = get_ref_label_at_cursor()
    if not label or label == '' then
      vim.notify('LaTeX preview: no \\ref/\\eqref at cursor', vim.log.levels.WARN)
      return
    end
    preview_label_async(state, label, bufnr)
  end, { buffer = bufnr, desc = '[L]atex preview [R]ef under cursor' })

  -- Show the preamble that will be used for the next render.
  vim.api.nvim_buf_create_user_command(bufnr, 'TexStatus', function()
    local root = find_root_file(bufnr)
    local preamble = build_preamble(bufnr)
    local lines = vim.split('% preamble source: ' .. (root or 'unknown') .. '\n' .. preamble, '\n')
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = 'tex'
    vim.bo[buf].bufhidden = 'wipe'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.cmd 'split'
    vim.api.nvim_win_set_buf(0, buf)
  end, { desc = 'Show the LaTeX preamble used for preview rendering' })
end

return M
