# SSH Manager - Windows OpenSSH TUI Management Tool
# Requires administrator privileges

#Requires -Version 5.1
Set-StrictMode -Version Latest

# ─── Privilege Check ─────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Please run this script as administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as administrator'" -ForegroundColor Yellow
    pause
    exit 1
}

$ErrorActionPreference = 'Continue'

# ─── Constants ────────────────────────────────────────────────────────
$SSHD_CONFIG        = "$env:ProgramData\ssh\sshd_config"
$SSH_DIR            = "$env:ProgramData\ssh"
$AUTH_KEYS_ADMIN    = "$env:ProgramData\ssh\administrators_authorized_keys"
$FW_RULE_NAME       = "OpenSSH-Server-In-TCP"

# ─── UI Helpers ───────────────────────────────────────────────────────
function Write-Header {
    param([string]$Title)
    $line = "=" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    $pad = [math]::Max(0, [math]::Floor((60 - $Title.Length) / 2))
    Write-Host (" " * $pad + $Title) -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  --- $Title ---" -ForegroundColor Yellow
}

function Write-Ok   { param([string]$Msg) Write-Host "  [+] $Msg" -ForegroundColor Green }
function Write-Fail { param([string]$Msg) Write-Host "  [x] $Msg" -ForegroundColor Red }
function Write-Warn { param([string]$Msg) Write-Host "  [!] $Msg" -ForegroundColor Yellow }
function Write-Info { param([string]$Msg) Write-Host "  [i] $Msg" -ForegroundColor Cyan }

function Pause-Menu {
    Write-Host ""
    Read-Host "  Press Enter to continue"
}

function Confirm {
    param([string]$Prompt)
    $ans = Read-Host "  $Prompt (Y/N)"
    return ($ans -match "^[Yy]$")
}

# ─── sshd_config Helpers ─────────────────────────────────────────────
function Get-ConfigValue {
    param([string]$Key)
    if (-not (Test-Path $SSHD_CONFIG)) { return $null }
    $line = Get-Content $SSHD_CONFIG |
        Where-Object { $_ -match "^\s*$Key\s+" } |
        Select-Object -Last 1
    if ($line) { return ($line -replace "^\s*$Key\s+", "").Trim() }
    return $null
}

function Set-ConfigValue {
    param([string]$Key, [string]$Value)
    if (-not (Test-Path $SSHD_CONFIG)) {
        Write-Fail "sshd_config not found: $SSHD_CONFIG"
        return $false
    }
    $content = Get-Content $SSHD_CONFIG
    $found   = $false
    $updated = $content | ForEach-Object {
        if ($_ -match "^#?\s*${Key}\s+") { $found = $true; "$Key $Value" }
        else { $_ }
    }
    if (-not $found) { $updated += "$Key $Value" }
    $updated | Set-Content $SSHD_CONFIG -Encoding UTF8
    return $true
}

function Remove-ConfigKey {
    param([string]$Key)
    if (-not (Test-Path $SSHD_CONFIG)) { return }
    $content = Get-Content $SSHD_CONFIG | Where-Object { $_ -notmatch "^\s*${Key}\s+" }
    $content | Set-Content $SSHD_CONFIG -Encoding UTF8
}

