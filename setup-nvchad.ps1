#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NvChad 設定 Windows 一鍵部署（對應 setup-nvchad.sh 的 Windows 版）。

.DESCRIPTION
    讓任何一台全新 Windows 機器一行指令裝好完整的 nvim 開發環境。流程：
      1. 確保 git 與 Neovim 已安裝（缺則用 winget 裝）。
      2. 用 git + HTTPS 把本設定 clone 到 %LOCALAPPDATA%\nvim
         （已存在則先備份；GitHub 為公開 repo，不需 SSH 金鑰）。
      3. 呼叫 clone 下來的 window_tool_script\install-msys2.ps1，安裝 MSYS2
         工具鏈（ripgrep / fd / gcc / make / chafa / bat / fzf）與 Node.js LTS。
      4. 以 headless 模式跑 Lazy sync，安裝所有 plugin。

    可直接從 GitHub 一行執行（以「系統管理員」開啟 PowerShell）：

        irm https://raw.githubusercontent.com/HANK572718/nvchad_config/main/setup-nvchad.ps1 | iex

    或先存檔再跑：

        .\setup-nvchad.ps1
        .\setup-nvchad.ps1 -Branch feat/portable-bootstrap -SkipTools

.PARAMETER Branch
    要 clone 的分支，預設 main。

.PARAMETER NvimConfig
    nvim 設定目標目錄，預設 %LOCALAPPDATA%\nvim。

.PARAMETER SkipTools
    跳過 install-msys2.ps1（MSYS2 工具鏈 + node）。

.PARAMETER SkipSync
    跳過 Lazy plugin 同步。

.NOTES
    與 setup-nvchad.sh 的差異：Windows 公開 repo 一律走 HTTPS，故不移植
    bash 版的「步驟 3：SSH Key 設定」（GitHub 公開 repo 不需要金鑰）。
#>

param(
    [string]$Branch     = "main",
    [string]$NvimConfig = "$env:LOCALAPPDATA\nvim",
    [switch]$SkipTools,
    [switch]$SkipSync
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── 執行期管理員檢查 ──────────────────────────────────────────
# #Requires -RunAsAdministrator 只在「以檔案執行」時強制；透過 irm|iex
# 把內容當字串跑時不會被檢查，故這裡再做一次執行期檢查，讓兩種執行方式
# 都能在一開始就明確擋下非管理員（否則會跑到寫 System PATH / 裝 MSYS2 才失敗）。
$__principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $__principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[FAIL] 需要系統管理員權限。" -ForegroundColor Red
    Write-Host "       請以「系統管理員」開啟 PowerShell 後再執行：" -ForegroundColor Yellow
    Write-Host "       irm https://raw.githubusercontent.com/HANK572718/nvchad_config/main/setup-nvchad.ps1 | iex" -ForegroundColor Cyan
    exit 1
}

# ── 設定（公開 repo，走 HTTPS）────────────────────────────────
$GitHubUser = "HANK572718"
$GitHubRepo = "nvchad_config"
$RepoHttps  = "https://github.com/$GitHubUser/$GitHubRepo.git"

# ── 輸出小工具 ────────────────────────────────────────────────
function Write-Step { param([string]$m) Write-Host ""; Write-Host "== $m ==" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "  [OK] $m"   -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "  [!!] $m"   -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red }

# winget 安裝小工具：偵測 command 缺失才裝。
function Install-IfMissing {
    param([string]$Command, [string]$WingetId, [string]$DisplayName)
    if (Get-Command $Command -ErrorAction SilentlyContinue) {
        Write-Ok "$DisplayName already present -> $((Get-Command $Command).Source)"
        return $true
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Fail "$DisplayName missing and winget unavailable. Install $DisplayName manually."
        return $false
    }
    Write-Warn "$DisplayName not found; installing via winget ($WingetId)..."
    try {
        winget install -e --id $WingetId --accept-source-agreements --accept-package-agreements
        Write-Ok "$DisplayName installed. (May need a new terminal to land on PATH.)"
        return $true
    }
    catch {
        Write-Fail "winget install of $DisplayName failed: $_"
        return $false
    }
}

Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  NvChad Windows one-shot installer" -ForegroundColor Magenta
Write-Host "  repo   : $RepoHttps" -ForegroundColor Magenta
Write-Host "  branch : $Branch" -ForegroundColor Magenta
Write-Host "  target : $NvimConfig" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

# =============================================================
# Step 1: 確保 git 與 Neovim 已安裝
# =============================================================
Write-Step "Step 1: ensuring git and Neovim are installed"

