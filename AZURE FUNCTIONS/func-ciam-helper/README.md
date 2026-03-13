# func-ciam-helper (getuserCount)

## Overview

`func-ciam-helper/getuserCount` is an Azure Functions HTTP-triggered PowerShell function that queries Microsoft Graph to return user counts for CIAM migration tracking.

It retrieves counts for:
- Total users
- Migrated users
- Not migrated users (computed)
- Total non-HCP (non-healthcare provider) users in the US
- Migrated non-HCP users in the US
- Not migrated non-HCP users in the US (computed)

## Purpose

This function is designed to provide quick telemetry for CIAM migration state across a tenant by leveraging Microsoft Graph's `$count` capability and filtering on custom extension attributes.

It is primarily useful for dashboards, monitoring, or automated reports where you need a fast snapshot of migration progress.

## Queries used in the function and their description

The function performs multiple parallel Graph API requests (`/beta/users/$count`) with optional `$filter` clauses.

| Key | Filter (OData) | Description |
|------|---------------|-------------|
| `totalUsers` | _none_ | Total number of users in the tenant.
| `migratedUsers` | `extension_requiresMigration eq false` | Users marked as migrated (migration flag is `false`).
| `totalnonhcpusersinus` | `extension_customer_id eq null and country eq 'US'` | Users in the US without a customer_id (non-HCP users).
| `migratednonhcpusersinus` | `extension_requiresMigration eq false and extension_customer_id eq null and country eq 'US'` | US non-HCP users who are migrated.
| `notmigratednonhcpusersinus` | `extension_requiresMigration eq true and extension_customer_id eq null and country eq 'US'` | US non-HCP users who are not migrated.

> Note: The migration state is determined by the custom extension attribute `extension_requiresMigration`.

## How to trigger this

This function is triggered via an HTTP GET request.

### Azure Function endpoint pattern

```
GET https://<your-function-app>.azurewebsites.net/api/getuserCount?code=<function_key>
```

- `function_key` is the function-level key from your Azure Function App (unless you set `authLevel` to `anonymous`).
- No request body or query parameters are required; it reads everything from environment configuration.

## Sample response

```json
{
  "totalUsers": 12345,
  "migrated_user_count": 6789,
  "not_migrated_user_count": 4556,
  "totalnonhcpusersinus": 3210,
  "migratednonhcpusersinus": 2100,
  "notmigratednonhcpusersinus": 1110
}
```

If there is an internal error (e.g., token acquisition failure or Graph API failure), the function returns HTTP 500 with a JSON payload like:

```json
{
  "error": "Internal server error",
  "message": "<detailed error message>"
}
```

## How to run locally

### Prerequisites

- [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local)
- PowerShell 7.x (the function uses PowerShell 7+ for `ForEach-Object -Parallel`)
- A service principal with permissions to read users from Microsoft Graph (e.g., `User.Read.All` or `Directory.Read.All`).

### Steps

1. Clone this repo and `cd` into the function folder:

```powershell
cd "<repo-root>/AZURE FUNCTIONS/func-ciam-helper"
```

2. Set the required environment variables in `local.settings.json` (or via the environment):

- `GRAPH_TENANT_ID` - your Azure AD tenant ID
- `GRAPH_CLIENT_ID` - service principal (app) client ID
- `GRAPH_CLIENT_SECRET` - service principal secret

3. Run the function locally:

```powershell
func start
```

4. Invoke the function (example):

```powershell
Invoke-RestMethod -Uri "http://localhost:7071/api/getuserCount" -Method Get
```

## Summary

`func-ciam-helper/getuserCount` is a lightweight Azure Functions endpoint for retrieving user migration metrics from Microsoft Graph. It uses `$count` queries with OData filters to efficiently compute totals and provides a simple JSON response for consumption by dashboards or automation.
