vim.opt_local.wrap = true
vim.opt_local.linebreak = true
vim.opt_local.textwidth = 0
vim.opt_local.spell = true
vim.opt_local.spelllang = 'en_us'

vim.keymap.set('n', 'j', 'gj', { buffer = true, silent = true })
vim.keymap.set('n', 'k', 'gk', { buffer = true, silent = true })

-- Go-to for \ref{}, \eqref{}, \input{}, \include{}
local ref_cmds  = { ['\\ref'] = true, ['\\eqref'] = true, ['\\cref'] = true, ['\\autoref'] = true, ['\\label'] = true }
local file_cmds = { ['\\input'] = true, ['\\include'] = true, ['\\includeonly'] = true }

local function get_cmd_at_cursor()
  local line = vim.fn.getline '.'
  local col  = vim.fn.col '.'
  local bstart
  for i = col, 1, -1 do
    local c = line:sub(i, i)
    if c == '{' then bstart = i; break end
    if c == '}' then break end
  end
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
    local dir      = (git_root and git_root ~= '') and git_root or file_dir
    local pattern  = '\\label{' .. arg .. '}'
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
      if f == '' then f = vim.fn.findfile(name, base .. '/**') end
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

local bufnr = vim.api.nvim_get_current_buf()

vim.api.nvim_create_autocmd('LspAttach', {
  buffer   = bufnr,
  callback = bind_latex_gd,
})

require('custom.latex_preview').attach(bufnr)
