-- 只忽略常見的大型資料夾，不忽略單獨的檔案
-- 這樣符合 .gitignore 中資料夾規則（如 build/）但不影響檔案規則（如 *.log）
local options = {
  defaults = {
    file_ignore_patterns = {
      -- Git 內部資料
      ".git/",

      -- Python 資料夾
      ".venv/",
      "venv/",
      "%.venv/",
      "__pycache__/",
      ".pytest_cache/",
      "%.egg%-info/",

      -- Build 和 dist 資料夾
      "build/",
      "dist/",
      "%.dist%-info/",

      -- Node.js 資料夾
      "node_modules/",
      "%.npm/",

      -- IDE 資料夾
      ".vscode/",
      ".idea/",

      -- 其他常見大型資料夾
      "%.cache/",
      "target/",
      "out/",
      "bin/",
      "obj/",
      ".next/",
      ".nuxt/",
      "coverage/",
      ".tox/",
      ".mypy_cache/",
      "htmlcov/",
    },
  },
}

return options
