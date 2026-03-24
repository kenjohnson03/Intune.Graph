function Remove-IntuneRoleAssignmentScopeTag {
<#
.SYNOPSIS
    Removes one or more scope tags from an Intune RBAC role assignment via Microsoft Graph.

.DESCRIPTION
    Reads the current roleScopeTagIds of a role assignment, filters out the specified tags, and PATCHes the remaining roleScopeTagIds back.

.PARAMETER RoleName
    The display name of the role definition.

.PARAMETER AssignmentName
    The display name of the existing role assignment to modify.

.PARAMETER ScopeTagNames
    The display names of the scope tags to remove from the assignment's roleScopeTagIds array.

.PARAMETER WhatIfMode
    When specified, shows what would be removed without making any changes.

.EXAMPLE
    # Remove a single scope tag from a role assignment.
    Remove-IntuneRoleAssignmentScopeTag -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -ScopeTagNames @("US-East")

.EXAMPLE
    # Preview removal of multiple scope tags without making changes.
    Remove-IntuneRoleAssignmentScopeTag -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -ScopeTagNames @("US-East","US-West") -WhatIfMode
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RoleName,

        [Parameter(Mandatory = $true)]
        [string] $AssignmentName,

        [Parameter(Mandatory = $true)]
        [string[]] $ScopeTagNames,

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

        $currentTagIds = @()
        if ($fullAssignment.roleScopeTagIds) {
            $currentTagIds += $fullAssignment.roleScopeTagIds
        }

        Write-Information "  Found $($currentTagIds.Count) existing roleScopeTagId(s)." -InformationAction Continue

        # --- Resolve scope tag names to IDs ---
        Write-Information "Resolving scope tag names to IDs..." -InformationAction Continue
        $allScopeTags = @()
        $requestUri = "$graphRoot/deviceManagement/roleScopeTags"

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $allScopeTags += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)
        }
        catch {
            Write-Error "Failed to retrieve scope tags: $_"
            return
        }

        $tagIdMap = @{}
        $notFoundTags = @()

        foreach ($tagName in $ScopeTagNames) {
            $tagMatch = $allScopeTags | Where-Object displayName -eq $tagName | Select-Object -First 1

            if (-not $tagMatch) {
                Write-Warning "Scope tag '$tagName' not found."
                $notFoundTags += $tagName
                continue
            }

            $tagIdMap[$tagName] = $tagMatch.id
            Write-Information "  Resolved '$tagName' -> $($tagMatch.id)" -InformationAction Continue
        }

        # --- Build removal set and filtered roleScopeTagIds ---
        $removeTagIds = @()
        foreach ($tName in $ScopeTagNames) {
            if ($tagIdMap.Keys -contains $tName) {
                $removeTagIds += $tagIdMap[$tName]
            }
        }

        $filteredTagIds = @()
        $removedTagIds = @()

        foreach ($tagId in $currentTagIds) {
            if ($removeTagIds -contains $tagId) {
                $removedTagIds += $tagId
            }
            else {
                $filteredTagIds += $tagId
            }
        }

        # --- Build results ---
        $results = @()

        foreach ($tagName in $ScopeTagNames) {
            if ($notFoundTags -contains $tagName) {
                $results += New-Object PSObject -Property @{
                    RoleName       = $RoleName
                    AssignmentName = $AssignmentName
                    ScopeTagName   = $tagName
                    Action         = "NOT FOUND"
                }
                continue
            }

            if (-not ($tagIdMap.Keys -contains $tagName)) {
                $results += New-Object PSObject -Property @{
                    RoleName       = $RoleName
                    AssignmentName = $AssignmentName
                    ScopeTagName   = $tagName
                    Action         = "NOT FOUND"
                }
                continue
            }

            $tId = $tagIdMap[$tagName]

            if ($removedTagIds -contains $tId) {
                if ($WhatIfMode) {
                    $results += New-Object PSObject -Property @{
                        RoleName       = $RoleName
                        AssignmentName = $AssignmentName
                        ScopeTagName   = $tagName
                        Action         = "WOULD REMOVE"
                    }
                }
                else {
                    $results += New-Object PSObject -Property @{
                        RoleName       = $RoleName
                        AssignmentName = $AssignmentName
                        ScopeTagName   = $tagName
                        Action         = "REMOVED"
                    }
                }
            }
            else {
                $results += New-Object PSObject -Property @{
                    RoleName       = $RoleName
                    AssignmentName = $AssignmentName
                    ScopeTagName   = $tagName
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
                if (-not $PSCmdlet.ShouldProcess("role assignment '$AssignmentName'", "Remove $($removedTagIds.Count) scope tag(s)")) {
                    return
                }
                Write-Information "Patching updated roleScopeTagIds ($($filteredTagIds.Count) remaining tag(s))..." -InformationAction Continue
                $patchBody = @{
                    roleScopeTagIds = $filteredTagIds
                } | ConvertTo-Json -Depth 10

                try {
                    Invoke-MgGraphRequest -Method PATCH -Uri $fullAssignmentUri -Body $patchBody -ContentType "application/json" | Out-Null
                    Write-Information "  roleScopeTagIds updated successfully." -InformationAction Continue
                }
                catch {
                    Write-Error "Failed to update roleScopeTagIds for assignment '$AssignmentName': $_"
                    return
                }
            }
            else {
                Write-Information "No matching scope tags to remove." -InformationAction Continue
            }
        }
        else {
            Write-Information "WhatIfMode: No changes were made." -InformationAction Continue
        }

        # --- Output ---
        $results | Sort-Object Action, ScopeTagName | Format-Table RoleName, AssignmentName, ScopeTagName, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Role assignment scope tag removal complete." -InformationAction Continue
    }

    end {
    }
}
