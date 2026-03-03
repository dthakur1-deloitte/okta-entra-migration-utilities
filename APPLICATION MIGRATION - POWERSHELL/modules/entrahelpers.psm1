function Get-AccessTokenForGraphAPI {

    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )

    try {
        Write-LogInfo "Requesting Graph API access token"

        $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

        $body = @{
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = "https://graph.microsoft.com/.default"
            grant_type    = "client_credentials"
        }

        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"

        if ($response.access_token) {
            Write-LogInfo "Graph API token acquired successfully"
            return $response.access_token
        }
        else {
            Write-Host "Failed to retrieve access token" -ForegroundColor Red
            Write-LogError "Token response missing access_token"
            return $null
        }
    }
    catch {
        Write-Host "Error retrieving Graph token" -ForegroundColor Red
        Write-LogError "Graph token error: $($_.Exception.Message)"
        return $null
    }
}

function Connect-GraphWithToken {
    param([string] $AccessToken)

    try {
        $secureAccessToken = $AccessToken | ConvertTo-SecureString -AsPlainText -Force
        Connect-MgGraph -AccessToken $secureAccessToken -NoWelcome | Out-Null
        Write-LogDebug "Connected to Microsoft Graph"
    }
    catch {
        Write-Host "Failed to connect to Graph" -ForegroundColor Red
        Write-LogError "Graph connection failed: $($_.Exception.Message)"
    }
}

function Build-EntraOIDCAppPayload {

    param(
        [string] $AppName,
        [string] $AppType,
        [string[]] $ReplyUrl,
        [string] $LogoutUrl,
        [bool] $EnableImplicit,
        [bool] $EnableNativeAuth
    )

    $requiredResourceAccess = @{
        ResourceAppId  = "00000003-0000-0000-c000-000000000000"
        ResourceAccess = @(
            @{ Id = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0"; Type = "Scope" }
            @{ Id = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182"; Type = "Scope" }
            @{ Id = "37f7f235-527c-4136-accd-4a02d197296e"; Type = "Scope" }
            @{ Id = "14dad69e-099b-42c9-810b-d002981feec1"; Type = "Scope" }
            @{ Id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; Type = "Scope" }
        )
    }

    $appParams = @{
        DisplayName                       = $AppName
        SignInAudience                    = "AzureADMyOrg"
        RequiredResourceAccess            = @($requiredResourceAccess)

        Api                               = @{
            AcceptMappedClaims          = $true
            RequestedAccessTokenVersion = 2
        }

        Spa                               = @{ RedirectUris = @() }
        Web                               = @{ RedirectUris = @() }
        PublicClient                      = @{ RedirectUris = @() }

        OptionalClaims                    = @{
            IdToken = @(
                @{
                    AdditionalProperties = @()
                    Essential = $false
                    Name = "email"
                    Source = $null
                }
            )
        }

        ServicePrincipalLockConfiguration = @{
            IsEnabled                  = $true
            AllProperties              = $true
            CredentialsWithUsageSign   = $true
            CredentialsWithUsageVerify = $true
        }
    }

    switch ($AppType) {
        "web" { 
            $appParams.Web.RedirectUris = @($ReplyUrl)
            $appParams.Web.LogoutUrl = $LogoutUrl
        }
        "browser" { $appParams.Spa.RedirectUris = @($ReplyUrl) }
    }
    
    # Enable implicit flow if present in Okta
    if ($EnableImplicit) {

        $appParams.Web.implicitGrantSettings = @{
            enableIdTokenIssuance     = $true
            enableAccessTokenIssuance = $true
        }
        Write-Host "Implicit flow enabled (ID + Access token) ...." -ForegroundColor Cyan
        Write-LogInfo "Implicit flow enabled (ID + Access token)"
    }

    # Enable native authentication if user selected
    if ($EnableNativeAuth) {
        $appParams.NativeAuthenticationApisEnabled = "all"
        Write-Host "Native authentication enabled ...." -ForegroundColor Cyan
        Write-LogInfo "Native authentication enabled"
    }

    return $appParams
}

function Add-ServicePrincipalClaimsMappingPolicy {

    param(
        [string]$ServicePrincipalId,
        [string]$PolicyId,
        [string]$AccessToken
    )

    try {
        Write-LogInfo "Assigning claims mapping policy"

        $uri = "https://graph.microsoft.com/v1.0/servicePrincipals/$ServicePrincipalId/claimsMappingPolicies/`$ref"

        $headers = @{
            "Content-Type"  = "application/json"
            "Authorization" = "Bearer $AccessToken"
        }

        $body = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/policies/claimsMappingPolicies/$PolicyId"
        } | ConvertTo-Json

        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body

        Write-LogInfo "Claims mapping policy assigned"
    }
    catch {
        Write-Host "Failed to assign claims mapping policy" -ForegroundColor Red
        Write-LogError "Claims mapping failed: $($_.Exception.Message)"
    }
}

function Add-AppToAuthUserFlow {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,
        
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        
        [Parameter(Mandatory = $true)]
        [string]$UserFLowId
    )
    
    try {
        # Construct the URI
        $uri = "https://graph.microsoft.com/v1.0/identity/authenticationEventsFlows/$UserFLowId/conditions/applications/includeApplications"
        
        # Prepare headers
        $headers = @{
            'Content-Type'  = 'application/json'
            'Authorization' = "Bearer $Token"
        }
        
        # Prepare body
        $body = @{
            '@odata.type' = '#microsoft.graph.authenticationConditionApplication'
            'appId'       = $AppId
        } | ConvertTo-Json
        
        # Make the API call
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        
        # Return the response
        return $response
    }
    catch {
        Write-Error "Failed to add application to user flow: $_"
        throw
    }
}

