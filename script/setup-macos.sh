#!/usr/bin/env bash
# =====================================================
# setup-macos.sh — nvchad_config 的 macOS 一鍵安裝 / 部署腳本
#
# 用途：在 macOS（Apple Silicon / Intel）上安裝依賴、部署設定 symlink、
#       同步 nvim 外掛，讓這份 repo 的 nvim + tmux + Ghostty 設定一次到位。
#       （Linux 請改用 setup-nvchad.sh；本腳本不適用 Linux。）
#
# 前置（新機器）：先把 repo clone 到 ~/.config/nvim 再跑本腳本
#   git clone git@github.com:HANK572718/nvchad_config.git ~/.config/nvim
#   bash ~/.config/nvim/script/setup-macos.sh
#   （若 clone 到別處也行，腳本會自動建立 ~/.config/nvim -> repo 的 symlink。）
#
# 選項：
#   --minimal   只裝 nvim 運作必要套件，略過選配工具
#   -h | --help 顯示本說明
#
# 特性：冪等、可重複執行（已安裝 / 已連結會自動跳過並印綠勾）；
#       除 Homebrew 官方安裝器外不用 sudo；不覆寫全域 git 身份；
#       不修改 macOS 系統設定。
# =====================================================
set -euo pipefail

# ---- 輸出樣式（非 tty 時關閉顏色）----
if [[ -t 1 ]]; then
  G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; B=$'\e[1m'; N=$'\e[0m'
else
  G=''; Y=''; R=''; B=''; N=''
fi
ok()   { printf '%s✓%s %s\n' "$G" "$N" "$*"; }
info() { printf '  %s•%s %s\n' "$B" "$N" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%s✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
step() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }

# ---- 參數 ----
INSTALL_OPTIONAL=1
for arg in "$@"; do
  case "$arg" in
    --minimal) INSTALL_OPTIONAL=0 ;;
    -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知參數：$arg（用 -h 看說明）" ;;
  esac
done

# ---- 僅支援 macOS ----
[[ "$(uname -s)" == "Darwin" ]] || die "本腳本僅適用 macOS。Linux 請用 setup-nvchad.sh。"

# ---- 解析 repo 根目錄（= 腳本所在的上一層）----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NVIM_CONFIG="$HOME/.config/nvim"

# ---- Neovim 釘版 ----
# 為什麼不是最新版：nvim-treesitter 的 master 分支已於 2026-04 封存，README 明確
# 寫「Neovim 0.10 or 0.11（0.12 is not supported）」。Neovim 0.12 移除了
# vim.treesitter.query.add_directive 的 all=false 相容層，directive handler 收到的
# 變成節點「陣列」而非單一節點，開含 fenced code block 的 markdown 會噴
# "attempt to call method 'range' (a nil value)"（image.nvim / foldexpr 都會踩）。
# 詳見 docs/development-notes/08151555-treesitter-0.12-directive-breaking-change.md
# 日後若整份 config 遷移到 nvim-treesitter main 分支，把這個字串改掉即可。
NVIM_VERSION="0.11.7"
NVIM_PREFIX="$HOME/.local/opt/nvim-${NVIM_VERSION}"

# ============ 1. Homebrew ============
step "1/8 Homebrew"
if command -v brew >/dev/null 2>&1; then
  ok "Homebrew 已安裝：$(brew --version | head -1)"
else
  info "安裝 Homebrew（過程會要求輸入密碼）…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# 確保本 shell 用得到 brew（Apple Silicon=/opt/homebrew、Intel=/usr/local）
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
command -v brew >/dev/null 2>&1 || die "brew 仍不可用，請重開終端機後再跑一次。"

# ---- brew 安裝輔助（失敗只警告、不中斷，維持冪等可重跑）----
brew_install() {  # $1 = formula
  if brew list --versions "$1" >/dev/null 2>&1; then
    ok "$1 已安裝"
  elif brew install "$1"; then
    ok "$1 安裝完成"
  else
    warn "$1 安裝失敗（可稍後重跑本腳本）"
  fi
}
cask_install() {  # $1 = cask
  if brew list --cask "$1" >/dev/null 2>&1; then
    ok "$1 已安裝"
  elif brew install --cask "$1"; then
    ok "$1 安裝完成"
  else
    warn "$1 安裝失敗（可稍後重跑本腳本）"
  fi
}

