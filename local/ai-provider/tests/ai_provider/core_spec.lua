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
    assert.is_truthy(ai_provider.get_provider_implementation 'ollama')
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

  it('select helper returns a provider/model reference without saving it globally', function()
    ai_provider.setup {
      default_provider = 'ollama',
      providers = {
        ollama = { default_model = 'gemma4:e2b' },
      },
    }

    local core = require 'ai-provider.core'
    local original_list_models = core.list_models
    local original_select = vim.ui.select
    local selected = nil

    rawset(core, 'list_models', function(provider, callback)
      callback(provider == 'ollama' and { 'gemma4:e2b 64k' } or {})
    end)
    rawset(vim.ui, 'select', function(items, _, on_choice)
      on_choice(items[1])
    end)

    ai_provider.select_helper(function(choice)
      selected = choice
    end)

    rawset(core, 'list_models', original_list_models)
    rawset(vim.ui, 'select', original_select)

    assert.are.same({ provider = 'ollama', model = 'gemma4:e2b 64k', label = 'ollama/gemma4:e2b 64k' }, selected)
    assert.are.same('gemma4:e2b', ai_provider.get_selected_model 'ollama')
  end)
end)
