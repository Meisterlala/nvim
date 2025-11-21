local M = {}

-- default excluded rules
M.ExculeRules = { 'PSAvoidGlobalVars', 'PSUseSingularNouns', 'PSAvoidUsingWriteHost' }

-- auto-install PSScriptAnalyzer if missing
local function ensure_pssa()
  local check = vim.fn.systemlist 'pwsh -NoProfile -Command "Get-Module -ListAvailable -Name PSScriptAnalyzer"'
  if #check == 0 then
    vim.notify('PSScriptAnalyzer not found, installing...', vim.log.levels.INFO)
    local _ = vim.fn.systemlist 'pwsh -NoProfile -Command "Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force"'
    if vim.v.shell_error ~= 0 then
      vim.notify('Failed to install PSScriptAnalyzer', vim.log.levels.ERROR)
      return false
    end
    vim.notify('PSScriptAnalyzer installed successfully!', vim.log.levels.INFO)
  end
  return true
end

function M.run_pssa()
  if not ensure_pssa() then
    return
  end

  local fname = vim.fn.expand '%:p'
  if not fname:match '%.ps1$' and not fname:match '%.psm1$' and not fname:match '%.psd1$' then
    return
  end

  local ns = vim.api.nvim_create_namespace 'PSSA'
  local buf_text = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local buffer_content = table.concat(buf_text, '\n')
  local rules_str = '"' .. table.concat(M.ExculeRules, '", "') .. '"'
  local pwsh_command = string.format(
    [[
      Import-Module PSScriptAnalyzer -Force;
      Invoke-ScriptAnalyzer -Settings @{ExcludeRules=@(%s)} -ScriptDefinition ([Console]::In.ReadToEnd()) |
      ForEach-Object { "$($_.Line):$($_.Column):$($_.Severity):$($_.RuleName):$($_.Message)" }
    ]],
    rules_str
  )

  local Job = require 'plenary.job'
  Job:new({
    command = 'pwsh',
    args = {
      '-NoProfile',
      '-NoLogo',
      '-Command',
      pwsh_command,
    },
    writer = buffer_content, -- plenary pipes this to stdin
    on_exit = function(j, _)
      local output = j:result()
      local diagnostics = {}

      for _, line in ipairs(output) do
        if line:match '%S' then
          local parts = vim.split(line, ':')
          local l = tonumber(parts[1]) or 0
          local c = tonumber(parts[2]) or 0
          local s = parts[3] or 'Info'
          local rule = parts[4] or 'Unknown'
          local msg = table.concat(vim.list_slice(parts, 5), ':') or ''

          if #msg > 0 then
            table.insert(diagnostics, {
              lnum = l - 1,
              col = c - 1,
              message = string.format('[%s] %s', rule, msg),
              severity = (s:lower() == 'error' and vim.diagnostic.severity.ERROR)
                or (s:lower() == 'warning' and vim.diagnostic.severity.WARN)
                or vim.diagnostic.severity.INFO,
              source = 'PSSA',
            })
          end
        end
      end

      vim.schedule(function()
        vim.diagnostic.set(ns, 0, diagnostics, {})
      end)
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        vim.schedule(function()
          local out = type(data) == 'table' and table.concat(data, '\n') or tostring(data)
          vim.notify(out, vim.log.levels.ERROR)
        end)
      end
    end,
  }):start()
end

-- auto-run
vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave' }, {
  pattern = { '*.ps1', '*.psm1', '*.psd1' },
  callback = M.run_pssa,
})

-- create main PSSA command
vim.api.nvim_create_user_command('PSScriptAnalyzer', function(opts)
  local arg = opts.args:lower()
  if arg == 'install' then
    ensure_pssa()
  else
    M.run_pssa()
  end
end, {
  nargs = '?',
  complete = function()
    return { 'install' }
  end,
  desc = 'Run PSScriptAnalyzer or install it: :PSSA [install]',
})

return M
