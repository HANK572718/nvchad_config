# NVChad 網頁多媒體瀏覽使用指南

## 功能概述

用 **filebrowser**（單一執行檔的檔案伺服器）把任一資料夾丟到瀏覽器瀏覽多媒體——格狀縮圖牆、內建圖片 viewer 與影片播放器、搜尋。顯示與互動全部交給瀏覽器,**不依賴終端機 graphics protocol**,所以 SSH 遠端、Jetson、手機都能用。

這是 [`IMAGE_PREVIEW_GUIDE.md`](IMAGE_PREVIEW_GUIDE.md)（`<leader>fp`,終端內 chafa ASCII 預覽）的孿生功能,兩者互補:

| | 顯示位置 | 適合 |
|--|---------|------|
| **圖片預覽**（`<leader>fp`） | 終端機內 | 快速翻單張圖,不離開 nvim |
| **網頁多媒體**（`<leader>fs`） | 瀏覽器 | 看整個資料夾、影片/PDF、要互動或給別台機器看 |

### 特點
- ✅ 縮圖牆 + 內建圖片/影片 viewer + 搜尋
- ✅ 不依賴終端機 graphics protocol,SSH / Jetson / 手機皆可
- ✅ 綁 `0.0.0.0`,同網段其他裝置可連入(notify 會列出區網網址)
- ✅ 自動找空 port(從 8000 起,被佔就跳下一個)
- ✅ 離開 nvim 自動關閉,不留殘留進程
- ✅ 首次使用自動建立設定資料庫(免登入),換機器免手動設定

---

## 使用方法

### 快捷鍵

在 Normal 模式下（leader 鍵預設為 `<Space>`）：

| 按鍵 | 動作 |
|------|------|
| `<leader>fs` | 服務**當前 tab 的 cwd**(配合 `:tcd` 的 tab-local 專案根工作流) |
| `<leader>fS` | 提示**輸入路徑**,服務指定資料夾 |
| `:WebMediaStop` | 手動停止 server |

### 操作流程

1. 在 Neovim 中按 `<leader>fs`（或 `<leader>fS` 輸入路徑）
2. 模組啟動 filebrowser,並自動用預設瀏覽器開啟頁面
3. notify 會顯示本機與區網網址,例如:
   ```
   Serving /home/suser/nh-smartsop
   → http://127.0.0.1:8000              (本機)
   → http://192.168.1.56:8000   (區網)
   ```
4. 在別台機器/手機,瀏覽器直接打上面的區網網址即可
5. 用完按 `:WebMediaStop`,或直接離開 nvim(會自動關閉)

> 同時只會跑一個 server;再按一次 `<leader>fs` 會先停掉舊的、改服務新資料夾。

---

## 安裝 filebrowser

模組依賴 `filebrowser` 執行檔,**優先找 PATH,退回 `~/.local/bin/filebrowser`**。這個 binary 不在本 repo 內,clone 設定後需自行安裝一次。

### Linux（含 Jetson aarch64）— 手動放到 ~/.local/bin

到 [filebrowser releases](https://github.com/filebrowser/filebrowser/releases/latest) 下載對應平台的壓縮檔,解出 `filebrowser` 放進 `~/.local/bin`:

```bash
mkdir -p ~/.local/bin
# x86_64：
ASSET=linux-amd64-filebrowser.tar.gz
# Jetson / aarch64 改用：
# ASSET=linux-arm64-filebrowser.tar.gz
curl -sL "https://github.com/filebrowser/filebrowser/releases/latest/download/$ASSET" \
  | tar -xz -C ~/.local/bin filebrowser
chmod +x ~/.local/bin/filebrowser
filebrowser version    # 驗證
```

確認 `~/.local/bin` 在 PATH 中(多數發行版預設已加入)。

### 官方安裝腳本（裝到 /usr/local/bin,需 sudo）

```bash
curl -fsSL https://raw.githubusercontent.com/filebrowser/filebrowser/master/scripts/get.sh | bash
```

### Windows

下載 `windows-amd64-filebrowser.zip`,解出 `filebrowser.exe` 放到 PATH 中的任一目錄即可。

---

## 技術細節

### 配置文件位置
- 模組: [`lua/configs/web_media.lua`](lua/configs/web_media.lua)
- 快捷鍵映射: `lua/mappings.lua`（`<leader>fp` 圖片預覽下方）
- filebrowser 設定資料庫: `~/.config/filebrowser/filebrowser.db`

### 設定資料庫（自動建立）

第一次按 `<leader>fs` 時,若 `~/.config/filebrowser/filebrowser.db` 不存在,模組會自動執行等同以下的初始化(`ensure_db`):

```bash
filebrowser config init  -d ~/.config/filebrowser/filebrowser.db
filebrowser config set --auth.method=noauth -d ~/.config/filebrowser/filebrowser.db
filebrowser users add admin <pw> --perm.admin -d ~/.config/filebrowser/filebrowser.db
```

- **auth.method=noauth**：免登入,進去直接用。noauth 仍需 DB 內有一個 user 供自動登入,故建一個 admin。
- root / 連線位址 / port **不寫進 db**,每次啟動由旗標指定:`filebrowser -d <db> -r <dir> -a 0.0.0.0 -p <port>`。

### 自動找空 port

`find_free_port(8000)` 從 8000 起逐一試 `bind + listen` 找第一個真正空的 port。
> 註:libuv 的 `bind()` 預設帶 `SO_REUSEADDR`,單獨 bind 不會報衝突,必須再 `listen()` 才偵測得到 port 已被佔用。

---

## 安全提醒

- 預設綁 `0.0.0.0` + `noauth` = **同網段任何人都能瀏覽該資料夾,且無密碼**。
- 在不信任的網路(咖啡廳、公司訪客 Wi-Fi)請勿開啟,或用完立即 `:WebMediaStop`。
- 若只想本機可連,將 `lua/configs/web_media.lua` 中 jobstart 的 `-a` 從 `0.0.0.0` 改回 `127.0.0.1`。

---

## 疑難排解

### 按了 `<leader>fs` 出現「filebrowser 退出 (code 1)，port XXXX 可能被佔用」
通常是同一個 port 被別的程式佔住。模組已會自動找空 port,若仍發生,可能是 50 個候選 port(8000–8050)都被佔,或剛改完模組需清快取重載:
```vim
:lua package.loaded['configs.web_media'] = nil
```

### 「找不到 filebrowser」
binary 沒裝或不在 PATH。見上方「安裝 filebrowser」,確認 `filebrowser version` 可執行,或放到 `~/.local/bin/filebrowser`。

### 區網別台機器連不上
- 確認雙方在同網段,且該機防火牆未擋對應 port
- 確認 server 真的綁 `0.0.0.0`(notify 有列出區網網址即代表有綁)

---

## 自訂

編輯 [`lua/configs/web_media.lua`](lua/configs/web_media.lua)：

| 想改什麼 | 改哪裡 |
|---------|--------|
| 起始 port | `find_free_port(8000)` 的 `8000` |
| 固定某個 port | 呼叫 `M.serve(dir, { port = 9000 })` |
| 只允許本機 | jobstart 的 `-a` 改為 `127.0.0.1` |
| 不自動開瀏覽器 | `M.serve(dir, { open = false })` |
| db 位置 | 檔案頂端的 `local DB = ...` |
