# artifacts — 檔案 ↔ 網址對照索引

本目錄存放由 Claude 產出的 artifact 原始檔。**原始檔一律留在此 repo**，
不放在 `~/.claude/jobs/<id>/tmp/`（該目錄會隨 job 刪除一起消失）。

重新發布時**必須帶 `url=`**，否則會開出一個全新的 artifact、舊網址孤兒化：

```
Artifact(file_path="artifacts/<檔名>.html", url="<下表的網址>")
```

| 檔名 | 網址 | 發布日 | 內容 |
|---|---|---|---|
| `osc52-clipboard-plan.html` | <https://claude.ai/artifact/W9zioNSmEL5ft8PqVsRhvj> | 2026-09-19 | tmux + nvim（含 SSH 遠端）讓 `v` 選取後按 `y` 直通系統剪貼簿的改動規劃，附 `set-clipboard external` vs `on` 的實測證據 |

> artifact 在 claude.ai 上是**私有頁面**，未主動分享則他人看不到。
