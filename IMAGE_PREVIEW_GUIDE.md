# NVChad 圖片預覽使用指南

## 功能概述

已成功配置 NVChad 圖片預覽功能，使用 **自定義 Telescope + chafa** 方案。

### 特點
✅ 在 MSYS2 Mintty 終端中穩定運行
✅ 支援遠端 SSH 連線（iPad Blink）
✅ ASCII/ANSI 輸出，不依賴 GUI 或 kitty graphics
✅ 支援多種圖片格式：PNG, JPG, JPEG, GIF, WebP, BMP, SVG, ICO

---

## 使用方法

### 快捷鍵

在 Normal 模式下按：
```
<leader>fp
```
（預設 leader 鍵是 `<Space>`，所以是 `Space + f + p`）

### 操作流程

1. 在 Neovim 中按 `<leader>fp`
2. Telescope 會開啟媒體文件瀏覽器
3. 使用方向鍵或 `Ctrl-n/Ctrl-p` 導航圖片
4. 選中圖片後會在預覽窗口顯示 ASCII 版本
5. 按 `Enter` 開啟圖片文件，或 `Esc` 關閉

---

## 技術細節

### 安裝的工具
- **chafa 1.16.2**: 將圖片轉換為 ASCII/ANSI 輸出
- **自定義 Telescope picker**: 直接使用 Telescope API（無需額外插件）

### 配置文件位置
- 圖片預覽模組: `lua/configs/image_preview.lua`
- 快捷鍵映射: `lua/mappings.lua:28-30`
- 插件配置: `lua/plugins/init.lua` (已移除不相容的 telescope-media-files)

### Chafa 設定
```lua
{
  format = "symbols",  -- 使用符號提供更好的畫質
  size = "80x40",      -- 80 欄 x 40 列
  animate = "off",     -- 關閉動畫以提升效能
  colors = "256",      -- 256 色渲染
}
```

---

## 疑難排解

### 如果圖片無法顯示

1. **確認 chafa 已安裝**
   ```bash
   C:\msys64_2\ucrt64\bin\chafa.exe --version
   ```

2. **測試 chafa 是否能單獨運行**
   ```bash
   chafa /path/to/image.png
   ```

3. **檢查 Telescope 擴展是否載入**
   在 Neovim 中執行：
   ```vim
   :Telescope
   ```
   應該會看到 `media_files` 選項

### 如果在遠端 SSH 中無法使用

- 確保遠端 MSYS2 環境也安裝了 chafa
- 確認終端支援 ANSI 色彩輸出
- iPad Blink 預設支援，無需額外配置

---

## 調整預覽大小

編輯 `lua/configs/image_preview.lua`，找到 `get_command` 函數，修改：
```lua
"-s", "80x40",  -- 改為你想要的大小，如 "100x50" 或 "120x60"
```

或修改配置區塊：
```lua
M.config = {
  chafa_args = "-f symbols -s 100x50 --animate off --colors 256",  -- 調整這裡
}
```

重啟 Neovim 即可生效。

---

## 支援的圖片格式

預設支援以下格式：
- PNG, JPG/JPEG
- GIF, WebP
- BMP, SVG
- ICO, TIFF/TIF

可在 `lua/configs/image_preview.lua` 的 `image_extensions` 中添加更多格式。

---

## 替代方案

如果需要更高畫質的圖片預覽：
- **本地 Windows**: 使用 Neovide、nvim-qt 等 GUI
- **Linux/WSL**: 可考慮 image.nvim + kitty 終端

但對於你的使用場景（MSYS2 + SSH），**當前自定義 Telescope 方案是最穩定可靠的**，專為 Windows 設計，無相容性問題。
