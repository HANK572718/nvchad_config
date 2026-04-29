#Requires -RunAsAdministrator
<#
.SYNOPSIS
    MSYS2 一鍵安裝與環境配置腳本（Windows）

.DESCRIPTION
    自動下載、靜默安裝 MSYS2，初始化 pacman，安裝常用開發工具，
    並將 UCRT64 路徑寫入使用者環境變數、系統環境變數（供 SSH 遠端使用）
    與 PowerShell Profile。

.PARAMETER InstallDir
    MSYS2 安裝目錄，預設為 C:\msys64

.PARAMETER Packages
    額外要安裝的 MSYS2 套件（逗號分隔），預設安裝 fd, ripgrep, make, gcc, git

.PARAMETER SkipProfileUpdate
    如果指定，跳過 PowerShell Profile 更新

.EXAMPLE
    .\install-msys2.ps1
    .\install-msys2.ps1 -InstallDir "D:\msys64"
    .\install-msys2.ps1 -Packages "mingw-w64-ucrt-x86_64-cmake,mingw-w64-ucrt-x86_64-ninja"
#>

param(
    [string]$InstallDir = "C:\msys64",
    [string]$Packages = "",
    [switch]$SkipProfileUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Config ---
$InstallerUrl = "https://github.com/msys2/msys2-installer/releases/download/2024-12-08/msys2-x86_64-20241208.exe"
$InstallerPath = "$env:TEMP\msys2-installer.exe"
$Ucrt64Bin = "$InstallDir\ucrt64\bin"
$UsrBin = "$InstallDir\usr\bin"
$BashExe = "$InstallDir\usr\bin\bash.exe"

# UCRT64 packages (installed via: pacman -S --needed)
$DefaultPackages = @(
    "mingw-w64-ucrt-x86_64-fd"
    "mingw-w64-ucrt-x86_64-ripgrep"
    "mingw-w64-ucrt-x86_64-make"
    "mingw-w64-ucrt-x86_64-gcc"
    "mingw-w64-ucrt-x86_64-git"
)

# MSYS layer packages (rsync etc. live here, not in ucrt64)
$MsysPackages = @(
    "rsync"
)

# --- Helper ---
function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ">>> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [!!] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

# =============================================================
# Step 0: Pre-flight check
# =============================================================
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  MSYS2 Installer for Windows" -ForegroundColor Magenta
Write-Host "  Install dir : $InstallDir" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

if (Test-Path $BashExe) {
    Write-Warn "MSYS2 already installed at $InstallDir"
    $answer = Read-Host "Reinstall? (y/N)"
    if ($answer -ne 'y') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

# =============================================================
# Step 1: Download installer
# =============================================================
Write-Step "Downloading MSYS2 installer..."

if (Test-Path $InstallerPath) {
    Write-Warn "Installer already cached at $InstallerPath, reusing."
} else {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
        Write-Ok "Downloaded to $InstallerPath"
    }
    catch {
        Write-Fail "Download failed: $_"
        exit 1
    }
}

# =============================================================
# Step 2: Silent install
# =============================================================
Write-Step "Installing MSYS2 to $InstallDir (silent)..."

# If the directory already exists, remove it first so the installer does not
# encounter an existing-directory conflict (which causes exit code 1 even
# though the installation actually succeeds in the background).
if (Test-Path $InstallDir) {
    Write-Warn "Removing existing $InstallDir before reinstall..."
    Remove-Item -Recurse -Force $InstallDir
    Write-Ok "Removed $InstallDir"
}

try {
    # Qt Installer Framework silent flags:
    #   in            = install operation
    #   --root        = target directory
    #   --accept-licenses          = auto-accept all licence agreements
    #   --accept-messages          = auto-dismiss any message dialogs
    #   --confirm-command          = suppress final confirmation prompt
    $proc = Start-Process -FilePath $InstallerPath `
        -ArgumentList "in", "--root", $InstallDir,
                      "--accept-licenses", "--accept-messages", "--confirm-command" `
        -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Fail "Installer exited with code $($proc.ExitCode)"
        exit 1
    }
    Write-Ok "MSYS2 installed successfully."
}
catch {
    Write-Fail "Installation failed: $_"
    exit 1
}

# =============================================================
# Step 3: Initialize pacman & update
# =============================================================
Write-Step "Initializing pacman and updating packages..."

