--- office_preview.lua — 在 nvim 裡直接讀 docx / xlsx / pptx / pdf
---
--- 問題：這些是二進位（zip / PDF）格式，nvim 直接開會顯示一整片亂碼
--- （`PK^C^D...docProps/app.xml`），完全不能用。
---
--- 做法：用 `BufReadCmd` 接管讀檔 —— 這個 event 會**取代** nvim 預設的讀檔行為，
--- 所以亂碼根本不會進到 buffer。我們改成呼叫外部工具抽出文字再填進去。
---
--- 刻意不裝 LibreOffice：轉換走 pandoc / xlsx2csv / unzip+sed / pdftotext，
--- 全部都是輕量工具（相依總和 < 100MB，對比 LibreOffice 的 GB 級）。
--- 這幾條管線與 configs/yazi/plugins/office.yazi/main.lua 是同一套，已實測。
---
--- 限制（誠實說明）：**只抽文字，看不到原始版面配置**。要看排版請用
--- 系統預設程式開；要操作表格請用 `vd`（VisiData，可搜尋/排序/篩選）。
---
--- buffer 一律設為唯讀且不可寫入（buftype=nowrite），避免不小心 `:w`
--- 把純文字覆蓋回原本的 docx/xlsx，那會直接毀檔。

local M = {}

--- 各副檔名的轉換管線。
--- 檔案路徑一律以 "$1" 傳入、絕不做字串內插 —— 路徑含空白、引號或中文
--- （你的檔名大量使用中文）才不會被 shell 拆開或注入。
--- @type table<string, { cmd: string, needs: string[], ft: string }>
local HANDLERS = {
  docx = {
    -- pandoc 直接吐 markdown；ft 設 markdown 讓 render-markdown.nvim 接手渲染
    cmd = [[pandoc -t markdown --wrap=none "$1" 2>/dev/null]],
    needs = { "pandoc" },
    ft = "markdown",
  },
  xlsx = {
    -- column 對齊成等寬表格；ft 不設 markdown（那些 | 不是 markdown 表格語法）
    cmd = [[xlsx2csv "$1" 2>/dev/null | column -s, -t]],
    needs = { "xlsx2csv", "column" },
    ft = "text",
  },
  pptx = {
    -- pptx 就是個 zip，投影片文字在 ppt/slides/slideN.xml 的 <a:t> 裡。
    -- 刻意不用 pptx2md（v2.0.6 實測會漏掉內文，且把 log 印在 stdout）。
    -- sort -V 是必要的：字典序會把 slide10 排在 slide2 前面。
    -- 分隔符用 [==[ ]==]：腳本內的 POSIX 字元類 [[:space:]] 結尾是 "]]"，
    -- 用普通長字串會被提前截斷。
    cmd = [==[
      n=0
      unzip -Z1 "$1" 'ppt/slides/slide*.xml' 2>/dev/null | sort -V | while IFS= read -r s; do
        n=$((n+1))
        printf '\n## Slide %s\n\n' "$n"
        unzip -p "$1" "$s" 2>/dev/null \
          | sed -e 's|</a:p>|\n|g' -e 's|<[^>]*>||g' \
                -e 's|&amp;|\&|g' -e 's|&lt;|<|g' -e 's|&gt;|>|g' \
                -e 's|&quot;|"|g' -e "s|&apos;|'|g" \
          | sed '/^[[:space:]]*$/d'
      done
    ]==],
    needs = { "unzip", "sed" },
    ft = "markdown",
  },
  pdf = {
    -- -layout 保留欄位相對位置，表格類 PDF 讀起來差很多。poppler 提供。
    cmd = [[pdftotext -layout "$1" - 2>/dev/null]],
    needs = { "pdftotext" },
    ft = "text",
  },
}

--- 回傳缺少的相依工具清單。
--- @param needs string[]
--- @return string[]
local function missing_tools(needs)
  local missing = {}
  for _, tool in ipairs(needs) do
    if vim.fn.executable(tool) == 0 then missing[#missing + 1] = tool end
  end
  return missing
end

--- 把轉換結果填進 buffer 並鎖成唯讀。
--- @param buf integer
--- @param lines string[]
--- @param ft string
local function fill(buf, lines, ft)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  -- nowrite：從此 buffer 無法寫回檔案，避免 :w 用純文字覆蓋掉原始 docx/xlsx。
  vim.bo[buf].buftype = "nowrite"
  vim.bo[buf].modifiable = false
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = ft
end

function M.setup()
  local group = vim.api.nvim_create_augroup("OfficePreview", { clear = true })

  local patterns = {}
  for ext, _ in pairs(HANDLERS) do
    patterns[#patterns + 1] = "*." .. ext
    patterns[#patterns + 1] = "*." .. ext:upper()
  end

  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = patterns,
    callback = function(event)
      local buf = event.buf
      local path = event.match ~= "" and event.match or vim.api.nvim_buf_get_name(buf)
      local ext = path:match("%.([^.]+)$")
      local h = ext and HANDLERS[ext:lower()]
      if not h then return end

      local missing = missing_tools(h.needs)
      if #missing > 0 then
        fill(buf, {
          ("無法預覽 %s：缺少工具 %s"):format(ext, table.concat(missing, ", ")),
          "",
          "安裝方式見 docs/development-notes/08160930-terminal-image-pdf-ecosystem.md",
        }, "text")
        return
      end

      -- sh -c <script> <$0> <$1>：第三個參數填 sh 當 $0，第四個才是 $1
      local result = vim.system(
        { "sh", "-c", h.cmd, "sh", path },
        { text = true }
      ):wait()

      local text = result.stdout or ""
      if text == "" then
        fill(buf, {
          ("轉換 %s 沒有產出內容（可能是空檔或格式不符）"):format(vim.fn.fnamemodify(path, ":t")),
          "",
          ("exit=%s  stderr=%s"):format(tostring(result.code), tostring(result.stderr):sub(1, 200)),
        }, "text")
        return
      end

      fill(buf, vim.split(text, "\n", { plain = true }), h.ft)
    end,
  })
end

return M
