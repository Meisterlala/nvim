local ai_provider = require 'ai-provider'

describe('ai-provider core', function()
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

end)
