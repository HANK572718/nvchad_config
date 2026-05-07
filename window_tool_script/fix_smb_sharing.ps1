# SMB Sharing Fix Script - Requires administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Please run this script as administrator!" -ForegroundColor Red
    Write-Host "Right-click on PowerShell and select 'Run as administrator'" -ForegroundColor Yellow
    pause
    exit
}

Write-Host "================================" -ForegroundColor Cyan
Write-Host "   SMB Sharing Fix Tool" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will enable necessary services and settings for file sharing." -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Continue? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Operation cancelled" -ForegroundColor Yellow
    exit
}

Write-Host ""

# Step 1: Enable SMB Services
Write-Host "[1] Starting SMB Services..." -ForegroundColor Yellow
$services = @("LanmanServer", "LanmanWorkstation", "FDResPub", "SSDPSRV")
foreach ($svc in $services) {
    try {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service) {
            Set-Service -Name $svc -StartupType Automatic -ErrorAction Stop
            Start-Service -Name $svc -ErrorAction Stop
            Write-Host "  $svc - Started and set to Automatic" -ForegroundColor Green
        }
    } catch {
        Write-Host "  $svc - Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host ""

# Step 2: Enable SMB2 Protocol
Write-Host "[2] Enabling SMB2 Protocol..." -ForegroundColor Yellow
try {
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction Stop
    Write-Host "  SMB2 Protocol enabled" -ForegroundColor Green
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 3: Configure Network Profile
Write-Host "[3] Checking Network Profile..." -ForegroundColor Yellow
$netProfile = Get-NetConnectionProfile
if ($netProfile.NetworkCategory -eq "Public") {
    Write-Host "  Current profile is Public" -ForegroundColor Yellow
    $changeProfile = Read-Host "  Change to Private network for better sharing? (Y/N)"
    if ($changeProfile -eq "Y" -or $changeProfile -eq "y") {
        try {
            Set-NetConnectionProfile -InterfaceIndex $netProfile.InterfaceIndex -NetworkCategory Private
            Write-Host "  Network profile changed to Private" -ForegroundColor Green
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  Network profile is $($netProfile.NetworkCategory)" -ForegroundColor Green
}
Write-Host ""

# Step 4: Enable Firewall Rules
Write-Host "[4] Enabling Firewall Rules for File Sharing..." -ForegroundColor Yellow
$firewallGroups = @(
    "@FirewallAPI.dll,-28502",  # File and Printer Sharing
    "@FirewallAPI.dll,-32752"   # Network Discovery
)

foreach ($group in $firewallGroups) {
    try {
        Enable-NetFirewallRule -Group $group -ErrorAction Stop
        Write-Host "  Enabled firewall group: $group" -ForegroundColor Green
    } catch {
        Write-Host "  Error enabling $group : $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Enable specific rules by display name
$specificRules = @(
    "*File and Printer Sharing (SMB-In)*",
    "*File and Printer Sharing (NB-Session-In)*",
    "*File and Printer Sharing (Echo Request - ICMPv4-In)*",
    "*Network Discovery*"
)

foreach ($ruleName in $specificRules) {
    try {
        Enable-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    } catch {
        # Silent fail for optional rules
    }
}
Write-Host "  Firewall rules enabled" -ForegroundColor Green
Write-Host ""

# Step 5: Enable Network Discovery via Registry
Write-Host "[5] Enabling Network Discovery via Registry..." -ForegroundColor Yellow
try {
    # Enable Network Discovery
    $regPaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff"
    )

    foreach ($path in $regPaths) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
    }
    Write-Host "  Network Discovery registry keys configured" -ForegroundColor Green
} catch {
    Write-Host "  Warning: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""

# Step 6: Configure SMB Settings
Write-Host "[6] Configuring SMB Server Settings..." -ForegroundColor Yellow
try {
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction Stop
    Set-SmbServerConfiguration -AnnounceServer $true -Force -ErrorAction SilentlyContinue
    Write-Host "  SMB Server configured" -ForegroundColor Green
} catch {
    Write-Host "  Warning: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""

# Step 7: Clear Credential Cache
Write-Host "[7] Clearing Cached Credentials..." -ForegroundColor Yellow
Write-Host "  This can help resolve authentication issues" -ForegroundColor Cyan
$clearCreds = Read-Host "  Clear all cached network credentials? (Y/N)"
if ($clearCreds -eq "Y" -or $clearCreds -eq "y") {
    try {
        # Get list of credentials and delete them
        $credOutput = cmdkey /list
        $credOutput | Select-String "Target:" | ForEach-Object {
            $target = ($_ -replace "Target: ", "").Trim()
            if ($target -notlike "*virtualapp*" -and $target -notlike "*WindowsLive*") {
                cmdkey /delete:$target
                Write-Host "  Deleted: $target" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  Error clearing credentials: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "  Skipped credential clearing" -ForegroundColor Yellow
}
Write-Host ""

# Step 8: Display Current IP
Write-Host "[8] Your Current IP Addresses..." -ForegroundColor Yellow
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
foreach ($adapter in $adapters) {
    $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipConfig) {
        Write-Host "  $($adapter.Name): $($ipConfig.IPAddress)" -ForegroundColor Cyan
    }
}
Write-Host ""

# Step 9: Restart Services
Write-Host "[9] Restarting Services..." -ForegroundColor Yellow
$restartServices = @("LanmanServer", "LanmanWorkstation")
foreach ($svc in $restartServices) {
    try {
        Restart-Service -Name $svc -Force -ErrorAction Stop
        Write-Host "  Restarted $svc" -ForegroundColor Green
    } catch {
        Write-Host "  Error restarting $svc : $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host ""

# Summary
Write-Host "================================" -ForegroundColor Cyan
Write-Host "   Setup Complete!" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Create a shared folder:" -ForegroundColor White
Write-Host "   Right-click folder -> Properties -> Sharing -> Advanced Sharing" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Or use PowerShell:" -ForegroundColor White
Write-Host "   New-SmbShare -Name 'ShareName' -Path 'C:\Path\To\Folder' -FullAccess 'Everyone'" -ForegroundColor Cyan
Write-Host ""
Write-Host "3. Access from another computer:" -ForegroundColor White
Write-Host "   \\YOUR_IP_ADDRESS\ShareName" -ForegroundColor Cyan
Write-Host ""
Write-Host "4. If still having issues:" -ForegroundColor White
Write-Host "   - Check third-party antivirus/firewall settings" -ForegroundColor Cyan
Write-Host "   - Ensure both computers are on the same network" -ForegroundColor Cyan
Write-Host "   - Try pinging the target computer first" -ForegroundColor Cyan
Write-Host "   - Reboot both computers" -ForegroundColor Cyan
Write-Host ""

pause
