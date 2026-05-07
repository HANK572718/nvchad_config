<#
.SYNOPSIS
    Verify Windows time synchronization status

.DESCRIPTION
    This script checks the operational status of Windows Time Service, including service status,
    time source, offset, connectivity, and generates a detailed diagnostic report.

.PARAMETER ShowDetails
    Display detailed diagnostic information

.PARAMETER LogPath
    Log file path, default is time_sync_verify.log

.PARAMETER ContinuousMode
    Continuous monitoring mode, updates every N seconds

.PARAMETER RefreshInterval
    Refresh interval in continuous monitoring mode (seconds), default is 5 seconds

.EXAMPLE
    .\verify_time_sync.ps1
    Perform basic time synchronization verification

.EXAMPLE
    .\verify_time_sync.ps1 -ShowDetails
    Display detailed diagnostic information

.EXAMPLE
    .\verify_time_sync.ps1 -ContinuousMode -RefreshInterval 10
    Update status every 10 seconds (press Ctrl+C to stop)

.NOTES
    Does not require administrator privileges, but some diagnostic functions may need it
    Author: Claude Code
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [switch]$ShowDetails,
    [string]$LogPath = "time_sync_verify.log",
    [switch]$ContinuousMode,
    [int]$RefreshInterval = 5
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

    .PARAMETER NoLog
        Do not write to log file, only display on console
    #>
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info',
        [switch]$NoLog
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
    if (-not $NoLog) {
        Add-Content -Path $LogPath -Value $logMessage
    }
}

# Get formatted timestamp
function Get-FormattedTimestamp {
    <#
    .SYNOPSIS
        Get formatted timestamp

    .OUTPUTS
        System.String - Formatted time string
    #>
    return Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
}

# Check service status
function Test-W32TimeService {
    <#
    .SYNOPSIS
        Check W32Time service status

    .OUTPUTS
        System.Object - Service status object
    #>
    try {
        $service = Get-Service W32Time -ErrorAction Stop
        return $service
    } catch {
        Write-Log "Error: Cannot get W32Time service information" -Level Error
        return $null
    }
}

# Get time synchronization status
function Get-TimeSyncStatus {
    <#
    .SYNOPSIS
        Get detailed time synchronization status

    .OUTPUTS
        System.Object - Time synchronization status object
    #>
    try {
        $status = w32tm /query /status 2>&1
        return $status
    } catch {
        Write-Log "Error: Cannot get time synchronization status" -Level Error
        return $null
    }
}

# Get time source configuration
function Get-TimeSourceConfig {
    <#
    .SYNOPSIS
        Get time source configuration

    .OUTPUTS
        System.String - Time source
    #>
    try {
        $ntpServer = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "NtpServer" -ErrorAction SilentlyContinue
        return $ntpServer.NtpServer
    } catch {
        return "Unable to retrieve"
    }
}

# Parse time synchronization status
function Parse-TimeSyncStatus {
    <#
    .SYNOPSIS
        Parse w32tm time synchronization status output

    .PARAMETER StatusOutput
        Output from w32tm /query /status

    .OUTPUTS
        System.Collections.Hashtable - Parsed status information
    #>
    param([string[]]$StatusOutput)

    $result = @{
        Source = "Unknown"
        LastSync = "Unknown"
        Offset = "Unknown"
        Stratum = "Unknown"
        LeapIndicator = "Unknown"
    }

    foreach ($line in $StatusOutput) {
        if ($line -match "來源:|Source:") {
            $result.Source = ($line -split ":|：")[1].Trim()
        }
        elseif ($line -match "上次成功同步時間:|Last Successful Sync Time:") {
            $result.LastSync = ($line -split ":|：")[1].Trim()
        }
        elseif ($line -match "階層:|Stratum:") {
            $result.Stratum = ($line -split ":|：")[1].Trim()
        }
        elseif ($line -match "躍點指示器:|Leap Indicator:") {
            $result.LeapIndicator = ($line -split ":|：")[1].Trim()
        }
    }

    return $result
}

# Test connection to time server
function Test-TimeServerConnection {
    <#
    .SYNOPSIS
        Test connectivity with configured time server

    .PARAMETER ServerAddress
        Server address

    .OUTPUTS
        System.Boolean - Whether server is reachable
    #>
    param([string]$ServerAddress)

    if ([string]::IsNullOrEmpty($ServerAddress) -or $ServerAddress -eq "Unable to retrieve") {
        return $false
    }

    # Remove flags (e.g. ",0x9")
    $server = ($ServerAddress -split ",")[0].Trim()

    try {
        $pingResult = Test-Connection -ComputerName $server -Count 1 -Quiet -ErrorAction Stop
        return $pingResult
    } catch {
        return $false
    }
}

