# Global variables for logging
$script:LogFolder = $null
$script:TranscriptPath = $null
$script:MainLogPath = $null
$script:CurrentAppLogPath = $null
$script:CurrentOktaAppId = $null

function Initialize-Logger {
    param([string]$BasePath)

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LogFolder = Join-Path $BasePath "logs"

    if (-not (Test-Path $script:LogFolder)) {
        New-Item -Path $script:LogFolder -ItemType Directory -Force | Out-Null
    }

    # CHANGE: Use separate filenames for transcript vs custom logs
    $script:TranscriptPath = Join-Path $script:LogFolder "transcript_$timestamp.log"
    $script:MainLogPath = Join-Path $script:LogFolder "main_$timestamp.log"

    try {
        $transcript = Start-Transcript -Path $script:TranscriptPath -Append
        Write-LogInfo "Transcript started: $script:TranscriptPath" 
    }
    catch {
        Write-LogInfo "Warning: Could not start transcript - $($_.Exception.Message)"
    }

    Write-LogInfo "Logger initialized at $script:LogFolder"
}

function Set-LogContext {
    param([string]$OktaAppId)

    $script:CurrentOktaAppId = $OktaAppId
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:CurrentAppLogPath = Join-Path $script:LogFolder "${OktaAppId}_$timestamp.log"

    Write-LogInfo "Log context set for app: $OktaAppId"
}

function Write-LogMessage {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # CHANGE: Use mutex/lock to prevent conflicts
    $mutex = New-Object System.Threading.Mutex($false, "LogFileMutex")
    try {
        $mutex.WaitOne() | Out-Null

        # Write to main log
        if ($script:MainLogPath) {
            Add-Content -Path $script:MainLogPath -Value $logEntry -Encoding UTF8
        }

        # Write to app-specific log if context is set
        if ($script:CurrentAppLogPath -and $script:CurrentOktaAppId) {
            $appLogEntry = "[$timestamp] [$Level] [$script:CurrentOktaAppId] $Message"
            Add-Content -Path $script:CurrentAppLogPath -Value $appLogEntry -Encoding UTF8
        }
    }
    finally {
        $mutex.ReleaseMutex()
    }
}

function Write-LogInfo {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "INFO"
}

function Write-LogError {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "ERROR"
}

function Write-LogDebug {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "DEBUG"
}

Export-ModuleMember -Function Initialize-Logger, Set-LogContext, Write-LogInfo, Write-LogError, Write-LogDebug
