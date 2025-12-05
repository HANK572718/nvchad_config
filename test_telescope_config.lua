-- Test script to verify Telescope configuration
-- Run with: :luafile %

print("=== Testing Telescope Configuration ===")
print("")

-- Check if telescope is loaded
local telescope_ok, telescope = pcall(require, "telescope")
if not telescope_ok then
  print("ERROR: Telescope not loaded!")
  return
end

-- Get current config
local config = require("telescope.config").values

print("1. Max Results Setting:")
print("   max_results = " .. tostring(config.max_results))
print("")

print("2. File Ignore Patterns (first 20):")
if config.file_ignore_patterns then
  for i, pattern in ipairs(config.file_ignore_patterns) do
    if i <= 20 then
      print(string.format("   %2d. %s", i, pattern))
    end
  end
  print("   ... total: " .. #config.file_ignore_patterns .. " patterns")
else
  print("   WARNING: No ignore patterns found!")
end
print("")

print("3. Path Display:")
print("   " .. vim.inspect(config.path_display))
print("")

print("=== Test Complete ===")
print("If max_results is NOT 1000, the config is not being applied!")
