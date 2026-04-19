vim.opt_local.wrap = true
vim.opt_local.linebreak = true
vim.opt_local.textwidth = 0
vim.opt_local.spell = true
vim.opt_local.spelllang = 'en_us'

vim.keymap.set('n', 'j', 'gj', { buffer = true, silent = true })
vim.keymap.set('n', 'k', 'gk', { buffer = true, silent = true })

-- Extract math content from the equation environment around the cursor
local function get_equation_around_cursor()
  local lnum = vim.fn.line('.')
  local col  = vim.fn.col('.')
  local total = vim.fn.line('$')

  -- Try $$...$$ (display math, possibly multi-line)
  do
    local start_line, end_line
    for i = lnum, 1, -1 do
      if vim.fn.getline(i):match('%$%$') then start_line = i; break end
    end
    if start_line then
      for i = lnum, total do
        local l = vim.fn.getline(i)
        local s = (i == start_line) and 3 or 1
        if l:sub(s):match('%$%$') then end_line = i; break end
      end
    end
    if start_line and end_line and start_line ~= end_line then
      local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
      local inner = table.concat(lines, ' '):match('%$%$(.-)%$%$')
      if inner then return vim.trim(inner) end
    end
  end

  -- Try $...$ on the current line
  do
    local line = vim.fn.getline(lnum)
    local pos = 1
    local opens = {}
    while true do
      local s = line:find('%$', pos)
      if not s then break end
      if line:sub(s, s + 1) == '$$' then pos = s + 2
      else table.insert(opens, s); pos = s + 1
      end
    end
    for i = 1, #opens - 1, 2 do
      local s, e = opens[i], opens[i + 1]
      if s and e and col >= s and col <= e then
        return vim.trim(line:sub(s + 1, e - 1))
      end
    end
  end

  -- Fall back to \begin{...}...\end{...}
  local start_line, end_line
  for i = lnum, 1, -1 do
    if vim.fn.getline(i):match('\\begin{') then start_line = i; break end
  end
  if not start_line then return nil end
  for i = lnum, total do
    if vim.fn.getline(i):match('\\end{') then end_line = i; break end
  end
  if not end_line then return nil end

  local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line - 1, false)
  return vim.trim(table.concat(lines, ' '))
end

-- Preview window state
local state = { win = nil, buf = nil }

local function close_preview()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
end

local function update_float(lines)
  while #lines > 0 and lines[#lines] == '' do table.remove(lines) end
  if #lines == 0 then return end

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.max(width + 2, 20)
  local height = #lines

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_set_option_value('modifiable', true, { buf = state.buf })
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = state.buf })
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_config(state.win, {
        relative = 'cursor', row = 1, col = 0,
        width = width, height = height,
      })
    end
  else
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = state.buf })
    state.win = vim.api.nvim_open_win(state.buf, false, {
      relative = 'cursor', row = 1, col = 0,
      width = width, height = height,
      style = 'minimal', border = 'rounded',
    })
    vim.keymap.set('n', 'q', close_preview, { buffer = state.buf, nowait = true })
  end
end

local sym_tex = vim.fn.expand('~/.config/tex/sym.tex')

local python_script = [[
import sys, re
from pylatexenc.latex2text import LatexNodes2Text

SUPS = str.maketrans('0123456789+-=()abcdefghijklmnoprstuvwxyzABDEGHIJKLMNOPRTUVW',
                     '⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻᴬᴮᴰᴱᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᴿᵀᵁᵛᵂ')
SUBS = str.maketrans('0123456789+-=()aehijklmnoprstuvx',
                     '₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ')

def apply_scripts(text):
    def replace_script(m, table, fallback_prefix):
        inner = m.group(1)
        converted = inner.translate(table)
        if converted != inner:
            return '{}' + converted
        return fallback_prefix + '{' + inner + '}'
    text = re.sub(r'\^\{([^}]*)\}', lambda m: replace_script(m, SUPS, '^'), text)
    text = re.sub(r'_\{([^}]*)\}',  lambda m: replace_script(m, SUBS, '_'), text)
    text = re.sub(r'\^([^ {])',  lambda m: '{}' + m.group(1).translate(SUPS), text)
    text = re.sub(r'_([^ {])',   lambda m: '{}' + m.group(1).translate(SUBS), text)
    return text

def load_macros(path):
    macros = {}
    try:
        with open(path) as f:
            for line in f:
                m = re.match(r'\\newcommand\{(\\[A-Za-z]+)\}\{(.+)\}', line.strip())
                if m:
                    macros[m.group(1)] = m.group(2)
    except FileNotFoundError:
        pass
    return macros

def expand(expr, macros):
    for _ in range(20):  # max expansion depth
        prev = expr
        for name, body in macros.items():
            expr = re.sub(re.escape(name) + r'(?![A-Za-z])', lambda m, b=body: b, expr)
        if expr == prev:
            break
    return expr

macros = load_macros(sys.argv[1])
result = expand(sys.argv[2], macros)
result = apply_scripts(result)
result = LatexNodes2Text().latex_to_text(result)
print(result)
]]

