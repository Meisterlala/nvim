--- @type LazySpec | LazySpec[]
return {
  'anasinnyk/nvim-k8s-crd',
  ft = { 'yaml' },
  dependencies = { 'neovim/nvim-lspconfig' },
  config = function()
    -- Check if kubectl is installed, if not, skip the setup
    if vim.fn.executable 'kubectl' == 0 then
      return
    end
    require('nvim-k8s-crd').setup {
      cache_dir = vim.fs.joinpath(vim.fn.stdpath 'data', 'k8s-crd-cache'),
      k8s = {
        file_mask = '*.yaml',
      },
    }
  end,
}
