--- @param cb fun(models: string[])
local function get_openrouter_models(cb)
  local curl = require 'plenary.curl'
  local log = (require 'plenary.log')
  local json = vim.json

  -- where to store cache
  local cache_file = vim.fn.stdpath 'cache' .. '/openrouter_models.json'

  -- check cache first
  local function load_cache()
    local f = io.open(cache_file, 'r')
    if not f then
      return nil
    end
    local content = f:read '*a'
    f:close()
    local ok, data = pcall(json.decode, content)
    if not ok or not data then
      return nil
    end

    -- expire after 1 day
    if os.time() - (data.timestamp or 0) > 24 * 60 * 60 then
      log.debug 'Old cache'
      return nil
    end
    return data.models
  end

  -- save cache
  local function save_cache(models)
    local f = io.open(cache_file, 'w')
    if not f then
      return
    end
    f:write(json.encode {
      timestamp = os.time(),
      models = models,
    })
    f:close()
  end

  -- try cache
  local cached = load_cache()
  if cached then
    log.debug 'Loading from cache'
    cb(cached)
    return
  end

  -- fallback to API call
  curl.get('https://openrouter.ai/api/v1/models', {
    headers = {
      ['Authorization'] = 'Bearer ' .. os.getenv 'OPENROUTER_API_KEY',
      ['Content-Type'] = 'application/json',
    },
    callback = function(res)
      if res.status ~= 200 then
        vim.schedule(function()
          vim.notify('Failed to fetch OpenRouter models: ' .. res.status, vim.log.levels.ERROR)
        end)
        return
      end

      local ok, body = pcall(json.decode, res.body)
      if not ok or not body.data then
        vim.schedule(function()
          vim.notify('Error decoding OpenRouter response', vim.log.levels.ERROR)
        end)
        return
      end

      local models = {}
      for _, m in ipairs(body.data) do
        table.insert(models, m.id)
      end

      log.debug 'Loaded '
      save_cache(models)

      vim.schedule(function()
        cb(models)
      end)
    end,
  })
end

function really_cool()
  -- return 43
  -- Do something here AI:
end

