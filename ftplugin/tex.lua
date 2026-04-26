vim.opt_local.wrap = true
vim.opt_local.linebreak = true
vim.opt_local.textwidth = 0
vim.opt_local.spell = true
vim.opt_local.spelllang = 'en_us'

vim.keymap.set('n', 'j', 'gj', { buffer = true, silent = true })
vim.keymap.set('n', 'k', 'gk', { buffer = true, silent = true })

local math_envs = {
  equation = true,
  ['equation*'] = true,
  align = true,
  ['align*'] = true,
  gather = true,
  ['gather*'] = true,
  multline = true,
  ['multline*'] = true,
  split = true,
  alignat = true,
  ['alignat*'] = true,
}

-- Returns math content and the line number of the closing delimiter (for float placement)
local function get_equation_at_cursor()
  local lnum = vim.fn.line '.'
  local col = vim.fn.col '.'
  local total = vim.fn.line '$'

  -- $$...$$ multi-line display math
  do
    local start_line, end_line
    for i = lnum, 1, -1 do
      if vim.fn.getline(i):match '%$%$' then
        start_line = i
        break
      end
    end
    if start_line then
      for i = lnum, total do
        local l = vim.fn.getline(i)
        local s = (i == start_line) and 3 or 1
        if l:sub(s):match '%$%$' then
          end_line = i
          break
        end
      end
    end
    if start_line and end_line and start_line ~= end_line then
      local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
      local inner = table.concat(lines, ' '):match '%$%$(.-)%$%$'
      if inner then
        return vim.trim(inner), end_line
      end
    end
  end

  -- $...$ inline on current line
  do
    local line = vim.fn.getline(lnum)
    local pos = 1
    local opens = {}
    while true do
      local s = line:find('%$', pos)
      if not s then
        break
      end
      if line:sub(s, s + 1) == '$$' then
        pos = s + 2
      else
        table.insert(opens, s)
        pos = s + 1
      end
    end
    for i = 1, #opens - 1, 2 do
      local s, e = opens[i], opens[i + 1]
      if s and e and col >= s and col <= e then
        return vim.trim(line:sub(s + 1, e - 1)), lnum
      end
    end
  end

  -- \begin{env}...\end{env} known math environments
  local start_line, end_line, env_name
  for i = lnum, 1, -1 do
    local env = vim.fn.getline(i):match '\\begin{([^}]+)}'
    if env and math_envs[env] then
      start_line = i
      env_name = env
      break
    end
  end
  if not start_line then
    return nil, nil
  end
  for i = start_line + 1, total do
    if vim.fn.getline(i):match('\\end{' .. vim.pesc(env_name) .. '}') then
      end_line = i
      break
    end
  end
  if not end_line then
    return nil, nil
  end
  if lnum > end_line then
    return nil, nil
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line - 1, false)
  local content = vim.trim(table.concat(lines, ' '))
  content = content:gsub('\\label{[^}]*}', '')
  return vim.trim(content), end_line
end

-- Image preview state
local current_image = nil
local preview_win = nil
local preview_buf = nil
local last_math = nil -- content of last successfully rendered equation
local render_generation = 0
if vim.b.tex_hover_enabled == nil then vim.b.tex_hover_enabled = false end

local function close_preview()
  render_generation = render_generation + 1
  if render_job then
    pcall(vim.fn.jobstop, render_job)
    render_job = nil
  end
  if current_image then
    pcall(function()
      current_image:clear()
    end)
    current_image = nil
  end
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    pcall(vim.api.nvim_win_close, preview_win, true)
  end
  if preview_buf and vim.api.nvim_buf_is_valid(preview_buf) then
    pcall(vim.api.nvim_buf_delete, preview_buf, { force = true })
  end
  preview_win = nil
  preview_buf = nil
  last_math = nil
end

local sym_tex = vim.fn.expand '~/.config/tex/sym.tex'
local tmp_dir = vim.fn.stdpath 'cache' .. '/tex_preview'
vim.fn.mkdir(tmp_dir, 'p')
local tmp_tex = tmp_dir .. '/preview.tex'
local tmp_pdf = tmp_dir .. '/preview.pdf'

