-- diffview.nvim: a GitHub-style "Files changed" view between any two points in git.
--
--   <leader>dg  pick a commit or branch from the git graph and diff against it
--   <leader>dh  history of the current file, one commit at a time
--   <leader>dq  close the diff
--
-- In the <leader>dg picker:
--   <CR>   what HEAD (plus uncommitted work) changed since it split from the
--          selection -- the PR view of this branch into it. Files are the real
--          ones on disk, so they are editable and LSP works.
--   <C-o>  the reverse: the selection as a PR into HEAD (review a branch)
--   <C-s>  only the selected commit's own changes
--   <Tab>  mark two commits; <CR> then diffs straight from the older to the newer

local function git_toplevel()
  local dir = vim.fn.expand '%:p:h'
  if vim.fn.isdirectory(dir) == 0 then
    dir = vim.uv.cwd()
  end
  local out = vim.system({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' }, { text = true }):wait()
  if out.code ~= 0 then
    return nil
  end
  return vim.trim(out.stdout)
end

-- The name git log decorates a commit with, or its hash. "HEAD -> master,
-- origin/master, tag: v1" gives "master", so the diff title reads master...HEAD.
local function rev_name(entry)
  for ref in vim.gsplit(entry.refs, ', ', { plain = true }) do
    ref = ref:gsub('^HEAD %-> ', ''):gsub('^tag: ', '')
    if ref ~= '' and ref ~= 'HEAD' then
      return ref
    end
  end
  return entry.hash
end

local function git_graph_picker()
  local top = git_toplevel()
  if not top then
    vim.notify('Not in a git repository', vim.log.levels.WARN)
    return
  end

  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local putils = require 'telescope.previewers.utils'

  local index = 0
  local function make_entry(line)
    index = index + 1
    local graph, hash, refs, subject = line:match '^(.-)\31(%x+)\31(.-)\31(.*)$'
    if not hash then
      -- A graph-only line (|\, |/ ...): shown to keep the graph whole, but it
      -- has nothing to match, so it drops out as soon as you type.
      return { value = line, ordinal = '', display = line, index = index }
    end

    local decorated = refs ~= '' and (' (' .. refs .. ')') or ''
    local text = graph .. hash .. decorated .. ' ' .. subject
    local h_end = #graph + #hash
    local highlights = {
      { { 0, #graph }, 'TelescopeResultsComment' },
      { { #graph, h_end }, 'TelescopeResultsIdentifier' },
      { { h_end, h_end + #decorated }, 'TelescopeResultsConstant' },
    }
    return {
      value = line,
      hash = hash,
      refs = refs,
      index = index,
      ordinal = refs .. ' ' .. subject .. ' ' .. hash,
      display = function()
        return text, highlights
      end,
    }
  end

  local function open(prompt_bufnr, args)
    actions.close(prompt_bufnr)
    table.insert(args, '-C' .. top)
    require('diffview').open(args)
  end

  local function selected_commit()
    local entry = action_state.get_selected_entry()
    if not (entry and entry.hash) then
      vim.notify('That line is part of the graph, not a commit', vim.log.levels.WARN)
      return nil
    end
    return entry
  end

  require('telescope.pickers')
    .new({
      sorting_strategy = 'ascending', -- newest at the top, so the graph reads the right way up
      layout_config = { prompt_position = 'top' },
    }, {
      prompt_title = 'Diff against',
      results_title = '<CR> HEAD vs this · <C-o> this as a PR · <C-s> this commit · <Tab> mark two',
      finder = require('telescope.finders').new_oneshot_job({
        'git', '-C', top, 'log', '--graph', '--all', '--color=never',
        '--format=%x1f%h%x1f%D%x1f%s',
      }, { entry_maker = make_entry }),
      sorter = require('telescope.config').values.generic_sorter {},
      previewer = require('telescope.previewers').new_buffer_previewer {
        title = 'Commit',
        define_preview = function(self, entry)
          if not entry.hash then
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {})
            return
          end
          putils.job_maker({ 'git', '-C', top, 'show', '--stat', '--patch', '--format=fuller', entry.hash }, self.state.bufnr, {
            value = entry.hash,
            bufname = self.state.bufname,
          })
          putils.regex_highlighter(self.state.bufnr, 'git')
        end,
      },
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local marked = vim.tbl_filter(function(e)
            return e.hash ~= nil
          end, picker:get_multi_selection())

          if #marked == 2 then
            table.sort(marked, function(a, b)
              return a.index > b.index -- older first: git log lists newest first
            end)
            open(prompt_bufnr, { marked[1].hash .. '..' .. marked[2].hash })
          elseif #marked > 0 then
            vim.notify('Mark exactly two commits with <Tab>', vim.log.levels.WARN)
          else
            local entry = selected_commit()
            if entry then
              open(prompt_bufnr, { rev_name(entry) .. '...HEAD', '--imply-local' })
            end
          end
        end)

        map({ 'i', 'n' }, '<C-o>', function()
          local entry = selected_commit()
          if entry then
            open(prompt_bufnr, { 'HEAD...' .. rev_name(entry) })
          end
        end, { desc = 'diff: selection as a PR into HEAD' })

        map({ 'i', 'n' }, '<C-s>', function()
          local entry = selected_commit()
          if entry then
            open(prompt_bufnr, { entry.hash .. '^!' })
          end
        end, { desc = 'diff: only this commit' })

        return true
      end,
    })
    :find()
end

return {
  'sindrets/diffview.nvim',

  config = function()
    require('diffview').setup {}

    vim.keymap.set('n', '<leader>dg', git_graph_picker, { desc = '[D]iff against the [G]it graph' })
    vim.keymap.set('n', '<leader>dh', '<cmd>DiffviewFileHistory %<CR>', { desc = '[D]iff [H]istory of this file' })
    vim.keymap.set('n', '<leader>dq', '<cmd>DiffviewClose<CR>', { desc = '[D]iff [Q]uit' })
  end,
}