return {
  'yetone/avante.nvim',
  -- Build function
  build = function()
    -- conditionally use the correct build system for the current OS
    if vim.fn.has 'win32' == 1 then
      return 'powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false'
    else
      return 'make'
    end
  end,
  event = 'VeryLazy',
  version = false, -- Never set this value to "*"! Never!
  config = function()
    ---@module 'avante'
    ---@type avante.Config
    local opt = {
      provider = 'openrouter',
      auto_suggestions_provider = 'copilot',

      providers = {
        copilot = {
          model = 'gpt-5-mini',
        },
        openrouter = {
          __inherited_from = 'openai',
          endpoint = 'https://openrouter.ai/api/v1',
          api_key_name = 'AVANTE_OPENROUTER',
          model = 'deepseek/deepseek-chat-v3.1',

          -- list_models = {
          --   { id = 'deepseek/deepseek-chat-v3.1', name = 'deepseek/deepseek-chat-v3' },
          --   { id = 'qwen/qwen3-coder', name = 'qwen/qwen3-coder' },
          --   { id = 'openai/gpt-5', name = 'openai/gpt-5' },
          --   { id = 'moonshotai/kimi-k2', name = 'moonshotai/kimi-k2' },
          --   { id = 'google/gemini-2.5-flash', name = 'google/gemini-2.5-flash' },
          -- },
          model_names = {
            'deepseek/deepseek-chat-v3.1',
            'qwen/qwen3-coder',
            'openai/gpt-5',
            'moonshotai/kimi-k2',
            'google/gemini-2.5-flash',
          },
        },
        -- openai = {
        -- list_models = {
        --   { id = 'gpt-5', name = 'gpt-5' },
        --   { id = 'gpt-5-mini', name = 'gpt-5-mini' },
        --   { id = 'gpt-4o', name = 'gpt-4o' },
        --   { id = 'gpt-4o-mini', name = 'gpt-4o-mini' },
        -- },
        -- extra_request_body = {},
        -- },
      },
      behaviour = {
        auto_suggestions = true,

        auto_set_keymaps = true,
        auto_apply_diff_after_generation = false,
        support_paste_from_clipboard = false,
      },
      prompt_logger = { -- logs prompts to disk (timestamped, for replay/debugging)
        enabled = true, -- toggle logging entirely
        log_dir = vim.fn.stdpath 'cache' .. '/avante_prompts', -- directory where logs are saved
        next_prompt = {
          normal = '<C-n>', -- load the next (newer) prompt log in normal mode
          insert = '<C-n>',
        },
        prev_prompt = {
          normal = '<C-p>', -- load the previous (older) prompt log in normal mode
          insert = '<C-p>',
        },
      },
      history = {
        max_tokens = 327680,
      },
      mappings = {
        --- @class AvanteConflictMappings
        diff = {
          ours = 'co',
          theirs = 'ct',
          all_theirs = 'ca',
          both = 'cb',
          cursor = 'cc',
          next = ']x',
          prev = '[x',
        },
        suggestion = {
          accept = '<M-y>',
          next = '<M-n>',
          prev = '<M-p>',
          dismiss = '<M-x>',
        },
        jump = {
          next = ']]',
          prev = '[[',
        },
        submit = {
          normal = '<CR>',
          insert = '<C-s>',
        },
        cancel = {
          normal = { '<C-c>', '<Esc>', 'q' },
          insert = { '<C-c>' },
        },
        sidebar = {
          apply_all = 'A',
          apply_cursor = 'a',
          retry_user_request = 'r',
          edit_user_request = 'e',
          switch_windows = '<Tab>',
          reverse_switch_windows = '<S-Tab>',
          remove_file = 'd',
          add_file = '@',
          close = { '<Esc>', 'q' },
          close_from_input = { '<Esc>' }, -- e.g., { normal = "<Esc>", insert = "<C-d>" }
        },
      },
      --- @class AvanteHintsConfig
      hints = { enabled = false },
      windows = {
        ---@type "right" | "left" | "top" | "bottom"
        position = 'right', -- the position of the sidebar
        wrap = true, -- similar to vim.o.wrap
        width = 35, -- default % based on available width
        sidebar_header = {
          enabled = false, -- true, false to enable/disable the header
          align = 'center', -- left, center, right for title
          rounded = true,
        },
      },
      suggestion = {
        debounce = 500,
        throttle = 800,
      },
      web_search_engine = {
        provider = 'tavily',
      },
      rag_service = { -- RAG Service configuration
        enabled = false, -- Enables the RAG service
        host_mount = os.getenv 'HOME', -- Host mount path for the rag service (Docker will mount this path)
        runner = 'docker', -- Runner for the RAG service (can use docker or nix)
        llm = { -- Language Model (LLM) configuration for RAG service
          provider = 'openai', -- LLM provider
          endpoint = 'https://api.openai.com/v1', -- LLM API endpoint
          api_key = 'AVANTE_OPENAI_API_KEY', -- Environment variable name for the LLM API key
          model = 'gpt-4o-mini', -- LLM model name
          extra = nil, -- Additional configuration options for LLM
        },
        embed = { -- Embedding model configuration for RAG service
          provider = 'openai', -- Embedding provider
          endpoint = 'https://api.openai.com/v1', -- Embedding API endpoint
          api_key = 'AVANTE_OPENAI_API_KEY', -- Environment variable name for the embedding API key
          model = 'text-embedding-3-large', -- Embedding model name
          extra = nil, -- Additional configuration options for the embedding model
        },
        docker_extra_args = '', -- Extra arguments to pass to the docker command
      },
    }

    -- Fill model list
    get_openrouter_models(function(models)
      -- Expand
      opt.providers.openrouter.model_names = models
      require('avante').setup(opt)
    end)
  end,
  dependencies = {
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
    --- The below dependencies are optional,
    'nvim-telescope/telescope.nvim', -- for file_selector provider telescope
    'hrsh7th/nvim-cmp', -- autocompletion for avante commands and mentions
    'zbirenbaum/copilot.lua',
    {
      -- support for image pasting
      'HakonHarnes/img-clip.nvim',
      event = 'VeryLazy',
      opts = {
        -- recommended settings
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
          -- required for Windows users
          use_absolute_path = true,
        },
      },
    },
    {
      -- Make sure to set this up properly if you have lazy=true
      'MeanderingProgrammer/render-markdown.nvim',
      opts = {
        file_types = { 'markdown', 'Avante' },
      },
      ft = { 'markdown', 'Avante' },
    },
  },
}