local function build_tex(math_content)
  local macro_block = ''
  local f = io.open(sym_tex, 'r')
  if f then
    macro_block = f:read '*a'
    f:close()
  end

  math_content = math_content:gsub('\\label{[^}]*}', '')

  local tex_src = table.concat({
    '\\documentclass[preview,border=3pt]{standalone}',
    '\\usepackage{xcolor}',
    '\\usepackage{amsmath,amssymb,amsfonts}',
    macro_block,
    '\\begin{document}',
    '\\pagecolor[HTML]{1e1e2e}',
    '{\\color{white}',
    '\\begin{equation*}',
    math_content,
    '\\end{equation*}',
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
  local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a * 16777216 + b * 65536 + c * 256 + d
  end
  return u32(data, 1), u32(data, 5)
end

local function show_image_below_line(png_path, below_lnum)
  local ok, image_api = pcall(require, 'image')
  if not ok then
    vim.notify('image.nvim not loaded', vim.log.levels.WARN)
    return
  end

  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.api.nvim_win_close(preview_win, true)
  end
  if current_image then
    pcall(function()
      current_image:clear()
    end)
    current_image = nil
  end

  local px_w, px_h = png_dimensions(png_path)

  local win_width = math.min(55, math.floor(vim.o.columns * 0.60))
  local win_height
  if px_w and px_h and px_w > 0 and px_h > 0 then
    win_height = math.max(math.ceil(win_width * px_h / px_w / 2), 2)
  else
    win_height = 4
  end
  win_height = math.min(win_height, math.floor(vim.o.lines * 0.30))
  local inner_w = win_width
  local inner_h = win_height

  local cur_win = vim.api.nvim_get_current_win()
  local anchor = math.min(below_lnum + 1, vim.fn.line '$')
  local spos = vim.fn.screenpos(cur_win, anchor, 1)
  local winfo = vim.fn.getwininfo(cur_win)[1]
  -- spos.row==0 means the line is off-screen; clamp to bottom of visible area
  local float_row = spos.row > 0 and (spos.row - winfo.winrow) or (winfo.height - 1)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'win',
    win = cur_win,
    row = float_row,
    col = 6,
    width = win_width,
    height = win_height,
    style = 'minimal',
    border = 'rounded',
  })
  preview_buf = buf
  preview_win = win
  vim.keymap.set('n', 'q', close_preview, { buffer = buf, nowait = true })

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
      img:render { width = inner_w, height = inner_h, x = 0, y = 0 }
      current_image = img
    end
  end, 80)
end

local render_job = nil
-- force=true bypasses hover_enabled (used by <leader>lv manual trigger)
local function render_async(math_content, end_lnum)
  render_generation = render_generation + 1
  local my_generation = render_generation
  if render_job then
    pcall(vim.fn.jobstop, render_job)
    render_job = nil
  end

  if not build_tex(math_content) then
    vim.notify('LaTeX preview: failed to write .tex file', vim.log.levels.ERROR)
    return
  end

  vim.notify('LaTeX preview: rendering...', vim.log.levels.INFO)

  local png_base = 'preview_' .. my_generation
  local png_path = tmp_dir .. '/' .. png_base .. '.png'

  local stderr_lines = {}
  render_job = vim.fn.jobstart({
    'sh',
    '-c',
    string.format(
      'cd %s && pdflatex -interaction=nonstopmode -halt-on-error preview.tex > /dev/null && ' .. 'pdftoppm -r 400 -png -singlefile preview.pdf %s',
      vim.fn.shellescape(tmp_dir),
      png_base
    ),
  }, {
    stderr_buffered = true,
    on_stderr = function(_, data)
      if data then
        for _, l in ipairs(data) do
          if l ~= '' then
            table.insert(stderr_lines, l)
          end
        end
      end
    end,
    on_exit = function(_, code)
      render_job = nil
      vim.schedule(function()
        if my_generation ~= render_generation then return end
        if code == 0 then
          last_math = math_content
          show_image_below_line(png_path, end_lnum)
        else
          vim.notify('LaTeX preview failed (code ' .. code .. '):\n' .. table.concat(stderr_lines, '\n'), vim.log.levels.ERROR)
        end
      end)
    end,
  })
end

local bufnr = vim.api.nvim_get_current_buf()

-- Show preview when cursor enters an equation; do nothing if already showing same equation
vim.api.nvim_create_autocmd('CursorHold', {
  buffer = bufnr,
  callback = function()
    if not vim.b.tex_hover_enabled then
      return
    end
    local math, end_lnum = get_equation_at_cursor()
    if not math or math == '' then
      return
    end
    -- already showing this equation — don't re-render
    if math == last_math and preview_win and vim.api.nvim_win_is_valid(preview_win) then
      return
    end
    render_async(math, end_lnum)
  end,
})

-- Close preview only when cursor leaves all equation environments
vim.api.nvim_create_autocmd('CursorMoved', {
  buffer = bufnr,
  callback = function()
    local math = get_equation_at_cursor()
    if not math then
      close_preview()
    end
  end,
})

