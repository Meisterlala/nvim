local M = {}

M.source_id = 'ai-commit-message'
M.summary_source_id = 'ai-commit-summarize'
M.message_source_id = 'ai-commit-message'

M.values = {
  provider = 'copilot',
  model = nil,
  model_name = nil,
  openrouter = {
    endpoint = 'https://openrouter.ai/api/v1',
    reasoning = false,
  },
  max_tokens = 10000,
  spinner_interval = 80,
  preview_lines = 5,
  max_diff_chars = 100000,
  chat_timeout = 30000,
  model_highlight_group = 'Special',
  prompt_dump_path = vim.fn.stdpath 'log' .. '/ai-commit-last-prompt.md',
  opencode_context = {
    enabled = true,
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
