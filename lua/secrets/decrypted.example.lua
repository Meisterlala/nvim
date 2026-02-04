-- Secrets file template
-- This file contains your age password and environment variables
-- rename it to decrypted.lua
-- Encrypt it with: :SecretManager encrypt <password>

return {
  password = 'your-age-password-here',
  env = {
    SECRET_ENV_VAR_1 = 'your-secret-value-1',
  },
}
