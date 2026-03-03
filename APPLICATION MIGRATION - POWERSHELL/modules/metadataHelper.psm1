function Invoke-MetadataCleanup {
    param ([string]$BasePath)

    try {
        if (-not $BasePath) {
            $BasePath = Join-Path $PSScriptRoot "metadata"
        }

        if (-not (Test-Path $BasePath)) {
            Write-LogInfo "No metadata folder found. Skipping cleanup."
            return
        }

        $previousPath = Join-Path $BasePath "previous"

        if (-not (Test-Path $previousPath)) {
            New-Item $previousPath -ItemType Directory | Out-Null
        }

        Get-ChildItem $BasePath | Where-Object { $_.Name -ne "previous" } | ForEach-Object {
            $dest = Join-Path $previousPath $_.Name
            Move-Item $_.FullName $dest -ErrorAction SilentlyContinue
        }

        Write-LogInfo "Metadata cleanup completed"
    }
    catch {
        Write-LogError "Metadata cleanup failed: $($_.Exception.Message)"
    }
}

function Get-ValidatedMetadataConfig {
    param([string]$ConfigPath)

    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-LogError "Invalid metadata config JSON"
        return $null
    }

    return $config
}

function New-AppMetadataPackage {
    param(
        [string]$TemplatePath,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$OktaAppId,
        [string]$AppName,
        [string]$MetadataConfigPath
    )

    try {
        Write-LogInfo "Creating metadata package for $OktaAppId"

        Invoke-MetadataCleanup

        $metadataConfig = Get-ValidatedMetadataConfig $MetadataConfigPath
        if (-not $metadataConfig) { return }

        $basePath = Join-Path (Get-Location) "metadata"
        $folderName = "${AppName}_${OktaAppId}"
        $appFolder = Join-Path $basePath $folderName
        $outputFile = Join-Path $appFolder "oidc_metadata_entra.txt"
        $zipPath = Join-Path $basePath "$folderName.zip"

        New-Item $appFolder -ItemType Directory -Force | Out-Null

        $content = Get-Content $TemplatePath -Raw
        $content = $content.Replace("{{CLIENT_ID}}", $ClientId)
        $content = $content.Replace("{{CLIENT_SECRET}}", $ClientSecret)
        $content = $content.Replace("{{TENANT_ID}}", $metadataConfig.TENANT_ID)
        $content = $content.Replace("{{AUTHORIZE_ENDPOINT}}", $metadataConfig.AUTHORIZE_URL)
        $content = $content.Replace("{{TOKEN_ENDPOINT}}", $metadataConfig.TOKEN_URL)
        $content = $content.Replace("{{WELLKNOWN_ENDPOINT}}", $metadataConfig.WELLKNOWN_URL)

        Set-Content $outputFile $content

        if (Test-Path $zipPath) {
            Remove-Item $zipPath -Force
        }

        Compress-Archive -Path $appFolder -DestinationPath $zipPath

        Write-Host "Package created: $zipPath" -ForegroundColor Green
        Write-LogInfo "Metadata package created: $zipPath"
    }
    catch {
        Write-Host "Failed to create metadata package" -ForegroundColor Red
        Write-LogError "Metadata creation failed: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-AppMetadataPackage