# ─── 1. Status Overview ───────────────────────────────────────────────
function Show-Status {
    Write-Header "SSH Status Overview"

    # SSH Client
    Write-Section "SSH Client"
    $sshExe = Get-Command ssh -ErrorAction SilentlyContinue
    if ($sshExe) {
        $ver = (& ssh -V 2>&1).ToString()
        Write-Ok "Installed: $ver"
        Write-Info "Path: $($sshExe.Source)"
    } else {
        Write-Fail "SSH client not found in PATH"
    }

    $clientCap = Get-WindowsCapability -Online -Name "OpenSSH.Client*" -ErrorAction SilentlyContinue
    if ($clientCap) {
        $color = if ($clientCap.State -eq "Installed") { "Green" } else { "Yellow" }
        Write-Host "  [i] Windows Feature: OpenSSH.Client -> $($clientCap.State)" -ForegroundColor $color
    }

    # SSH Server
    Write-Section "SSH Server (sshd)"
    $serverCap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" -ErrorAction SilentlyContinue
    if ($serverCap) {
        $color = if ($serverCap.State -eq "Installed") { "Green" } else { "Yellow" }
        Write-Host "  [i] Windows Feature: OpenSSH.Server -> $($serverCap.State)" -ForegroundColor $color
    }

    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($svc) {
        $color = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
        $icon  = if ($svc.Status -eq "Running") { "+" } else { "x" }
        Write-Host "  [$icon] sshd service: $($svc.Status)  (StartType: $($svc.StartType))" -ForegroundColor $color
    } else {
        Write-Fail "sshd service not found (OpenSSH Server not installed)"
    }

    # Current config values
    Write-Section "Current Configuration"
    $port    = Get-ConfigValue "Port";                    if (-not $port) { $port    = "22 (default)" }
    $pwAuth  = Get-ConfigValue "PasswordAuthentication";  if (-not $pwAuth) { $pwAuth  = "yes (default)" }
    $pkAuth  = Get-ConfigValue "PubkeyAuthentication";    if (-not $pkAuth) { $pkAuth  = "yes (default)" }
    $rootL   = Get-ConfigValue "PermitRootLogin";         if (-not $rootL) { $rootL   = "prohibit-password (default)" }

    Write-Info "Port                  : $port"
    $pwColor = if ($pwAuth -like "no*") { "Green" } else { "Yellow" }
    Write-Host "  [i] PasswordAuthentication : $pwAuth" -ForegroundColor $pwColor
    Write-Info "PubkeyAuthentication  : $pkAuth"
    Write-Info "PermitRootLogin       : $rootL"

    # Listening ports
    Write-Section "Network Listening"
    $rawPort = ($port -split " ")[0]
    try {
        $listeners = netstat -an 2>$null |
            Select-String "TCP\s+.*:($rawPort|22)\s+.*LISTENING"
        if ($listeners) {
            $listeners | ForEach-Object { Write-Ok $_.ToString().Trim() }
        } else {
            Write-Warn "Port $rawPort is not listening (service may be stopped)"
        }
    } catch { Write-Warn "Could not check listening ports" }

    # Firewall
    Write-Section "Firewall"
    $fw = Get-NetFirewallRule -Name $FW_RULE_NAME -ErrorAction SilentlyContinue
    if ($fw) {
        $color = if ($fw.Enabled -eq "True") { "Green" } else { "Yellow" }
        $icon  = if ($fw.Enabled -eq "True") { "+" } else { "!" }
        $portFilter = $fw | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
        $fwPort = if ($portFilter) { $portFilter.LocalPort } else { "?" }
        Write-Host "  [$icon] Rule '$FW_RULE_NAME': Enabled=$($fw.Enabled), Port=$fwPort" -ForegroundColor $color
    } else {
        Write-Fail "Firewall rule '$FW_RULE_NAME' not found"
    }

    Pause-Menu
}