# ---- Neovim 釘版安裝（不用 sudo：裝到 ~/.local/opt 再 symlink 進 ~/.local/bin）----
# 刻意不走 brew：homebrew-core 沒有 neovim@0.11 formula，brew 只給得到最新版。
# 回傳目前 PATH 上的 nvim 版本號（沒裝則回傳空字串）。
# 註：用 sed 而非 head，避免 set -o pipefail 下 head 提早關閉管線讓 nvim 收到
#     SIGPIPE（exit 141）而誤判成失敗。
nvim_installed_version() {
  command -v nvim >/dev/null 2>&1 || return 0
  nvim --version 2>/dev/null | sed -n '1s/^NVIM v//p'
}

install_neovim_pinned() {
  local tarball tmp url
  case "$(uname -m)" in
    arm64)  tarball="nvim-macos-arm64"  ;;
    x86_64) tarball="nvim-macos-x86_64" ;;
    *)      warn "未知架構 $(uname -m)，略過 Neovim 安裝"; return 0 ;;
  esac
  # brew 版 neovim 在 /opt/homebrew/bin，PATH 順序可能蓋過釘版，先移除
  if brew list --versions neovim >/dev/null 2>&1; then
    info "移除 brew 的 neovim（會蓋過釘版）…"
    brew uninstall neovim >/dev/null 2>&1 || warn "brew uninstall neovim 失敗，請手動處理"
  fi
  url="https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/${tarball}.tar.gz"
  tmp="$(mktemp -d)"
  info "下載 Neovim v${NVIM_VERSION}（${tarball}）…"
  if ! curl -fsSL "$url" -o "$tmp/${tarball}.tar.gz"; then
    rm -rf "$tmp"; warn "Neovim 下載失敗：$url"; return 0
  fi
  tar xzf "$tmp/${tarball}.tar.gz" -C "$tmp"
  rm -rf "$NVIM_PREFIX"
  mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
  cp -R "$tmp/${tarball}" "$NVIM_PREFIX"
  ln -sfn "$NVIM_PREFIX/bin/nvim" "$HOME/.local/bin/nvim"
  rm -rf "$tmp"
  ok "Neovim v${NVIM_VERSION} 安裝完成 → ~/.local/bin/nvim"
}

# ---- filebrowser 官方 binary（不走 brew）----
# brew 的 filebrowser 沒把前端打包進去（缺 public/index.html），網頁 UI 會一律 404；
# 官方 release 的 binary 內嵌前端才正常。故抓官方 darwin release 到 ~/.local/bin。
# 註：filebrowser/filebrowser 專案 2026-09-01 起封存停更，日後可考慮換工具。
install_filebrowser() {
  local dest="$HOME/.local/bin/filebrowser" asset tag url tmp
  if [[ -x "$dest" ]]; then ok "filebrowser（官方版）已在 ~/.local/bin"; return 0; fi
  # 若殘留 brew 版（缺前端），先移除以免 PATH 蓋過官方版
  if brew list --versions filebrowser >/dev/null 2>&1; then
    info "移除 brew 的 filebrowser（缺前端會 404）…"
    brew uninstall filebrowser >/dev/null 2>&1 || warn "brew uninstall filebrowser 失敗，請手動處理"
  fi
  case "$(uname -m)" in
    arm64)  asset="darwin-arm64-filebrowser.tar.gz"  ;;
    x86_64) asset="darwin-amd64-filebrowser.tar.gz"  ;;
    *)      warn "未知架構 $(uname -m)，略過 filebrowser"; return 0 ;;
  esac
  tag="$(curl -fsSL https://api.github.com/repos/filebrowser/filebrowser/releases/latest \
         | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | sed -n '1p')"
  [[ -n "$tag" ]] || { warn "查不到 filebrowser release，略過"; return 0; }
  url="https://github.com/filebrowser/filebrowser/releases/download/${tag}/${asset}"
  tmp="$(mktemp -d)"
  info "下載 filebrowser（官方 ${tag}）…"
  if curl -fsSL "$url" -o "$tmp/fb.tar.gz" && tar xzf "$tmp/fb.tar.gz" -C "$tmp" filebrowser; then
    mkdir -p "$HOME/.local/bin"
    mv "$tmp/filebrowser" "$dest"; chmod +x "$dest"
    ok "filebrowser（官方 ${tag}）→ ~/.local/bin/filebrowser"
  else
    warn "filebrowser 下載 / 解壓失敗，略過"
  fi
  rm -rf "$tmp"
}

