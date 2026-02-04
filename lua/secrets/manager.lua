-- Secrets Manager with age encryption
-- Stores password and env vars in encrypted file
-- Auto-loads from decrypted plaintext on startup

local M = {}

-- Path to files
local ENCRYPTED_FILE = vim.fn.stdpath 'config' .. '/lua/secrets/secrets.enc'
local DECRYPTED_FILE = vim.fn.stdpath 'config' .. '/lua/secrets/decrypted.lua'

-- Encryption algorithm (chacha20 is modern and fast)
local CIPHER = 'chacha20'

---Load decrypted secrets file and return the table
---@return table|nil secrets {password = "...", env = {...}}
---@return string|nil error
local function load_decrypted_file()
  if vim.fn.filereadable(DECRYPTED_FILE) ~= 1 then
    return nil, 'Decrypted file not found'
  end

  local chunk, err = loadfile(DECRYPTED_FILE)
  if not chunk then
    return nil, 'Failed to load file: ' .. (err or 'unknown error')
  end

  local ok, result = pcall(chunk)
  if not ok then
    return nil, 'Failed to execute file: ' .. result
  end

  if type(result) ~= 'table' then
    return nil, 'File must return a table'
  end

  return result, nil
end

---Decrypt encrypted file with password
---@param password string
---@return boolean success
---@return string|nil error
function M.decrypt(password)
  if vim.fn.executable('openssl') ~= 1 then
    return false, 'openssl not found. Install with: sudo pacman -S openssl'
  end

  if vim.fn.filereadable(ENCRYPTED_FILE) ~= 1 then
    return false, 'Encrypted file not found: ' .. ENCRYPTED_FILE
  end

  if not password or password == '' then
    return false, 'Password required'
  end

  -- Use openssl for decryption
  local cmd = string.format(
    'openssl enc -%s -d -pbkdf2 -in %s -out %s -pass pass:%s 2>&1',
    CIPHER,
    vim.fn.shellescape(ENCRYPTED_FILE),
    vim.fn.shellescape(DECRYPTED_FILE),
    vim.fn.shellescape(password)
  )

  local result = vim.fn.system(cmd)
  local success = vim.v.shell_error == 0

  if success then
    vim.notify('Decrypted to: ' .. DECRYPTED_FILE, vim.log.levels.INFO)
    return true, nil
  else
    return false, 'Decryption failed. Check your password: ' .. result
  end
end

---Encrypt decrypted file
---@param new_password string|nil Optional new password (uses stored password if not provided)
---@return boolean success
---@return string|nil error
function M.encrypt(new_password)
  if vim.fn.executable('openssl') ~= 1 then
    return false, 'openssl not found. Install with: sudo pacman -S openssl'
  end

  local secrets, err = load_decrypted_file()
  if not secrets then
    return false, 'Cannot load decrypted file: ' .. (err or 'unknown error')
  end

  -- Use new password or stored password
  local password = new_password or secrets.password
  if not password or password == '' then
    return false, 'No password found. Use: SecretManager encrypt <password>'
  end

  -- Update password in file if new password provided
  if new_password and new_password ~= secrets.password then
    secrets.password = new_password

    -- Read current file content
    local file = io.open(DECRYPTED_FILE, 'r')
    if not file then
      return false, 'Failed to read file'
    end
    local content = file:read('*a')
    file:close()

    -- Replace password line
    content = content:gsub('password%s*=%s*[^\n]+', 'password = ' .. string.format('%q', new_password))

    -- Write back
    file = io.open(DECRYPTED_FILE, 'w')
    if not file then
      return false, 'Failed to write file'
    end
    file:write(content)
    file:close()
  end

  -- Use openssl for symmetric encryption
  local cmd = string.format(
    'openssl enc -%s -salt -pbkdf2 -in %s -out %s -pass pass:%s 2>&1',
    CIPHER,
    vim.fn.shellescape(DECRYPTED_FILE),
    vim.fn.shellescape(ENCRYPTED_FILE),
    vim.fn.shellescape(password)
  )

  local result = vim.fn.system(cmd)
  local success = vim.v.shell_error == 0

  if success then
    vim.notify('Encrypted to: ' .. ENCRYPTED_FILE, vim.log.levels.INFO)
    if new_password then
      vim.notify('Password updated', vim.log.levels.INFO)
    end
    return true, nil
  else
    return false, 'Encryption failed: ' .. result
  end