# Perform verification
function Invoke-Verification {
    <#
    .SYNOPSIS
        Perform complete time synchronization verification
    #>
    $timestamp = Get-FormattedTimestamp

    Write-Log "========================================" -Level Info
    Write-Log "Windows Time Synchronization Status Verification" -Level Info
    Write-Log "Check time: $timestamp" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "" -Level Info

    # 1. Check service status
    Write-Log "[1] Checking W32Time service status" -Level Info
    $service = Test-W32TimeService

    if ($null -eq $service) {
        Write-Log "✗ W32Time service cannot be retrieved" -Level Error
        return
    }

    if ($service.Status -eq "Running") {
        Write-Log "✓ Service status: $($service.Status)" -Level Success
        Write-Log "  Startup type: $($service.StartType)" -Level Info
    } else {
        Write-Log "✗ Service status: $($service.Status)" -Level Error
        Write-Log "  Please run: Start-Service W32Time" -Level Warning
        return
    }

    Write-Log "" -Level Info

    # 2. Check time source configuration
    Write-Log "[2] Checking time source configuration" -Level Info
    $ntpServer = Get-TimeSourceConfig

    if ($ntpServer -and $ntpServer -ne "Unable to retrieve") {
        Write-Log "✓ Time source: $ntpServer" -Level Success

        # Test connectivity
        $servers = $ntpServer -split " "
        foreach ($server in $servers) {
            $serverAddr = ($server -split ",")[0]
            $isConnected = Test-TimeServerConnection -ServerAddress $serverAddr

            if ($isConnected) {
                Write-Log "  ✓ $serverAddr - Connection normal" -Level Success
            } else {
                Write-Log "  ✗ $serverAddr - Cannot connect" -Level Warning
            }
        }
    } else {
        Write-Log "✗ Cannot retrieve time source configuration" -Level Error
    }

    Write-Log "" -Level Info

    # 3. Get synchronization status
    Write-Log "[3] Time synchronization status" -Level Info
    $statusOutput = Get-TimeSyncStatus

    if ($statusOutput) {
        $parsedStatus = Parse-TimeSyncStatus -StatusOutput $statusOutput

        Write-Log "  Time source: $($parsedStatus.Source)" -Level Info
        Write-Log "  Stratum: $($parsedStatus.Stratum)" -Level Info
        Write-Log "  Last sync time: $($parsedStatus.LastSync)" -Level Info

        if ($parsedStatus.LastSync -ne "Unknown" -and $parsedStatus.LastSync -notlike "*unspecified*" -and $parsedStatus.LastSync -notlike "*未指定*") {
            Write-Log "  ✓ Successfully synchronized" -Level Success
        } else {
            Write-Log "  ✗ Not yet synchronized or sync failed" -Level Warning
        }
    }

    Write-Log "" -Level Info

    # 4. Display detailed information
    if ($ShowDetails) {
        Write-Log "[4] Detailed diagnostic information" -Level Info
        Write-Log "Running w32tm /query /status..." -Level Info
        Write-Log "----------------------------------------" -Level Info
        w32tm /query /status
        Write-Log "----------------------------------------" -Level Info
        Write-Log "" -Level Info

        Write-Log "Running w32tm /query /configuration..." -Level Info
        Write-Log "----------------------------------------" -Level Info
        w32tm /query /configuration
        Write-Log "----------------------------------------" -Level Info
        Write-Log "" -Level Info

        Write-Log "Running w32tm /query /peers..." -Level Info
        Write-Log "----------------------------------------" -Level Info
        w32tm /query /peers
        Write-Log "----------------------------------------" -Level Info
    }

    # 5. Summary
    Write-Log "" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "Verification complete" -Level Success
    Write-Log "========================================" -Level Info

    if (-not $ShowDetails) {
        Write-Log "" -Level Info
        Write-Log "Tip: Use -ShowDetails parameter to display more detailed information" -Level Info
    }

    Write-Log "" -Level Info
}

# Main program
function Main {
    if ($ContinuousMode) {
        Write-Log "Continuous monitoring mode started (updating every $RefreshInterval seconds)" -Level Info
        Write-Log "Press Ctrl+C to stop monitoring" -Level Info
        Write-Log "" -Level Info

        while ($true) {
            Clear-Host
            Invoke-Verification
            Start-Sleep -Seconds $RefreshInterval
        }
    } else {
        Invoke-Verification
    }
}

# Run main program
Main
