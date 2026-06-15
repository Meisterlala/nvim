local ai_provider = require 'ai-provider'
local core = require 'ai-provider.core'

local function preferences_path()
  return vim.fn.stdpath 'data' .. '/ai-provider-preferences.json'
end

describe('ai-provider core', function()
  local original_preferences

  before_each(function()
    local file = io.open(preferences_path(), 'r')
    if file then
      original_preferences = file:read '*a'
      file:close()
    else
      original_preferences = nil
    end
    os.remove(preferences_path())
  end)

  after_each(function()
    if original_preferences then
      local file = assert(io.open(preferences_path(), 'w'))
      file:write(original_preferences)
      file:close()
    else
      os.remove(preferences_path())
    end
  end)

  it('exposes only configured providers', function()
    ai_provider.setup {
      default_provider = 'ollama',
      providers = {
        ollama = { default_model = 'gemma4:e2b' },
      },
    }

    assert.are.same({ 'ollama' }, ai_provider.list_providers())
    assert.is_truthy(ai_provider.get_provider 'ollama')
    assert.is_nil(ai_provider.get_provider 'codex')
  end)

  it('rejects missing default provider config', function()
    local ok, err = pcall(ai_provider.setup, {
      default_provider = 'codex',
      providers = {
        ollama = { default_model = 'gemma4:e2b' },
      },
    })

    assert.is_false(ok)
    assert.matches('default_provider must be configured', err)
  end)

  it('accepts github as a copilot provider alias', function()
    ai_provider.setup {
      default_provider = 'copilot',
      providers = {
        copilot = { default_model = 'auto' },
      },
    }

    assert.is_truthy(ai_provider.get_provider 'github')
    assert.are.same({ default_model = 'auto' }, ai_provider.get_provider_config 'github')
    assert.is_true(ai_provider.set_default_provider 'github')
    assert.are.same('copilot', ai_provider.get_default_provider())
    assert.is_true(ai_provider.set_selected_model('github', 'auto'))
    assert.are.same('auto', ai_provider.get_selected_model 'github')
    assert.is_true(ai_provider.set_source_selection('ai-commit', 'github', 'default'))
    assert.are.same('copilot', core.load_preferences().sources['ai-commit'].provider)
  end)

  it('keeps source default as a preference sentinel', function()
    ai_provider.setup {
      default_provider = 'ollama',
      providers = {
        ollama = { default_model = 'gemma4:e2b' },
      },
    }

    assert.is_true(ai_provider.set_source_selection('ai-commit', 'ollama', 'default'))
    assert.are.same('default', core.load_preferences().sources['ai-commit'].model)
    assert.are.same('gemma4:e2b', ai_provider.get_selected_model('ollama', 'ai-commit'))
    assert.are.same('gemma4:e2b', ai_provider.get_source_selection('ai-commit').model)

    ai_provider.setup {
      default_provider = 'ollama',
      providers = {
        ollama = { default_model = 'qwen3.5:4b' },
      },
    }

    assert.are.same('default', core.load_preferences().sources['ai-commit'].model)
    assert.are.same('qwen3.5:4b', ai_provider.get_selected_model('ollama', 'ai-commit'))
    assert.are.same('qwen3.5:4b', ai_provider.get_source_selection('ai-commit').model)
  end)

  it('does not persist resolved defaults during source chat', function()
    ai_provider.setup {
      default_provider = 'ollama',
      providers = {
        ollama = { default_model = 'gemma4:e2b' },
      },
    }
    assert.is_true(ai_provider.set_source_selection('ai-commit', 'ollama', 'default'))

    local provider = assert(ai_provider.get_provider 'ollama')
    local original_chat = provider.chat
    provider.chat = function(request)
      if request.callback then
        request.callback('ok', { requested_model = request.model, used_model = request.model, elapsed_ms = 0 })
      end
      return { shutdown = function() end }
    end

    local done = false
    ai_provider.chat {
      source_id = 'ai-commit',
      prompt = 'test',
      callback = function()
        done = true
      end,
    }

    provider.chat = original_chat

    assert.is_true(done)
    assert.are.same('default', core.load_preferences().sources['ai-commit'].model)
  end)
end)
