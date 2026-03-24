function Remove-IntuneRoleAssignmentMember {
<#
.SYNOPSIS
    Removes one or more Azure AD member groups from an Intune RBAC role assignment via Microsoft Graph.

.DESCRIPTION
    Reads the current members array of a role assignment, filters out the specified groups, and PATCHes the remaining members back.

.PARAMETER RoleName
    The display name of the role definition.

.PARAMETER AssignmentName
    The display name of the existing role assignment to modify.

.PARAMETER MemberGroupNames
    The display names of the Azure AD groups to remove from the assignment's members array.

.PARAMETER WhatIfMode
    When specified, shows what would be removed without making any changes.

.EXAMPLE
    # Remove a single member group from a role assignment.
    Remove-IntuneRoleAssignmentMember -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -MemberGroupNames @("SG-OldTeam")

.EXAMPLE
    # Preview removal of multiple member groups without making changes.
    Remove-IntuneRoleAssignmentMember -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -MemberGroupNames @("SG-OldTeam","SG-ContractorsExpired") -WhatIfMode
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RoleName,

        [Parameter(Mandatory = $true)]
        [string] $AssignmentName,

        [Parameter(Mandatory = $true)]
        [string[]] $MemberGroupNames,

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

        $currentMembers = @()
        if ($fullAssignment.members) {
            $currentMembers += $fullAssignment.members
        }

        Write-Information "  Found $($currentMembers.Count) existing member(s)." -InformationAction Continue

        # --- Resolve group names to IDs ---
        Write-Information "Resolving group names to IDs..." -InformationAction Continue
        $groupIdMap = @{}
        $notFoundGroups = @()

        foreach ($groupName in $MemberGroupNames) {
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

        # --- Build removal set and filtered members ---
        $removeGroupIds = @()
        foreach ($gName in $MemberGroupNames) {
            if ($groupIdMap.Keys -contains $gName) {
                $removeGroupIds += $groupIdMap[$gName]
            }
        }

        $filteredMembers = @()
        $removedGroupIds = @()

        foreach ($memberId in $currentMembers) {
            if ($removeGroupIds -contains $memberId) {
                $removedGroupIds += $memberId
            }
            else {
                $filteredMembers += $memberId
            }
        }

        # --- Build results ---
        $results = @()

        foreach ($groupName in $MemberGroupNames) {
            if ($notFoundGroups -contains $groupName) {
                $results += New-Object PSObject -Property @{
                    RoleName        = $RoleName
                    AssignmentName  = $AssignmentName
                    MemberGroupName = $groupName
                    Action          = "NOT FOUND"
                }
                continue
            }

            if (-not ($groupIdMap.Keys -contains $groupName)) {
                $results += New-Object PSObject -Property @{
                    RoleName        = $RoleName
                    AssignmentName  = $AssignmentName
                    MemberGroupName = $groupName
                    Action          = "NOT FOUND"
                }
                continue
            }

            $gId = $groupIdMap[$groupName]

            if ($removedGroupIds -contains $gId) {
                if ($WhatIfMode) {
                    $results += New-Object PSObject -Property @{
                        RoleName        = $RoleName
                        AssignmentName  = $AssignmentName
                        MemberGroupName = $groupName
                        Action          = "WOULD REMOVE"
                    }
                }
                else {
                    $results += New-Object PSObject -Property @{
                        RoleName        = $RoleName
                        AssignmentName  = $AssignmentName
                        MemberGroupName = $groupName
                        Action          = "REMOVED"
                    }
                }
            }
            else {
                $results += New-Object PSObject -Property @{
                    RoleName        = $RoleName
                    AssignmentName  = $AssignmentName
                    MemberGroupName = $groupName
                    Action          = "NOT ASSIGNED"
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
                if (-not $PSCmdlet.ShouldProcess("role assignment '$AssignmentName'", "Remove $($removedGroupIds.Count) member group(s)")) {
                    return
                }
                Write-Information "Patching updated members ($($filteredMembers.Count) remaining member(s))..." -InformationAction Continue
                $patchBody = @{
                    members = $filteredMembers
                } | ConvertTo-Json -Depth 10

                try {
                    Invoke-MgGraphRequest -Method PATCH -Uri $fullAssignmentUri -Body $patchBody -ContentType "application/json" | Out-Null
                    Write-Information "  Members updated successfully." -InformationAction Continue
                }
                catch {
                    Write-Error "Failed to update members for assignment '$AssignmentName': $_"
                    return
                }
            }
            else {
                Write-Information "No matching member groups to remove." -InformationAction Continue
            }
        }
        else {
            Write-Information "WhatIfMode: No changes were made." -InformationAction Continue
        }

        # --- Output ---
        $results | Sort-Object Action, MemberGroupName | Format-Table RoleName, AssignmentName, MemberGroupName, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Role assignment member removal complete." -InformationAction Continue
    }

    end {
    }
}
