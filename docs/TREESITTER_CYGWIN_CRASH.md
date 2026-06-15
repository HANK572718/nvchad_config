# Neovim 開檔閃退 — Cygwin 編譯器污染 Treesitter Parser

> 故障排除實錄。發生日期：2026-06-12
> 相關文件：[MSYS2_SETUP_GUIDE.md](./MSYS2_SETUP_GUIDE.md)（工具安裝），[setup_nvchad.md](./setup_nvchad.md)
>
> **⚠️ 修復已模組化（2026-06-15）**：原本寫死在 init.lua 的 `C:/msys64/ucrt64/bin/gcc.exe`
> 已改為機群可攜的 **`lua/configs/bootstrap.lua`**，用 `gcc -dumpmachine` 辨別 cygwin/native、
> 從環境變數 glob 探測編譯器，零寫死、跨 Windows/Linux/ARM。本文記錄的原始排查仍有效，
> 但實際邏輯請以該模組為準。可攜設計細節見本文「九、機群可攜化」。

## 一、症狀

- 在某個專案資料夾（如 `D:\project\intel_ARC_support\ITRI_questcomposite`）開啟 Neovim 後：
  - 一開始：進入 nvim 即閃退
  - 刪掉 auto-session 後：可進入，但**開啟任一實體檔案 / 切換 buffer 時隨機閃退**
- **非穩定重現**：同一操作有時正常、有時崩潰（約 1/8 機率），這是關鍵特徵
- **這台電腦才有**，其他電腦同一份 config 正常

## 二、誤判與排除過程（記錄走過的彎路）

最初懷疑是 auto-session 的問題，因為 session 檔記錄了被 `:file` 重新命名的 terminal buffer（`git`、`cc1.a` 等），還原時把它們當成不存在的實體檔案開啟。

- 嘗試：刪 session 檔、加 `SessionLoadPost` 清假 buffer、改 `save_extra_cmds` / `restore_extra_data` 重建 terminal
- **結果：全部無效**，閃退照舊 → 證明 session 不是根因

> 教訓：「開檔後才崩潰」「非穩定重現」這兩個特徵，指向的是**底層二進位 / parser 問題**，不是 Lua 設定層問題。一開始就該往 treesitter parser 查。

## 三、真正的根因（已驗證）

崩潰堆疊指向 treesitter：

```
.../runtime/lua/vim/treesitter.lua:431: Parser could not be created for buffer 1 and language "toml"
[C]: in function 'assert'
```

壓力測試（用 pcall 反覆建立 parser）時，**nvim 進程直接 exit code 5（硬崩潰）**，`pcall` 攔不住 → 確認是 C 層級 abort，不是可捕捉的 Lua error。

用 `objdump -p` 檢查 parser 二進位的依賴：

```
toml.so (2026/6/9 build) 依賴的 DLL:
    cygwin1.dll          ← 問題所在
    KERNEL32.dll
```

**根因**：這台電腦的 `gcc` 是 **Cygwin 版**（`C:\cygwin64\bin\gcc.exe`，`-dumpmachine` 為 `x86_64-pc-cygwin`）。
nvim-treesitter 在這台機器編譯 parser 時用到它，產出的 `.so` 連結到 **`cygwin1.dll`**（POSIX 模擬層）。

但 Neovim 是**原生 Windows 程式**。原生 Windows 的 nvim 載入依賴 `cygwin1.dll` 的 parser 時，ABI 不相容 → 隨機觸發 assert 失敗 → 整個進程崩潰（即「閃退」）。

### 因果鏈總結

| 觀察 | 解釋 |
|------|------|
| 開實體檔案才崩 | 檔案觸發 filetype → treesitter attach parser |
| 非穩定重現 | ABI 不相容的 parser 視記憶體狀態隨機 abort |
| 其他電腦正常 | 它們用原生編譯器（MSVC / MinGW），parser 乾淨 |
| `pcall` 攔不住 | C 層 abort，非 Lua error |

## 四、解法

用**原生 Windows 編譯器**（MinGW-w64 / UCRT64）重編 parser，**不可用 Cygwin**。

### 步驟 1：安裝 native UCRT64 gcc

