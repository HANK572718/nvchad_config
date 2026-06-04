# SMB Sharing Diagnostic Script - Requires administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Please run this script as administrator!" -ForegroundColor Red
    Write-Host "Right-click on PowerShell and select 'Run as administrator'" -ForegroundColor Yellow
    pause
    exit
}

Write-Host "================================" -ForegroundColor Cyan
Write-Host "   SMB Sharing Diagnostic Tool" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check SMB Service Status
Write-Host "[1] Checking SMB Services..." -ForegroundColor Yellow
$smbServices = @("LanmanServer", "LanmanWorkstation")
foreach ($service in $smbServices) {
    $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
    if ($svc) {
        $status = if ($svc.Status -eq "Running") { "Running" } else { "Stopped" }
        $color = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "  $service : $status" -ForegroundColor $color

        if ($svc.Status -ne "Running") {
            Write-Host "  Attempting to start $service..." -ForegroundColor Yellow
            try {
                Start-Service -Name $service -ErrorAction Stop
                Write-Host "  Successfully started $service" -ForegroundColor Green
            } catch {
                Write-Host "  Failed to start $service : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}
Write-Host ""

# 2. Check Network Discovery and File Sharing Settings
Write-Host "[2] Checking Network Discovery Settings..." -ForegroundColor Yellow
$netProfile = Get-NetConnectionProfile
Write-Host "  Network Profile Type: $($netProfile.NetworkCategory)" -ForegroundColor Cyan
if ($netProfile.NetworkCategory -eq "Public") {
    Write-Host "  WARNING: Network is set to Public. File sharing is typically disabled on Public networks." -ForegroundColor Red
    Write-Host "  Consider changing to Private network for file sharing." -ForegroundColor Yellow
}
Write-Host ""

# 3. Check SMB Protocol Versions
Write-Host "[3] Checking SMB Protocol Status..." -ForegroundColor Yellow
$smb1 = Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol
$smb2 = Get-SmbServerConfiguration | Select-Object EnableSMB2Protocol
Write-Host "  SMB1 Protocol: $($smb1.EnableSMB1Protocol)" -ForegroundColor $(if ($smb1.EnableSMB1Protocol) {"Yellow"} else {"Green"})
Write-Host "  SMB2 Protocol: $($smb2.EnableSMB2Protocol)" -ForegroundColor $(if ($smb2.EnableSMB2Protocol) {"Green"} else {"Red"})

if (-not $smb2.EnableSMB2Protocol) {
    Write-Host "  WARNING: SMB2 is disabled! Enabling..." -ForegroundColor Red
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force
}
Write-Host ""

# 4. Check Current Shares
Write-Host "[4] Current Shared Folders..." -ForegroundColor Yellow
$shares = Get-SmbShare | Where-Object { $_.Name -notlike "*$" }
if ($shares) {
    $shares | Select-Object Name, Path, Description | Format-Table -AutoSize
} else {
    Write-Host "  No user-created shares found" -ForegroundColor Yellow
}
Write-Host ""

# 5. Check Firewall Rules for File Sharing
Write-Host "[5] Checking Firewall Rules..." -ForegroundColor Yellow
$firewallRules = @(
    "File and Printer Sharing (SMB-In)",
    "File and Printer Sharing (NB-Session-In)",
    "File and Printer Sharing (Echo Request - ICMPv4-In)"
)

foreach ($ruleName in $firewallRules) {
    $rule = Get-NetFirewallRule -DisplayName "*$ruleName*" -ErrorAction SilentlyContinue |
            Where-Object { $_.Direction -eq "Inbound" } | Select-Object -First 1

    if ($rule) {
        $enabled = $rule.Enabled
        $color = if ($enabled) { "Green" } else { "Red" }
        Write-Host "  $ruleName : $enabled" -ForegroundColor $color

        if (-not $enabled) {
            Write-Host "    Attempting to enable rule..." -ForegroundColor Yellow
            try {
                Enable-NetFirewallRule -DisplayName "*$ruleName*" -ErrorAction Stop
                Write-Host "    Successfully enabled" -ForegroundColor Green
            } catch {
                Write-Host "    Failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}
Write-Host ""

# 6. Check Network Adapter and IP Address
Write-Host "[6] Network Information..." -ForegroundColor Yellow
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
foreach ($adapter in $adapters) {
    $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipConfig) {
        Write-Host "  Adapter: $($adapter.Name)" -ForegroundColor Cyan
        Write-Host "  IP Address: $($ipConfig.IPAddress)" -ForegroundColor Green
        Write-Host "  Subnet: $($ipConfig.PrefixLength)" -ForegroundColor Green
    }
}
Write-Host ""

# 7. Check Guest Account Status
Write-Host "[7] Checking Guest Account..." -ForegroundColor Yellow
$guest = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
if ($guest) {
    Write-Host "  Guest Account Enabled: $($guest.Enabled)" -ForegroundColor $(if ($guest.Enabled) {"Green"} else {"Yellow"})
}
Write-Host ""

# 8. Test SMB Access
Write-Host "[8] Testing Local SMB Access..." -ForegroundColor Yellow
$computerName = $env:COMPUTERNAME
try {
    $localShares = Get-ChildItem "\\$computerName\C$" -ErrorAction Stop
    Write-Host "  Successfully accessed \\$computerName\C$ (Admin Share)" -ForegroundColor Green
} catch {
    Write-Host "  Failed to access \\$computerName\C$" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 9. Check Credential Manager
Write-Host "[9] Checking Stored Credentials..." -ForegroundColor Yellow
try {
    $creds = cmdkey /list
    if ($creds -match "TERMSRV|Domain:target") {
        Write-Host "  Stored credentials found" -ForegroundColor Green
        Write-Host "  You can clear problematic credentials with: cmdkey /delete:TARGETNAME" -ForegroundColor Cyan
    } else {
        Write-Host "  No network credentials stored" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Could not check credentials" -ForegroundColor Yellow
}
Write-Host ""

# 10. Summary and Recommendations
Write-Host "================================" -ForegroundColor Cyan
Write-Host "   Diagnostic Summary" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Common Solutions:" -ForegroundColor Yellow
Write-Host "1. Ensure both computers are on the same network/subnet" -ForegroundColor White
Write-Host "2. Set network profile to 'Private' instead of 'Public'" -ForegroundColor White
Write-Host "3. Enable 'Network Discovery' and 'File Sharing' in Network Settings" -ForegroundColor White
Write-Host "4. Check if third-party antivirus/firewall is blocking SMB" -ForegroundColor White
Write-Host "5. Try accessing with: \\IP_ADDRESS\ShareName" -ForegroundColor White
Write-Host "6. Clear cached credentials: cmdkey /delete:TARGET" -ForegroundColor White
Write-Host "7. Restart 'Server' service: Restart-Service LanmanServer" -ForegroundColor White
Write-Host ""

Write-Host "Need to create a new share? Run the sharing setup script." -ForegroundColor Cyan
Write-Host ""
pause
