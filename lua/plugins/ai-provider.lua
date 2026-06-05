--- @type LazySpec
return {
  dir = vim.fn.stdpath 'config' .. '/local/ai-provider',
  name = 'ai-provider',
  event = 'VeryLazy',
  cmd = { 'AIProvider' },
  dependencies = { 'nvim-lua/plenary.nvim' },
  opts = {
    default_provider = 'ollama',
    providers = {
      ollama = {
        default_model = 'gemma4:e4b',
        context_size = 1024 * 8,
        load_timeout = 120000,
        keep_alive = '1h',
        models = {
          ['gemma4:e2b 32k'] = {
            model = 'gemma4:e2b',
            context_size = 1024 * 32,
          },
          ['gemma4:e2b 64k'] = {
            model = 'gemma4:e2b',
            context_size = 1024 * 64,
          },
          ['qwen3.5:4b 128k'] = {
            model = 'qwen3.5:4b',
            context_size = 1024 * 128,
            think = false,
          },
          ['qwen3.5:4b 256k'] = {
            model = 'qwen3.5:4b',
            context_size = 1024 * 256,
            think = false,
          },
        },
      },
    },
  },
  keys = {
    {
      '<leader>pm',
      function()
        require('ai-provider').select_source_model()
      end,
      desc = 'AI [P]rovider Source [M]odel',
    },
    {
      '<leader>pM',
      function()
        require('ai-provider').select_model()
      end,
      desc = 'AI [P]rovider Default [M]odel',
    },
    {
      '<leader>pd',
      '<cmd>AIProvider default<cr>',
      desc = 'AI [P]rovider [D]efault',
    },
    {
      '<leader>pc',
      '<cmd>AIProvider ollama check<cr>',
      desc = 'AI [P]rovider [C]heck Ollama',
    },
    {
      '<leader>pl',
      '<cmd>AIProvider models<cr>',
      desc = 'AI [P]rovider [L]ist Models',
    },
  },
  config = function(_, opts)
    require('ai-provider').setup(opts)
  end,
}