利用既有的 MSYS2（`C:\msys64`）安裝原生 gcc：

```bash
C:\msys64\usr\bin\bash.exe -lc "pacman -S --noconfirm mingw-w64-ucrt-x86_64-gcc"
```

### 步驟 2：驗證安裝正確

```bash
C:\msys64\ucrt64\bin\gcc.exe -dumpmachine
# 必須輸出 x86_64-w64-mingw32（原生），不是 x86_64-pc-cygwin
```

本機驗證結果（2026-06-12）：
- `gcc.exe (Rev8, Built by MSYS2 project) 15.2.0`
- `-dumpmachine` → `x86_64-w64-mingw32` ✅
- 測試編譯的 DLL 只依賴 `KERNEL32.dll` + `api-ms-win-crt-*`（原生 UCRT），**無 `cygwin1.dll`** ✅

> ⚠️ **重要陷阱**：直接呼叫 `C:\msys64\ucrt64\bin\gcc.exe` 若 PATH 沒有 `C:\msys64\ucrt64\bin`，會**靜默失敗**（exit 1 卻無任何錯誤訊息、不產生輸出檔）。使用前務必先把該目錄加入 PATH：
> ```bash
> export PATH="/c/msys64/ucrt64/bin:$PATH"
> ```

### 步驟 3：讓 nvim 用 native gcc 並重編 parser（✅ 已完成 2026-06-15）

**關鍵發現**：本機 PATH 裡 `gcc` 解析到 `C:\cygwin64\bin\gcc.EXE`（nvim 內 `:lua print(vim.fn.exepath('gcc'))` 確認）。
若直接 `:TSUpdate` 會**再次用 Cygwin gcc 編出壞 parser**，所以必須先強制指定編譯器。

實際採用的做法（已寫進 config，跨機自動生效）：

1. **`init.lua` 開頭**設定 `vim.env.CC` 指向原生 gcc，並把 `C:\msys64\ucrt64\bin` 插到 PATH 最前面
   （nvim-treesitter 的 `M.compilers = { $CC, "cc", "gcc", ... }` 第一順位讀 `$CC`）。
2. **`lua/plugins/init.lua`** 的 treesitter spec 加 `init` 函式，再把
   `require("nvim-treesitter.install").compilers = { "C:/msys64/ucrt64/bin/gcc.exe" }` 釘死（雙重保險）。
3. 備份並刪掉所有 Cygwin parser：
   ```powershell
   Copy-Item <parserDir> <backup> -Recurse   # 備份到 nvim-data\parser_cygwin_backup
   Remove-Item <parserDir>\*.so -Force        # 24 個
   ```
4. 同步重編（headless 下 async job 會被 `qa!` 提早砍掉，需用 `vim.wait` 輪詢 parser 檔案出現後才退出）：
   ```lua
   install.commands.TSInstallSync["run!"](lang)
   vim.wait(120000, function() return vim.fn.filereadable(pdir..lang..".so")==1 end, 200)
   ```
   結果：22/22 parser 全部重編成功。

### 步驟 4：驗證（✅ 全數通過）

- `objdump -p <parser>.so | grep "DLL Name"`：22 個 parser 全部 **native（KERNEL32 + api-ms-win-crt-*），0 個 cygwin**
- 重現先前崩潰路徑（開 pyproject.toml + 反覆 reattach highlight）跑 20 次：**0 崩潰**（先前約 1/8）
- 原始壓力測試（7 parser × 150 次 parse = 1050 次）：**0 fails、exit 0**（先前在 toml 後直接 exit 5 硬崩潰）

## 五、診斷工具速查

```powershell
# 找系統上的編譯器，確認是不是 Cygwin
@("gcc","cc","clang") | % { (Get-Command $_ -EA SilentlyContinue).Source }
& <gcc路徑> -dumpmachine     # x86_64-pc-cygwin = 有問題

# 檢查某個 parser 依賴哪些 DLL
objdump -p <parser>.so | Select-String "DLL Name"

# 重現 treesitter 崩潰（用完整 config，非 --clean）
nvim --headless -c "edit some.toml" -c "qa!" 2> crash.txt
```