# ============ 2. 必要套件 ============
step "2/8 必要套件"
# 註：neovim 不在此清單 —— 它走下方 install_neovim_pinned 釘版安裝。
REQUIRED=(tmux git ripgrep fd node python stylua yarn)
for f in "${REQUIRED[@]}"; do brew_install "$f"; done

CUR_NVIM="$(nvim_installed_version)"
if [[ "$CUR_NVIM" == "$NVIM_VERSION" && -L "$HOME/.local/bin/nvim" ]]; then
  ok "Neovim v${NVIM_VERSION} 已是釘版"
else
  # 註：不寫成 `[[ ... ]] && info ...`——條件為假時整段回傳 1，在 set -e 下會中斷腳本。
  if [[ -n "$CUR_NVIM" ]]; then
    info "目前 nvim 為 v${CUR_NVIM}，換成釘版 v${NVIM_VERSION}"
  fi
  install_neovim_pinned
fi

# 釘版裝在 ~/.local/bin，必須在 PATH 且排在 /opt/homebrew/bin 之前才會生效
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ok "~/.local/bin 已在 PATH" ;;
  *) warn "~/.local/bin 不在 PATH。請加進 shell profile：export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# ============ 3. 選配套件 ============
step "3/8 選配套件"
# yazi 及其預覽相依：
#   yazi     終端檔案瀏覽 / 多格式預覽中樞（設定見 configs/yazi/）
#   poppler  提供 pdftoppm —— yazi 內建 PDF 預覽器靠它把頁面轉圖
#   pandoc   docx → markdown（configs/yazi 的 office 外掛用）
#   glow     markdown 渲染（yazi 的 opener）
#   visidata 表格「操作」用（可搜尋 / 排序 / 篩選，圖片式預覽做不到）
#   jq       yazi 內建 json 預覽器
#   sevenzip yazi 內建壓縮檔預覽器
# 刻意不裝 libreoffice：office 類走「抽文字」而非「轉圖」，省下 GB 級相依。
OPTIONAL=(chafa imagemagick luarocks lazygit git-delta bat fzf coreutils
          yazi poppler pandoc glow visidata jq sevenzip)
if [[ "$INSTALL_OPTIONAL" == "1" ]]; then
  for f in "${OPTIONAL[@]}"; do brew_install "$f"; done
  install_filebrowser   # filebrowser 改走官方 binary（brew 版缺前端會 404），見上方函式
else
  warn "--minimal：略過選配工具（${OPTIONAL[*]} + filebrowser）"
fi

# ============ 4. Ghostty + Nerd Font ============
step "4/8 Ghostty + Nerd Font"
cask_install ghostty
cask_install font-jetbrains-mono-nerd-font

# ============ 5. nvim 設定就位 ============
step "5/8 nvim 設定位置（~/.config/nvim）"
if [[ "$REPO_ROOT" == "$NVIM_CONFIG" ]]; then
  ok "repo 本身就在 ~/.config/nvim"
elif [[ -L "$NVIM_CONFIG" && "$(readlink "$NVIM_CONFIG")" == "$REPO_ROOT" ]]; then
  ok "~/.config/nvim 已 symlink 到 repo"
else
  mkdir -p "$(dirname "$NVIM_CONFIG")"
  if [[ -e "$NVIM_CONFIG" || -L "$NVIM_CONFIG" ]]; then
    bak="$NVIM_CONFIG.bak.$(date +%Y%m%d_%H%M%S)"
    mv "$NVIM_CONFIG" "$bak"; warn "既有 ~/.config/nvim 已備份為 $bak"
  fi
  ln -sfn "$REPO_ROOT" "$NVIM_CONFIG"
  ok "已建立 ~/.config/nvim -> $REPO_ROOT"
fi

