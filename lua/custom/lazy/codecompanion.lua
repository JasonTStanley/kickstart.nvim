return {
  'olimorris/codecompanion.nvim',
  dependencies = {
    { 'nvim-treesitter/nvim-treesitter', build = ':TSUpdate' },
    { 'nvim-lua/plenary.nvim' },
    { 'hrsh7th/nvim-cmp' },
  },
  opts = {
    strategies = {
      chat = { adapter = 'copilot' },
      inline = { adapter = 'copilot' },
    },
  },
}