# First update may close the terminal, so we run it twice
& $BashExe -lc "pacman -Syu --noconfirm" 2>$null
Start-Sleep -Seconds 2
& $BashExe -lc "pacman -Syu --noconfirm"

Write-Ok "pacman updated."

# =============================================================
# Step 4: Install default packages
# =============================================================
Write-Step "Installing default packages..."

# 4a: UCRT64 packages
$allPackages = $DefaultPackages
if ($Packages -ne "") {
    $allPackages += ($Packages -split ',')
}

$pkgList = $allPackages -join ' '
& $BashExe -lc "pacman -S --needed --noconfirm $pkgList"
Write-Ok "UCRT64 packages installed: $pkgList"

# 4b: MSYS layer packages (rsync, etc.)
$msysPkgList = $MsysPackages -join ' '
& $BashExe -lc "pacman -S --needed --noconfirm $msysPkgList"
Write-Ok "MSYS packages installed: $msysPkgList"

# =============================================================
# Step 5: Set environment variables (User scope)
# =============================================================
Write-Step "Configuring environment variables..."

# Set MY_UNIX_TOOLS
[Environment]::SetEnvironmentVariable("MY_UNIX_TOOLS", $Ucrt64Bin, "User")
Write-Ok "MY_UNIX_TOOLS = $Ucrt64Bin"

# Add to User PATH (both ucrt64/bin and usr/bin)
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathsToAdd = @($Ucrt64Bin, $UsrBin)
$changed = $false

foreach ($p in $pathsToAdd) {
    if ($userPath -split ';' -notcontains $p) {
        $userPath = "$p;$userPath"
        $changed = $true
        Write-Ok "Added to PATH: $p"
    } else {
        Write-Warn "Already in PATH: $p"
    }
}

if ($changed) {
    [Environment]::SetEnvironmentVariable("Path", $userPath, "User")
    Write-Ok "User PATH updated."
}

# Refresh current session
$env:MY_UNIX_TOOLS = $Ucrt64Bin
$env:Path = "$Ucrt64Bin;$UsrBin;$env:Path"

# =============================================================
# Step 6: Set System PATH (for SSH / remote access)
# =============================================================
Write-Step "Configuring System-level PATH (for SSH remote access)..."

$sysPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$sysChanged = $false

foreach ($p in $pathsToAdd) {
    if ($sysPath -split ';' -notcontains $p) {
        $sysPath = "$p;$sysPath"
        $sysChanged = $true
        Write-Ok "Added to System PATH: $p"
    } else {
        Write-Warn "Already in System PATH: $p"
    }
}

if ($sysChanged) {
    [Environment]::SetEnvironmentVariable("Path", $sysPath, "Machine")
    Write-Ok "System PATH updated."
}

# Restart sshd if running so it picks up the new System PATH
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshd -and $sshd.Status -eq 'Running') {
    Restart-Service sshd -ErrorAction SilentlyContinue
    Write-Ok "sshd restarted to load new System PATH."
} elseif ($sshd) {
    Write-Warn "sshd exists but is not running. Start it manually if you need SSH access."
} else {
    Write-Warn "sshd not installed. Remote rsync via SSH will not work until OpenSSH Server is set up."
}

# =============================================================
# Step 7: Update PowerShell Profile
# =============================================================
if (-not $SkipProfileUpdate) {
    Write-Step "Updating PowerShell Profile..."

    $profileMarker = "# --- MSYS2 Environment (auto-generated) ---"
    $profileBlock = @"

$profileMarker
`$env:MY_UNIX_TOOLS = "$Ucrt64Bin"
`$env:Path = "$Ucrt64Bin;$UsrBin;`$env:Path"
# --- End MSYS2 ---
"@

    if (!(Test-Path $PROFILE)) {
        New-Item -Path $PROFILE -ItemType File -Force | Out-Null
        Write-Ok "Created new profile at $PROFILE"
    }

    $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($profileContent -and $profileContent.Contains($profileMarker)) {
        Write-Warn "MSYS2 block already exists in profile, skipping."
    } else {
        Add-Content -Path $PROFILE -Value $profileBlock
        Write-Ok "Added MSYS2 block to $PROFILE"
    }
}

# =============================================================
# Step 8: Cleanup
# =============================================================
Write-Step "Cleaning up..."
Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
Write-Ok "Installer removed."

# =============================================================
# Step 9: Verification
# =============================================================
Write-Step "Verifying installation..."

