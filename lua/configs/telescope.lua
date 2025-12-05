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
      local subfolder_path = folder_path .. "\\" .. name
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
  git_root = git_root:gsub("/", "\\")

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
      local folder_path = git_root .. "\\" .. name
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

  local gitignore_path = git_root .. "\\.gitignore"

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
  }
end

-- Merge base patterns with .gitignore folder patterns and large folders
local function get_file_ignore_patterns()
  local base_patterns = get_base_patterns()
  local gitignore_patterns = parse_gitignore_folders()
  local large_folders = scan_large_folders(200)  -- Ignore folders with > 200 files

  -- Merge all patterns
  for _, pattern in ipairs(gitignore_patterns) do
    table.insert(base_patterns, pattern)
  end

  for _, folder in ipairs(large_folders) do
    table.insert(base_patterns, folder)
  end

  return base_patterns
end

-- Generate depth filter patterns (ignore files deeper than max_depth)
-- Depth is counted from git root: depth 1 = root/file.txt, depth 5 = root/a/b/c/d/file.txt
local function get_depth_filter_patterns(max_depth)
  local patterns = {}

  -- Create pattern for paths with more than max_depth levels
  -- Pattern counts the number of slashes to determine depth
  -- For example, max_depth=5 means we ignore anything with 6+ slashes
  -- Pattern: match paths that have (max_depth + 1) or more path separators

  -- Build a pattern that matches paths deeper than max_depth
  -- Example: if max_depth=5, we want to ignore "a/b/c/d/e/f/file.txt" (6+ levels)
  local separator_count = max_depth
  local pattern_parts = {}

  for i = 1, separator_count + 1 do
    table.insert(pattern_parts, "[^/]+")
  end

  -- This pattern matches any path with more than max_depth levels
  local depth_pattern = table.concat(pattern_parts, "/")
  table.insert(patterns, depth_pattern)

  return patterns
end

-- Merge all ignore patterns including depth filter
local function get_all_ignore_patterns(max_depth)
  local all_patterns = get_file_ignore_patterns()
  local depth_patterns = get_depth_filter_patterns(max_depth)

  for _, pattern in ipairs(depth_patterns) do
    table.insert(all_patterns, pattern)
  end

  return all_patterns
end

local options = {
  defaults = {
    file_ignore_patterns = get_all_ignore_patterns(5),  -- Maximum depth: 5 levels
  },
}

return options
