local config = require 'ai-commit.config'
local generator = require 'ai-commit.generator'
local log = require('ai-commit.log').get
local providers = require 'ai-commit.providers'
local state = require 'ai-commit.state'

local M = {}

---@param opts table|nil
function M.setup(opts)
  config.setup(opts)

  local logger = log()
  local ok, ai_provider = pcall(require, 'ai-provider')
  if ok then
    local sources = {
      { id = config.summary_source_id, name = 'AI Commit: OpenCode Summary' },
      { id = config.message_source_id, name = 'AI Commit: Commit Message' },
      { id = config.refine_source_id, name = 'AI Commit: Refinement' },
    }
    for _, source in ipairs(sources) do
      ai_provider.register_source(source.id, { name = source.name })
      local source_id = source.id
      local selection = ai_provider.get_source_selection(source_id)
      if selection then
        logger.info('Using AI provider source=' .. source_id .. ' model=' .. selection.label)
      end
    end
  end

  state.ns_id = vim.api.nvim_create_namespace 'ai_commit_spinner'

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'gitcommit',
    group = vim.api.nvim_create_augroup('AICommitMessage', { clear = true }),
    callback = function()
      logger.debug 'gitcommit FileType autocmd triggered'
      vim.keymap.set('n', '<leader>ga', generator.insert, {
        buffer = true,
        desc = '[G]it [A]I commit message',
      })
      vim.schedule(generator.insert)
    end,
  })

  vim.api.nvim_create_user_command('AICommit', generator.insert, {
    desc = 'Generate AI commit message',
  })

  vim.api.nvim_create_user_command('AICommitModel', providers.select_model, {
    desc = 'Select AI commit model',
  })

  vim.api.nvim_create_user_command('AICommitSummaryModel', providers.select_summary_model, {
    desc = 'Select AI commit summary model',
  })

  vim.api.nvim_create_user_command('AICommitRefinementModel', providers.select_refinement_model, {
    desc = 'Select AI commit refinement model',
  })
end

function M.insert()
  generator.insert()
end

function M.select_model()
  providers.select_model()
end

function M.select_refinement_model()
  providers.select_refinement_model()
end

return M
