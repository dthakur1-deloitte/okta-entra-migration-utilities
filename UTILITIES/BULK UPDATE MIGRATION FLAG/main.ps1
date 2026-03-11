param(
    [ValidateSet("np", "prod")]
    [string]$Environment = "np"
)

# SCRIPT EXECUTION PATH
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# IMPORTING REQUIRED MODULES
Import-Module "$scriptRoot\helpers.psm1" -Force

$configFolder = Join-Path $scriptRoot "config"
$csvPath = Join-Path $scriptRoot "users.csv"

# Initialize counters
$successCount = 0
$failureCount = 0
$skippedCount = 0
$failedUsers = @()

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  User Migration Flag Update Script" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

# ENVIRONMENT-BASED CONFIG SELECTION
switch ($Environment) {
    "np" {
        $ConfigFilePath = Join-Path $configFolder "np-config.json"
        Write-Host "Environment: NON-PROD" -ForegroundColor Yellow
    }
    "prod" {
        $ConfigFilePath = Join-Path $configFolder "prod-config.json"
        Write-Host "Environment: PROD" -ForegroundColor Yellow
    }
}

# LOAD AND VALIDATE CONFIGURATION
$config = Get-ValidatedConfig -ConfigPath $ConfigFilePath

if ($null -eq $config) {
    Write-Host "`n✗ Script terminated due to configuration errors`n" -ForegroundColor Red
    exit 1
}

# AUTHENTICATE TO GRAPH API
try {
    $accessToken = Get-AccessTokenForGraphAPI -TenantId $config.ENTRA_TENANT_ID -ClientId $config.ENTRA_CLIENT_ID -ClientSecret $config.ENTRA_CLIENT_SECRET
}
catch {
    Write-Host "`n✗ Script terminated due to authentication failure`n" -ForegroundColor Red
    exit 1
}

# VALIDATE CSV FILE
if (-not (Test-Path $csvPath)) {
    Write-Error "CSV file not found: $csvPath"
    Write-Host "`n✗ Script terminated: CSV file missing`n" -ForegroundColor Red
    exit 1
}

# IMPORT USERS FROM CSV
try {
    $users = Import-Csv -Path $csvPath -ErrorAction Stop
}
catch {
    Write-Error "Failed to read CSV file: $($_.Exception.Message)"
    Write-Host "`n✗ Script terminated: Invalid CSV format`n" -ForegroundColor Red
    exit 1
}

$totalUsers = $users.Count
Write-Host "`nProcessing $totalUsers user(s)...`n" -ForegroundColor Cyan

# PROCESS EACH USER
foreach ($user in $users) {
    $emailAddress = $user.emailAddress
    $migrationFlag = $user.migrationFlag

    Write-Host "Processing: $emailAddress" -ForegroundColor White

    # Validate migration flag value
    $migrationFlagBoolean = switch ($migrationFlag.ToLower()) {
        "true" { $true }
        "false" { $false }
        default { 
            Write-Warning "  Invalid migration flag value: '$migrationFlag' (expected 'true' or 'false'). Skipping..."
            $skippedCount++
            $failedUsers += [PSCustomObject]@{
                Email  = $emailAddress
                Reason = "Invalid migration flag value: '$migrationFlag'"
            }
            continue
        }
    }

    # Get user object ID
    try {
        $objectId = Get-UserObjectId -EmailAddress $emailAddress -Issuer $config.ENTRA_ISSUER -AccessToken $accessToken
        
        if ($null -eq $objectId) {
            Write-Warning "  User not found in directory. Skipping..."
            $skippedCount++
            $failedUsers += [PSCustomObject]@{
                Email  = $emailAddress
                Reason = "User not found in directory"
            }
            continue
        }
    }
    catch {
        Write-Error "  Error retrieving user: $($_.Exception.Message)"
        $failureCount++
        $failedUsers += [PSCustomObject]@{
            Email  = $emailAddress
            Reason = "Error retrieving user: $($_.Exception.Message)"
        }
        continue
    }

    # Update migration flag
    try {
        $updateResult = Update-UserMigrationFlag -ObjectId $objectId -RequiresMigration $migrationFlagBoolean -AccessToken $accessToken -B2CApplicationId $config.B2C_APPLICATION_ID
        
        if ($updateResult) {
            Write-Host "  ✓ Successfully updated migration flag to: $migrationFlagBoolean" -ForegroundColor Green
            $successCount++
        }
        else {
            Write-Warning "  Update operation returned false"
            $failureCount++
            $failedUsers += [PSCustomObject]@{
                Email  = $emailAddress
                Reason = "Update operation failed"
            }
        }
    }
    catch {
        Write-Error "  Failed to update user: $($_.Exception.Message)"
        $failureCount++
        $failedUsers += [PSCustomObject]@{
            Email  = $emailAddress
            Reason = "Update failed: $($_.Exception.Message)"
        }
    }

    Write-Host ""
}

# PRINT SUMMARY
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  EXECUTION SUMMARY" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Total Users Processed: $totalUsers" -ForegroundColor White
Write-Host "Successful Updates:    $successCount" -ForegroundColor Green
Write-Host "Failed Updates:        $failureCount" -ForegroundColor Red
Write-Host "Skipped:               $skippedCount" -ForegroundColor Yellow
Write-Host "================================================`n" -ForegroundColor Cyan

# SHOW FAILED USERS DETAILS IF ANY
if ($failedUsers.Count -gt 0) {
    Write-Host "Failed/Skipped Users:" -ForegroundColor Yellow
    foreach ($failed in $failedUsers) {
        Write-Host "  • $($failed.Email)" -ForegroundColor Yellow
        Write-Host "    Reason: $($failed.Reason)" -ForegroundColor Gray
    }
    Write-Host ""
}

# EXIT WITH APPROPRIATE CODE
if ($failureCount -gt 0) {
    exit 1
}
else {
    exit 0
}
