-- Custom image preview using Telescope + chafa
-- Windows-compatible solution for MSYS2 Mintty and SSH

local M = {}

-- Configuration（跨平台、零寫死：一律從 PATH 解析工具）
-- chafa / fd 的所在目錄由 configs.bootstrap.setup_search_tools() 在啟動時補進 PATH
-- （winget / msys2 / scoop / cargo …），這裡只認 PATH 上的工具，找不到就退回裸名
-- （picker 啟動時自然失敗、不會崩潰）。詳見 docs/RIPGREP_FD_PATH_SETUP.md。
local function tool(name)
  if vim.fn.executable(name) == 1 then return vim.fn.exepath(name) end
  return name  -- 裸名：仍不在 PATH 上時 picker 啟動失敗即可，不寫死任何磁碟/版本路徑
end

M.config = {
  chafa_path = tool("chafa"),
  fd_path    = tool("fd"),
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
