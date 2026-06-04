<#
.SYNOPSIS
    Configure Windows computer as NTP time client

.DESCRIPTION
    This script automatically configures Windows Time Service (W32Time) to NTP Client mode,
    connects to the specified time server, and sets up high-frequency synchronization (every 60 seconds).

.PARAMETER ServerIP
    IP address of the time server (required parameter)

.PARAMETER SyncInterval
    Time synchronization interval (seconds), default is 60 seconds

.PARAMETER LogPath
    Log file path, default is time_sync_client.log

.EXAMPLE
    .\setup_time_client.ps1 -ServerIP "192.168.1.100"
    Connect to time server with IP 192.168.1.100

.EXAMPLE
    .\setup_time_client.ps1 -ServerIP "192.168.1.100" -SyncInterval 30
    Connect to time server and set synchronization every 30 seconds

.NOTES
    Requires system administrator privileges to execute
    Author: Claude Code
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Please enter the IP address of the time server")]
    [ValidateNotNullOrEmpty()]
    [string]$ServerIP,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 3600)]
    [int]$SyncInterval = 60,

    [string]$LogPath = "time_sync_client.log"
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

# Test connectivity with server
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
    Write-Log "========================================" -Level Info
    Write-Log "Starting Windows Time Client setup" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "Target server: $ServerIP" -Level Info
    Write-Log "Sync interval: $SyncInterval seconds" -Level Info
    Write-Log "" -Level Info

    # Check administrator privileges
    if (-not (Test-Administrator)) {
        Write-Log "Error: This script requires administrator privileges" -Level Error
        Write-Log "Please run PowerShell as administrator and try again" -Level Error
        return
    }

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

        # Stop W32Time service
        Write-Log "Stopping W32Time service..." -Level Info
        Stop-Service W32Time -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Configure W32Time as NTP Client
        Write-Log "Configuring W32Time as NTP Client mode..." -Level Info

        # Set as NTP type
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
        Write-Log "Setting sync interval to $SyncInterval seconds..." -Level Info

        # SpecialPollInterval: synchronization interval (seconds)
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" `
            -Name "SpecialPollInterval" -Value $SyncInterval

        # Set update interval
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
            -Name "UpdateInterval" -Value $SyncInterval

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

        # Re-register time source
        Write-Log "Re-registering time source..." -Level Info
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
        Write-Log "Windows Time Client setup completed!" -Level Success
        Write-Log "========================================" -Level Success
        Write-Log "" -Level Info
        Write-Log "Configuration summary:" -Level Info
        Write-Log "  Time server: $ServerIP" -Level Info
        Write-Log "  Sync interval: $SyncInterval seconds" -Level Info
        Write-Log "  Service status: $(( Get-Service W32Time).Status)" -Level Info
        Write-Log "" -Level Info

        # Display current time information
        Write-Log "Running w32tm /query /status to check status..." -Level Info
        w32tm /query /status

        Write-Log "" -Level Info
        Write-Log "Setup completed! This computer will sync with server every $SyncInterval seconds" -Level Success
        Write-Log "You can verify sync status using verify_time_sync.ps1" -Level Info

    } catch {
        Write-Log "Error occurred: $($_.Exception.Message)" -Level Error
        Write-Log "Detailed error: $($_.Exception.ToString())" -Level Error
    }
}

# Run main program
Main
