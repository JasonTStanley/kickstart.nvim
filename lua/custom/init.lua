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