$gitOk  = Install-IfMissing -Command "git"  -WingetId "Git.Git"        -DisplayName "Git"
$nvimOk = Install-IfMissing -Command "nvim" -WingetId "Neovim.Neovim"  -DisplayName "Neovim"

if (-not $gitOk) { Write-Fail "git is required to clone the config. Aborting."; exit 1 }

# winget 剛裝的 git/nvim 可能還不在「當前 session」PATH，補進來讓後續步驟可用。
foreach ($p in @(
    "$env:ProgramFiles\Git\cmd",
    "$env:ProgramFiles\Neovim\bin",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
)) {
    if ((Test-Path $p) -and (($env:Path -split ';') -notcontains $p)) {
        $env:Path = "$p;$env:Path"
    }
}

# =============================================================
# Step 2: clone 設定（git + HTTPS；已存在則備份）
# =============================================================
Write-Step "Step 2: cloning config to $NvimConfig (git+https)"

$gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $gitExe) { Write-Fail "git still not on PATH. Open a new admin PowerShell and re-run."; exit 1 }

if (Test-Path $NvimConfig) {
    # 已是同一個 repo 的 working tree → 直接拉更新；否則備份後重新 clone。
    $isRepo = Test-Path (Join-Path $NvimConfig ".git")
    if ($isRepo) {
        Write-Warn "$NvimConfig already a git repo; fetching latest on $Branch..."
        & $gitExe -C $NvimConfig fetch origin $Branch 2>&1 | Out-Null
        & $gitExe -C $NvimConfig checkout $Branch 2>&1 | Out-Null
        & $gitExe -C $NvimConfig pull --ff-only origin $Branch 2>&1 | Out-Null
        Write-Ok "Updated existing config."
    } else {
        $backup = "$NvimConfig.bak.$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
        Write-Warn "$NvimConfig exists (not a repo); backing up to $backup"
        Move-Item -Path $NvimConfig -Destination $backup
        & $gitExe clone --branch $Branch $RepoHttps $NvimConfig
        Write-Ok "Cloned fresh config (old one backed up)."
    }
} else {
    & $gitExe clone --branch $Branch $RepoHttps $NvimConfig
    Write-Ok "Cloned config to $NvimConfig."
}

# =============================================================
# Step 3: MSYS2 工具鏈 + Node.js（呼叫 clone 下來的子腳本）
# =============================================================
if (-not $SkipTools) {
    Write-Step "Step 3: installing MSYS2 toolchain + Node.js"

    $toolScript = Join-Path $NvimConfig "window_tool_script\install-msys2.ps1"
    if (Test-Path $toolScript) {
        # 用同一個 admin session 直接點源呼叫；install-msys2.ps1 自帶
        # #Requires -RunAsAdministrator，本腳本也要求管理員，故可直接執行。
        # -NonInteractive：MSYS2 已裝時不問 Reinstall?，避免無人值守流程卡住。
        & $toolScript -NonInteractive
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Toolchain script finished."
        } else {
            Write-Warn "Toolchain script reported issues (exit $LASTEXITCODE); check its output above. Continuing."
        }
    } else {
        Write-Fail "Tool script not found at $toolScript (clone incomplete?). Skipping toolchain."
    }
} else {
    Write-Warn "Step 3 skipped (-SkipTools)."
}

# =============================================================
# Step 4: Lazy plugin 同步（headless）
# =============================================================
if (-not $SkipSync) {
    Write-Step "Step 4: syncing Neovim plugins (Lazy)"

    # nvim 可能剛由 winget 裝、還不在當前 session PATH；解析實際路徑。
    $nvimExe = (Get-Command nvim -ErrorAction SilentlyContinue).Source
    if (-not $nvimExe -and (Test-Path "$env:ProgramFiles\Neovim\bin\nvim.exe")) {
        $nvimExe = "$env:ProgramFiles\Neovim\bin\nvim.exe"
    }
    if ($nvimExe) {
        Write-Warn "Running headless Lazy sync (may take 2-5 minutes)..."
        & $nvimExe --headless "+Lazy! sync" +qa 2>&1 | Out-Null
        Write-Ok "Plugin sync done."
    } else {
        Write-Warn "nvim not resolvable yet. Open a NEW terminal and run: nvim +'Lazy! sync' +qa"
    }
} else {
    Write-Warn "Step 4 skipped (-SkipSync)."
}

# =============================================================
# 完成
# =============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Done. Open a NEW terminal, then run: nvim" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next inside nvim: :MasonInstall pyright black isort debugpy" -ForegroundColor Cyan
Write-Host "  Keys: <Space>ff find files   <Space>fw live grep   <F5> debug" -ForegroundColor Cyan
Write-Host ""
