function Add-IntuneRoleDefinitionPermission {
<#
.SYNOPSIS
    Adds one or more permissions to a custom Intune role definition.

.DESCRIPTION
    Appends allowedResourceActions to an existing custom Intune role definition via Microsoft Graph PATCH, skipping duplicates and ignoring built-in roles.

.PARAMETER RoleName
    The display name of the custom role definition to update.

.PARAMETER Permissions
    One or more Intune RBAC permission action strings to add (e.g., "microsoft.intune_managedApps_read"); permissions already present are skipped.

.PARAMETER WhatIfMode
    Preview-only mode that shows what would be added without making changes.

.EXAMPLE
    # Add a permission to a custom role.
    Add-IntuneRoleDefinitionPermission -RoleName "HelpDesk Reader" -Permissions @("microsoft.intune_managedApps_read")

.EXAMPLE
    # Preview the permission addition without applying it.
    Add-IntuneRoleDefinitionPermission -RoleName "HelpDesk Reader" -Permissions @("microsoft.intune_managedApps_read") -WhatIfMode
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
                Added         = ""
                Action        = "SKIPPED (BUILT-IN)"
            }

            $result | Format-Table RoleName, RoleId, PreviousCount, NewCount, Added, Action -AutoSize

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

        $newPermissions = @()
        foreach ($perm in $Permissions) {
            if ($currentPermissions -contains $perm) {
                Write-Warning "Permission already present, skipping: $perm"
            }
            else {
                $newPermissions += $perm
            }
        }

        if ($newPermissions.Count -eq 0) {
            $result = New-Object PSObject -Property @{
                RoleName      = $RoleName
                RoleId        = $roleId
                PreviousCount = $currentPermissions.Count
                NewCount      = $currentPermissions.Count
                Added         = 0
                Action        = "NO CHANGE"
            }
        }
        elseif ($WhatIfMode) {
            $mergedPermissions = @($currentPermissions) + @($newPermissions)
            Write-Information "WOULD ADD $($newPermissions.Count) permission(s) to role definition '$RoleName' (ID: $roleId)" -InformationAction Continue
            $result = New-Object PSObject -Property @{
                RoleName      = $RoleName
                RoleId        = $roleId
                PreviousCount = $currentPermissions.Count
                NewCount      = $mergedPermissions.Count
                Added         = $newPermissions.Count
                Action        = "WOULD ADD"
            }
        }
        else {
            if (-not $PSCmdlet.ShouldProcess("role definition '$RoleName' (ID: $roleId)", "Add $($newPermissions.Count) permission(s)")) {
                return
            }
            try {
                $mergedPermissions = @($currentPermissions) + @($newPermissions)
                Write-Information "Adding $($newPermissions.Count) permission(s) to role definition '$RoleName' (ID: $roleId)..." -InformationAction Continue
                $body = @{
                    rolePermissions = @(
                        @{
                            resourceActions = @(
                                @{
                                    allowedResourceActions = $mergedPermissions
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
                    NewCount      = $mergedPermissions.Count
                    Added         = $newPermissions.Count
                    Action        = "ADDED"
                }
            }
            catch {
                Write-Error "Failed to update role definition '$RoleName': $_"
                return
            }
        }

        $result | Format-Table RoleName, RoleId, PreviousCount, NewCount, Added, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Role definition permissions operation complete." -InformationAction Continue
    }

    end {
    }
}
