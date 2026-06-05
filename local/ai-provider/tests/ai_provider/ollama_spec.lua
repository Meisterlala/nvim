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

local function run_command(command)
  local result = vim.system(command, { text = true }):wait()
  assert.are.same(0, result.code)
  return result.stdout or ''
end

local function unload_ollama_model(model)
  run_command {
    'curl',
    '--silent',
    '--show-error',
    '--request',
    'POST',
    '--header',
    'Content-Type: application/json',
    '--data',
    string.format('{"model":"%s","keep_alive":0}', model),
    'http://127.0.0.1:11434/api/generate',
  }
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
      max_tokens = 256,
      timeout = 30000,
      callback = function(result, result_meta)
        message = result
        meta = result_meta
        done = true
      end,
    })

    wait_for(function()
      return done
    end)
    assert.is_string(message)
    assert.is_true(#message > 0)
    assert.is_table(meta)
    ---@cast meta table
    assert.are.same('gemma4:e2b 32k', meta.requested_model)
    assert.are.same('gemma4:e2b', meta.used_model)
  end)

  it('streams response chunks', function()
    local done = false
    local chunks = {}
    local message = nil
    local meta = nil

    ai_provider.chat('ollama', {
      model = 'gemma4:e2b',
      prompt = 'Reply with exactly: ok',
      max_tokens = 16,
      timeout = 30000,
      on_chunk = function(chunk)
        table.insert(chunks, chunk)
      end,
      callback = function(result, result_meta)
        message = result
        meta = result_meta
        done = true
      end,
    })

    wait_for(function()
      return done
    end)
    assert.is_string(message)
    assert.is_true(#message > 0)
    assert.is_true(#chunks > 0)
    assert.are.same(message, table.concat(chunks, ''))
    assert.is_table(meta)
  end)

  it('returns an error when the prompt exceeds a small loaded context window', function()
    unload_ollama_model 'gemma4:e2b'

    local done = false
    ---@type string|nil
    local message = 'unset'
    ---@type table|nil
    local meta = nil
    local prompt = table.concat(vim.fn['repeat']({ 'context-overflow-token' }, 5000), ' ')

    ai_provider.chat('ollama', {
      model = 'gemma4:e2b',
      prompt = prompt,
      context_size = 2048,
      max_tokens = 32,
      timeout = 60000,
      callback = function(result, result_meta)
        message = result
        meta = result_meta
        done = true
      end,
    })

    wait_for(function()
      return done
    end, 70000)

    local ps = run_command { 'ollama', 'ps' }
    assert.matches('gemma4:e2b', ps)
    assert.matches('%s2048%s', ps)
    assert.is_nil(message)
    assert.is_table(meta)
    ---@cast meta table
    assert.are.same('length', meta.done_reason)
    assert.matches('length limit', meta.error)
  end)
end)