# ─── 2. Install / Repair ──────────────────────────────────────────────
function Install-SshComponents {
    Write-Header "Install / Repair SSH"

    # OpenSSH Client
    Write-Section "OpenSSH Client"
    $cap = Get-WindowsCapability -Online -Name "OpenSSH.Client*" -ErrorAction SilentlyContinue
    if ($cap -and $cap.State -eq "Installed") {
        Write-Ok "OpenSSH Client already installed"
    } elseif ($cap) {
        if (Confirm "OpenSSH Client not installed. Install now?") {
            Write-Info "Installing (requires internet)..."
            try {
                Add-WindowsCapability -Online -Name $cap.Name | Out-Null
                Write-Ok "OpenSSH Client installed successfully"
            } catch { Write-Fail "Install failed: $_" }
        }
    } else {
        Write-Warn "Could not detect OpenSSH Client feature"
    }

    # OpenSSH Server
    Write-Section "OpenSSH Server"
    $srvCap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" -ErrorAction SilentlyContinue
    if ($srvCap -and $srvCap.State -eq "Installed") {
        Write-Ok "OpenSSH Server already installed"
    } elseif ($srvCap) {
        if (Confirm "OpenSSH Server not installed. Install now?") {
            Write-Info "Installing (requires internet)..."
            try {
                Add-WindowsCapability -Online -Name $srvCap.Name | Out-Null
                Write-Ok "OpenSSH Server installed"

                Write-Info "Setting sshd to start automatically..."
                Set-Service -Name sshd -StartupType Automatic
                Start-Service sshd
                Write-Ok "sshd service started"

                Write-Info "Adding firewall rule..."
                if (-not (Get-NetFirewallRule -Name $FW_RULE_NAME -ErrorAction SilentlyContinue)) {
                    New-NetFirewallRule -Name $FW_RULE_NAME `
                        -DisplayName "OpenSSH Server (sshd)" `
                        -Enabled True -Direction Inbound -Protocol TCP `
                        -Action Allow -LocalPort 22 | Out-Null
                    Write-Ok "Firewall rule created (Port 22)"
                } else {
                    Write-Ok "Firewall rule already exists"
                }
            } catch { Write-Fail "Install failed: $_" }
        }
    } else {
        Write-Warn "Could not detect OpenSSH Server feature"
    }

    # Host keys
    Write-Section "Host Keys"
    $keyFiles = @("$SSH_DIR\ssh_host_rsa_key", "$SSH_DIR\ssh_host_ecdsa_key", "$SSH_DIR\ssh_host_ed25519_key")
    $missing  = $keyFiles | Where-Object { -not (Test-Path $_) }
    if ($missing.Count -eq 0) {
        Write-Ok "All host keys present"
    } else {
        Write-Warn "Missing: $($missing -join ', ')"
        if (Confirm "Regenerate all host keys?") {
            $sshKeygen = "$env:SystemRoot\System32\OpenSSH\ssh-keygen.exe"
            if (Test-Path $sshKeygen) {
                & $sshKeygen -A 2>&1 | ForEach-Object { Write-Info $_ }
                Write-Ok "Host keys generated"
            } else {
                Write-Fail "ssh-keygen not found at $sshKeygen"
            }
        }
    }

    Pause-Menu
}

# ─── 3. Service Management ────────────────────────────────────────────
function Manage-Service {
    while ($true) {
        Write-Header "Service Management"

        $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Fail "sshd service not found - please install OpenSSH Server first"
            Pause-Menu; return
        }

        $color = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "  Status   : " -NoNewline; Write-Host $svc.Status -ForegroundColor $color
        Write-Host "  StartType: $($svc.StartType)"
        Write-Host ""
        Write-Host "  [1] Start sshd"           -ForegroundColor White
        Write-Host "  [2] Stop sshd"            -ForegroundColor White
        Write-Host "  [3] Restart sshd"         -ForegroundColor White
        Write-Host "  [4] Set to Auto start"    -ForegroundColor White
        Write-Host "  [5] Set to Manual start"  -ForegroundColor White
        Write-Host "  [6] Disable service"      -ForegroundColor White
        Write-Host "  [0] Back"                 -ForegroundColor Gray
        Write-Host ""

        $ch = Read-Host "  Select"
        switch ($ch) {
            "1" { Start-Service   sshd -ErrorAction SilentlyContinue; Write-Ok "Started" }
            "2" { Stop-Service    sshd -ErrorAction SilentlyContinue; Write-Ok "Stopped" }
            "3" { Restart-Service sshd -ErrorAction SilentlyContinue; Write-Ok "Restarted" }
            "4" { Set-Service sshd -StartupType Automatic; Write-Ok "Set to Automatic" }
            "5" { Set-Service sshd -StartupType Manual;    Write-Ok "Set to Manual" }
            "6" {
                if (Confirm "Disable sshd service?") {
                    Stop-Service sshd -Force -ErrorAction SilentlyContinue
                    Set-Service  sshd -StartupType Disabled
                    Write-Ok "Service disabled"
                }
            }
            "0" { return }
            default { Write-Warn "Invalid option" }
        }
        Start-Sleep -Milliseconds 600
    }
}

# ─── 4. sshd_config Settings ─────────────────────────────────────────
function Manage-Config {
    while ($true) {
        Write-Header "sshd_config Settings"

        if (-not (Test-Path $SSHD_CONFIG)) {
            Write-Fail "sshd_config not found: $SSHD_CONFIG"
            Write-Warn "Please install OpenSSH Server first"
            Pause-Menu; return
        }

        # Read current values (show default when not set)
        $port      = Get-ConfigValue "Port"                    ; $portD      = if ($port)      { $port }      else { "22" }
        $pwAuth    = Get-ConfigValue "PasswordAuthentication"  ; $pwAuthD    = if ($pwAuth)    { $pwAuth }    else { "yes" }
        $pkAuth    = Get-ConfigValue "PubkeyAuthentication"    ; $pkAuthD    = if ($pkAuth)    { $pkAuth }    else { "yes" }
        $rootLogin = Get-ConfigValue "PermitRootLogin"         ; $rootLoginD = if ($rootLogin) { $rootLogin } else { "prohibit-password" }
        $maxTries  = Get-ConfigValue "MaxAuthTries"            ; $maxTriesD  = if ($maxTries)  { $maxTries }  else { "6" }
        $aliveInt  = Get-ConfigValue "ClientAliveInterval"     ; $aliveIntD  = if ($aliveInt)  { $aliveInt }  else { "0" }
        $aliveMax  = Get-ConfigValue "ClientAliveCountMax"     ; $aliveMaxD  = if ($aliveMax)  { $aliveMax }  else { "3" }
        $allowU    = Get-ConfigValue "AllowUsers"              ; $allowUD    = if ($allowU)    { $allowU }    else { "(all users)" }
        $denyU     = Get-ConfigValue "DenyUsers"               ; $denyUD     = if ($denyU)     { $denyU }     else { "(none)" }
        $x11       = Get-ConfigValue "X11Forwarding"           ; $x11D       = if ($x11)       { $x11 }       else { "no" }
        $subsystem = Get-ConfigValue "Subsystem"               ; $subsystemD = if ($subsystem) { $subsystem } else { "sftp sftp-server.exe" }
        $banner    = Get-ConfigValue "Banner"                  ; $bannerD    = if ($banner)    { $banner }    else { "(none)" }

        function Write-Cfg {
            param([string]$Num, [string]$Label, [string]$Val, [string]$Warn = "")
            $vc = if ($Warn -and $Val -eq $Warn) { "Yellow" } else { "Cyan" }
            Write-Host ("  [{0}] {1,-28}" -f $Num, $Label) -NoNewline -ForegroundColor White
            Write-Host $Val -ForegroundColor $vc
        }

        Write-Cfg  "1"  "Port"                    $portD
        Write-Cfg  "2"  "PasswordAuthentication"  $pwAuthD    "yes"
        Write-Cfg  "3"  "PubkeyAuthentication"    $pkAuthD
        Write-Cfg  "4"  "PermitRootLogin"         $rootLoginD "yes"
        Write-Cfg  "5"  "MaxAuthTries"            $maxTriesD
        Write-Cfg  "6"  "ClientAliveInterval (s)" $aliveIntD
        Write-Cfg  "7"  "ClientAliveCountMax"     $aliveMaxD
        Write-Cfg  "8"  "AllowUsers"              $allowUD
        Write-Cfg  "9"  "DenyUsers"               $denyUD
        Write-Cfg  "A"  "X11Forwarding"           $x11D       "yes"
        Write-Cfg  "B"  "Subsystem"               $subsystemD
        Write-Cfg  "C"  "Banner"                  $bannerD
        Write-Host ""
        Write-Host "  [R] Reload sshd (apply changes)" -ForegroundColor Green
        Write-Host "  [V] Validate config (sshd -t)"   -ForegroundColor Green
        Write-Host "  [E] Open sshd_config in Notepad"  -ForegroundColor Gray
        Write-Host "  [0] Back"                         -ForegroundColor Gray
        Write-Host ""

        $ch = (Read-Host "  Select").ToUpper()

        switch ($ch) {
            "1" {
                $v = Read-Host "  New Port (current: $portD, Enter=cancel)"
                if ($v -match "^\d+$" -and [int]$v -ge 1 -and [int]$v -le 65535) {
                    Set-ConfigValue "Port" $v | Out-Null
                    Write-Ok "Port set to $v"
                    if (Confirm "Also update firewall rule to port $v?") {
                        Remove-NetFirewallRule -Name $FW_RULE_NAME -ErrorAction SilentlyContinue
                        New-NetFirewallRule -Name $FW_RULE_NAME `
                            -DisplayName "OpenSSH Server (sshd)" `
                            -Enabled True -Direction Inbound -Protocol TCP `
                            -Action Allow -LocalPort ([int]$v) | Out-Null
                        Write-Ok "Firewall rule updated to port $v"
                    }
                } elseif ($v -ne "") { Write-Fail "Invalid port number" }
            }
            "2" {
                $new = if ($pwAuthD -eq "yes") { "no" } else { "yes" }
                $warn = if ($new -eq "yes") { " (WARNING: password login is a security risk)" } else { "" }
                if (Confirm "Toggle PasswordAuthentication: $pwAuthD -> $new$warn") {
                    Set-ConfigValue "PasswordAuthentication" $new | Out-Null
                    Write-Ok "Set to $new"
                }
            }
            "3" {
                $new = if ($pkAuthD -eq "yes") { "no" } else { "yes" }
                if (Confirm "Toggle PubkeyAuthentication: $pkAuthD -> $new") {
                    Set-ConfigValue "PubkeyAuthentication" $new | Out-Null
                    Write-Ok "Set to $new"
                }
            }
            "4" {
                Write-Info "Options: prohibit-password | yes | no | forced-commands-only"
                $v = Read-Host "  PermitRootLogin (current: $rootLoginD)"
                $valid = @("yes","no","prohibit-password","forced-commands-only")
                if ($v -ne "" -and $v -in $valid) {
                    Set-ConfigValue "PermitRootLogin" $v | Out-Null; Write-Ok "Set to $v"
                } elseif ($v -ne "") { Write-Fail "Invalid value. Options: $($valid -join ' | ')" }
            }
            "5" {
                $v = Read-Host "  MaxAuthTries (current: $maxTriesD, recommended: 3-6)"
                if ($v -match "^\d+$") { Set-ConfigValue "MaxAuthTries" $v | Out-Null; Write-Ok "Set to $v" }
                elseif ($v -ne "") { Write-Fail "Enter a number" }
            }
            "6" {
                $v = Read-Host "  ClientAliveInterval seconds (current: $aliveIntD, 0=off, recommended: 300)"
                if ($v -match "^\d+$") { Set-ConfigValue "ClientAliveInterval" $v | Out-Null; Write-Ok "Set to $v" }
                elseif ($v -ne "") { Write-Fail "Enter a number" }
            }
            "7" {
                $v = Read-Host "  ClientAliveCountMax (current: $aliveMaxD)"
                if ($v -match "^\d+$") { Set-ConfigValue "ClientAliveCountMax" $v | Out-Null; Write-Ok "Set to $v" }
                elseif ($v -ne "") { Write-Fail "Enter a number" }
            }
            "8" {
                Write-Info "Space-separated users, e.g.: alice bob domain\carol"
                Write-Info "Leave blank to remove restriction (allow all)"
                $v = Read-Host "  AllowUsers"
                if ($v -eq "") { Remove-ConfigKey "AllowUsers"; Write-Ok "AllowUsers restriction removed" }
                else { Set-ConfigValue "AllowUsers" $v | Out-Null; Write-Ok "Set to: $v" }
            }
            "9" {
                Write-Info "Space-separated users to block"
                Write-Info "Leave blank to remove DenyUsers"
                $v = Read-Host "  DenyUsers"
                if ($v -eq "") { Remove-ConfigKey "DenyUsers"; Write-Ok "DenyUsers removed" }
                else { Set-ConfigValue "DenyUsers" $v | Out-Null; Write-Ok "Set to: $v" }
            }
            "A" {
                $new = if ($x11D -eq "yes") { "no" } else { "yes" }
                if (Confirm "Toggle X11Forwarding: $x11D -> $new") {
                    Set-ConfigValue "X11Forwarding" $new | Out-Null; Write-Ok "Set to $new"
                }
            }
            "B" {
                Write-Info "Default: sftp   sftp-server.exe"
                $v = Read-Host "  Subsystem value (Enter=cancel)"
                if ($v -ne "") { Set-ConfigValue "Subsystem" $v | Out-Null; Write-Ok "Set to: $v" }
            }
            "C" {
                Write-Info "Path to a text file shown before login, or blank to remove"
                $v = Read-Host "  Banner file path"
                if ($v -eq "") { Remove-ConfigKey "Banner"; Write-Ok "Banner removed" }
                else { Set-ConfigValue "Banner" $v | Out-Null; Write-Ok "Set to: $v" }
            }
            "R" {
                $test = & sshd -t 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Restart-Service sshd -ErrorAction SilentlyContinue
                    Write-Ok "sshd restarted - changes applied"
                } else {
                    Write-Fail "Config validation failed - NOT restarting:"
                    $test | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
                }
            }
            "V" {
                Write-Info "Running: sshd -t"
                $result = & sshd -t 2>&1
                if ($LASTEXITCODE -eq 0) { Write-Ok "Config is valid" }
                else { $result | ForEach-Object { Write-Fail $_ } }
                Pause-Menu
            }
            "E" { Start-Process notepad.exe $SSHD_CONFIG }
            "0" { return }
            default { Write-Warn "Invalid option" }
        }
    }
}

