--- @type LazySpec | LazySpec[]
return {
  'CRAG666/code_runner.nvim',
  opts = {
    filetype = {
      python = 'python3 -u',
      javascript = 'node',
      typescript = 'deno run',
      rust = 'cargo run',
      go = 'go run',
      cpp = 'cd $dir && g++ $fileName -o $fileNameWithoutExt && $dir/$fileNameWithoutExt',
      c = 'cd $dir && gcc $fileName -o $fileNameWithoutExt && $dir/$fileNameWithoutExt',
      java = 'cd $dir && javac $fileName && java $fileNameWithoutExt',
      php = 'php',
      ruby = 'ruby',
      sh = 'bash',
      lua = 'lua',
    },
  },
  config = function(_, opts)
    require('code_runner').setup(opts)
  end,
  keys = {
    {
      '<leader>b',
      function()
        require('code_runner').run_code()
      end,
      desc = 'Run Code',
    },
  },
}
