# Setup-NTPServer.ps1
# Configure Windows 10 as NTP Server

param(
    [string]$ManualTime = ""
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configure Windows 10 as NTP Server" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Stop service
Write-Host "[1] Stopping Windows Time service..." -ForegroundColor Yellow
Stop-Service w32time -Force
Start-Sleep -Seconds 2

# 2. Enable NTP Server
Write-Host "[2] Enabling NTP Server feature..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" -Name "Enabled" -Value 1

# 3. Set as reliable time source
Write-Host "[3] Setting as reliable time source..." -ForegroundColor Yellow
w32tm /config /reliable:YES /update

# 4. Configure Announce Flags
Write-Host "[4] Configuring Announce Flags..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" -Name "AnnounceFlags" -Value 5

# 5. Set as local clock (no external dependency)
Write-Host "[5] Configuring as local clock..." -ForegroundColor Yellow
w32tm /config /manualpeerlist:"" /syncfromflags:NO /update

# 6. Manually set time (if provided)
if ($ManualTime) {
    Write-Host "[6] Setting system time to: $ManualTime" -ForegroundColor Yellow
    try {
        Set-Date -Date $ManualTime
        Write-Host "    Time set successfully!" -ForegroundColor Green
    } catch {
        Write-Host "    Failed to set time: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "[6] Skipping time configuration (no time parameter provided)" -ForegroundColor Gray
}

# 7. Configure firewall
Write-Host "[7] Configuring firewall rules..." -ForegroundColor Yellow
# Remove old rule if exists
Remove-NetFirewallRule -DisplayName "NTP Server - Inbound" -ErrorAction SilentlyContinue
# Add new rule
New-NetFirewallRule `
    -DisplayName "NTP Server - Inbound" `
    -Direction Inbound `
    -Protocol UDP `
    -LocalPort 123 `
    -Action Allow `
    -Enabled True `
    -Profile Any | Out-Null
Write-Host "    Firewall rule created" -ForegroundColor Green

# 8. Start service
Write-Host "[8] Starting Windows Time service..." -ForegroundColor Yellow
Start-Service w32time
Set-Service w32time -StartupType Automatic
Start-Sleep -Seconds 3

# 9. Verify configuration
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verification Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check service
$service = Get-Service w32time
Write-Host "Service Status: $($service.Status)" -ForegroundColor $(if($service.Status -eq "Running"){"Green"}else{"Red"})
Write-Host "Startup Type: $($service.StartType)" -ForegroundColor Cyan

# Check NTP Server configuration
$ntpEnabled = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer").Enabled
Write-Host "NTP Server Enabled: $($ntpEnabled -eq 1)" -ForegroundColor $(if($ntpEnabled -eq 1){"Green"}else{"Red"})

# Check firewall
$fwRule = Get-NetFirewallRule -DisplayName "NTP Server - Inbound" -ErrorAction SilentlyContinue
Write-Host "Firewall Rule Configured: $($null -ne $fwRule)" -ForegroundColor $(if($null -ne $fwRule){"Green"}else{"Red"})

# Display time status
Write-Host ""
Write-Host "Time Service Status:" -ForegroundColor Cyan
w32tm /query /status | Select-String "Leap|Stratum|Source|Last Successful"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuration Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This computer's IP address:" -ForegroundColor Yellow
Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "127.*"} | Select-Object IPAddress, InterfaceAlias | Format-Table
Write-Host ""
Write-Host "Clients can use the following command to connect to this NTP Server:" -ForegroundColor Yellow
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "127.*"})[0].IPAddress
Write-Host "w32tm /config /manualpeerlist:`"$ip`" /syncfromflags:manual /update" -ForegroundColor Cyan
Write-Host ""
