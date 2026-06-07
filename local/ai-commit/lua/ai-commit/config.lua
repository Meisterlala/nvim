local M = {}

M.summary_source_id = 'ai-commit-summarize'
M.message_source_id = 'ai-commit-message'

M.values = {
  context = {
    opencode = true,
    recent_commits = true,
    staged_changes = true,
  },
  max_tokens = 10000,
  spinner_interval = 80,
  preview_lines = 5,
  max_diff_chars = 100000,
  diff_context = {
    small_changed_lines = 100,
    medium_changed_lines = 500,
  },
  model_highlight_group = 'Special',
  prompt_dump_path = vim.fn.stdpath 'log' .. '/ai-commit-last-prompt.md',
  opencode_context = {
    db_path = vim.fn.expand '~/.local/share/opencode/opencode.db',
    recent_ms = 60 * 60 * 1000,
    assistant_messages = 4,
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
