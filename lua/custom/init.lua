require 'custom.set'
require 'custom.remap'
require 'custom.lazy_init'

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- remove trailing whitespace from a buffer on save.
vim.api.nvim_create_autocmd('BufWritePre', {
  desc = 'trim trailing whitespace on save',
  group = vim.api.nvim_create_augroup('remove-whitespace', { clear = true }),
  pattern = '*',
  command = [[%s/\s\+$//e]],
})
vim.api.nvim_create_autocmd('BufNewFile', {
  pattern = 'CMakeLists.txt',
  callback = function()
    local template = vim.fn.stdpath 'config' .. '/templates/cmake_template.cmake'
    vim.cmd('0r ' .. template)

    local pos = vim.fn.search('ProjectName', 'c')
    if pos > 0 then
      -- select the word under cursor
      vim.cmd 'normal viw'
    end
  end,
})
vim.api.nvim_create_autocmd('BufNewFile', {
  pattern = 'Dockerfile',
  callback = function()
    local template = vim.fn.stdpath 'config' .. '/templates/dockerfile_template'
    vim.cmd('0r ' .. template)
  end,
})
vim.api.nvim_create_autocmd({ 'BufWritePre' }, {
  pattern = '*.xml',
  callback = function(args)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local handle = io.popen('xmllint --noout ' .. filename .. ' 2>&1')
    local result = handle:read '*a'
    handle:close()

    -- Clear previous virtual text
    vim.api.nvim_buf_clear_namespace(bufnr, 0, 0, -1)

    if result ~= '' then
      vim.notify('XML errors detected:\n' .. result, vim.log.levels.ERROR)
      -- Optionally display errors inline with virtual text
      for line in result:gmatch ':(%d+):' do
        local lnum = tonumber(line) - 1
        vim.api.nvim_buf_set_virtual_text(bufnr, 0, lnum, { { '⛔ XML Error', 'ErrorMsg' } }, {})
      end
      return false
    end
  end,
})
