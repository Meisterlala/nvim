describe('ollama provider options', function()
  local original_curl

  before_each(function()
    original_curl = package.loaded['ai-provider.curl']
    package.loaded['ai-provider.providers.ollama'] = nil
  end)

  after_each(function()
    package.loaded['ai-provider.curl'] = original_curl
    package.loaded['ai-provider.providers.ollama'] = nil
  end)

  it('sends profile context size and provider keep_alive', function()
    ---@type table|nil
    local captured = nil
    package.loaded['ai-provider.curl'] = {
      stream_json_lines = function(request)
        captured = request.body
        request.on_json_line { model = 'gemma4:e2b', message = { content = 'ok' } }
        request.callback(0)
        return { shutdown = function() end }
      end,
    }

    local ollama = require 'ai-provider.providers.ollama'
    local done = false
    local message = nil

    ollama.chat {
      model = 'gemma4:e2b 64k',
      prompt = 'Reply with exactly: ok',
      max_tokens = 4,
      provider_config = {
        context_size = 1024 * 8,
        keep_alive = '4h',
        models = {
          ['gemma4:e2b 64k'] = {
            model = 'gemma4:e2b',
            context_size = 1024 * 64,
          },
        },
      },
      callback = function(result)
        message = result
        done = true
      end,
    }

    assert.is_true(done)
    assert.are.same('ok', message)
    assert.is_table(captured)
    ---@cast captured table
    assert.is_table(captured.options)
    assert.are.same('gemma4:e2b', captured.model)
    assert.are.same(4, captured.options.num_predict)
    assert.are.same(1024 * 64, captured.options.num_ctx)
    assert.are.same('4h', captured.keep_alive)
  end)

  it('lets request options override profile and provider options', function()
    ---@type table|nil
    local captured = nil
    package.loaded['ai-provider.curl'] = {
      stream_json_lines = function(request)
        captured = request.body
        request.callback(0)
        return { shutdown = function() end }
      end,
    }

    local ollama = require 'ai-provider.providers.ollama'

    ollama.chat {
      model = 'gemma4:e2b 32k',
      prompt = 'Reply with exactly: ok',
      context_size = 1024 * 16,
      keep_alive = '10m',
      provider_config = {
        context_size = 1024 * 8,
        keep_alive = '4h',
        models = {
          ['gemma4:e2b 32k'] = {
            model = 'gemma4:e2b',
            context_size = 1024 * 32,
          },
        },
      },
      callback = function() end,
    }

    assert.is_table(captured)
    ---@cast captured table
    assert.is_table(captured.options)
    assert.are.same(1024 * 16, captured.options.num_ctx)
    assert.are.same('10m', captured.keep_alive)
  end)
end)
