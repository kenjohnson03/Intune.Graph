function Get-IntuneRoleDefinitionPermissions {
<#
.SYNOPSIS
    Gets the permissions of an Intune role definition.

.DESCRIPTION
    Retrieves the allowedResourceActions for an Intune role definition from Microsoft Graph, supporting both built-in and custom roles.

.PARAMETER RoleName
    The display name of the role definition to retrieve permissions for.

.PARAMETER RoleId
    The ID of the role definition to retrieve permissions for.

.EXAMPLE
    # List all permissions for a role by display name.
    Get-IntuneRoleDefinitionPermissions -RoleName "Help Desk Operator"

.EXAMPLE
    # List all permissions for a role by ID.
    Get-IntuneRoleDefinitionPermissions -RoleId "00000000-0000-0000-0000-000000000000"
#>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory, ParameterSetName = "ByName", Position = 0)]
        [string] $RoleName,

        [Parameter(Mandatory, ParameterSetName = "ById", Position = 0)]
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
                $match = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + "/deviceManagement/roleDefinitions/$RoleId")
            }
            catch {
                Write-Error "Failed to get role definition ID '$RoleId': $_"
                return
            }
        }
        else {
            Write-Information "Resolving role name '$RoleName'..." -InformationAction Continue
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

            $match = $allRoles | Where-Object displayName -eq $RoleName | Select-Object -First 1

            if (-not $match) {
                throw "Role definition '$RoleName' not found."
            }
        }

        Write-Information "  Role: $($match.displayName) (ID: $($match.id))" -InformationAction Continue

        $permissions = @()
        if ($match.rolePermissions -and $match.rolePermissions.Count -gt 0) {
            $firstRolePerm = $match.rolePermissions[0]
            if ($firstRolePerm.resourceActions -and $firstRolePerm.resourceActions.Count -gt 0) {
                $permissions = @($firstRolePerm.resourceActions[0].allowedResourceActions)
            }
        }

        if ($permissions.Count -eq 0) {
            Write-Information "No permissions found for role '$($match.displayName)'." -InformationAction Continue
            return
        }

        Write-Information "Found $($permissions.Count) permission(s) for role '$($match.displayName)'." -InformationAction Continue
        Write-Information "" -InformationAction Continue

        $results = foreach ($perm in ($permissions | Sort-Object)) {
            New-Object PSObject -Property @{
                Permission = $perm
            }
        }

        $results | Format-Table Permission -AutoSize
    }

    end {
    }
}