vim.api.nvim_create_autocmd('BufLeave', {
  buffer = bufnr,
  callback = close_preview,
})

-- Go-to for \ref{}, \eqref{}, \input{}, \include{}
local ref_cmds = { ['\\ref'] = true, ['\\eqref'] = true, ['\\cref'] = true, ['\\autoref'] = true, ['\\label'] = true }
local file_cmds = { ['\\input'] = true, ['\\include'] = true, ['\\includeonly'] = true }

local function get_cmd_at_cursor()
  local line = vim.fn.getline '.'
  local col = vim.fn.col '.'
  local bstart
  for i = col, 1, -1 do
    local c = line:sub(i, i)
    if c == '{' then
      bstart = i
      break
    end
    if c == '}' then
      break
    end
  end
  if not bstart then
    for i = col, #line do
      local c = line:sub(i, i)
      if c == '{' then
        bstart = i
        break
      end
      if c == ' ' then
        break
      end
    end
  end
  if not bstart then
    return nil, nil
  end
  local bend
  for i = bstart + 1, #line do
    if line:sub(i, i) == '}' then
      bend = i
      break
    end
  end
  if not bend then
    return nil, nil
  end
  local arg = line:sub(bstart + 1, bend - 1)
  local cmd = line:sub(1, bstart - 1):match '(\\%a+)%s*$'
  return cmd, arg
end

local function latex_gd()
  local cmd, arg = get_cmd_at_cursor()
  if not cmd or not arg or arg == '' then
    vim.notify('No LaTeX reference or input at cursor', vim.log.levels.WARN)
    return
  end

  if ref_cmds[cmd] then
    local pos = vim.fn.searchpos('\\V\\\\label{' .. arg .. '}', 'nw')
    if pos[1] ~= 0 then
      vim.fn.cursor(pos[1], pos[2])
      return
    end

    local file_dir = vim.fn.expand '%:p:h'
    local git_root = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(file_dir) .. ' rev-parse --show-toplevel')[1]
    local dir = (git_root and git_root ~= '') and git_root or file_dir
    local pattern = '\\label{' .. arg .. '}'
    vim.fn.jobstart({ 'rg', '-F', '--with-filename', '--line-number', '--no-heading', pattern, '--glob', '*.tex', dir }, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        vim.schedule(function()
          for _, line in ipairs(data) do
            local file, lnum = line:match '^(.+):(%d+):'
            if file and lnum then
              vim.cmd('edit ' .. vim.fn.fnameescape(file))
              vim.fn.cursor(tonumber(lnum), 1)
              return
            end
          end
          vim.notify('Label not found: ' .. arg, vim.log.levels.WARN)
        end)
      end,
    })
  elseif file_cmds[cmd] then
    local base = vim.fn.expand '%:p:h'
    local found
    for _, name in ipairs { arg, arg .. '.tex' } do
      local f = vim.fn.findfile(name, base .. ';')
      if f == '' then
        f = vim.fn.findfile(name, base .. '/**')
      end
      if f ~= '' then
        found = vim.fn.fnamemodify(f, ':p')
        break
      end
    end
    if found then
      vim.cmd('edit ' .. vim.fn.fnameescape(found))
    else
      vim.notify('File not found: ' .. arg, vim.log.levels.WARN)
    end
  else
    vim.notify('gd: unrecognised command ' .. cmd, vim.log.levels.WARN)
  end
end

local function bind_latex_gd()
  vim.keymap.set('n', '<leader>gd', latex_gd, { buffer = true, desc = '[G]o to LaTeX [D]efinition' })
end

bind_latex_gd()

vim.api.nvim_create_autocmd('LspAttach', {
  buffer = bufnr,
  callback = bind_latex_gd,
})

vim.keymap.set('n', '<leader>lp', function()
  vim.b.tex_hover_enabled = not vim.b.tex_hover_enabled
  if not vim.b.tex_hover_enabled then
    if render_job then
      pcall(vim.fn.jobstop, render_job)
      render_job = nil
    end
    close_preview()
  end
  vim.notify('Latex hover preview ' .. (vim.b.tex_hover_enabled and 'enabled' or 'disabled'), vim.log.levels.INFO)
end, { buffer = true, desc = '[L]atex [P]review toggle' })

vim.keymap.set('n', '<leader>lv', function()
  local math, end_lnum = get_equation_at_cursor()
  if not math or math == '' then
    vim.notify('No equation found around cursor', vim.log.levels.WARN)
    return
  end
  render_async(math, end_lnum)
end, { buffer = true, desc = '[L]atex [V]iew equation' })
