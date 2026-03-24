function Remove-IntuneRoleDefinitionPermission {
<#
.SYNOPSIS
    Removes specific permissions from a custom Intune Role Definition via Microsoft Graph.

.DESCRIPTION
    Reads the current allowedResourceActions of a custom role definition, removes the specified permissions, and PATCHes the remainder back; built-in roles are skipped.

.PARAMETER RoleName
    The display name of the custom role definition to update.

.PARAMETER Permissions
    The Intune RBAC permission action strings to remove from the role (e.g., "microsoft.intune_managedApps_read").

.PARAMETER WhatIfMode
    When specified, shows what would be removed without making any changes.

.EXAMPLE
    # Remove a specific permission from a role definition.
    Remove-IntuneRoleDefinitionPermission -RoleName "HelpDesk Reader" -Permissions @("microsoft.intune_managedApps_read")

.EXAMPLE
    # Preview the removal without applying any changes.
    Remove-IntuneRoleDefinitionPermission -RoleName "HelpDesk Reader" -Permissions @("microsoft.intune_managedApps_read") -WhatIfMode
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
                RoleName      = $RoleName
                RoleId        = $roleId
                PreviousCount = ""
                NewCount      = ""
                Removed       = ""
                Action        = "SKIPPED (BUILT-IN)"
            }

            $result | Format-Table RoleName, RoleId, PreviousCount, NewCount, Removed, Action -AutoSize

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

        $notFound = @($Permissions | Where-Object { $currentPermissions -notcontains $_ })
        if ($notFound.Count -gt 0) {
            foreach ($perm in $notFound) {
                Write-Warning "Permission not present on role '$RoleName': $perm"
            }
        }

        $actuallyRemoved = @($Permissions | Where-Object { $currentPermissions -contains $_ })
        $remainingPermissions = @($currentPermissions | Where-Object { $Permissions -notcontains $_ })

        if ($actuallyRemoved.Count -eq 0) {
            $result = New-Object PSObject -Property @{
                RoleName      = $RoleName
                RoleId        = $roleId
                PreviousCount = $currentPermissions.Count
                NewCount      = $currentPermissions.Count
                Removed       = 0
                Action        = "NO CHANGE"
            }
        }
        elseif ($WhatIfMode) {
            Write-Information "WOULD REMOVE $($actuallyRemoved.Count) permission(s) from role definition '$RoleName' (ID: $roleId)" -InformationAction Continue
            $result = New-Object PSObject -Property @{
                RoleName      = $RoleName
                RoleId        = $roleId
                PreviousCount = $currentPermissions.Count
                NewCount      = $remainingPermissions.Count
                Removed       = $actuallyRemoved.Count
                Action        = "WOULD REMOVE"
            }
        }
        else {
            if (-not $PSCmdlet.ShouldProcess("role definition '$RoleName' (ID: $roleId)", "Remove $($actuallyRemoved.Count) permission(s)")) {
                return
            }
            try {
                Write-Information "Removing $($actuallyRemoved.Count) permission(s) from role definition '$RoleName' (ID: $roleId)..." -InformationAction Continue
                $body = @{
                    rolePermissions = @(
                        @{
                            resourceActions = @(
                                @{
                                    allowedResourceActions = $remainingPermissions
                                }
                            )
                        }
                    )
                } | ConvertTo-Json -Depth 10

                Invoke-MgGraphRequest -Method PATCH -Uri "$graphRoot/deviceManagement/roleDefinitions/$roleId" -Body $body -ContentType "application/json" | Out-Null

                $result = New-Object PSObject -Property @{
                    RoleName      = $RoleName
                    RoleId        = $roleId
                    PreviousCount = $currentPermissions.Count
                    NewCount      = $remainingPermissions.Count
                    Removed       = $actuallyRemoved.Count
                    Action        = "REMOVED"
                }
            }
            catch {
                Write-Error "Failed to update role definition '$RoleName': $_"
                return
            }
        }

        $result | Format-Table RoleName, RoleId, PreviousCount, NewCount, Removed, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Role definition permissions operation complete." -InformationAction Continue
    }

    end {
    }
}