# ============ 6. 部署設定 symlink（ghostty / tmux）============
step "6/8 部署設定 symlink"
link() {  # $1 = repo 內來源, $2 = 目的地
  local src="$1" dest="$2"
  [[ -e "$src" ]] || { warn "找不到來源 $src，略過"; return 0; }
  mkdir -p "$(dirname "$dest")"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    ok "$(basename "$dest") 已連結"; return 0
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    local bak="$dest.bak.$(date +%Y%m%d_%H%M%S)"
    mv "$dest" "$bak"; warn "既有 $dest 已備份為 $bak"
  fi
  ln -sfn "$src" "$dest"
  ok "$dest -> $src"
}
link "$REPO_ROOT/configs/ghostty.config"    "$HOME/.config/ghostty/config"
link "$REPO_ROOT/script/devtools/tmux.conf" "$HOME/.tmux.conf"
link "$REPO_ROOT/configs/yazi"              "$HOME/.config/yazi"

# xlsx 預覽需要 xlsx2csv（純 Python，PyPI）。用 uv tool 裝成獨立工具，
# 不汙染系統 Python，也不用 pipx。uv 若不在就跳過，只影響 xlsx 預覽。
if [[ "$INSTALL_OPTIONAL" == "1" ]]; then
  if command -v uv >/dev/null 2>&1; then
    if command -v xlsx2csv >/dev/null 2>&1; then
      ok "xlsx2csv 已安裝"
    elif uv tool install xlsx2csv >/dev/null 2>&1; then
      ok "xlsx2csv 安裝完成（uv tool）"
    else
      warn "xlsx2csv 安裝失敗——yazi 的 xlsx 預覽會失效，其餘不受影響"
    fi
  else
    warn "找不到 uv，略過 xlsx2csv（yazi 的 xlsx 預覽會失效）"
  fi
fi

# ============ 7. tmux 外掛（TPM）============
step "7/8 tmux 外掛（TPM）"
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ -d "$TPM_DIR" ]]; then
  ok "TPM 已存在"
else
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
  ok "TPM clone 完成"
fi
[[ -x "$TPM_DIR/bin/install_plugins" ]] && "$TPM_DIR/bin/install_plugins" >/dev/null 2>&1 || true
ok "TPM 外掛已安裝 / 更新"

# ============ 8. 同步 nvim 外掛（Lazy）============
step "8/8 同步 nvim 外掛（Lazy）"
if nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1; then
  ok "Lazy sync 完成"
else
  warn "Lazy sync 非零結束——可手動開一次 nvim 觀察，或稍後重跑本腳本"
fi

# LSP server / formatter / DAP 安裝。
# mason.nvim 沒有 ensure_installed 選項，清單掛在 lua/chadrc.lua 的 M.mason.pkgs
# （= nvconfig.mason.pkgs），由這支腳本實際安裝。少了這步，開專案時會噴
# "Spawning language server ... failed"。詳細的坑（非同步安裝被提前終止、
# :MasonInstallAll 在 headless 下不存在）寫在 script/mason-install.lua 的檔頭。
MASON_LUA="$REPO_ROOT/script/mason-install.lua"
if [[ -f "$MASON_LUA" ]]; then
  info "安裝 LSP server / formatter（可能需要數分鐘）…"
  if nvim --headless -c "luafile $MASON_LUA" >/dev/null 2>&1; then
    ok "LSP / formatter 安裝完成"
  else
    warn "部分套件未裝完——可在 nvim 內重跑 :MasonInstallAll"
  fi
else
  warn "找不到 $MASON_LUA，請在 nvim 內手動執行 :MasonInstallAll"
fi

# ============ 完成提醒 ============
cat <<EOF

${B}✓ 安裝 / 部署完成${N}

後續手動事項：
  ${B}•${N} 開 Ghostty → 字型設為 "JetBrainsMono Nerd Font Mono"（若未自動套用）
  ${B}•${N} 重啟 Ghostty 讓設定生效
  ${B}•${N} tmux 首次進入後可按 prefix(Ctrl-b) + I 再確認外掛
  ${B}•${N} 切換鍵：cmd/opt+數字 = nvim buffer；opt+shift+數字 = tmux window
  ${B}•${N} 提醒：cmd+shift+3/4/5 是 macOS 系統截圖（本腳本不改系統設定）

本腳本可安全重跑（已安裝 / 已連結會自動跳過並印綠勾）。
EOF
