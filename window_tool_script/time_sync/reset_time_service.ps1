<#
.SYNOPSIS
    Reset Windows Time Service to default settings

.DESCRIPTION
    This script restores Windows Time Service (W32Time) to Windows default settings,
    removing all custom NTP server or client configurations.

.PARAMETER RestoreToDefault
    Restore to Windows default time server (time.windows.com)

.PARAMETER LogPath
    Log file path, default is time_sync_reset.log

.EXAMPLE
    .\reset_time_service.ps1
    Reset to basic settings without using any time server

.EXAMPLE
    .\reset_time_service.ps1 -RestoreToDefault
    Reset and configure to use Windows default time server

.NOTES
    Requires system administrator privileges to execute
    Author: Claude Code
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [switch]$RestoreToDefault,
    [string]$LogPath = "time_sync_reset.log"
)

# Log recording function
function Write-Log {
    <#
    .SYNOPSIS
        Write log message

    .PARAMETER Message
        Log message content

    .PARAMETER Level
        Log level (Info, Warning, Error, Success)
    #>
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
    <#
    .SYNOPSIS
        Check if administrator privileges are available

    .OUTPUTS
        System.Boolean - Whether user is administrator
    #>
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Main execution flow
function Main {
    Write-Log "========================================" -Level Info
    Write-Log "Resetting Windows Time Service" -Level Info
    Write-Log "========================================" -Level Info

    # Check administrator privileges
    if (-not (Test-Administrator)) {
        Write-Log "Error: This script requires administrator privileges" -Level Error
        Write-Log "Please run PowerShell as administrator and try again" -Level Error
        return
    }

    try {
        # Stop service
        Write-Log "Stopping W32Time service..." -Level Info
        Stop-Service W32Time -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Unregister service
        Write-Log "Unregistering W32Time service..." -Level Info
        w32tm /unregister | Out-Null
        Start-Sleep -Seconds 2

        # Re-register service (this will restore default settings)
        Write-Log "Re-registering W32Time service (restoring defaults)..." -Level Info
        w32tm /register | Out-Null
        Start-Sleep -Seconds 2

        if ($RestoreToDefault) {
            Write-Log "Configuring to use Windows default time server..." -Level Info

            # Set as NTP type
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
                -Name "Type" -Value "NTP"

            # Set default time server
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
                -Name "NtpServer" -Value "time.windows.com,0x9"

            # Enable NTP Client
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" `
                -Name "Enabled" -Value 1

            # Disable NTP Server
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" `
                -Name "Enabled" -Value 0

            # Set default sync interval (3600 seconds = 1 hour)
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" `
                -Name "SpecialPollInterval" -Value 3600

            Write-Log "Configured to use time.windows.com" -Level Success
        } else {
            Write-Log "Restored to basic default settings (no external time server)" -Level Success
        }

        # Set service startup type to automatic
        Write-Log "Setting service to auto-start..." -Level Info
        Set-Service W32Time -StartupType Automatic

        # Start service
        Write-Log "Starting W32Time service..." -Level Info
        Start-Service W32Time
        Start-Sleep -Seconds 2

        # Update settings
        Write-Log "Updating settings..." -Level Info
        w32tm /config /update | Out-Null

        # If default server was configured, perform synchronization
        if ($RestoreToDefault) {
            Write-Log "Forcing synchronization with Windows time server..." -Level Info
            w32tm /resync /force | Out-Null
        }

        # Remove firewall rules if they exist
        Write-Log "Removing custom firewall rules..." -Level Info
        Remove-NetFirewallRule -DisplayName "NTP Server (UDP-In)" -ErrorAction SilentlyContinue

        # Display results
        Write-Log "" -Level Info
        Write-Log "========================================" -Level Success
        Write-Log "Reset completed!" -Level Success
        Write-Log "========================================" -Level Success
        Write-Log "" -Level Info

        # Display current status
        Write-Log "Current service status:" -Level Info
        $serviceStatus = Get-Service W32Time
        Write-Log "  Service status: $($serviceStatus.Status)" -Level Info
        Write-Log "  Startup type: $($serviceStatus.StartType)" -Level Info

        if ($RestoreToDefault) {
            Write-Log "" -Level Info
            Write-Log "Time source configured as: time.windows.com" -Level Info
            Write-Log "Sync interval: 3600 seconds (1 hour)" -Level Info
        } else {
            Write-Log "" -Level Info
            Write-Log "Restored to Windows default settings" -Level Info
            Write-Log "Tip: To use Internet time server, please run:" -Level Info
            Write-Log "  .\reset_time_service.ps1 -RestoreToDefault" -Level Info
        }

        Write-Log "" -Level Info
        Write-Log "Running w32tm /query /status to check status..." -Level Info
        w32tm /query /status

    } catch {
        Write-Log "Error occurred: $($_.Exception.Message)" -Level Error
        Write-Log "Detailed error: $($_.Exception.ToString())" -Level Error
        Write-Log "" -Level Error
        Write-Log "If issues persist, please try:" -Level Warning
        Write-Log "  1. Restart the computer" -Level Warning
        Write-Log "  2. Run manually: w32tm /unregister then w32tm /register" -Level Warning
    }
}

# Run main program
Main