# ─── 5. Key Management ────────────────────────────────────────────────
function Manage-Keys {
    while ($true) {
        Write-Header "Key Management"
        Write-Host "  [1] Show Host Key fingerprints"              -ForegroundColor White
        Write-Host "  [2] View administrators_authorized_keys"     -ForegroundColor White
        Write-Host "  [3] Add public key to authorized_keys"       -ForegroundColor White
        Write-Host "  [4] View authorized_keys for a user"         -ForegroundColor White
        Write-Host "  [5] Generate new key pair (client)"          -ForegroundColor White
        Write-Host "  [6] Fix authorized_keys permissions"         -ForegroundColor White
        Write-Host "  [0] Back"                                    -ForegroundColor Gray
        Write-Host ""

        $ch = Read-Host "  Select"
        switch ($ch) {
            "1" {
                Write-Section "Host Key Fingerprints"
                @("rsa","ecdsa","ed25519") | ForEach-Object {
                    $kp = "$SSH_DIR\ssh_host_${_}_key"
                    if (Test-Path $kp) {
                        $fp = & ssh-keygen -lf $kp 2>&1
                        Write-Ok "$_ : $fp"
                    } else { Write-Warn "$_ key not found" }
                }
                Pause-Menu
            }
            "2" {
                Write-Section "administrators_authorized_keys"
                if (Test-Path $AUTH_KEYS_ADMIN) {
                    $keys = Get-Content $AUTH_KEYS_ADMIN | Where-Object { $_ -notmatch "^\s*#" -and $_ -ne "" }
                    if ($keys) {
                        $i = 1
                        $keys | ForEach-Object {
                            $parts   = $_ -split "\s+"
                            $comment = if ($parts.Count -ge 3) { $parts[-1] } else { "(no comment)" }
                            $preview = if ($parts.Count -ge 2) { $parts[1].Substring(0, [Math]::Min(24, $parts[1].Length)) + "..." } else { "?" }
                            Write-Host ("  [{0}] {1,-30} {2} {3}" -f $i, $comment, $parts[0], $preview) -ForegroundColor White
                            $i++
                        }
                    } else { Write-Info "File exists but is empty" }
                } else {
                    Write-Warn "File not found: $AUTH_KEYS_ADMIN"
                    if (Confirm "Create empty administrators_authorized_keys?") {
                        New-Item $AUTH_KEYS_ADMIN -ItemType File -Force | Out-Null
                        icacls $AUTH_KEYS_ADMIN /inheritance:r /grant "Administrators:(F)" /grant "SYSTEM:(F)" 2>&1 | Out-Null
                        Write-Ok "Created with correct permissions"
                    }
                }
                Pause-Menu
            }
            "3" {
                $user = Read-Host "  Username (blank = administrators_authorized_keys)"
                $key  = Read-Host "  Paste public key (ssh-ed25519/ssh-rsa/ecdsa-...)"
                if ($key -notmatch "^(ssh-|ecdsa-)") {
                    Write-Fail "Does not look like a valid public key"
                } else {
                    if ($user -eq "") {
                        if (-not (Test-Path $AUTH_KEYS_ADMIN)) {
                            New-Item $AUTH_KEYS_ADMIN -ItemType File -Force | Out-Null
                        }
                        Add-Content $AUTH_KEYS_ADMIN $key
                        icacls $AUTH_KEYS_ADMIN /inheritance:r /grant "Administrators:(F)" /grant "SYSTEM:(F)" 2>&1 | Out-Null
                        Write-Ok "Key added to administrators_authorized_keys"
                    } else {
                        $sshPath  = "C:\Users\$user\.ssh"
                        $authKeys = "$sshPath\authorized_keys"
                        if (-not (Test-Path $sshPath)) { New-Item $sshPath -ItemType Directory -Force | Out-Null }
                        Add-Content $authKeys $key
                        icacls $sshPath  /inheritance:r /grant "${user}:(OI)(CI)F" /grant "Administrators:(OI)(CI)F" /grant "SYSTEM:(OI)(CI)F" 2>&1 | Out-Null
                        icacls $authKeys /inheritance:r /grant "${user}:(F)" /grant "Administrators:(F)" /grant "SYSTEM:(F)" 2>&1 | Out-Null
                        Write-Ok "Key added to $authKeys"
                    }
                }
                Pause-Menu
            }
            "4" {
                $user     = Read-Host "  Username"
                $authKeys = "C:\Users\$user\.ssh\authorized_keys"
                Write-Section "authorized_keys for $user"
                if (Test-Path $authKeys) {
                    Get-Content $authKeys | Where-Object { $_ -ne "" } | ForEach-Object {
                        Write-Host "  $_" -ForegroundColor Gray
                    }
                } else { Write-Warn "Not found: $authKeys" }
                Pause-Menu
            }
            "5" {
                Write-Section "Generate Key Pair"
                Write-Host "  [1] ed25519 (recommended)"
                Write-Host "  [2] rsa 4096"
                Write-Host "  [3] ecdsa"
                $kt = Read-Host "  Key type"
                $algo = switch ($kt) { "1" { "ed25519" } "2" { "rsa" } "3" { "ecdsa" } default { "ed25519" } }
                $name = Read-Host "  Key filename (default: id_$algo)"
                if ($name -eq "") { $name = "id_$algo" }
                $outPath = "C:\Users\$env:USERNAME\.ssh\$name"
                if (Test-Path $outPath) {
                    if (-not (Confirm "File $outPath exists. Overwrite?")) { continue }
                }
                $args = @("-t", $algo, "-f", $outPath)
                if ($algo -eq "rsa") { $args += @("-b", "4096") }
                Write-Info "Generating $algo key -> $outPath"
                & ssh-keygen @args
                Write-Ok "Public key: $outPath.pub"
                Pause-Menu
            }
            "6" {
                Write-Section "Fix Permissions"
                if (Test-Path $AUTH_KEYS_ADMIN) {
                    icacls $AUTH_KEYS_ADMIN /inheritance:r /grant "Administrators:(F)" /grant "SYSTEM:(F)" 2>&1 | Out-Null
                    Write-Ok "administrators_authorized_keys permissions fixed"
                }
                $user = Read-Host "  Fix .ssh dir for which user? (blank=skip)"
                if ($user -ne "") {
                    $sshPath = "C:\Users\$user\.ssh"
                    if (Test-Path $sshPath) {
                        icacls $sshPath /inheritance:r `
                            /grant "${user}:(OI)(CI)F" `
                            /grant "Administrators:(OI)(CI)F" `
                            /grant "SYSTEM:(OI)(CI)F" 2>&1 | Out-Null
                        Write-Ok "$sshPath permissions fixed"
                        $ak = "$sshPath\authorized_keys"
                        if (Test-Path $ak) {
                            icacls $ak /inheritance:r /grant "${user}:(F)" /grant "Administrators:(F)" /grant "SYSTEM:(F)" 2>&1 | Out-Null
                            Write-Ok "authorized_keys permissions fixed"
                        }
                    } else { Write-Warn "Directory not found: $sshPath" }
                }
                Pause-Menu
            }
            "0" { return }
            default { Write-Warn "Invalid option" }
        }
    }
}

# ─── 6. Firewall Management ───────────────────────────────────────────
function Manage-Firewall {
    while ($true) {
        Write-Header "Firewall Management"

        $cfgPort = Get-ConfigValue "Port"; if (-not $cfgPort) { $cfgPort = "22" }
        $rule    = Get-NetFirewallRule -Name $FW_RULE_NAME -ErrorAction SilentlyContinue

        if ($rule) {
            $color     = if ($rule.Enabled -eq "True") { "Green" } else { "Yellow" }
            $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            $rulePort  = if ($portFilter) { $portFilter.LocalPort } else { "?" }
            Write-Host "  Rule '$FW_RULE_NAME'" -ForegroundColor White
            Write-Host "  Enabled: $($rule.Enabled)   Port: $rulePort" -ForegroundColor $color
            if ($rulePort -ne $cfgPort) {
                Write-Warn "Firewall port ($rulePort) differs from sshd_config port ($cfgPort)"
            }
        } else {
            Write-Fail "Rule '$FW_RULE_NAME' not found"
        }

        Write-Host ""
        Write-Host "  [1] Create / update rule for port $cfgPort" -ForegroundColor White
        Write-Host "  [2] Enable rule"                            -ForegroundColor White
        Write-Host "  [3] Disable rule"                           -ForegroundColor White
        Write-Host "  [4] Delete rule"                            -ForegroundColor White
        Write-Host "  [5] Test local port connectivity"           -ForegroundColor White
        Write-Host "  [6] List all SSH-related firewall rules"    -ForegroundColor White
        Write-Host "  [0] Back"                                   -ForegroundColor Gray
        Write-Host ""

        $ch = Read-Host "  Select"
        switch ($ch) {
            "1" {
                if (Confirm "Create/update firewall rule for TCP port $cfgPort inbound?") {
                    Remove-NetFirewallRule -Name $FW_RULE_NAME -ErrorAction SilentlyContinue
                    New-NetFirewallRule -Name $FW_RULE_NAME `
                        -DisplayName "OpenSSH Server (sshd)" `
                        -Enabled True -Direction Inbound -Protocol TCP `
                        -Action Allow -LocalPort ([int]$cfgPort) | Out-Null
                    Write-Ok "Rule created/updated (port $cfgPort)"
                }
            }
            "2" {
                if ($rule) { Set-NetFirewallRule -Name $FW_RULE_NAME -Enabled True;  Write-Ok "Rule enabled"  }
                else { Write-Fail "Rule not found" }
            }
            "3" {
                if ($rule) { Set-NetFirewallRule -Name $FW_RULE_NAME -Enabled False; Write-Ok "Rule disabled" }
                else { Write-Fail "Rule not found" }
            }
            "4" {
                if (Confirm "Delete rule '$FW_RULE_NAME'?") {
                    Remove-NetFirewallRule -Name $FW_RULE_NAME -ErrorAction SilentlyContinue
                    Write-Ok "Rule deleted"
                }
            }
            "5" {
                $targetPort = Read-Host "  Port to test (default: $cfgPort)"
                if ($targetPort -eq "") { $targetPort = $cfgPort }
                Write-Info "Testing TCP 127.0.0.1:$targetPort..."
                $tcp = New-Object System.Net.Sockets.TcpClient
                try {
                    $tcp.Connect("127.0.0.1", [int]$targetPort)
                    Write-Ok "Port $targetPort is reachable (localhost)"
                    $tcp.Close()
                } catch {
                    Write-Fail "Port $targetPort unreachable: $($_.Exception.Message)"
                }
                Pause-Menu
            }
            "6" {
                Write-Section "SSH-related Firewall Rules"
                Get-NetFirewallRule | Where-Object { $_.DisplayName -match "SSH|sshd|OpenSSH" } |
                    ForEach-Object {
                        $c = if ($_.Enabled -eq "True") { "Green" } else { "Gray" }
                        Write-Host ("  [{0,-6}] {1}" -f $_.Enabled, $_.Name) -ForegroundColor $c
                    }
                Pause-Menu
            }
            "0" { return }
            default { Write-Warn "Invalid option" }
        }
    }
}

# ─── 7. Permission Check ──────────────────────────────────────────────
function Check-Permissions {
    Write-Header "Permission Check"

    # sshd_config
    Write-Section "sshd_config"
    if (Test-Path $SSHD_CONFIG) {
        $acl = Get-Acl $SSHD_CONFIG
        Write-Info "Owner: $($acl.Owner)"
        $acl.Access | ForEach-Object {
            Write-Host ("    {0,-40} {1} [{2}]" -f $_.IdentityReference, $_.FileSystemRights, $_.AccessControlType) -ForegroundColor Gray
        }
        $risky = $acl.Access | Where-Object {
            $_.IdentityReference -notmatch "SYSTEM|Administrators|BUILTIN\\Administrators|NT AUTHORITY\\SYSTEM"
        }
        if ($risky) { Write-Warn "Non-admin accounts have access to sshd_config" }
        else        { Write-Ok  "sshd_config permissions look correct" }
    } else { Write-Fail "sshd_config not found" }

    # Host keys
    Write-Section "Host Keys"
    @("rsa","ecdsa","ed25519") | ForEach-Object {
        $kp = "$SSH_DIR\ssh_host_${_}_key"
        if (Test-Path $kp) {
            $acl   = Get-Acl $kp
            $risky = $acl.Access | Where-Object {
                $_.IdentityReference -notmatch "SYSTEM|Administrators|BUILTIN\\Administrators|NT SERVICE\\sshd"
            }
            if ($risky) { Write-Warn "$_ private key: non-system accounts have access (risk!)" }
            else        { Write-Ok  "$_ key: permissions OK" }
        } else { Write-Warn "$_ key not found" }
    }

    # administrators_authorized_keys
    Write-Section "administrators_authorized_keys"
    if (Test-Path $AUTH_KEYS_ADMIN) {
        $acl   = Get-Acl $AUTH_KEYS_ADMIN
        Write-Info "Owner: $($acl.Owner)"
        $risky = $acl.Access | Where-Object {
            $_.IdentityReference -notmatch "SYSTEM|Administrators|BUILTIN\\Administrators"
        }
        if ($risky) {
            Write-Fail "Non-admin accounts have access - pubkey auth may fail!"
            Write-Warn "Use [5] -> [6] to fix permissions"
        } else { Write-Ok "authorized_keys permissions OK" }
    } else { Write-Info "administrators_authorized_keys does not exist" }

    # Current user .ssh
    Write-Section "Current User .ssh ($env:USERNAME)"
    $userSsh = "$env:USERPROFILE\.ssh"
    if (Test-Path $userSsh) {
        $acl   = Get-Acl $userSsh
        $risky = $acl.Access | Where-Object {
            $_.IdentityReference -notmatch [regex]::Escape($env:USERNAME) -and
            $_.IdentityReference -notmatch "SYSTEM|Administrators|BUILTIN\\Administrators"
        }
        if ($risky) { Write-Warn ".ssh directory has unexpected accounts - SSH may reject keys" }
        else        { Write-Ok  ".ssh directory permissions OK" }

        $idFiles = Get-ChildItem $userSsh -Filter "id_*" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch "\.pub$" }
        foreach ($f in $idFiles) {
            $acl   = Get-Acl $f.FullName
            $risky = $acl.Access | Where-Object {
                $_.IdentityReference -notmatch [regex]::Escape($env:USERNAME) -and
                $_.IdentityReference -notmatch "SYSTEM|Administrators|BUILTIN\\Administrators"
            }
            if ($risky) { Write-Warn "$($f.Name): private key accessible by others" }
            else        { Write-Ok  "$($f.Name): permissions OK" }
        }
    } else { Write-Info ".ssh directory not found ($userSsh)" }

    # Check for other local users' .ssh
    Write-Section "Other Local Users"
    Get-LocalUser | Where-Object { $_.Enabled } | ForEach-Object {
        $u     = $_.Name
        $uSsh  = "C:\Users\$u\.ssh\authorized_keys"
        if (Test-Path $uSsh) {
            $acl   = Get-Acl $uSsh
            $risky = $acl.Access | Where-Object {
                $_.IdentityReference -notmatch [regex]::Escape($u) -and
                $_.IdentityReference -notmatch "SYSTEM|Administrators|BUILTIN\\Administrators"
            }
            if ($risky) { Write-Warn "${u}: authorized_keys has unexpected access" }
            else        { Write-Ok  "${u}: authorized_keys permissions OK" }
        }
    }

    Pause-Menu
}

