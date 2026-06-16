describe('copilot provider', function()
  local original_curl
  local original_path
  local original_log

  before_each(function()
    original_curl = package.loaded['ai-provider.curl']
    original_path = package.loaded['plenary.path']
    original_log = package.loaded['ai-provider.log']
    package.loaded['ai-provider.providers.copilot'] = nil
    package.loaded['ai-provider.log'] = {
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }

    local fake_path = {}
    function fake_path:joinpath()
      return self
    end
    function fake_path:exists()
      return true
    end
    function fake_path:read()
      return vim.json.encode { ['github.com'] = { oauth_token = 'oauth-token' } }
    end

    package.loaded['plenary.path'] = {
      new = function()
        return fake_path
      end,
    }
  end)

  after_each(function()
    package.loaded['ai-provider.curl'] = original_curl
    package.loaded['plenary.path'] = original_path
    package.loaded['ai-provider.log'] = original_log
    package.loaded['ai-provider.providers.copilot'] = nil
  end)

  it('streams chat completion deltas through provider chunks', function()
    local captured_body = nil
    package.loaded['ai-provider.curl'] = {
      json = function(request)
        assert.matches('/copilot_internal/v2/token$', request.url)
        request.callback {
          status = 200,
          json = {
            token = 'api-token',
            expires_at = os.time() + 60,
            endpoints = { api = 'https://copilot.example.test' },
          },
        }
        return { shutdown = function() end }
      end,
      stream_json_lines = function(request)
        captured_body = request.body
        request.on_json_line { model = 'gpt-4o', choices = { { delta = { content = 'he' } } } }
        request.on_json_line { model = 'gpt-4o', choices = { { delta = { content = 'llo' } } } }
        request.callback(0, nil, 200)
        return { shutdown = function() end }
      end,
    }

    local copilot = require 'ai-provider.providers.copilot'
    local chunks = {}
    local message = nil
    local meta = nil

    local job = copilot.chat {
      model = 'gpt-4o',
      prompt = 'Say hello',
      on_chunk = function(chunk)
        table.insert(chunks, chunk)
      end,
      callback = function(result, result_meta)
        message = result
        meta = result_meta
      end,
    }

    assert.is_table(job)
    assert.is_table(captured_body)
    ---@cast captured_body table
    assert.are.same(true, captured_body.stream)
    assert.are.same('hello', table.concat(chunks, ''))
    assert.are.same('hello', message)
    assert.is_table(meta)
    ---@cast meta table
    assert.are.same('gpt-4o', meta.used_model)
  end)
end)
