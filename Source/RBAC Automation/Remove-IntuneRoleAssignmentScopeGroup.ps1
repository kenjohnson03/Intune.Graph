function Remove-IntuneRoleAssignmentScopeGroup {
<#
.SYNOPSIS
    Removes one or more Azure AD scope groups from an Intune RBAC role assignment via Microsoft Graph.

.DESCRIPTION
    Reads the current resourceScopes array of a role assignment, filters out the specified groups, and PATCHes the remaining resourceScopes back.

.PARAMETER RoleName
    The display name of the role definition.

.PARAMETER AssignmentName
    The display name of the existing role assignment to modify.

.PARAMETER ScopeGroupNames
    The display names of the Azure AD groups to remove from the assignment's resourceScopes array.

.PARAMETER WhatIfMode
    When specified, shows what would be removed without making any changes.

.EXAMPLE
    # Remove a single scope group from a role assignment.
    Remove-IntuneRoleAssignmentScopeGroup -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -ScopeGroupNames @("SG-OldDevices")

.EXAMPLE
    # Preview removal of multiple scope groups without making changes.
    Remove-IntuneRoleAssignmentScopeGroup -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -ScopeGroupNames @("SG-OldDevices","SG-OldUsers") -WhatIfMode
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RoleName,

        [Parameter(Mandatory = $true)]
        [string] $AssignmentName,

        [Parameter(Mandatory = $true)]
        [string[]] $ScopeGroupNames,

        [switch] $WhatIfMode
    )

    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementRBAC.ReadWrite.All","Group.Read.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementRBAC.ReadWrite.All","Group.Read.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementRBAC.ReadWrite.All","Group.Read.All"'
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

        # --- Resolve role definition name to ID ---
        Write-Information "Resolving role definition '$RoleName'..." -InformationAction Continue
        $rolesUri = "$graphRoot/deviceManagement/roleDefinitions"
        $allRoles = @()
        $requestUri = $rolesUri

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

        $role = $allRoles | Where-Object displayName -eq $RoleName | Select-Object -First 1
        if (-not $role) {
            Write-Error "Role definition '$RoleName' not found."
            return
        }

        $roleId = $role.id
        Write-Information "  Resolved '$RoleName' -> ID $roleId" -InformationAction Continue

        # --- Get assignments for this role and find matching assignment ---
        Write-Information "Retrieving assignments for role '$RoleName'..." -InformationAction Continue
        $assignmentsUri = "$graphRoot/deviceManagement/roleDefinitions/$roleId/roleAssignments"
        $allAssignments = @()
        $requestUri = $assignmentsUri

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $allAssignments += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)
        }
        catch {
            Write-Error "Failed to retrieve role assignments for '$RoleName': $_"
            return
        }

        $assignment = $allAssignments | Where-Object displayName -eq $AssignmentName | Select-Object -First 1
        if (-not $assignment) {
            Write-Error "Assignment '$AssignmentName' not found for role '$RoleName'."
            return
        }

        $assignmentId = $assignment.id
        Write-Information "  Found assignment '$AssignmentName' -> ID $assignmentId" -InformationAction Continue

        # --- Get full assignment details ---
        Write-Information "Retrieving full assignment details..." -InformationAction Continue
        $fullAssignmentUri = "$graphRoot/deviceManagement/roleAssignments/$assignmentId"

        try {
            $fullAssignment = Invoke-MgGraphRequest -Method GET -Uri $fullAssignmentUri
        }
        catch {
            Write-Error "Failed to retrieve assignment details for '$AssignmentName': $_"
            return
        }

        $currentScopes = @()
        if ($fullAssignment.resourceScopes) {
            $currentScopes += $fullAssignment.resourceScopes
        }

        Write-Information "  Found $($currentScopes.Count) existing resourceScope(s)." -InformationAction Continue

        # --- Resolve group names to IDs ---
        Write-Information "Resolving group names to IDs..." -InformationAction Continue
        $groupIdMap = @{}
        $notFoundGroups = @()

        foreach ($groupName in $ScopeGroupNames) {
            $filterUri = "$graphRoot/groups?`$filter=displayName eq '$groupName'&`$select=id,displayName"
            try {
                $groupResponse = Invoke-MgGraphRequest -Method GET -Uri $filterUri
            }
            catch {
                Write-Error "Failed to query group '$groupName': $_"
                return
            }

            if (-not $groupResponse.value -or $groupResponse.value.Count -eq 0) {
                Write-Warning "Group '$groupName' not found in Azure AD."
                $notFoundGroups += $groupName
                continue
            }

            $groupIdMap[$groupName] = $groupResponse.value[0].id
            Write-Information "  Resolved '$groupName' -> $($groupResponse.value[0].id)" -InformationAction Continue
        }

        # --- Build removal set and filtered resourceScopes ---
        $removeGroupIds = @()
        foreach ($gName in $ScopeGroupNames) {
            if ($groupIdMap.Keys -contains $gName) {
                $removeGroupIds += $groupIdMap[$gName]
            }
        }

        $filteredScopes = @()
        $removedGroupIds = @()

        foreach ($scopeId in $currentScopes) {
            if ($removeGroupIds -contains $scopeId) {
                $removedGroupIds += $scopeId
            }
            else {
                $filteredScopes += $scopeId
            }
        }

        # --- Build results ---
        $results = @()

        foreach ($groupName in $ScopeGroupNames) {
            if ($notFoundGroups -contains $groupName) {
                $results += New-Object PSObject -Property @{
                    RoleName       = $RoleName
                    AssignmentName = $AssignmentName
                    ScopeGroupName = $groupName
                    Action         = "NOT FOUND"
                }
                continue
            }

            if (-not ($groupIdMap.Keys -contains $groupName)) {
                $results += New-Object PSObject -Property @{
                    RoleName       = $RoleName
                    AssignmentName = $AssignmentName
                    ScopeGroupName = $groupName
                    Action         = "NOT FOUND"
                }
                continue
            }

            $gId = $groupIdMap[$groupName]

            if ($removedGroupIds -contains $gId) {
                if ($WhatIfMode) {
                    $results += New-Object PSObject -Property @{
                        RoleName       = $RoleName
                        AssignmentName = $AssignmentName
                        ScopeGroupName = $groupName
                        Action         = "WOULD REMOVE"
                    }
                }
                else {
                    $results += New-Object PSObject -Property @{
                        RoleName       = $RoleName
                        AssignmentName = $AssignmentName
                        ScopeGroupName = $groupName
                        Action         = "REMOVED"
                    }
                }
            }
            else {
                $results += New-Object PSObject -Property @{
                    RoleName       = $RoleName
                    AssignmentName = $AssignmentName
                    ScopeGroupName = $groupName
                    Action         = "NOT ASSIGNED"
                }
            }
        }

        # --- Apply changes ---
        if (-not $WhatIfMode) {
            $hasRemovals = $false
            foreach ($r in $results) {
                if ($r.Action -eq "REMOVED") {
                    $hasRemovals = $true
                    break
                }
            }

            if ($hasRemovals) {
                if (-not $PSCmdlet.ShouldProcess("role assignment '$AssignmentName'", "Remove $($removedGroupIds.Count) scope group(s)")) {
                    return
                }
                Write-Information "Patching updated resourceScopes ($($filteredScopes.Count) remaining scope(s))..." -InformationAction Continue
                $patchBody = @{
                    resourceScopes = $filteredScopes
                } | ConvertTo-Json -Depth 10

                try {
                    Invoke-MgGraphRequest -Method PATCH -Uri $fullAssignmentUri -Body $patchBody -ContentType "application/json" | Out-Null
                    Write-Information "  resourceScopes updated successfully." -InformationAction Continue
                }
                catch {
                    Write-Error "Failed to update resourceScopes for assignment '$AssignmentName': $_"
                    return
                }
            }
            else {
                Write-Information "No matching scope groups to remove." -InformationAction Continue
            }
        }
        else {
            Write-Information "WhatIfMode: No changes were made." -InformationAction Continue
        }

        # --- Output ---
        $results | Sort-Object Action, ScopeGroupName | Format-Table RoleName, AssignmentName, ScopeGroupName, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Role assignment scope group removal complete." -InformationAction Continue
    }

    end {
    }
}