end

---Load environment variables from decrypted file
---@param silent boolean|nil Don't show notifications if true
---@return boolean success
---@return string|nil error
function M.load(silent)
  local secrets, err = load_decrypted_file()

  if not secrets then
    if not silent then
      vim.notify('No decrypted secrets file found', vim.log.levels.WARN)
      vim.notify('Run: SecretManager decrypt <password>', vim.log.levels.INFO)
    end
    return false, err
  end

  if not secrets.env or type(secrets.env) ~= 'table' then
    if not silent then
      vim.notify('No env variables found in secrets file', vim.log.levels.ERROR)
    end
    return false, 'Invalid secrets format'
  end

  -- Load into environment
  local count = 0
  for key, value in pairs(secrets.env) do
    vim.env[key] = value
    count = count + 1
  end

  if not silent then
    vim.notify(string.format('Loaded %d secret(s) into environment', count), vim.log.levels.INFO)
  end

  return true, nil
end

---Auto-load on startup (shows hint if no decrypted file exists)
function M.auto_load()
  -- No secret files to load
  if vim.fn.filereadable(DECRYPTED_FILE) ~= 1 and vim.fn.filereadable(ENCRYPTED_FILE) ~= 1 then
    return
  end

  -- Hint to decrypt if no decrypted file
  if vim.fn.filereadable(DECRYPTED_FILE) ~= 1 then
    vim.defer_fn(function()
      vim.notify('Run: SecretManager decrypt <password>', vim.log.levels.WARN)
    end, 500)
    return
  end

  -- Warn if decrypted file exists without encrypted file
  if vim.fn.filereadable(ENCRYPTED_FILE) ~= 1 and vim.fn.filereadable(DECRYPTED_FILE) == 1 then
    vim.defer_fn(function()
      vim.notify('Decrypted secrets file found without corresponding encrypted file. Run :SecretManager encrypt <password>', vim.log.levels.WARN)
    end, 500)
  end

  -- Load silently if file exists
  return M.load(true)
end

-- Create user command
vim.api.nvim_create_user_command('SecretManager', function(opts)
  local args = vim.split(opts.args, '%s+')
  local cmd = args[1]

  if cmd == 'decrypt' then
    local password = args[2]

    -- Try to get password from existing decrypted file if not provided
    if not password then
      local secrets = load_decrypted_file()
      if secrets and secrets.password then
        password = secrets.password
      else
        vim.notify('Usage: SecretManager decrypt <password>', vim.log.levels.ERROR)
        return
      end
    end

    local ok, err = M.decrypt(password)
    if not ok then
      vim.notify('Decrypt failed: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
    end

  elseif cmd == 'encrypt' then
    local new_password = args[2]
    local ok, err = M.encrypt(new_password)
    if not ok then
      vim.notify('Encrypt failed: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
    end

  elseif cmd == 'load' or cmd == 'refresh' then
    M.load()
  elseif cmd == 'status' then
    local has_encrypted = vim.fn.filereadable(ENCRYPTED_FILE) == 1
    local has_decrypted = vim.fn.filereadable(DECRYPTED_FILE) == 1

    local status = 'Secrets Manager Status:\n'
    status = status .. '  Encrypted file: ' .. (has_encrypted and 'yes' or 'no') .. '\n'
    status = status .. '  Decrypted file: ' .. (has_decrypted and 'yes' or 'no')

    if has_decrypted then
      local secrets = load_decrypted_file()
      if secrets and secrets.env then
        local count = 0
        for _ in pairs(secrets.env) do
          count = count + 1
        end
        status = status .. '\n  Env variables: ' .. count
      end
    end

    vim.notify(status, vim.log.levels.INFO)
  end
end, {
  nargs = '*',
  complete = function(_, line)
    local cmds = { 'decrypt', 'encrypt', 'load', 'refresh', 'status' }
    local args = vim.split(line, '%s+')
    if #args <= 2 then
      return cmds
    end
    return {}
  end,
})

return M
