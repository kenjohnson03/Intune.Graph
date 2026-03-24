function Get-IntuneRoleDefinition {
<#
.SYNOPSIS
    Lists or searches Intune RBAC role definitions.

.DESCRIPTION
    Retrieves Intune RBAC role definitions from Microsoft Graph, with optional filtering by name or ID.

.PARAMETER RoleName
    The display name of the role definition to filter by.

.PARAMETER RoleId
    The ID of the role definition to retrieve.

.EXAMPLE
    # List all role definitions.
    Get-IntuneRoleDefinition

.EXAMPLE
    # Find a specific role definition by name.
    Get-IntuneRoleDefinition -RoleName "Help Desk Operator"
#>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string] $RoleName,
        [string] $RoleId
    )

    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementRBAC.ReadWrite.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementRBAC.ReadWrite.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementRBAC.ReadWrite.All"'
            $script:__SkipProcessBlock = $true
            return
        }
        $script:__SkipProcessBlock = $false

        switch ($context.Environment) {
            "USGov"    { $uri = "https://graph.microsoft.us" }
            "USGovDoD" { $uri = "https://dod-graph.microsoft.us" }
            Default    { $uri = "https://graph.microsoft.com" }
        }

        $graphRoot = "$uri/beta"

        Write-Information "Connected to: $($context.Environment) ($uri)" -InformationAction Continue
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        if ($RoleId) {
            Write-Information "Getting role definition ID: $RoleId" -InformationAction Continue
            try {
                $role = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + "/deviceManagement/roleDefinitions/$RoleId")
                $results = @(
                    New-Object PSObject -Property @{
                        Id                      = $role.id
                        DisplayName             = $role.displayName
                        Description             = $role.description
                        IsBuiltIn               = $role.isBuiltIn
                        IsBuiltInRoleDefinition = $role.isBuiltInRoleDefinition
                    }
                )
            }
            catch {
                Write-Error "Failed to get role definition ID '$RoleId': $_"
                return
            }
        }
        else {
            Write-Information "Loading role definitions..." -InformationAction Continue
            $allRoles = @()
            $requestUri = ($graphRoot + '/deviceManagement/roleDefinitions')

            try {
                do {
                    $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                    $allRoles += $response.value
                    $nextLink = $null
                    if ($response.Keys -contains '@odata.nextLink') {
                        $nextLink = $response.'@odata.nextLink'
                    }
                    $requestUri = $nextLink
                } while ($null -ne $requestUri)
            }
            catch {
                Write-Error "Failed to retrieve role definitions: $_"
                return
            }

            if ($RoleName) {
                $allRoles = $allRoles | Where-Object displayName -eq $RoleName
            }

            $results = foreach ($role in $allRoles) {
                New-Object PSObject -Property @{
                    Id                      = $role.id
                    DisplayName             = $role.displayName
                    Description             = $role.description
                    IsBuiltIn               = $role.isBuiltIn
                    IsBuiltInRoleDefinition = $role.isBuiltInRoleDefinition
                }
            }
        }

        if (-not $results -or $results.Count -eq 0) {
            Write-Information "No role definitions found." -InformationAction Continue
        }
        else {
            Write-Information "Found $($results.Count) role definition(s)." -InformationAction Continue
            $results | Sort-Object Id | Format-Table Id, DisplayName, Description, IsBuiltIn, IsBuiltInRoleDefinition -AutoSize
        }
    }

    end {
    }
}
