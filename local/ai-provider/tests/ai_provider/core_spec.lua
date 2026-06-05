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

  it('selects and saves a model for a source id', function()
    ai_provider.setup {
      default_provider = 'ollama',
      providers = {
        ollama = { default_model = 'gemma4:e2b' },
      },
    }

    local core = require 'ai-provider.core'
    local original_load_preferences = core.load_preferences
    local original_save_preferences = core.save_preferences
    local original_list_models = core.list_models
    local original_select = vim.ui.select
    local prefs = {}

    rawset(core, 'load_preferences', function()
      return vim.deepcopy(prefs)
    end)
    rawset(core, 'save_preferences', function(next_prefs)
      prefs = vim.deepcopy(next_prefs)
      return true
    end)

    rawset(core, 'list_models', function(provider, callback)
      callback(provider == 'ollama' and { 'gemma4:e2b 64k' } or {})
    end)
    rawset(vim.ui, 'select', function(items, _, on_choice)
      on_choice(items[1])
    end)

    assert.is_true(ai_provider.register_source 'ai-commit')
    ai_provider.select_source_model 'ai-commit'

    rawset(core, 'load_preferences', original_load_preferences)
    rawset(core, 'save_preferences', original_save_preferences)
    rawset(core, 'list_models', original_list_models)
    rawset(vim.ui, 'select', original_select)

    assert.are.same({ provider = 'ollama', model = 'gemma4:e2b 64k', label = 'ollama/gemma4:e2b 64k' }, prefs.sources['ai-commit'])
  end)

  it('stores model preferences per source id', function()
    ai_provider.setup {
      default_provider = 'ollama',
      providers = {
        ollama = { default_model = 'gemma4:e2b' },
      },
    }

    local core = require 'ai-provider.core'
    local original_load_preferences = core.load_preferences
    local original_save_preferences = core.save_preferences
    local prefs = {}

    rawset(core, 'load_preferences', function()
      return vim.deepcopy(prefs)
    end)
    rawset(core, 'save_preferences', function(next_prefs)
      prefs = vim.deepcopy(next_prefs)
      return true
    end)

    assert.is_true(ai_provider.register_source 'ai-commit')
    assert.are.same({ 'ai-commit' }, ai_provider.list_sources())
    assert.is_true(ai_provider.set_source_selection('ai-commit', 'ollama', 'gemma4:e2b 64k'))
    assert.are.same('gemma4:e2b 64k', ai_provider.get_selected_model('ollama', 'ai-commit'))
    assert.are.same({ provider = 'ollama', model = 'gemma4:e2b 64k', label = 'ollama/gemma4:e2b 64k' }, ai_provider.get_source_selection 'ai-commit')

    rawset(core, 'load_preferences', original_load_preferences)
    rawset(core, 'save_preferences', original_save_preferences)
  end)
end)