$checks = @(
    @{ Name = "bash";   Cmd = "bash" }
    @{ Name = "pacman"; Cmd = "pacman" }
    @{ Name = "gcc";    Cmd = "gcc" }
    @{ Name = "fd";     Cmd = "fd" }
    @{ Name = "rg";     Cmd = "rg" }
    @{ Name = "make";   Cmd = "make" }
    @{ Name = "rsync";  Cmd = "rsync" }
)

$allGood = $true
$failedTools = @()
foreach ($c in $checks) {
    $found = Get-Command $c.Cmd -ErrorAction SilentlyContinue
    if ($found) {
        Write-Ok "$($c.Name) -> $($found.Source)"
    } else {
        Write-Fail "$($c.Name) not found"
        $failedTools += $c.Name
        $allGood = $false
    }
}

# --- PATH priority check ---
Write-Step "Checking PATH priority (MSYS2 vs Git)..."

$bashAll = Get-Command bash -All -ErrorAction SilentlyContinue
if ($bashAll -and $bashAll.Count -gt 0) {
    $first = $bashAll[0].Source
    if ($first -like "*msys64*") {
        Write-Ok "bash priority: MSYS2 is first -> $first"
    } else {
        Write-Warn "bash priority: MSYS2 is NOT first -> $first"
        Write-Warn "Another bash (e.g. Git Bash) may take precedence."
    }
} else {
    Write-Fail "bash not found in PATH at all."
}

# --- System PATH check for SSH ---
Write-Step "Checking System PATH for SSH remote access..."

$sysPathCheck = [Environment]::GetEnvironmentVariable("Path", "Machine")
$sysHasUcrt = ($sysPathCheck -split ';') -contains $Ucrt64Bin
$sysHasUsr  = ($sysPathCheck -split ';') -contains $UsrBin

if ($sysHasUcrt -and $sysHasUsr) {
    Write-Ok "System PATH includes MSYS2 paths. SSH remote tools (rsync, etc.) are available."
} else {
    Write-Fail "System PATH is missing MSYS2 paths. Remote rsync via SSH will NOT work."
    Write-Warn "Try re-running this script as Administrator."
}

# =============================================================
# Summary
# =============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  Installation Summary" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""

if ($allGood) {
    Write-Host "  ALL CHECKS PASSED" -ForegroundColor Green
    Write-Host ""
    Write-Host "  What to do next:" -ForegroundColor Cyan
    Write-Host "    1. Restart your PowerShell terminal for PATH changes to take full effect." -ForegroundColor White
    Write-Host "    2. Local usage  : fd, rg, gcc, make, rsync, bash are ready to use." -ForegroundColor White
    Write-Host "    3. Remote rsync : From a Linux machine, run:" -ForegroundColor White
    Write-Host "         rsync -avz /src/ user@this-windows-ip:/cygdrive/c/Users/.../" -ForegroundColor Gray
    Write-Host "    4. Verify SSH   : ssh user@this-windows-ip `"rsync --version`"" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "  SOME CHECKS FAILED: $($failedTools -join ', ')" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Troubleshooting:" -ForegroundColor Yellow
    Write-Host "    1. Close ALL terminals and open a new PowerShell as Administrator." -ForegroundColor White
    Write-Host "    2. Re-run this script:  .\install-msys2.ps1" -ForegroundColor White
    Write-Host "    3. If pacman failed (DNS timeout), check your network connection." -ForegroundColor White
    Write-Host "       MSYS2 DNS issue workaround: create C:\msys64\etc\resolv.conf with:" -ForegroundColor White
    Write-Host "         nameserver 8.8.8.8" -ForegroundColor Gray
    Write-Host "         nameserver 8.8.4.4" -ForegroundColor Gray
    Write-Host "    4. Then retry:  C:\msys64\usr\bin\bash.exe -lc `"pacman -S --needed --noconfirm rsync`"" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  If issues persist, manually verify:" -ForegroundColor Yellow
    Write-Host "    - User   PATH: [Environment]::GetEnvironmentVariable('Path','User')" -ForegroundColor Gray
    Write-Host "    - System PATH: [Environment]::GetEnvironmentVariable('Path','Machine')" -ForegroundColor Gray
    Write-Host "    - Profile    : Get-Content `$PROFILE" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "  Installed at : $InstallDir" -ForegroundColor DarkGray
Write-Host "  Profile      : $PROFILE" -ForegroundColor DarkGray
Write-Host ""
