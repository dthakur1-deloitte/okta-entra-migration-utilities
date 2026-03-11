function Get-AccessTokenForGraphAPI {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientSecret
    )

    try {
        $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        $body = @{
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = "https://graph.microsoft.com/.default"
            grant_type    = "client_credentials"
        }

        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        
        if (-not $response.access_token) {
            throw "Access token not returned from authentication endpoint"
        }
        
        return $response.access_token
    }
    catch {
        Write-Error "Authentication failed: $($_.Exception.Message)"
        throw
    }
}

function Get-ValidatedConfig {
    param([string]$ConfigPath)

    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "Invalid configuration format" -ForegroundColor Red
        Write-LogError "Invalid JSON in config"
        return $null
    }

    $requiredProps = @(
        "ENTRA_TENANT_ID",
        "ENTRA_CLIENT_ID",
        "ENTRA_CLIENT_SECRET"
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

function Get-UserObjectId {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EmailAddress,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Issuer,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken
    )
    
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }
    
    $filter = "identities/any(c:c/issuerAssignedId eq '$EmailAddress' and c/issuer eq '$Issuer')"
    $select = "id"
    
    # URL encode the filter and select parameters
    $encodedFilter = [System.Web.HttpUtility]::UrlEncode($filter)
    $encodedSelect = [System.Web.HttpUtility]::UrlEncode($select)
    
    $uri = "https://graph.microsoft.com/v1.0/users?`$select=$encodedSelect&`$filter=$encodedFilter"
    
    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        
        # Check if user was found
        if ($response.value -and $response.value.Count -gt 0) {
            return $response.value[0].id
        }
        else {
            Write-Host "No user found for $EmailAddress"
            return $null
        }
    }
    catch {
        Write-Warning "Failed to get user ID for $EmailAddress : $_"
        return $null
    }
}

function Update-UserMigrationFlag {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectId,

        [Parameter(Mandatory = $true)]
        [bool]$RequiresMigration,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$B2CApplicationId
    )
    
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }
    
    $extensionAttributeName = "extension_${B2CApplicationId}_requiresMigration"

    $body = @{
        $extensionAttributeName = $RequiresMigration
    } | ConvertTo-Json
    
    $uri = "https://graph.microsoft.com/v1.0/users/$ObjectId"
    
    try {
        Write-Host "  Object ID: $ObjectId" -ForegroundColor Cyan
        Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body $body
        return $true
    }
    catch {
        Write-Error "Failed to update migration flag for user $ObjectId : $_"
        Write-Error "Response: $($_.Exception.Message)"
        return $false
    }
}


Export-ModuleMember -Function @(
    'Get-AccessTokenForGraphAPI',
    'Get-ValidatedConfig',
    'Get-UserObjectId',
    'Update-UserMigrationFlag'
)
