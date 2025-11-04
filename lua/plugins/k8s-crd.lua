--- @type LazySpec | LazySpec[]
return {
  'anasinnyk/nvim-k8s-crd',
  event = { 'BufReadPre', 'BufNewFile' },
  ft = 'yaml',
  dependencies = { 'neovim/nvim-lspconfig' },
  config = function()
    require('nvim-k8s-crd').setup {
      cache_dir = vim.fs.joinpath(vim.fn.stdpath 'data', 'k8s-crd-cache'),
      k8s = {
        file_mask = '*.yaml',
      },
    }
  end,
}
