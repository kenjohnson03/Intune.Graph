function Add-IntuneRoleAssignmentMember {
<#
.SYNOPSIS
    Adds one or more member groups to an existing Intune RBAC role assignment.

.DESCRIPTION
    Appends Azure AD groups to the members array of an Intune role assignment via Microsoft Graph PATCH, skipping groups that are already present.

.PARAMETER RoleName
    The display name of the role definition.

.PARAMETER AssignmentName
    The display name of the existing role assignment.

.PARAMETER MemberGroupNames
    One or more Azure AD group display names to add as members, resolved to object IDs via Microsoft Graph.

.PARAMETER WhatIfMode
    Preview-only mode that shows what would be added without making changes.

.EXAMPLE
    # Add a single group as a member to a role assignment.
    Add-IntuneRoleAssignmentMember -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -MemberGroupNames @("SG-HelpDeskTeam")

.EXAMPLE
    # Preview adding multiple member groups without making changes.
    Add-IntuneRoleAssignmentMember -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -MemberGroupNames @("SG-HelpDeskTeam","SG-Tier2Support") -WhatIfMode
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
        $allRoles = @()
        $requestUri = "$graphRoot/deviceManagement/roleDefinitions"

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

        $roleMatch = $allRoles | Where-Object displayName -eq $RoleName | Select-Object -First 1
        if (-not $roleMatch) {
            throw "Role definition '$RoleName' not found. Available roles: $(($allRoles | ForEach-Object { $_.displayName }) -join ', ')"
        }

        $roleDefId = $roleMatch.id
        Write-Information "  Resolved '$RoleName' -> $roleDefId" -InformationAction Continue

        # --- Get assignments for this role ---
        Write-Information "Retrieving assignments for role '$RoleName'..." -InformationAction Continue
        $allAssignments = @()
        $requestUri = "$graphRoot/deviceManagement/roleDefinitions/$roleDefId/roleAssignments"

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
            Write-Error "Failed to retrieve role assignments: $_"
            return
        }

        $assignmentMatch = $allAssignments | Where-Object displayName -eq $AssignmentName | Select-Object -First 1
        if (-not $assignmentMatch) {
            throw "Assignment '$AssignmentName' not found for role '$RoleName'. Available assignments: $(($allAssignments | ForEach-Object { $_.displayName }) -join ', ')"
        }

        $assignmentId = $assignmentMatch.id
        Write-Information "  Resolved '$AssignmentName' -> $assignmentId" -InformationAction Continue

        # --- Get full assignment details ---
        Write-Information "Retrieving full assignment details..." -InformationAction Continue
        try {
            $assignmentDetails = Invoke-MgGraphRequest -Method GET -Uri "$graphRoot/deviceManagement/roleAssignments/$assignmentId"
        }
        catch {
            Write-Error "Failed to retrieve assignment details: $_"
            return
        }

        # --- Read current members ---
        $currentMemberIds = @()
        if ($assignmentDetails.members) {
            $currentMemberIds = @($assignmentDetails.members)
        }

        Write-Information "  Found $($currentMemberIds.Count) existing member group(s)." -InformationAction Continue

        # --- Resolve member group names to IDs ---
        Write-Information "Resolving member group names to IDs..." -InformationAction Continue
        $groupIdMap = @{}

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
                throw "Could not find Azure AD group with display name '$groupName'."
            }

            $groupIdMap[$groupName] = $groupResponse.value[0].id
            Write-Information "  Resolved '$groupName' -> $($groupIdMap[$groupName])" -InformationAction Continue
        }

        # --- Check for duplicates and build updated list ---
        $updatedMemberIds = @() + $currentMemberIds
        $results = @()

        foreach ($groupName in $MemberGroupNames) {
            $gId = $groupIdMap[$groupName]

            if ($currentMemberIds -contains $gId) {
                Write-Information "  Member group '$groupName' ($gId) is already assigned." -InformationAction Continue
                $results += New-Object PSObject -Property @{
                    RoleName        = $RoleName
                    AssignmentName  = $AssignmentName
                    MemberGroupName = $groupName
                    MemberGroupId   = $gId
                    Action          = "ALREADY ASSIGNED"
                }
            }
            else {
                if ($WhatIfMode) {
                    Write-Information "WOULD ADD member group '$groupName' ($gId) to assignment '$AssignmentName'." -InformationAction Continue
                    $results += New-Object PSObject -Property @{
                        RoleName        = $RoleName
                        AssignmentName  = $AssignmentName
                        MemberGroupName = $groupName
                        MemberGroupId   = $gId
                        Action          = "WOULD ADD"
                    }
                }
                else {
                    $updatedMemberIds += $gId
                    $results += New-Object PSObject -Property @{
                        RoleName        = $RoleName
                        AssignmentName  = $AssignmentName
                        MemberGroupName = $groupName
                        MemberGroupId   = $gId
                        Action          = "ADDED"
                    }
                }
            }
        }

        # --- PATCH the assignment ---
        if (-not $WhatIfMode) {
            $hasAdditions = $false
            foreach ($r in $results) {
                if ($r.Action -eq "ADDED") {
                    $hasAdditions = $true
                    break
                }
            }

            if ($hasAdditions) {
                if (-not $PSCmdlet.ShouldProcess("role assignment '$AssignmentName'", "Add $($updatedMemberIds.Count - $currentMemberIds.Count) member group(s)")) {
                    return
                }
                Write-Information "Patching assignment with $($updatedMemberIds.Count) member group(s)..." -InformationAction Continue
                $patchBody = @{
                    members = @($updatedMemberIds)
                } | ConvertTo-Json

                try {
                    Invoke-MgGraphRequest -Method PATCH -Uri "$graphRoot/deviceManagement/roleAssignments/$assignmentId" -Body $patchBody -ContentType "application/json" | Out-Null
                    Write-Information "  Assignment updated successfully." -InformationAction Continue
                }
                catch {
                    Write-Error "Failed to update assignment '$AssignmentName': $_"
                    foreach ($r in $results) {
                        if ($r.Action -eq "ADDED") {
                            $r.Action = "FAILED"
                        }
                    }
                }
            }
            else {
                Write-Information "No new member groups to add." -InformationAction Continue
            }
        }
        else {
            Write-Information "WhatIfMode: No changes were made." -InformationAction Continue
        }

        # --- Output ---
        $results | Sort-Object Action, MemberGroupName | Format-Table RoleName, AssignmentName, MemberGroupName, MemberGroupId, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Member group assignment operation complete." -InformationAction Continue
    }

    end {
    }
}