# ─── Main Menu ────────────────────────────────────────────────────────
function Show-MainMenu {
    while ($true) {
        Write-Header "SSH Manager"

        # Quick status bar
        $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
        $svcStr   = if ($svc) { $svc.Status } else { "Not Installed" }
        $svcColor = if ($svc -and $svc.Status -eq "Running") { "Green" } elseif ($svc) { "Yellow" } else { "Red" }
        $cfgPort  = Get-ConfigValue "Port"; if (-not $cfgPort) { $cfgPort = "22" }
        $fw       = Get-NetFirewallRule -Name $FW_RULE_NAME -ErrorAction SilentlyContinue
        $fwStr    = if ($fw -and $fw.Enabled -eq "True") { "Open" } elseif ($fw) { "Disabled" } else { "No Rule" }
        $fwColor  = if ($fw -and $fw.Enabled -eq "True") { "Green" } else { "Red" }

        Write-Host "  sshd: " -NoNewline; Write-Host $svcStr -NoNewline -ForegroundColor $svcColor
        Write-Host "   Port: $cfgPort   Firewall: " -NoNewline
        Write-Host $fwStr -ForegroundColor $fwColor
        Write-Host ""

        Write-Host "  [1] Status overview"               -ForegroundColor White
        Write-Host "  [2] Install / repair SSH"          -ForegroundColor White
        Write-Host "  [3] Service management"            -ForegroundColor White
        Write-Host "  [4] sshd_config settings"          -ForegroundColor White
        Write-Host "  [5] Key management"                -ForegroundColor White
        Write-Host "  [6] Firewall management"           -ForegroundColor White
        Write-Host "  [7] Permission check"              -ForegroundColor White
        Write-Host ""
        Write-Host "  [0] Exit"                          -ForegroundColor Gray
        Write-Host ""

        $ch = Read-Host "  Select"
        switch ($ch) {
            "1" { Show-Status }
            "2" { Install-SshComponents }
            "3" { Manage-Service }
            "4" { Manage-Config }
            "5" { Manage-Keys }
            "6" { Manage-Firewall }
            "7" { Check-Permissions }
            "0" { Write-Host ""; Write-Host "  Bye!" -ForegroundColor Cyan; Write-Host ""; exit 0 }
            default { Write-Warn "Invalid option" }
        }
    }
}

# ─── Entry Point ──────────────────────────────────────────────────────
Show-MainMenu
