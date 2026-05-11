# Git 操作技巧

本文收錄在管理此 repo（nvim 設定、tmux 設定、腳本部署）過程中常用的 git 指令與注意事項。

---

## `^{}` — Tag 解參考（dereference）

### 情境

將某個 annotated tag 所指向的 commit 直接推送到某個 branch：

```bash
git push origin <tagname>^{}:refs/heads/<branch>

# 例：將 v1.0.0 這個 tag 底層的 commit 推到 main
git push origin v1.0.0^{}:refs/heads/main
```

### 為何需要 `^{}`

| 狀況 | 說明 |
|---|---|
| Annotated tag | 本身是一個 **tag object**，不是 commit object |
| GitHub branch head | 必須指向 **commit object** |
| 少了 `^{}` | GitHub 拒絕推送（型別不符） |
| 加了 `^{}` | Git 自動解出 tag 底層的 commit，GitHub 接受 |

Lightweight tag 直接指向 commit，不需要 `^{}`；**annotated tag 才需要**。

### 常見使用場景（此 repo）

- 在 Raspberry Pi 或 Jetson 上打好 tag 後，想把該版本推回 `main`
- CI/CD 流程中從 tag 部署 nvim / tmux 設定到新機器
- 從舊 tag 回復某個已知穩定的設定版本到 branch

---

## Rebase 取代 Merge（保持線性歷史）

本地有少量 commit、remote 有多個新 commit 時，用 rebase 取代 merge：

```bash
# 使用 vim 進行 interactive rebase
GIT_EDITOR=vim git rebase -i origin/main
```

- `pick` → 保留 commit 不動
- `reword` → 保留但改 commit 訊息
- `squash` → 合併進前一個 commit

結果為線性歷史，不產生 merge commit。

---