local function render_async(math_content)
  vim.fn.jobstart({ 'python3', '-c', python_script, sym_tex, math_content }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      vim.schedule(function() update_float(data) end)
    end,
    on_stderr = function(_, data)
      if data and #data > 0 and data[1] ~= '' then
        vim.schedule(function()
          vim.notify('Preview error: ' .. table.concat(data, ' '), vim.log.levels.ERROR)
        end)
      end
    end,
  })
end

-- Debounce timer for live updates
local debounce_timer = nil
local function debounced_render()
  if debounce_timer then
    pcall(function() debounce_timer:stop(); debounce_timer:close() end)
    debounce_timer = nil
  end
  debounce_timer = vim.defer_fn(function()
    debounce_timer = nil
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local math = get_equation_around_cursor()
      if math and math ~= '' then render_async(math) end
    end
  end, 400)
end

local bufnr = vim.api.nvim_get_current_buf()
local hover_enabled = true

-- Auto-show on hover
vim.api.nvim_create_autocmd('CursorHold', {
  buffer = bufnr,
  callback = function()
    if not hover_enabled then return end
    local math = get_equation_around_cursor()
    if math and math ~= '' then render_async(math) end
  end,
})

-- Close when cursor leaves an equation
vim.api.nvim_create_autocmd('CursorMoved', {
  buffer = bufnr,
  callback = function()
    if not get_equation_around_cursor() then close_preview() end
  end,
})

-- Live update while typing
vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
  buffer = bufnr,
  callback = function()
    if hover_enabled then debounced_render() end
  end,
})

vim.api.nvim_create_autocmd('BufLeave', {
  buffer = bufnr,
  callback = close_preview,
})

-- Go-to for \ref{}, \eqref{}, \input{}, \include{}
local ref_cmds  = { ['\\ref']=true, ['\\eqref']=true, ['\\cref']=true, ['\\autoref']=true, ['\\label']=true }
local file_cmds = { ['\\input']=true, ['\\include']=true, ['\\includeonly']=true }

local function get_cmd_at_cursor()
  local line = vim.fn.getline('.')
  local col  = vim.fn.col('.')
  -- search backward for { (cursor inside braces)
  local bstart
  for i = col, 1, -1 do
    local c = line:sub(i, i)
    if c == '{' then bstart = i; break end
    if c == '}' then break end
  end
  -- if not found, search forward (cursor is on the command name before the brace)
  if not bstart then
    for i = col, #line do
      local c = line:sub(i, i)
      if c == '{' then bstart = i; break end
      if c == ' ' then break end
    end
  end
  if not bstart then return nil, nil end
  local bend
  for i = bstart + 1, #line do
    if line:sub(i, i) == '}' then bend = i; break end
  end
  if not bend then return nil, nil end
  local arg = line:sub(bstart + 1, bend - 1)
  local cmd = line:sub(1, bstart - 1):match('(\\%a+)%s*$')
  return cmd, arg
end

local function latex_gd()
  local cmd, arg = get_cmd_at_cursor()
  if not cmd or not arg or arg == '' then
    vim.notify('No LaTeX reference or input at cursor', vim.log.levels.WARN)
    return
  end

  if ref_cmds[cmd] then
    -- search current buffer first (\V = very nomagic, \\ = literal backslash)
    local pos = vim.fn.searchpos('\\V\\\\label{' .. arg .. '}', 'nw')
    if pos[1] ~= 0 then
      vim.fn.cursor(pos[1], pos[2])
      return
    end

    -- fall back: rg across all .tex files from git root (or file dir)
    local file_dir = vim.fn.expand('%:p:h')
    local git_root = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(file_dir) .. ' rev-parse --show-toplevel')[1]
    local dir = (git_root and git_root ~= '') and git_root or file_dir
    local pattern = '\\label{' .. arg .. '}'
    vim.fn.jobstart({ 'rg', '-F', '--with-filename', '--line-number', '--no-heading', pattern, '--glob', '*.tex', dir }, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        vim.schedule(function()
          for _, line in ipairs(data) do
            local file, lnum = line:match('^(.+):(%d+):')
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
    local base = vim.fn.expand('%:p:h')
    local found
    for _, name in ipairs({ arg, arg .. '.tex' }) do
      local f = vim.fn.findfile(name, base .. ';')   -- search upward
      if f == '' then f = vim.fn.findfile(name, base .. '/**') end  -- search downward
      if f ~= '' then found = vim.fn.fnamemodify(f, ':p'); break end
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

-- Re-bind after LSP attaches (LSP on_attach overwrites <leader>gd)
vim.api.nvim_create_autocmd('LspAttach', {
  buffer = bufnr,
  callback = bind_latex_gd,
})

-- Toggle hover preview on/off
vim.keymap.set('n', '<leader>lp', function()
  hover_enabled = not hover_enabled
  if not hover_enabled then close_preview() end
  vim.notify('Latex hover preview ' .. (hover_enabled and 'enabled' or 'disabled'), vim.log.levels.INFO)
end, { buffer = true, desc = '[L]atex [P]review toggle' })

-- Manual view
vim.keymap.set('n', '<leader>lv', function()
  local math = get_equation_around_cursor()
  if not math or math == '' then
    vim.notify('No equation found around cursor', vim.log.levels.WARN)
    return
  end
  render_async(math)
end, { buffer = true, desc = '[L]atex [V]iew equation' })
