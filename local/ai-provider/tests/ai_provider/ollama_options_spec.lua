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

  it('uses configured request timeout for streaming chat', function()
    local captured_timeout = nil
    package.loaded['ai-provider.curl'] = {
      stream_json_lines = function(request)
        captured_timeout = request.timeout
        request.callback(0)
        return { shutdown = function() end }
      end,
    }

    local ollama = require 'ai-provider.providers.ollama'

    ollama.chat {
      model = 'gemma4:e2b',
      prompt = 'Reply with exactly: ok',
      provider_config = {
        timeout = 180000,
      },
      callback = function() end,
    }

    assert.are.same(180000, captured_timeout)
  end)

  it('sends configured thinking mode for reasoning model profiles', function()
    ---@type table|nil
    local captured = nil
    package.loaded['ai-provider.curl'] = {
      stream_json_lines = function(request)
        captured = request.body
        request.on_json_line { model = 'qwen3.5:4b', message = { content = 'ok' }, done_reason = 'stop' }
        request.callback(0)
        return { shutdown = function() end }
      end,
    }

    local ollama = require 'ai-provider.providers.ollama'

    ollama.chat {
      model = 'qwen3.5:4b 256k',
      prompt = 'Reply with exactly: ok',
      provider_config = {
        models = {
          ['qwen3.5:4b 256k'] = {
            model = 'qwen3.5:4b',
            context_size = 1024 * 256,
            think = false,
          },
        },
      },
      callback = function() end,
    }

    assert.is_table(captured)
    ---@cast captured table
    assert.are.same('qwen3.5:4b', captured.model)
    assert.are.same(1024 * 256, captured.options.num_ctx)
    assert.are.same(false, captured.think)
  end)

  it('returns an error instead of partial output when ollama stops for length', function()
    package.loaded['ai-provider.curl'] = {
      stream_json_lines = function(request)
        request.on_json_line { model = 'gemma4:e2b', message = { content = 'Ref' }, done_reason = 'length' }
        request.callback(0)
        return { shutdown = function() end }
      end,
    }

    local ollama = require 'ai-provider.providers.ollama'
    local message = 'unset'
    local meta = nil

    ollama.chat {
      model = 'gemma4:e2b',
      prompt = 'large prompt',
      callback = function(result, result_meta)
        message = result
        meta = result_meta
      end,
    }

    assert.is_nil(message)
    assert.is_table(meta)
    ---@cast meta table
    assert.are.same('length', meta.done_reason)
    assert.matches('length limit', meta.error)
  end)

  it('emits standardized thinking and generating status events', function()
    package.loaded['ai-provider.curl'] = {
      stream_json_lines = function(request)
        request.on_json_line { model = 'gemma4:e2b', message = { thinking = 'thinking...' }, eval_count = 7, eval_duration = 1000000000 }
        request.on_json_line { model = 'gemma4:e2b', message = { content = 'ok' }, eval_count = 9, eval_duration = 1000000000 }
        request.on_json_line { model = 'gemma4:e2b', done_reason = 'stop', eval_count = 9, eval_duration = 1000000000 }
        request.callback(0)
        return { shutdown = function() end }
      end,
    }

    local ollama = require 'ai-provider.providers.ollama'
    local statuses = {}

    ollama.chat {
      model = 'gemma4:e2b',
      prompt = 'Reply with exactly: ok',
      on_status = function(status)
        table.insert(statuses, status)
      end,
      callback = function() end,
    }

    vim.wait(1000, function()
      return #statuses >= 4
    end, 10)

    assert.are.same('context', statuses[1].phase)
    assert.are.same('thinking', statuses[2].phase)
    assert.are.same(7, statuses[2].tokens_per_second)
    assert.are.same('generating', statuses[3].phase)
    assert.are.same(9, statuses[3].tokens_per_second)
    assert.are.same('done', statuses[4].phase)
  end)

  it('estimates live tokens per second before final ollama metrics arrive', function()
    package.loaded['ai-provider.curl'] = {
      stream_json_lines = function(request)
        request.on_json_line { model = 'gemma4:e2b', message = { thinking = 'thinking...' } }
        request.on_json_line { model = 'gemma4:e2b', message = { content = 'ok' } }
        request.on_json_line { model = 'gemma4:e2b', done_reason = 'stop', eval_count = 9, eval_duration = 1000000000 }
        request.callback(0)
        return { shutdown = function() end }
      end,
    }

    local ollama = require 'ai-provider.providers.ollama'
    local statuses = {}

    ollama.chat {
      model = 'gemma4:e2b',
      prompt = 'Reply with exactly: ok',
      on_status = function(status)
        table.insert(statuses, status)
      end,
      callback = function() end,
    }

    vim.wait(1000, function()
      return #statuses >= 4
    end, 10)

    assert.are.same('context', statuses[1].phase)
    assert.are.same('thinking', statuses[2].phase)
    assert.is_number(statuses[2].tokens_per_second)
    assert.are.same('generating', statuses[3].phase)
    assert.is_number(statuses[3].tokens_per_second)
    assert.are.same('done', statuses[4].phase)
    assert.are.same(9, statuses[4].tokens_per_second)
  end)

  it('checks loaded models before chat and skips loading status when resident', function()
    package.loaded['ai-provider.curl'] = {
      json = function(request)
        assert.matches('/api/ps$', request.url)
        request.callback { status = 200, json = { models = { { name = 'gemma4:e2b' } } } }
        return { shutdown = function() end }
      end,
      stream_json_lines = function(request)
        request.on_json_line { model = 'gemma4:e2b', message = { content = 'ok' } }
        request.callback(0)
        return { shutdown = function() end }
      end,
    }

    local ollama = require 'ai-provider.providers.ollama'
    local statuses = {}

    ollama.chat {
      model = 'gemma4:e2b',
      prompt = 'Reply with exactly: ok',
      on_status = function(status)
        table.insert(statuses, status.phase)
      end,
      callback = function() end,
    }

    vim.wait(1000, function()
      return #statuses >= 3
    end, 10)

    assert.are.same('loaded', statuses[1])
    assert.are.same('context', statuses[2])
    assert.are.same('generating', statuses[3])
  end)

  it('checks loaded models before chat and reports loading when absent', function()
    package.loaded['ai-provider.curl'] = {
      json = function(request)
        assert.matches('/api/ps$', request.url)
        request.callback { status = 200, json = { models = {} } }
        return { shutdown = function() end }
      end,
      stream_json_lines = function(request)
        request.on_json_line { model = 'gemma4:e2b', message = { content = 'ok' } }
        request.callback(0)
        return { shutdown = function() end }
      end,
    }

    local ollama = require 'ai-provider.providers.ollama'
    local statuses = {}

    ollama.chat {
      model = 'gemma4:e2b',
      prompt = 'Reply with exactly: ok',
      on_status = function(status)
        table.insert(statuses, status.phase)
      end,
      callback = function() end,
    }

    vim.wait(1000, function()
      return #statuses >= 4
    end, 10)

    assert.are.same('loading', statuses[1])
    assert.are.same('context', statuses[2])
    assert.are.same('generating', statuses[3])
  end)
end)