## 六、關鍵教訓

1. **非穩定重現 + 開檔才崩 = 往二進位 / parser 層查**，不要先怪 Lua 設定。
2. Windows 上的原生程式（如 nvim）**絕不能載入 Cygwin 編譯的動態庫**，要用 MinGW-w64 / UCRT64。
3. `pcall` 攔不到的崩潰（進程直接 exit）幾乎都是 C 層 abort，是底層線索。
4. MSYS2 的 `ucrt64` gcc 直接呼叫時，**PATH 沒設好會靜默失敗**，排查時容易誤判成「裝壞了」。

## 七、回退方式（萬一新 parser 有問題）

舊的 Cygwin parser 已備份在 `C:\Users\<user>\AppData\Local\nvim-data\parser_cygwin_backup`。
若需回退：刪掉 `parser\*.so`，把備份的 `.so` 複製回去即可。（但不建議——舊的就是會閃退那批。）
確認新 parser 穩定後可刪除此備份。

## 九、機群可攜化（2026-06-15，取代寫死路徑）

原本的修復把 `C:/msys64/ucrt64/bin/gcc.exe` 寫死在 init.lua，只對這台機器有效。
為了跨整個機群（多台 Windows / Linux x86_64 / ARM Jetson）共用一份 config，改成
**`lua/configs/bootstrap.lua`** 模組，由 init.lua 一行 `require("configs.bootstrap").setup()` 呼叫。

### 編譯器偵測（可攜、零寫死）

- **辨別 cygwin vs native 的權威方法**：`gcc -dumpmachine`
  - native MinGW-w64 → `x86_64-w64-mingw32`（或 `aarch64-w64-mingw32`）→ ✅ 用
  - **Cygwin → `x86_64-pc-cygwin`** → ❌ 拒（連 cygwin1.dll，會崩）
  - MSYS subsystem（`/usr/bin`）→ `x86_64-pc-msys` → ❌ 拒
  - `cl.exe`/`zig` 不會是 cygwin → 免驗
- **資料驅動候選表**：`{pat=glob, kind}` 有序清單，從環境變數（`SCOOP`/`LOCALAPPDATA`/
  `ProgramFiles`/`~`）推導 MSYS2(ucrt64>clang64>mingw64)、scoop、choco、LLVM、zig、
  vswhere 的 cl.exe。新增工具鏈 = 加一列。
- **Linux/ARM**：不動預設 `cc`（Cygwin 問題只在 Windows）。唯一防的是 active conda 的
  無前綴 cc 蓋掉系統 cc（用 `CONDA_PREFIX` + 路徑邊界判斷，誤判 `/opt/conda` vs
  `/opt/condatools` 已修）。
- **找不到原生編譯器時（Windows）**：主動把 treesitter 預設 compilers 改成 `{clang,cl,zig}`，
  避免它從 PATH 靜默挑到 Cygwin gcc 又崩潰。

### 驗證（2026-06-15）

- 本機實測：模組找到 `C:/msys64/ucrt64/bin/gcc.exe`（`-dumpmachine`=`x86_64-w64-mingw32`），
  `$CC` 與 treesitter `compilers[1]` 都正確；完整 config 啟動 exit 0。
- 崩潰路徑壓力測試（開 toml + reattach）×15：**0 崩潰**（重構無回歸）。

## 八、更新記錄

- **2026-06-12**：建立。記錄 Cygwin parser 污染導致的閃退、誤判 auto-session 的彎路、native UCRT64 gcc 的安裝與驗證。
- **2026-06-15**：✅ 完成修復。在 `init.lua` 與 treesitter spec 強制用 ucrt64 gcc（`$CC` + `install.compilers`），刪除 24 個 Cygwin parser 並重編 22 個原生 parser，全數驗證無 cygwin1.dll 依賴；崩潰路徑與壓力測試 0 崩潰。
- **2026-06-15（可攜化）**：把寫死路徑抽成 `lua/configs/bootstrap.lua`，用 `-dumpmachine` + 資料驅動候選表跨機群偵測編譯器，零寫死。多代理工作流設計 + 對抗驗證，本機 0 崩潰回歸。詳見第九節。
