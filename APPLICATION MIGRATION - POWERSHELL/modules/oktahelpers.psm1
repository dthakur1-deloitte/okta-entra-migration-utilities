function Get-OktaApp {
    param(
        [string]$AppId,
        [string]$OktaDomain,
        [string]$ApiToken
    )

    $headers = @{
        Authorization = "SSWS $ApiToken"
        Accept        = "application/json"
    }

    $uri = "https://$OktaDomain/api/v1/apps/$AppId"

    try {
        Write-LogDebug "Calling Okta API for AppId: $AppId"
        return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    }
    catch {
        $status = $_.Exception.Response?.StatusCode.value__

        if ($status -eq 404) {
            Write-Host "Okta App not found: $AppId" -ForegroundColor Yellow
            Write-LogError "Okta App not found: $AppId"
        }
        else {
            Write-Host "Failed to fetch Okta App: $AppId" -ForegroundColor Red
            Write-LogError "Error fetching Okta App $AppId : $($_.Exception.Message)"
        }

        return $null
    }
}

Export-ModuleMember -Function Get-OktaApp