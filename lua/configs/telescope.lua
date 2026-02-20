-- Count files in a folder recursively (with early exit optimization)
-- Returns file count, stops counting after max_count is exceeded
local function count_files_in_folder(folder_path, max_count, current_count)
  current_count = current_count or 0

  local handle = vim.loop.fs_scandir(folder_path)
  if not handle then
    return current_count
  end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    -- Skip hidden files/folders and common system folders
    if name:match("^%.") or name == "node_modules" or name == "__pycache__" then
      goto continue
    end

    if type == "file" then
      current_count = current_count + 1
      -- Early exit if we've already exceeded the limit
      if current_count > max_count then
        return current_count
      end
    elseif type == "directory" then
      local sep = vim.fn.has("win32") == 1 and "\\" or "/"
      local subfolder_path = folder_path .. sep .. name
      current_count = count_files_in_folder(subfolder_path, max_count, current_count)
      -- Early exit if we've already exceeded the limit
      if current_count > max_count then
        return current_count
      end
    end

    ::continue::
  end

  return current_count
end

-- Scan project root for large folders (folders with > max_file_count files)
-- Returns array of folder names to ignore
local function scan_large_folders(max_file_count)
  local large_folders = {}

  -- Find git root directory
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>nul")[1]
  if vim.v.shell_error ~= 0 or not git_root then
    return large_folders
  end

  -- Convert Unix path to Windows path if needed
  if vim.fn.has("win32") == 1 then
    git_root = git_root:gsub("/", "\\")
  end

  local handle = vim.loop.fs_scandir(git_root)
  if not handle then
    return large_folders
  end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    -- Only check directories (skip files and .git)
    if type == "directory" and name ~= ".git" then
      local sep = vim.fn.has("win32") == 1 and "\\" or "/"
      local folder_path = git_root .. sep .. name
      local file_count = count_files_in_folder(folder_path, max_file_count, 0)

      if file_count > max_file_count then
        table.insert(large_folders, name .. "/")
      end
    end
  end

  return large_folders
end

-- Parse .gitignore and extract folder patterns (lines ending with /)
-- Only ignores folders, not individual files
local function parse_gitignore_folders()
  local patterns = {}

  -- Find git root directory
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>nul")[1]
  if vim.v.shell_error ~= 0 or not git_root then
    return patterns
  end

  local sep = vim.fn.has("win32") == 1 and "\\" or "/"
  local gitignore_path = git_root .. sep .. ".gitignore"

  -- Check if .gitignore exists
  if vim.fn.filereadable(gitignore_path) == 0 then
    return patterns
  end

  -- Read .gitignore file
  local lines = vim.fn.readfile(gitignore_path)

  for _, line in ipairs(lines) do
    -- Skip comments and empty lines
    if line:match("^%s*#") or line:match("^%s*$") then
      goto continue
    end

    -- Remove leading/trailing whitespace
    line = line:match("^%s*(.-)%s*$")

    -- Check if it's a folder (ends with /)
    if line:match("/$") then
      -- Convert gitignore pattern to Lua pattern
      -- Remove leading wildcards like **/ or */
      local pattern = line:gsub("^%*%*/", ""):gsub("^%*/", "")

      -- Escape special Lua pattern characters except * and ?
      pattern = pattern:gsub("([%.%-%+%[%]%(%)%$%^%%])", "%%%1")

      -- Convert gitignore wildcards to Lua patterns
      pattern = pattern:gsub("%*", ".*")  -- * -> .*
      pattern = pattern:gsub("%?", ".")   -- ? -> .

      table.insert(patterns, pattern)
    end

    ::continue::
  end

  return patterns
end

-- Get base folder ignore patterns (always applied)
local function get_base_patterns()
  return {
    -- Git internals
    ".git/",

    -- Common large folders that should always be ignored
    "node_modules/",
    "__pycache__/",
    ".pytest_cache/",
    ".mypy_cache/",
    ".tox/",
    "%.egg%-info/",

    -- IDE folders
    ".vscode/",
    ".idea/",

    -- Project-specific large folders (from TelescopeAnalyzeFolders)
    "wheel%-packages_before_1022/",
    "wheel%-packages/",
    "wheel%-packages_old/",
    "cache/",
    "results_ov_inferencer/",
    "logs/",
    "model_use/",
    "docs/",
    "API_logs/",

    -- Image folders (large amounts of images)
    "test_captures/",
    "test_captures.*",  -- Matches test_captures* pattern
    "data/",
  }
end

-- Smart previewer that detects images and uses chafa
local function create_smart_previewer()
  local previewers = require("telescope.previewers")
  local from_entry = require("telescope.from_entry")

  -- Image extensions to detect
  local image_extensions = {
    png = true, jpg = true, jpeg = true, gif = true,
    webp = true, bmp = true, svg = true, ico = true,
    tiff = true, tif = true,
  }

  -- Check if file is an image
  local function is_image(filepath)
    local ext = filepath:match("%.([^%.]+)$")
    return ext and image_extensions[ext:lower()]
  end

  -- Get default file previewer as fallback
  local default_previewer = previewers.vim_buffer_cat.new({})

  return previewers.new_termopen_previewer({
    get_command = function(entry)
      local path = from_entry.path(entry, true)
      if not path then
        return nil
      end

      -- If it's an image, use chafa
      if is_image(path) then
        local chafa_cmd = vim.fn.has("win32") == 1 and "C:\\msys64_2\\ucrt64\\bin\\chafa.exe" or "chafa"
        return {
          chafa_cmd,
          "-f", "symbols",
          "-s", "80x40",
          "--animate", "off",
          "--colors", "256",
          path
        }
      end

      -- For non-images, return nil to use default buffer previewer
      return nil
    end,
  })
end

local options = {
  defaults = {
    -- Static ignore patterns (no dynamic scanning for stability)
    file_ignore_patterns = get_base_patterns(),

    -- Safety net: cap results regardless of search tool
    max_results = 2000,

    -- Use smart previewer that handles images
    buffer_previewer_maker = nil, -- Use default for buffers
    file_previewer = create_smart_previewer,

    -- Additional settings
    path_display = { "truncate" },
    sorting_strategy = "ascending",
    layout_strategy = "vertical",
    layout_config = {
      prompt_position = "top",
      width = 0.95,
      height = 0.95,
      preview_cutoff = 1,      -- 幾乎永不停用預覽（適合小螢幕大字體）
      preview_height = 0.5,    -- 預覽與列表各佔 50%
      mirror = false,          -- 預覽在上，結果在下
    },
  },
  pickers = {
    find_files = {
      hidden = false,
      follow = false,

      -- fd 尊重 .gitignore（預設行為，不需額外設定）
      -- Linux/Mac：timeout 3 fd ...（真正的 3 秒 timeout）
      -- Windows：--max-results 2000（無對應 timeout 指令）
      -- fd 未安裝：nil（telescope fallback 到內建 find）
      find_command = (function()
        if vim.fn.executable("fd") ~= 1 then return nil end
        local base = {
          "fd", "--type", "f",
          "--hidden",
          "--exclude", ".git",
          "--strip-cwd-prefix",
          "--color", "never",
        }
        if vim.fn.has("win32") ~= 1 and vim.fn.executable("timeout") == 1 then
          -- Linux/Mac: wrap with timeout for 3-second limit
          return vim.list_extend({"timeout", "3"}, base)
        else
          -- Windows fallback: max-results as safety net
          return vim.list_extend(base, {"--max-results", "2000"})
        end
      end)(),
    },
  },
}

return options
