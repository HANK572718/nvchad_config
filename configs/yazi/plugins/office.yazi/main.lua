--- office.yazi — 不依賴 LibreOffice 的 Office / 表格文件預覽器
---
--- 設計取捨：
---   * 刻意不用 macydnah/office.yazi —— 那支走 libreoffice --headless 轉 PDF 再轉圖，
---     功能完整但要背一個 GB 級的 LibreOffice。這裡改成「抽文字」路線，全部依賴
---     加起來不到 100MB。代價是看不到原始版面配置，只看得到內容。
---   * 三種格式共用同一條程式路徑（sh -c + 管線），因為 pptx 本來就需要多段管線，
---     統一之後只有一份讀取／渲染邏輯要維護。
---
--- 相依：pandoc（docx）、xlsx2csv（xlsx）、unzip + sed（pptx，macOS 內建）、
---       column（csv/xlsx 對齊，POSIX 內建）
---
--- 渲染骨架抄自 yazi 內建的 json 預覽器（preset/plugins/json.lua），
--- 保持與 job.skip / job.area 的捲動語意一致。

local M = {}

--- 各副檔名對應的轉換管線。
--- 檔案路徑一律以 "$1" 傳入、不做字串內插 —— 路徑含空白、引號或中文時才不會被
--- shell 拆開或注入。
local PIPELINES = {
  -- pandoc 直接吐 markdown 到 stdout。--wrap=none 交給 yazi 自己決定換行寬度。
  docx = [[pandoc -t markdown --wrap=none "$1" 2>/dev/null]],

  -- xlsx2csv 吐 CSV 到 stdout，再用 column 對齊成表格比較好讀。
  xlsx = [[xlsx2csv "$1" 2>/dev/null | column -s, -t]],

  csv = [[column -s, -t "$1" 2>/dev/null]],

  -- pptx 本身就是個 zip，投影片文字在 ppt/slides/slideN.xml 的 <a:t> 元素裡。
  --
  -- 刻意不用 pptx2md（v2.0.6）：實測它會**漏掉內文**（測試檔裡的「要點 A」在
  -- 檔案中存在、輸出卻只剩標題），而且把 loguru 的 INFO log 印到 stdout，
  -- 用 -o /dev/stdout 時會和內容混在一起。
  --
  -- sort -V 是必要的：字典序會把 slide10 排在 slide2 前面。
  --
  -- 注意分隔符用 [==[ ]==] 而非 [[ ]]：腳本裡的 POSIX 字元類 [[:space:]] 結尾是
  -- "]]"，會把普通的 Lua 長字串提前關掉，造成 "unexpected symbol near '$'"。
  pptx = [==[
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
}

function M:peek(job)
  local ext = tostring(job.file.url):match("%.([^.]+)$")
  local script = ext and PIPELINES[ext:lower()]
  -- 不是我們處理的格式就退回內建 code 預覽器（原始位元組），不要留白畫面
  if not script then
    return require("code"):peek(job)
  end

  -- sh -c <script> <$0> <$1>：第三個參數是 $0（慣例填 sh），第四個才是 $1
  local child = Command("sh")
    :arg({ "-c", script, "sh", tostring(job.file.path) })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :spawn()

  if not child then
    return require("code"):peek(job)
  end

  local opt = { tab_size = rt.preview.tab_size, wrap = rt.preview.wrap, width = job.area.w }
  local limit = job.area.h
  local i, lines = 0, {}
  repeat
    local next, event = child:read_line()
    if event == 1 then
      return require("code"):peek(job)
    elseif event ~= 0 then
      break
    end

    local wrapped = ui.lines(next, opt)
    local from = math.max(1, job.skip - i + 1)
    local to = math.min(#wrapped, job.skip + limit - i)

    i = i + #wrapped
    for j = from, to do
      lines[#lines + 1] = wrapped[j]
    end
  until i >= job.skip + limit

  child:start_kill()
  if job.skip > 0 and i < job.skip + limit then
    ya.emit("peek", { math.max(0, i - limit), only_if = job.file.url, upper_bound = true })
  else
    ya.preview_widget(job, ui.Text(lines):area(job.area))
  end
end

function M:seek(job) require("code"):seek(job) end

return M
