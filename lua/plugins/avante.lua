-- Import the model fetcher utility
local model_fetcher = require 'model_fetcher'

--- @type LazySpec
return {
  'yetone/avante.nvim',
  event = 'VeryLazy',
  version = false, -- Never set to "*"
  -- Build function
  build = vim.fn.has 'win32' == 1 and 'powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false' or 'make',
  config = function()
    ---@module 'avante'
    ---@type avante.Config
    local opt = {
      -- Default provider
      provider = 'opencode',
      auto_suggestions_provider = 'copilot',
      -- ACP Provider Configuration - Integration with Claude Code
      acp_providers = {
        ['claude-code'] = {
          command = 'npx',
          args = { '@zed-industries/claude-code-acp' },
          env = {
            NODE_NO_WARNINGS = '1',
            ANTHROPIC_API_KEY = os.getenv 'ANTHROPIC_API_KEY',
          },
        },
        ['opencode'] = {
          command = 'opencode',
          args = { 'acp' },
        },
      },

      -- Provider configurations
      providers = {
        -- OpenCode ACP Provider (also in acp_providers)
        -- This dummy entry prevents errors when ACP is the active provider
        opencode = {
          __inherited_from = 'openai', -- Required by avante, but not actually used for ACP
          model = 'default',
          hide_in_model_selector = true, -- Hide from model selector since it's ACP
        },

        -- Copilot for auto-suggestions
        copilot = {
          model = 'gpt-4o-2024-11-20',
        },

        -- OpenRouter with dynamic model loading
        openrouter = {
          __inherited_from = 'openai',
          endpoint = 'https://openrouter.ai/api/v1',
          api_key_name = 'AVANTE_OPENROUTER_API_KEY',
          model = 'anthropic/claude-sonnet-4-20250514',
          model_names = {
            'anthropic/claude-sonnet-4-20250514',
            'deepseek/deepseek-chat-v3.1',
            'x-ai/grok-code-fast-1',
            'qwen/qwen3-coder',
            'openai/gpt-4o',
            'google/gemini-2.5-flash-exp',
          },
        },

        -- Cerebro (if you still use it)
        cerebro = {
          __inherited_from = 'openai',
          endpoint = 'https://chat.cerebroai.de/api/v1',
          api_key_name = 'AVANTE_CEREBRO_API_KEY',
          model = 'gemini-3-pro-preview',
          model_names = {
            'gemini-3-pro-preview',
            'gemini-2.5-flash',
            'gpt-5-chat-latest',
            'gpt-4o',
          },
        },
      },

      -- Behavior settings
      behaviour = {
        auto_suggestions = false, -- Enable/disable inline suggestions
        auto_set_keymaps = true,
        auto_apply_diff_after_generation = false,
        support_paste_from_clipboard = false,
      },

      -- Prompt logger for debugging
      prompt_logger = {
        enabled = true,
        log_dir = vim.fn.stdpath 'cache' .. '/avante_prompts',
        next_prompt = {
          normal = '<C-n>',
          insert = '<C-n>',
        },
        prev_prompt = {
          normal = '<C-p>',
          insert = '<C-p>',
        },
      },

      -- History configuration
      history = {
        max_tokens = 327680,
      },

      -- Keymaps
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
          close_from_input = { '<Esc>' },
        },
      },

      --- @class AvanteHintsConfig
      hints = { enabled = true },

      -- Window configuration
      windows = {
        ---@type "right" | "left" | "top" | "bottom"
        position = 'right',
        wrap = true,
        width = 35, -- % of available width
        sidebar_header = {
          enabled = true,
          align = 'center',
          rounded = true,
        },
      },

      -- Suggestion settings
      suggestion = {
        debounce = 500,
        throttle = 800,
      },
    }

    -- Load cached models synchronously if available
    local openrouter_cached = model_fetcher.load_cached_models 'openrouter'
    if openrouter_cached and #openrouter_cached > 0 then
      opt.providers.openrouter.model_names = openrouter_cached
    end

    local cerebro_cached = model_fetcher.load_cached_models 'cerebro'
    if cerebro_cached and #cerebro_cached > 0 then
      opt.providers.cerebro.model_names = cerebro_cached
    end

    -- Setup Avante with loaded configuration (using cached models if available)
    require('avante').setup(opt)

    -- Fetch models in the background to update cache for next session
    -- This happens asynchronously and won't block usage
    model_fetcher.fetch_openrouter_models(function(models)
      -- Models will be cached and available on next restart
    end)

    model_fetcher.fetch_cerebro_models(function(models)
      -- Models will be cached and available on next restart
    end)

    -- Additional keymaps for Avante
    vim.keymap.set({ 'n', 'v' }, '<leader>aa', function()
      require('avante.api').ask()
    end, { desc = '[A]vante [A]sk' })

    vim.keymap.set('n', '<leader>ac', function()
      vim.cmd 'AvanteChat'
    end, { desc = '[A]vante [C]hat' })

    vim.keymap.set('n', '<leader>ar', function()
      require('avante.api').refresh()
    end, { desc = '[A]vante [R]efresh' })

    vim.keymap.set('v', '<leader>ae', function()
      require('avante.api').edit()
    end, { desc = '[A]vante [E]dit' })

    -- Provider switcher that works with both ACP and regular providers
    vim.keymap.set('n', '<leader>ap', function()
      local Config = require 'avante.config'
      local providers = {}

      -- Add ACP providers
      for name, _ in pairs(Config.acp_providers or {}) do
        table.insert(providers, { name = name, type = 'acp' })
      end

      -- Add regular providers
      for name, _ in pairs(Config.providers or {}) do
        if name ~= 'opencode' and name ~= 'copilot' then -- Exclude ACP entries and copilot
          table.insert(providers, { name = name, type = 'regular' })
        end
      end

      -- Use vim.ui.select to show provider picker
      vim.ui.select(providers, {
        prompt = 'Select Provider:',
        format_item = function(item)
          return item.name .. ' (' .. item.type .. ')'
        end,
      }, function(choice)
        if choice then
          require('avante.providers').refresh(choice.name)
          vim.notify('Switched to provider: ' .. choice.name, vim.log.levels.INFO)
        end
      end)
    end, { desc = '[A]vante [P]rovider switch' })

    -- Zen mode alias for terminal
    vim.api.nvim_create_user_command('AvanteZen', function()
      require('avante.api').zen_mode()
    end, { desc = 'Start Avante in Zen mode' })
  end,

  dependencies = {
    -- Required dependencies
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',

    -- File selector (pick one or multiple)
    'nvim-telescope/telescope.nvim',
    -- 'ibhagwan/fzf-lua',
    -- 'echasnovski/mini.pick',

    -- Input provider (recommended)
    {
      'folke/snacks.nvim',
      opts = {
        input = {},
        picker = {},
        terminal = {},
      },
    },
    -- 'stevearc/dressing.nvim',

    -- Icons
    'nvim-tree/nvim-web-devicons',

    -- Completion
    'hrsh7th/nvim-cmp',

    -- Copilot integration
    'zbirenbaum/copilot.lua',

    -- Image pasting support
    {
      'HakonHarnes/img-clip.nvim',
      event = 'VeryLazy',
      opts = {
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
          use_absolute_path = true,
        },
      },
    },

    -- Markdown rendering for Avante
    {
      'MeanderingProgrammer/render-markdown.nvim',
      opts = {
        file_types = { 'markdown', 'Avante' },
      },
      ft = { 'markdown', 'Avante' },
    },
  },
}
