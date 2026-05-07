<#
.SYNOPSIS
    Simplified NTP Client Setup Tool - Complete Configuration in One Step

.DESCRIPTION
    This script configures Windows as an NTP client with all necessary settings:
    - Connect to specified time server
    - Configure 64-second high-frequency sync (using MinPollInterval/MaxPollInterval)
    - No need to run configure_sync_interval.ps1 separately

.PARAMETER ServerIP
    IP address of the time server (optional, will prompt if not provided)

.PARAMETER SyncInterval
    Synchronization interval in seconds, default 64, range 64-3600

.EXAMPLE
    .\setup_ntp_client_simple.ps1 -ServerIP "192.168.168.199"
    Configure client to connect to specified server with default 64-second interval

.EXAMPLE
    .\setup_ntp_client_simple.ps1 -ServerIP "192.168.168.199" -SyncInterval 128
    Configure client to connect to specified server with 128-second interval

.NOTES
    Requires administrator privileges
    Author: Claude Code
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Please enter the IP address of the time server")]
    [string]$ServerIP,

    [Parameter(Mandatory=$false)]
    [ValidateRange(64, 3600)]
    [int]$SyncInterval = 64
)

# Logging function
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
}

# Check administrator privileges
function Test-Administrator {
    <#
    .SYNOPSIS
        Check if running with administrator privileges

    .OUTPUTS
        System.Boolean - Whether current user is administrator
    #>
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Calculate poll interval power (W32Time uses 2^n seconds)
function Get-PollIntervalPower {
    <#
    .SYNOPSIS
        Calculate the power of 2 for W32Time polling interval

    .PARAMETER Seconds
        Target seconds

    .OUTPUTS
        System.Int32 - Power of 2 (n) where 2^n is closest to target seconds
    #>
    param([int]$Seconds)

    # Find the closest 2^n
    $power = [Math]::Floor([Math]::Log($Seconds, 2))

    # Limit range (6 = 64 seconds, 17 = 131072 seconds)
    if ($power -lt 6) { $power = 6 }
    if ($power -gt 17) { $power = 17 }

    return $power
}

# Test server connectivity
function Test-ServerConnectivity {
    <#
    .SYNOPSIS
        Test network connectivity with time server

    .PARAMETER ServerIP
        Server IP address

    .OUTPUTS
        System.Boolean - Whether server is reachable
    #>
    param([string]$ServerIP)

    Write-Log "Testing connectivity with server $ServerIP..." -Level Info

    # Test Ping
    $pingResult = Test-Connection -ComputerName $ServerIP -Count 2 -Quiet
    if (-not $pingResult) {
        Write-Log "Warning: Unable to ping server $ServerIP" -Level Warning
        Write-Log "This may indicate network issues or server firewall blocking ICMP" -Level Warning
        return $false
    }

    Write-Log "Successfully pinged server $ServerIP" -Level Success
    return $true
}

# Main execution flow
function Main {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   Simplified NTP Client Setup Tool" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check administrator privileges
    if (-not (Test-Administrator)) {
        Write-Log "Error: This script requires administrator privileges" -Level Error
        Write-Log "Please run PowerShell as administrator and try again" -Level Error
        return
    }

    # If ServerIP not provided, prompt for input
    if ([string]::IsNullOrEmpty($ServerIP)) {
        Write-Host "Please enter the IP address of the NTP time server" -ForegroundColor Yellow
        $ServerIP = Read-Host "Server IP"

        if ([string]::IsNullOrEmpty($ServerIP)) {
            Write-Log "Error: Server IP address is required" -Level Error
            return
        }
    }

    Write-Log "========================================" -Level Info
    Write-Log "Starting Windows Time Client Setup" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "Target server: $ServerIP" -Level Info
    Write-Log "Sync interval: $SyncInterval seconds" -Level Info
    Write-Log "" -Level Info

    try {
        # Test server connectivity
        $isConnected = Test-ServerConnectivity -ServerIP $ServerIP
        if (-not $isConnected) {
            Write-Log "Suggestions to check:" -Level Warning
            Write-Log "  1. Are both computers on the same network segment?" -Level Warning
            Write-Log "  2. Has setup_time_server.ps1 been run on the server?" -Level Warning
            Write-Log "  3. Is the network connection normal?" -Level Warning
            Write-Log "" -Level Warning
            Write-Log "Continue with setup? (may fail)" -Level Warning
            $continue = Read-Host "Enter Y to continue, or any other key to cancel"
            if ($continue -ne "Y" -and $continue -ne "y") {
                Write-Log "User cancelled operation" -Level Info
                return
            }
        }

        # Calculate poll interval power
        $pollPower = Get-PollIntervalPower -Seconds $SyncInterval
        $actualInterval = [Math]::Pow(2, $pollPower)

        Write-Log "Calculation result: 2^$pollPower = $actualInterval seconds" -Level Info
        Write-Log "" -Level Info

        # Stop W32Time service
        Write-Log "Stopping W32Time service..." -Level Info
        Stop-Service W32Time -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Configure W32Time as NTP Client mode
        Write-Log "Configuring W32Time as NTP Client mode..." -Level Info

        # Set to NTP type
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
            -Name "Type" -Value "NTP"

        # Set time server
        Write-Log "Setting time server to: $ServerIP" -Level Info
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
            -Name "NtpServer" -Value "$ServerIP,0x9"

        # Enable NTP Client
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" `
            -Name "Enabled" -Value 1

        # Disable NTP Server function (this machine is a client)
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" `
            -Name "Enabled" -Value 0

        # Configure high-frequency synchronization parameters
        Write-Log "Setting sync interval to $actualInterval seconds..." -Level Info

        # Critical setting: MinPollInterval and MaxPollInterval
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "MinPollInterval" -Value $pollPower
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "MaxPollInterval" -Value $pollPower

        Write-Log "Set MinPollInterval = MaxPollInterval = $pollPower (${actualInterval} seconds)" -Level Success

        # SpecialPollInterval: synchronization interval (seconds)
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" `
            -Name "SpecialPollInterval" -Value $actualInterval

        # Set update interval
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "UpdateInterval" -Value 100

        # Set time adjustment parameters (allow larger time offset)
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "MaxPosPhaseCorrection" -Value 3600
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "MaxNegPhaseCorrection" -Value 3600

        # Set as reliable time source
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "AnnounceFlags" -Value 10

        # Set service startup type to automatic
        Write-Log "Setting service to auto-start..." -Level Info
        Set-Service W32Time -StartupType Automatic

        # Start service
        Write-Log "Starting W32Time service..." -Level Info
        Start-Service W32Time
        Start-Sleep -Seconds 2

        # Update configuration
        Write-Log "Updating configuration..." -Level Info
        w32tm /config /update | Out-Null

        # Force synchronization
        Write-Log "Forcing synchronization with server..." -Level Info
        $syncResult = w32tm /resync /force 2>&1

        if ($syncResult -match "successfully" -or $syncResult -match "成功") {
            Write-Log "Time synchronization successful!" -Level Success
        } else {
            Write-Log "Sync command executed, result: $syncResult" -Level Warning
            Write-Log "Check status later using verify_time_sync.ps1" -Level Warning
        }

        # Display configuration results
        Write-Log "" -Level Info
        Write-Log "========================================" -Level Success
        Write-Log "Windows Time Client Setup Completed!" -Level Success
        Write-Log "========================================" -Level Success
        Write-Log "" -Level Info
        Write-Log "Configuration summary:" -Level Info
        Write-Log "  Time server: $ServerIP" -Level Info
        Write-Log "  Sync interval: $actualInterval seconds (2^$pollPower)" -Level Info
        Write-Log "  Service status: $((Get-Service W32Time).Status)" -Level Info
        Write-Log "" -Level Info

        # Display current time information
        Write-Log "Running w32tm /query /status to check status..." -Level Info
        w32tm /query /status

        Write-Log "" -Level Info
        Write-Log "Setup completed! This computer will sync with server every $actualInterval seconds" -Level Success
        Write-Log "You can verify sync status using verify_time_sync.ps1" -Level Info

    } catch {
        Write-Log "Error occurred: $($_.Exception.Message)" -Level Error
        Write-Log "Detailed error: $($_.Exception.ToString())" -Level Error
    }
}

# Execute main program
Main
