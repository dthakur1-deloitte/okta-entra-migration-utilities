using namespace System.Net

param($Request, $TriggerMetadata)

function Get-AccessTokenForGraphAPI {
    param(
        [string]$TenantId,
        [string]$ClientId,
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

function Get-UsersCount {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [string]$Filter
    )
    
    try {
        $uri = "https://graph.microsoft.com/beta/users/`$count"
        
        if ($Filter) {
            $uri += "?`$filter=$([System.Uri]::EscapeDataString($Filter))"
        }
        
        $headers = @{
            'ConsistencyLevel' = 'eventual'
            'Authorization'    = "Bearer $AccessToken"
        }
        
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
        return [int]$response
    }
    catch {
        Write-Error "Graph API call failed for filter '$Filter': $($_.Exception.Message)"
        throw
    }
}

try {
    # Validate configuration
    $tenantId = $env:GRAPH_TENANT_ID
    $clientId = $env:GRAPH_CLIENT_ID
    $clientSecret = $env:GRAPH_CLIENT_SECRET

    if (-not $tenantId -or -not $clientId -or -not $clientSecret) {
        throw "Missing required environment variables: GRAPH_TENANT_ID, GRAPH_CLIENT_ID, or GRAPH_CLIENT_SECRET"
    }

    # Get access token
    $accessToken = Get-AccessTokenForGraphAPI -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret

    # Define all queries
    $queries = @(
        @{ Key = 'totalUsers'; Filter = $null }
        @{ Key = 'migratedUsers'; Filter = "extension_a99b8832d4604fcd9bac53a0a39261e2_requiresMigration eq false" }
        @{ Key = 'totalnonhcpusersinus'; Filter = "extension_a99b8832d4604fcd9bac53a0a39261e2_customer_id eq null and country eq 'US'" }
        @{ Key = 'migratednonhcpusersinus'; Filter = "extension_a99b8832d4604fcd9bac53a0a39261e2_requiresMigration eq false and extension_a99b8832d4604fcd9bac53a0a39261e2_customer_id eq null and country eq 'US'" }
        @{ Key = 'notmigratednonhcpusersinus'; Filter = "extension_a99b8832d4604fcd9bac53a0a39261e2_requiresMigration eq true and extension_a99b8832d4604fcd9bac53a0a39261e2_customer_id eq null and country eq 'US'" }
    )

    # Execute all queries in parallel (PowerShell 7+)
    $results = $queries | ForEach-Object -Parallel {
        $query = $_
        $token = $using:accessToken
        
        try {
            $uri = "https://graph.microsoft.com/beta/users/`$count"
            
            if ($query.Filter) {
                $uri += "?`$filter=$([System.Uri]::EscapeDataString($query.Filter))"
            }
            
            $headers = @{
                'ConsistencyLevel' = 'eventual'
                'Authorization'    = "Bearer $token"
            }
            
            $count = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
            
            [PSCustomObject]@{
                Key   = $query.Key
                Count = [int]$count
                Error = $null
            }
        }
        catch {
            [PSCustomObject]@{
                Key   = $query.Key
                Count = 0
                Error = $_.Exception.Message
            }
        }
    } -ThrottleLimit 5

    # Check for errors
    $errors = $results | Where-Object { $_.Error }
    if ($errors) {
        $errorMessages = ($errors | ForEach-Object { "$($_.Key): $($_.Error)" }) -join "; "
        throw "One or more Graph API calls failed: $errorMessages"
    }

    # Build results hashtable
    $counts = @{}
    $results | ForEach-Object { $counts[$_.Key] = $_.Count }

    # Build response
    $responseBody = @{
        totalUsers                 = $counts.totalUsers
        migrated_user_count        = $counts.migratedUsers
        not_migrated_user_count    = $counts.totalUsers - $counts.migratedUsers
        totalnonhcpusersinus       = $counts.totalnonhcpusersinus
        migratednonhcpusersinus    = $counts.migratednonhcpusersinus
        notmigratednonhcpusersinus = $counts.notmigratednonhcpusersinus
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $responseBody
        })
}
catch {
    Write-Error "Function execution failed: $($_.Exception.Message)"
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
                error   = "Internal server error"
                message = $_.Exception.Message
            }
        })
}