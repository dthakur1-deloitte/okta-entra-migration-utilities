param(
    [ValidateSet("np", "prod")]
    [string]$Environment = "np"
)

# SCRIPT EXECUTION PATH
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# IMPORTING REQUIRED MODULES
Import-Module Microsoft.Graph.Applications
Import-Module "$scriptRoot\modules\logging.psm1" -Force
Import-Module "$scriptRoot\modules\helpers.psm1" -Force
Import-Module "$scriptRoot\modules\oktahelpers.psm1" -Force
Import-Module "$scriptRoot\modules\entrahelpers.psm1" -Force
Import-Module "$scriptRoot\modules\metadataHelper.psm1" -Force

# DECLARING REQUIRED FILE PATHS
$OktaAppsFilePath = Join-Path $scriptRoot "apps.txt"
$configFolder = Join-Path $scriptRoot "config"
$MetadataTemplatePath = Join-Path $scriptRoot "templates\oidc-metadata-template.txt"

# ENVIRONMENT-BASED CONFIG SELECTION
switch ($Environment) {
    "np" {
        $ConfigFilePath = Join-Path $configFolder "np-config.json"
        $MetadataConfigFilePath = Join-Path $configFolder "np-metadataConfig.json"
        Write-Host "Running in NON-PROD environment" -ForegroundColor Cyan
    }
    "prod" {
        $ConfigFilePath = Join-Path $configFolder "prod-config.json"
        $MetadataConfigFilePath = Join-Path $configFolder "prod-metadataConfig.json"
        Write-Host "Running in PROD environment" -ForegroundColor Cyan
    }
}

try {

    Initialize-Logger -BasePath $scriptRoot
    Write-LogInfo "========== SCRIPT STARTED =========="
    
    # VALIDATE FILES
    $filesValid = Test-RequiredFiles `
    -ConfigFilePath $ConfigFilePath `
    -MetadataConfigFilePath $MetadataConfigFilePath `
    -OktaAppsFilePath $OktaAppsFilePath
    if (-not $filesValid) {
        Write-Host "Required files missing. Exiting" -ForegroundColor Red
        return
    }
    Write-LogInfo "All required files validated"

    # LOAD CONFIG
    $config = Get-ValidatedConfig -ConfigPath $ConfigFilePath
    Write-LogInfo "Configuration files loaded"

    if ($null -eq $config) {
        exit
    }
    
    # LOAD APP IDS
    $allOktaAppIds = Get-OktaAppIdsFromFile -FilePath $OktaAppsFilePath
    if (-not $allOktaAppIds -or $allOktaAppIds.Count -eq 0) {
        Write-Host "`nNo applications to migrate. Exiting" -ForegroundColor Blue
        Write-LogInfo "No Okta App IDs found"
        return
    }
    Write-LogInfo "Total apps to process: $($allOktaAppIds.Count)"

    # GET GRAPH TOKEN
    $graphApiAccessToken = Get-AccessTokenForGraphAPI `
        -TenantId $config.ENTRA_TENANT_ID `
        -ClientId $config.ENTRA_CLIENT_ID `
        -ClientSecret $config.ENTRA_CLIENT_SECRET
    if (-not $graphApiAccessToken) {
        Write-Host "Failed to acquire Graph token. Exiting." -ForegroundColor Red
        Write-LogError "Graph token is null. Stopping execution"
        return
    }
    Write-Host "Graph API Access Token fetched ..." -ForegroundColor Cyan
    
    $UserAccessToken = $config.USER_ACCESS_TOKEN
    Write-Host "User Access Token fetched ..." -ForegroundColor Cyan

    foreach ($oktaAppid in $allOktaAppIds) {

        try {
            # Set per-app logging
            Set-LogContext -OktaAppId $oktaAppid

            Write-Host "====== `nProcessing Okta App ID: $oktaAppid`n======" -ForegroundColor Cyan
            Write-LogInfo "---- Processing App: $oktaAppid ----"

            # FETCH OKTA APP
            $oktaApp = Get-OktaApp `
                -AppId $oktaAppid `
                -OktaDomain $config.OKTA_DOMAIN `
                -ApiToken $config.OKTA_API_TOKEN

            if (-not $oktaApp) {
                Write-LogError "Skipping app (not found): $oktaAppid"
                continue
            }

            $oktaAppLabel = $oktaApp.label
            $oktaAppSignOnMode = $oktaApp.signOnMode

            Write-Host "APPLICATION NAME : $oktaAppLabel" -ForegroundColor Yellow
            Write-Host "SIGN ON MODE  : $oktaAppSignOnMode" -ForegroundColor Yellow

            Write-LogInfo "App Name: $oktaAppLabel"
            Write-LogInfo "SignOnMode: $oktaAppSignOnMode"

            switch ($oktaAppSignOnMode) {

                "OPENID_CONNECT" {
                    Write-LogInfo "OIDC flow started"

                    $entraApp = New-EntraOIDCAppFromOkta `
                        -GraphAccessToken $graphApiAccessToken `
                        -UserAccessToken $UserAccessToken `
                        -ClaimMappingPolicyId $config.CLAIMS_MAPPING_POLICY `
                        -ListenerPolicyId $config.LISTENER_POLICY_ID `
                        -UserFlowId $config.USER_FLOW_ID `
                        -OktaApp $oktaApp

                    if (-not $entraApp) {
                        Write-LogError "Failed to create Entra app"
                        continue
                    }

                    Write-LogInfo "Entra app created successfully"

                    # METADATA PACKAGE
                    New-AppMetadataPackage `
                        -TemplatePath $MetadataTemplatePath `
                        -ClientId $entraApp.ClientId `
                        -ClientSecret $entraApp.ClientSecret `
                        -OktaAppId $oktaAppid `
                        -AppName $oktaAppLabel `
                        -MetadataConfigPath $MetadataConfigFilePath

                    Write-LogInfo "Metadata package created"
                }

                default {
                    Write-Host "UNKNOWN SIGN MODE DETECTED" -ForegroundColor Red
                    Write-LogError "Unsupported SignOnMode: $oktaAppSignOnMode"
                }
            }

            Write-LogInfo "Completed App: $oktaAppid"
        }
        catch {
            Write-Host "Error processing App ID: $oktaAppid" -ForegroundColor Red
            Write-LogError "Unhandled error: $($_.Exception.Message)"
            continue
        }
    }

    Write-LogInfo "========== SCRIPT COMPLETED =========="
}
catch {
    Write-Host "Fatal error occurred. Check logs." -ForegroundColor Red
    Write-LogError "Fatal error: $($_.Exception.Message)"
}