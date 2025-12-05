-- Custom image preview using Telescope + chafa
-- Windows-compatible solution for MSYS2 Mintty and SSH

local M = {}

-- Configuration
M.config = {
  chafa_path = "C:\\msys64_2\\ucrt64\\bin\\chafa.exe",
  fd_path = "C:\\msys64_2\\ucrt64\\bin\\fd.exe",
  image_extensions = { "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "ico", "tiff", "tif" },
}

-- Create a custom previewer for images using chafa
local function create_image_previewer()
  local previewers = require("telescope.previewers")
  local putils = require("telescope.previewers.utils")

  return previewers.new_termopen_previewer({
    get_command = function(entry)
      local path = entry.value or entry.path or entry[1]
      if not path then
        return nil
      end

      -- Return command as table
      return {
        M.config.chafa_path,
        "-f", "symbols",
        "-s", "80x40",
        "--animate", "off",
        "--colors", "256",
        path
      }
    end,
  })
end

-- Create a Telescope picker for images
function M.find_images()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  -- Build fd command arguments as a table
  local fd_args = { "--type", "f", "--hidden", "--no-ignore" }

  -- Add extension filters
  for _, ext in ipairs(M.config.image_extensions) do
    table.insert(fd_args, "-e")
    table.insert(fd_args, ext)
  end

  pickers.new({}, {
    prompt_title = "圖片瀏覽器 (Image Browser)",
    finder = finders.new_oneshot_job(
      vim.tbl_flatten({ M.config.fd_path, fd_args }),
      {}
    ),
    sorter = conf.file_sorter({}),
    previewer = create_image_previewer(),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          -- Open the image file in Neovim
          vim.cmd("edit " .. vim.fn.fnameescape(selection.value))
        end
      end)
      return true
    end,
  }):find()
end

return M
