<#
.SYNOPSIS
    Configure Windows computer as NTP time server

.DESCRIPTION
    This script automatically configures Windows Time Service (W32Time) to NTP Server mode,
    opens firewall rules, and sets high-precision time synchronization parameters.

.PARAMETER LogPath
    Log file path, default is time_sync_server.log

.EXAMPLE
    .\setup_time_server.ps1
    Configure this computer as time server with default settings

.NOTES
    Requires system administrator privileges to execute
    Author: Claude Code
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [string]$LogPath = "time_sync_server.log"
)

# Log recording function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Output to console
    switch ($Level) {
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }

    # Write to log file
    Add-Content -Path $LogPath -Value $logMessage
}

# Check administrator privileges
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Main execution flow
function Main {
    Write-Log "========================================" -Level Info
    Write-Log "Starting Windows Time Server setup" -Level Info
    Write-Log "========================================" -Level Info

    # Check administrator privileges
    if (-not (Test-Administrator)) {
        Write-Log "Error: This script requires administrator privileges" -Level Error
        Write-Log "Please run PowerShell as administrator and try again" -Level Error
        return
    }

    try {
        # Display local IP information
        Write-Log "Obtaining local IP information..." -Level Info
        $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" }
        foreach ($ip in $ipAddresses) {
            Write-Log "  Interface: $($ip.InterfaceAlias), IP: $($ip.IPAddress)" -Level Info
        }

        # Stop W32Time service
        Write-Log "Stopping W32Time service..." -Level Info
        Stop-Service W32Time -Force -ErrorAction SilentlyContinue

        # Configure W32Time as NTP Server
        Write-Log "Configuring W32Time as NTP Server mode..." -Level Info

        # Set as local clock
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
            -Name "Type" -Value "NTP"

        # Enable NTP Server
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" `
            -Name "Enabled" -Value 1

        # Allow client queries
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "AnnounceFlags" -Value 5

        # Configure high-precision time synchronization parameters
        Write-Log "Configuring high-precision time sync parameters..." -Level Info

        # Set update interval to 60 seconds
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" `
            -Name "UpdateInterval" -Value 60

        # Set time adjustment parameters
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "MaxPosPhaseCorrection" -Value 3600
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "MaxNegPhaseCorrection" -Value 3600

        # Configure NTP Client (Server also needs to sync external time)
        Write-Log "Setting external time source..." -Level Info
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
            -Name "NtpServer" -Value "time.windows.com,0x9 time.google.com,0x9"

        # Set service startup type to automatic
        Write-Log "Setting service to auto-start..." -Level Info
        Set-Service W32Time -StartupType Automatic

        # Start service
        Write-Log "Starting W32Time service..." -Level Info
        Start-Service W32Time

        # Force synchronization
        Write-Log "Forcing synchronization with external time source..." -Level Info
        w32tm /resync /force | Out-Null

        # Configure firewall rules
        Write-Log "Configuring firewall rules (allowing UDP 123)..." -Level Info

        # Remove old rules if they exist
        Remove-NetFirewallRule -DisplayName "NTP Server (UDP-In)" -ErrorAction SilentlyContinue

        # Add firewall rule
        New-NetFirewallRule -DisplayName "NTP Server (UDP-In)" `
            -Direction Inbound `
            -Protocol UDP `
            -LocalPort 123 `
            -Action Allow `
            -Profile Any `
            -Description "Allow inbound connections for NTP time synchronization service" | Out-Null

        Write-Log "Firewall rules configured successfully" -Level Success

        # Display configuration results
        Write-Log "" -Level Info
        Write-Log "========================================" -Level Success
        Write-Log "Time server setup completed!" -Level Success
        Write-Log "========================================" -Level Success
        Write-Log "" -Level Info
        Write-Log "Client computers should use the following IP address to connect:" -Level Info
        foreach ($ip in $ipAddresses) {
            if ($ip.InterfaceAlias -like "*Ethernet*" -or $ip.InterfaceAlias -like "*乙太網路*") {
                Write-Log "  Recommended: $($ip.IPAddress) (Interface: $($ip.InterfaceAlias))" -Level Success
            }
        }
        Write-Log "" -Level Info

        # Display current status
        Write-Log "Current service status:" -Level Info
        $serviceStatus = Get-Service W32Time
        Write-Log "  Service status: $($serviceStatus.Status)" -Level Info
        Write-Log "  Startup type: $($serviceStatus.StartType)" -Level Info

        # Display time source
        Write-Log "" -Level Info
        Write-Log "Running w32tm /query /status to check status..." -Level Info
        w32tm /query /status

        Write-Log "" -Level Info
        Write-Log "Setup completed! This computer is now an NTP time server" -Level Success
        Write-Log "Other computers can connect to this server using setup_time_client.ps1" -Level Info

    } catch {
        Write-Log "Error occurred: $($_.Exception.Message)" -Level Error
        Write-Log "Detailed error: $($_.Exception.ToString())" -Level Error
    }
}

# Run main program
Main
