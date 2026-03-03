# ====================================================================
# Configuration Variables - Update these before running!
# ====================================================================
$RoleName      = "Application Administrator" # The exact display name of the role
$Justification = "Performing daily maintenance tasks via PowerShell"
$DurationHours = 2 # How many hours you want the role active (Max depends on your org policies)
$UPN           = "your.name@yourcompany.com"

# ====================================================================
# 1. Connect to Microsoft Graph
# ====================================================================
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
# This will open a browser window to authenticate. 
# It requests the minimum permissions needed to read directory data and activate roles.
Connect-MgGraph -Scopes "RoleAssignmentSchedule.ReadWrite.Directory", "Directory.Read.All" -AccountId $UPN

# ====================================================================
# 2. Get Current User ID and Role Definition ID
# ====================================================================
# Get the currently signed-in user's Object ID
$Context = Get-MgContext
$UserId  = (Get-MgUser -UserId $Context.Account).Id

Write-Host "Looking up Role ID for: $RoleName" -ForegroundColor Cyan
# Retrieve the Role Definition ID based on the display name
$Role = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$RoleName'"

if (-not $Role) {
    Write-Warning "Could not find a role named '$RoleName'. Please check the spelling."
    Exit
}

$RoleDefinitionId = $Role.Id

# ====================================================================
# 3. Construct the PIM Activation Request
# ====================================================================
Write-Host "Constructing the activation request..." -ForegroundColor Cyan

# Format duration according to ISO 8601 standard (e.g., PT2H for 2 hours)
$DurationString = "PT$($DurationHours)H"

# Build the payload
$Params = @{
    Action           = "SelfActivate"
    PrincipalId      = $UserId
    RoleDefinitionId = $RoleDefinitionId
    DirectoryScopeId = "/" # "/" means tenant-wide scope
    Justification    = $Justification
    ScheduleInfo     = @{
        StartDateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        Expiration    = @{
            Type     = "AfterDuration"
            Duration = $DurationString
        }
    }
}

# ====================================================================
# 4. Submit the Request
# ====================================================================
Write-Host "Submitting PIM activation request for '$RoleName'..." -ForegroundColor Cyan

try {
    $Result = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $Params
    Write-Host "Success! Role activation request submitted." -ForegroundColor Green
    Write-Host "Request Status: $($Result.Status)" -ForegroundColor Yellow
    Write-Host "Note: It may take 1-5 minutes for the permissions to fully propagate across the tenant." -ForegroundColor Yellow
}
catch {
    Write-Error "Failed to activate role. Error details: $_"
}

# Optional: Disconnect when finished
# Disconnect-MgGraph