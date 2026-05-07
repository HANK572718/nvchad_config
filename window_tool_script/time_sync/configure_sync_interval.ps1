<#
.SYNOPSIS
    Fix time sync interval settings to achieve true high-frequency synchronization

.DESCRIPTION
    This script fixes the W32Time polling interval settings to ensure 60-second high-frequency sync.
    Windows Time Service uses MinPollInterval and MaxPollInterval to control actual polling intervals.

.PARAMETER Role
    Role: Server or Client

.PARAMETER ServerIP
    If Client, specify Server IP

.PARAMETER SyncInterval
    Sync interval (seconds), default 60 seconds, range 64-3600

.EXAMPLE
    .\fix_sync_interval.ps1 -Role Server
    Fix Server-side sync settings

.EXAMPLE
    .\fix_sync_interval.ps1 -Role Client -ServerIP "192.168.168.199" -SyncInterval 64
    Fix Client-side sync settings to 64 seconds

.NOTES
    Requires administrator privileges
    Author: Claude Code
    Version: 1.1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Server', 'Client')]
    [string]$Role,

    [Parameter(Mandatory=$false)]
    [string]$ServerIP,

    [Parameter(Mandatory=$false)]
    [ValidateRange(64, 3600)]
    [int]$SyncInterval = 64
)

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }
}

# Check administrator privileges
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Calculate poll interval power (W32Time uses 2^n seconds)
function Get-PollIntervalPower {
    param([int]$Seconds)

    # Find the closest 2^n
    $power = [Math]::Floor([Math]::Log($Seconds, 2))

    # Limit range (6 = 64 seconds, 17 = 131072 seconds)
    if ($power -lt 6) { $power = 6 }
    if ($power -gt 17) { $power = 17 }

    return $power
}

# Main program
function Main {
    Write-Log "========================================" -Level Info
    Write-Log "Fix Time Sync Interval Settings" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "Role: $Role" -Level Info
    Write-Log "Target sync interval: $SyncInterval seconds" -Level Info
    Write-Log "" -Level Info

    if (-not (Test-Administrator)) {
        Write-Log "Error: Administrator privileges required" -Level Error
        return
    }

    try {
        # Calculate poll interval power
        $pollPower = Get-PollIntervalPower -Seconds $SyncInterval
        $actualInterval = [Math]::Pow(2, $pollPower)

        Write-Log "Calculation result: 2^$pollPower = $actualInterval seconds" -Level Info
        Write-Log "" -Level Info

        # Stop service
        Write-Log "Stopping W32Time service..." -Level Info
        Stop-Service W32Time -Force
        Start-Sleep -Seconds 2

        if ($Role -eq "Server") {
            # Server side configuration
            Write-Log "Configuring Server parameters..." -Level Info

            # Configure NTP Server
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" `
                -Name "Enabled" -Value 1

            # Set to NTP mode
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
                -Name "Type" -Value "NTP"

            # Set external time source
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
                -Name "NtpServer" -Value "time.google.com,0x9 time.windows.com,0x9"

            # Configure NTP Client parameters (Server also needs to sync with external time as Client)
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" `
                -Name "Enabled" -Value 1

            # Key point: Set polling interval
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
                -Name "MinPollInterval" -Value $pollPower
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
                -Name "MaxPollInterval" -Value $pollPower

            Write-Log "Set MinPollInterval = MaxPollInterval = $pollPower (${actualInterval} seconds)" -Level Success

        } else {
            # Client side configuration
            if ([string]::IsNullOrEmpty($ServerIP)) {
                Write-Log "Error: Client mode requires -ServerIP parameter" -Level Error
                return
            }

            Write-Log "Configuring Client parameters..." -Level Info
            Write-Log "Time server: $ServerIP" -Level Info

            # Set to NTP mode
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
                -Name "Type" -Value "NTP"

            # Set time server
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
                -Name "NtpServer" -Value "$ServerIP,0x9"

            # Enable NTP Client
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" `
                -Name "Enabled" -Value 1

            # Disable NTP Server (Client doesn't need it)
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" `
                -Name "Enabled" -Value 0

            # Key point: Set polling interval
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
                -Name "MinPollInterval" -Value $pollPower
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
                -Name "MaxPollInterval" -Value $pollPower

            # Set SpecialPollInterval
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" `
                -Name "SpecialPollInterval" -Value $actualInterval

            Write-Log "Set MinPollInterval = MaxPollInterval = $pollPower (${actualInterval} seconds)" -Level Success
        }

        # Set update interval
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "UpdateInterval" -Value 100

        # Set to allow larger time offsets
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "MaxPosPhaseCorrection" -Value 3600
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "MaxNegPhaseCorrection" -Value 3600

        # Start service
        Write-Log "Starting W32Time service..." -Level Info
        Start-Service W32Time
        Start-Sleep -Seconds 2

        # Update configuration
        Write-Log "Updating configuration..." -Level Info
        w32tm /config /update | Out-Null

        # Force sync
        Write-Log "Forcing synchronization..." -Level Info
        $result = w32tm /resync /force 2>&1

        Start-Sleep -Seconds 2

        # Display results
        Write-Log "" -Level Info
        Write-Log "========================================" -Level Success
        Write-Log "Configuration complete!" -Level Success
        Write-Log "========================================" -Level Success
        Write-Log "" -Level Info

        # Display current status
        Write-Log "Current status:" -Level Info
        w32tm /query /status

        Write-Log "" -Level Info
        Write-Log "Please wait a few minutes, then use verify_time_sync.ps1 to check if root dispersion has decreased" -Level Info

    } catch {
        Write-Log "Error occurred: $($_.Exception.Message)" -Level Error
    }
}

# Execute
Main
