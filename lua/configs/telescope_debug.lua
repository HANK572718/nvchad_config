-- Telescope debug utilities
-- Helps diagnose why searches are finding too many files

local M = {}

-- Show all current ignore patterns
function M.show_ignore_patterns()
  local telescope_config = require("telescope.config")
  local patterns = telescope_config.values.file_ignore_patterns

  print("=== Telescope File Ignore Patterns ===")
  print("Total patterns: " .. #patterns)
  print("")

  for i, pattern in ipairs(patterns) do
    print(string.format("%3d. %s", i, pattern))
  end
end

-- Count files in current directory (for debugging)
function M.count_files_in_cwd()
  local cwd = vim.fn.getcwd()
  print("Counting files in: " .. cwd)
  print("Please wait...")

  local count = 0
  local handle = vim.loop.fs_scandir(cwd)

  if not handle then
    print("Error: Cannot scan directory")
    return
  end

  local function count_recursive(path, depth)
    if depth > 5 then
      return 0  -- Respect depth limit
    end

    local local_count = 0
    local dir_handle = vim.loop.fs_scandir(path)

    if not dir_handle then
      return 0
    end

    while true do
      local name, type = vim.loop.fs_scandir_next(dir_handle)
      if not name then
        break
      end

      -- Skip .git and other common folders
      if name == ".git" or name == "node_modules" or name == "__pycache__" then
        goto continue
      end

      if type == "file" then
        local_count = local_count + 1
      elseif type == "directory" then
        local subpath = path .. "\\" .. name
        local_count = local_count + count_recursive(subpath, depth + 1)
      end

      ::continue::
    end

    return local_count
  end

  count = count_recursive(cwd, 1)
  print("")
  print("=== File Count Results ===")
  print("Total files found (depth <= 5): " .. count)

  if count > 1000 then
    print("WARNING: File count exceeds 1000!")
    print("Consider:")
    print("  1. Reducing depth limit (currently 5)")
    print("  2. Adding more folders to ignore patterns")
    print("  3. Using a more specific search path")
  end
end

-- Show top-level folders and their file counts
function M.analyze_folders()
  local cwd = vim.fn.getcwd()
  print("=== Analyzing folders in: " .. cwd .. " ===")
  print("")

  local handle = vim.loop.fs_scandir(cwd)
  if not handle then
    print("Error: Cannot scan directory")
    return
  end

  local folders = {}

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == "directory" and name ~= ".git" then
      local folder_path = cwd .. "\\" .. name
      local file_count = 0

      -- Quick count (depth 1 only for speed)
      local dir_handle = vim.loop.fs_scandir(folder_path)
      if dir_handle then
        while true do
          local fname, ftype = vim.loop.fs_scandir_next(dir_handle)
          if not fname then break end
          if ftype == "file" then
            file_count = file_count + 1
          end
        end
      end

      table.insert(folders, { name = name, count = file_count })
    end
  end

  -- Sort by file count descending
  table.sort(folders, function(a, b)
    return a.count > b.count
  end)

  print(string.format("%-30s %s", "Folder", "Files (depth 1)"))
  print(string.rep("-", 45))

  for _, folder in ipairs(folders) do
    print(string.format("%-30s %d", folder.name, folder.count))
  end

  print("")
  print("Tip: Add large folders to .gitignore or ignore patterns")
end

return M
