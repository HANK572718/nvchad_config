require "nvchad.autocmds"

-- Force ensure Telescope max_results is applied
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.schedule(function()
      local ok, telescope_config = pcall(require, "telescope.config")
      if ok then
        -- Force set max_results if not already set
        if not telescope_config.values.max_results or telescope_config.values.max_results ~= 1000 then
          telescope_config.values.max_results = 1000
          vim.notify("Force applied: Telescope max_results = 1000", vim.log.levels.WARN)
        end
      end
    end)
  end,
})
