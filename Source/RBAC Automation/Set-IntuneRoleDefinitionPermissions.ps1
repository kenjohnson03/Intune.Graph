function Set-IntuneRoleDefinitionPermissions {
<#
.SYNOPSIS
    Replaces the full permission set on a custom Intune Role Definition via Microsoft Graph.

.DESCRIPTION
    Updates the allowedResourceActions on a custom Intune Role Definition by replacing the existing permissions entirely; built-in roles are skipped.

.PARAMETER RoleName
    The display name of the custom role definition to update.

.PARAMETER Permissions
    The new full set of Intune RBAC permission action strings to apply, replacing all existing permissions (e.g., "microsoft.intune_deviceConfigurations_read").

.PARAMETER WhatIfMode
    When specified, shows what would change without applying the update.

.EXAMPLE
    # Replace permissions on a role definition.
    Set-IntuneRoleDefinitionPermissions -RoleName "HelpDesk Reader" -Permissions @("microsoft.intune_deviceConfigurations_read","microsoft.intune_managedDevices_read")

.EXAMPLE
    # Preview what would change without applying the update.
    Set-IntuneRoleDefinitionPermissions -RoleName "HelpDesk Reader" -Permissions @("microsoft.intune_deviceConfigurations_read") -WhatIfMode
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RoleName,

        [Parameter(Mandatory = $true)]
        [string[]] $Permissions,

        [switch] $WhatIfMode
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

        Write-Information "Loading existing role definitions..." -InformationAction Continue
        $existingRoles = @()
        $requestUri = "$graphRoot/deviceManagement/roleDefinitions"

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $existingRoles += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)
        }
        catch {
            Write-Error "Failed to retrieve existing role definitions: $_"
            return
        }

        $match = $existingRoles | Where-Object displayName -eq $RoleName | Select-Object -First 1

        if (-not $match) {
            throw "Role definition '$RoleName' not found."
        }

        $roleId = $match.id

        if ($match.isBuiltIn -eq $true -or $match.isBuiltInRoleDefinition -eq $true) {
            Write-Warning "Skipping built-in role definition: $RoleName (ID: $roleId)"
            $result = New-Object PSObject -Property @{
                RoleName           = $RoleName
                RoleId             = $roleId
                OldPermissionCount = ""
                NewPermissionCount = ""
                Action             = "SKIPPED (BUILT-IN)"
            }

            $result | Format-Table RoleName, RoleId, OldPermissionCount, NewPermissionCount, Action -AutoSize

            Write-Information "" -InformationAction Continue
            Write-Information "Role definition permissions operation complete." -InformationAction Continue
            return
        }

        $currentPermissions = @()
        if ($match.rolePermissions -and $match.rolePermissions.Count -gt 0) {
            $firstRolePerm = $match.rolePermissions[0]
            if ($firstRolePerm.resourceActions -and $firstRolePerm.resourceActions.Count -gt 0) {
                $currentPermissions = @($firstRolePerm.resourceActions[0].allowedResourceActions)
            }
        }

        $oldSorted = $currentPermissions | Sort-Object
        $newSorted = $Permissions | Sort-Object
        $oldJoined = ($oldSorted -join ",")
        $newJoined = ($newSorted -join ",")

        if ($oldJoined -eq $newJoined) {
            $result = New-Object PSObject -Property @{
                RoleName           = $RoleName
                RoleId             = $roleId
                OldPermissionCount = $currentPermissions.Count
                NewPermissionCount = $Permissions.Count
                Action             = "NO CHANGE"
            }
        }
        elseif ($WhatIfMode) {
            Write-Information "WOULD UPDATE permissions for role definition '$RoleName' (ID: $roleId)" -InformationAction Continue
            $result = New-Object PSObject -Property @{
                RoleName           = $RoleName
                RoleId             = $roleId
                OldPermissionCount = $currentPermissions.Count
                NewPermissionCount = $Permissions.Count
                Action             = "WOULD UPDATE"
            }
        }
        else {
            if (-not $PSCmdlet.ShouldProcess("role definition '$RoleName' (ID: $roleId)", "Update permissions ($($currentPermissions.Count) -> $($Permissions.Count))")) {
                return
            }
            try {
                Write-Information "Updating permissions for role definition '$RoleName' (ID: $roleId)..." -InformationAction Continue
                $body = @{
                    rolePermissions = @(
                        @{
                            resourceActions = @(
                                @{
                                    allowedResourceActions = $Permissions
                                }
                            )
                        }
                    )
                } | ConvertTo-Json -Depth 10

                Invoke-MgGraphRequest -Method PATCH -Uri "$graphRoot/deviceManagement/roleDefinitions/$roleId" -Body $body -ContentType "application/json" | Out-Null

                $result = New-Object PSObject -Property @{
                    RoleName           = $RoleName
                    RoleId             = $roleId
                    OldPermissionCount = $currentPermissions.Count
                    NewPermissionCount = $Permissions.Count
                    Action             = "UPDATED"
                }
            }
            catch {
                Write-Error "Failed to update role definition '$RoleName': $_"
                return
            }
        }

        $result | Format-Table RoleName, RoleId, OldPermissionCount, NewPermissionCount, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Role definition permissions operation complete." -InformationAction Continue
    }

    end {
    }
}
