local M = {}

M.summary_source_id = 'ai-commit-summarize'
M.message_source_id = 'ai-commit-message'
M.refine_source_id = 'ai-commit-refine'

M.values = {
  context = {
    opencode = true,
    recent_commits = true,
    staged_changes = true,
  },
  max_tokens = 32768,
  spinner_interval = 80,
  preview_lines = 5,
  preview_max_chars = 4000,
  max_diff_chars = 100000,
  prompt_context_ratio = 0.8,
  refinement = {
    enabled = true,
    max_iterations = 2,
    include_context = {
      recent_commits = false,
      staged_files = true,
      staged_changes = false,
      session_context = false,
    },
    recent_commits_with_body = false,
  },
  diff_context = {
    small_changed_lines = 100,
    medium_changed_lines = 500,
  },
  model_highlight_group = 'Special',
  prompt_dump_dir = vim.fn.stdpath 'log' .. '/ai-commit-promts',
  opencode_context = {
    db_path = vim.fn.expand '~/.local/share/opencode/opencode.db',
    recent_ms = 60 * 60 * 1000,
    recent_user_messages = 4,
    max_message_chars = 5000,
    max_transcript_chars = 30000,
  },
  log_level = 'warn',
}

---@param opts table|nil
function M.setup(opts)
  if type(opts) == 'table' then
    M.values = vim.tbl_deep_extend('force', M.values, opts)
  end
end

return M
