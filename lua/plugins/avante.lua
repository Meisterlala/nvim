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
  opts = function()
    ---@module 'avante'
    ---@type avante.Config
    return {
      provider = 'copilot',
      auto_suggestions_provider = 'copilot',

      providers = {
        copilot = {
          model = 'gpt-5-mini',
        },
        openrouter = {
          __inherited_from = 'openai',
          endpoint = 'https://openrouter.ai/api/v1',
          model = 'qwen/qwen3-coder',
          api_key_name = 'AVANTE_OPENROUTER',
        },
        openai = {
          list_models = {
            { id = 'gpt-5', name = 'gpt-5', display_name = 'GPT-5' },
            { id = 'gpt-5-mini', name = 'gpt-5-mini', display_name = 'GPT-5 Mini' },
            { id = 'gpt-4o', name = 'gpt-4o', display_name = 'GPT-4o' },
            { id = 'gpt-4o-mini', name = 'gpt-4o-mini', display_name = 'GPT-4o Mini' },
          },
        },
      },
      behaviour = {
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
        max_tokens = 32768,
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
          accept = '<M-l>',
          next = '<M-]>',
          prev = '<M-[>',
          dismiss = '<C-]>',
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
          enabled = true, -- true, false to enable/disable the header
          align = 'center', -- left, center, right for title
          rounded = true,
        },
      },
      suggestion = {
        debounce = 600,
        throttle = 600,
      },
      web_search_engine = {
        provider = 'tavily',
      },
    }
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