function Add-AppToAuthEventListener {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,
        
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        
        [Parameter(Mandatory = $true)]
        [string]$PolicyId
    )
    
    try {
        # Construct the URI
        $uri = "https://graph.microsoft.com/beta/identity/authenticationEventListeners/$PolicyId/conditions/applications/includeApplications"
        
        # Prepare headers
        $headers = @{
            'Content-Type'  = 'application/json'
            'Authorization' = "Bearer $Token"
        }
        
        # Prepare body
        $body = @{
            '@odata.type' = '#microsoft.graph.authenticationConditionApplication'
            'appId'       = $AppId
        } | ConvertTo-Json
        
        # Make the API call
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        
        # Return the response
        return $response
    }
    catch {
        Write-Error "Failed to add application to authentication event listener: $_"
        throw
    }
}


function New-EntraOIDCAppFromOkta {

    param(
        [string]$GraphAccessToken,
        [string]$UserAccessToken,
        [string]$ClaimMappingPolicyId,
        [string]$ListenerPolicyId,
        [string]$UserFlowId,
        [pscustomobject]$OktaApp
    )

    try {
        Write-LogInfo "Starting Entra app creation"

        Connect-GraphWithToken -AccessToken $GraphAccessToken
        Write-Host "Connected with Entra ...." -ForegroundColor Cyan

        $appName = [string]$OktaApp.label

        $replyUrls = @()
        try { $replyUrls = @($OktaApp.settings.oauthClient.redirect_uris) | Where-Object { $_ } } catch {}

        $appType = "web"
        try {
            if ($OktaApp.settings.oauthClient.application_type -eq "browser") {
                $appType = "browser"
            }
        }
        catch {}

        $logoutUrl = $null
        try { $logoutUrl = $OktaApp.settings.oauthClient.post_logout_redirect_uris[0] } catch {}

        Write-LogDebug "AppType: $appType"

        $enableImplicit = $false
        try {
            if ($OktaApp.settings.oauthClient.grant_types -contains "implicit") {
                $enableImplicit = $true
            }
        }
        catch {}

        # Ask user for native authentication
        $nativeInput = Read-Host "Enable Native Authentication for '$appName'? (y/n)"
        $enableNativeAuth = $false
        if ($nativeInput -eq "y") {
            $enableNativeAuth = $true
        }

        $appParams = Build-EntraOIDCAppPayload `
            -AppName $appName `
            -AppType $appType `
            -ReplyUrl $replyUrls `
            -LogoutUrl $logoutUrl `
            -EnableImplicit $enableImplicit `
            -EnableNativeAuth $enableNativeAuth

        # $cj = $appParams | ConvertTo-Json
        # Write-Host $cj
            
        Write-Host "Attempting to create application in Entra ...." -ForegroundColor Cyan
        $application = New-MgApplication @appParams -ErrorAction Stop
        Write-Host "Entra Application Created ...." -ForegroundColor Cyan
        Write-LogInfo "Application created"
        
        Start-Sleep -Seconds 2
        
        Write-Host "Attempting to create Service principal Entra ...." -ForegroundColor Cyan
        $servicePrincipal = New-MgServicePrincipal -BodyParameter @{ AppId = $application.AppId } -ErrorAction Stop
        Write-Host "Service Principal Created ...." -ForegroundColor Cyan
        Write-LogInfo "Service principal created"
        
        Start-Sleep -Seconds 2
        
        $secret = $null
        
        if ($appType -eq "web") {
            $today = Get-Date -Format 'MM-dd-yyyy'
            $secretDisplayName = "Secret $today"
            $secret = Add-MgApplicationPassword -ApplicationId $application.Id -PasswordCredential @{
                displayName   = $secretDisplayName
                startDateTime = (Get-Date).ToString("o")
                endDateTime   = (Get-Date).AddMonths(18).ToString("o")
            }
            
            Write-Host "Client secret created ...." -ForegroundColor Cyan
            Write-LogInfo "Client secret created"
        }
        
        # SET APPLICATION VISIBILITY TO NO
        $tags = $servicePrincipal.tags
        $tags += "HideApp"
        Update-MgServicePrincipal -ServicePrincipalID $servicePrincipal.Id -Tags $tags
        Write-Host "App visibility set to NO ...." -ForegroundColor Cyan
        Write-LogInfo "App visibility updated"
        
        # ASSIGN CLAIMS MAPPING POLICY TO APPLICATION
        Write-Host "Attempting to assign claims mapping policy ...." -ForegroundColor Cyan
        Add-ServicePrincipalClaimsMappingPolicy `
            -ServicePrincipalId $servicePrincipal.Id `
            -PolicyId $ClaimMappingPolicyId `
            -AccessToken $GraphAccessToken
        Write-Host "Claims mapping policy assigned ...." -ForegroundColor Cyan
        
        # ASSIGN APPLICATION TO USER FLOW
        $result = Add-AppToAuthUserFlow `
            -Token $UserAccessToken `
            -AppId $application.AppId `
            -UserFLowId $UserFlowId
        if ($result ) {
            Write-Host "Assigned the application to SIGNIN_ONLY_WITH_EMAIL_PASSWORD User Flow ..." -ForegroundColor Cyan
        }

        # ASSIGN APPLICATION TO LISTENER POLICY
        $result = Add-AppToAuthEventListener `
            -Token $UserAccessToken `
            -AppId $application.AppId `
            -PolicyId $ListenerPolicyId
        if ($result ) {
            Write-Host "Assigned the application to Listerner Policy ..." -ForegroundColor Cyan
        }
        
        return [pscustomobject]@{
            Application      = $application
            ServicePrincipal = $servicePrincipal
            ClientId         = $application.AppId
            ClientSecret     = $secret.secretText
        }
    }
    catch {
        Write-Host "Failed to create Entra app" -ForegroundColor Red
        Write-LogError "Entra app creation failed: $($_.Exception.Message)"
        return $null
    }
}

Export-ModuleMember -Function Get-AccessTokenForGraphAPI, New-EntraOIDCAppFromOkta