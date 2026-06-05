local ai_provider = require 'ai-provider'

local config = {
  default_provider = 'ollama',
  providers = {
    ollama = {
      default_model = 'gemma4:e2b',
      context_size = 1024 * 8,
      keep_alive = '4h',
      models = {
        ['gemma4:e2b 32k'] = {
          model = 'gemma4:e2b',
          context_size = 1024 * 32,
        },
        ['gemma4:e2b 64k'] = {
          model = 'gemma4:e2b',
          context_size = 1024 * 64,
        },
      },
    },
  },
}

local function wait_for(done, timeout)
  local ok = vim.wait(timeout or 20000, function()
    return done()
  end, 50)
  assert.is_true(ok)
end

describe('ollama provider integration', function()
  before_each(function()
    ai_provider.setup(config)
  end)

  it('checks provider availability', function()
    local done = false
    local working = nil

    ai_provider.check('ollama', function(result)
      working = result
      done = true
    end, { force = true, timeout = 1000 })

    wait_for(function()
      return done
    end)
    assert.is_true(working)
  end)

  it('lists raw models and configured logical profiles', function()
    local done = false
    ---@type string[]|nil
    local models = nil

    ai_provider.list_models('ollama', function(result)
      models = result
      done = true
    end)

    wait_for(function()
      return done
    end)

    assert.is_table(models)
    ---@cast models string[]
    assert.is_true(vim.tbl_contains(models, 'gemma4:e2b'))
    assert.is_true(vim.tbl_contains(models, 'gemma4:e2b 32k'))
    assert.is_true(vim.tbl_contains(models, 'gemma4:e2b 64k'))
  end)

  it('runs a prompt through a logical model profile', function()
    local done = false
    local message = nil
    ---@type table|nil
    local meta = nil

    ai_provider.chat('ollama', {
      model = 'gemma4:e2b 32k',
      prompt = 'Reply with exactly: ok',
      max_tokens = 4,
      timeout = 10000,
      callback = function(result, result_meta)
        message = result
        meta = result_meta
        done = true
      end,
    })

    wait_for(function()
      return done
    end)
    assert.are.same('ok', message)
    assert.is_table(meta)
    ---@cast meta table
    assert.are.same('gemma4:e2b 32k', meta.requested_model)
    assert.are.same('gemma4:e2b', meta.used_model)
  end)

  it('streams response chunks', function()
    local done = false
    local chunks = {}
    local message = nil

    ai_provider.chat('ollama', {
      model = 'gemma4:e2b',
      prompt = 'Reply with exactly: ok',
      max_tokens = 4,
      timeout = 10000,
      on_chunk = function(chunk)
        table.insert(chunks, chunk)
      end,
      callback = function(result)
        message = result
        done = true
      end,
    })

    wait_for(function()
      return done
    end)
    assert.are.same('ok', message)
    assert.is_true(#chunks > 0)
    assert.are.same('ok', table.concat(chunks, ''))
  end)
end)
