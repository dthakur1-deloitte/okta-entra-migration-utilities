function Test-RequiredFiles {
    param(
        [string]$ConfigFilePath,
        [string]$MetadataConfigFilePath,
        [string]$OktaAppsFilePath
    )

    $allValid = $true

    if (-not (Test-Path $ConfigFilePath)) {
        $fileName = Split-Path $ConfigFilePath -Leaf
        Write-Host "$fileName not found" -ForegroundColor Red
        Write-LogError "Missing file: $fileName"
        $allValid = $false
    }

    if (-not (Test-Path $MetadataConfigFilePath)) {
        $fileName = Split-Path $MetadataConfigFilePath -Leaf
        Write-Host "$fileName not found" -ForegroundColor Red
        Write-LogError "Missing file: $fileName"
        $allValid = $false
    }

    if (-not (Test-Path $OktaAppsFilePath)) {
        $fileName = Split-Path $OktaAppsFilePath -Leaf
        Write-Host "$fileName not found" -ForegroundColor Red
        Write-LogError "Missing file: $fileName"
        $allValid = $false
    }

    Write-Host "All required files validated ..." -ForegroundColor Cyan

    return $allValid
}

function Get-ValidatedConfig {
    param([string]$ConfigPath)

    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "Invalid config.json format" -ForegroundColor Red
        Write-LogError "Invalid JSON in config"
        return $null
    }

    $requiredProps = @(
        "OKTA_DOMAIN",
        "OKTA_API_TOKEN",
        "ENTRA_TENANT_ID",
        "ENTRA_CLIENT_ID",
        "ENTRA_CLIENT_SECRET",
        "CLAIMS_MAPPING_POLICY"
    )

    $missing = @()

    foreach ($prop in $requiredProps) {
        if (-not $config.$prop) {
            $missing += $prop
        }
    }

    if ($missing.Count -gt 0) {
        Write-Host "Missing config values: $($missing -join ', ')" -ForegroundColor Red
        Write-LogError "Missing config values: $($missing -join ', ')"
        return $null
    }

    Write-Host "Configuration loaded ..." -ForegroundColor Cyan

    return $config
}

function Get-OktaAppIdsFromFile {
    param([string]$FilePath)

    try {
        $appIds = Get-Content $FilePath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ } |
        Sort-Object -Unique

        Write-Host "Loaded $($appIds.Count) Okta App IDs." -ForegroundColor Cyan
        Write-LogInfo "Loaded $($appIds.Count) Okta App IDs"

        return $appIds
    }
    catch {
        $fileName = Split-Path $FilePath -Leaf
        Write-Host "Failed to read $fileName" -ForegroundColor Red
        Write-LogError "Failed reading $fileName : $($_.Exception.Message)"
        Write-LogError "Failed reading Okta App IDs: $($_.Exception.Message)"
        return @()
    }
}

Export-ModuleMember -Function Test-RequiredFiles, Get-ValidatedConfig, Get-OktaAppIdsFromFile