function Add-IntuneRoleAssignmentScopeTag {
<#
.SYNOPSIS
    Adds one or more scope tags to an existing Intune RBAC role assignment.

.DESCRIPTION
    Appends scope tags to the roleScopeTagIds array of an Intune role assignment via Microsoft Graph PATCH, resolving tag names to IDs and skipping tags already present.

.PARAMETER RoleName
    The display name of the role definition.

.PARAMETER AssignmentName
    The display name of the existing role assignment.

.PARAMETER ScopeTagNames
    One or more scope tag display names to add, resolved to IDs via deviceManagement/roleScopeTags.

.PARAMETER WhatIfMode
    Preview-only mode that shows what would be added without making changes.

.EXAMPLE
    # Add a single scope tag to a role assignment.
    Add-IntuneRoleAssignmentScopeTag -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -ScopeTagNames @("US-East")

.EXAMPLE
    # Preview adding multiple scope tags without making changes.
    Add-IntuneRoleAssignmentScopeTag -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -ScopeTagNames @("US-East","US-West") -WhatIfMode
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

        # --- Read current roleScopeTagIds ---
        $currentTagIds = @()
        if ($assignmentDetails.roleScopeTagIds) {
            $currentTagIds = @($assignmentDetails.roleScopeTagIds)
        }

        Write-Information "  Found $($currentTagIds.Count) existing scope tag(s)." -InformationAction Continue

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

        foreach ($tagName in $ScopeTagNames) {
            $tagMatch = $allScopeTags | Where-Object displayName -eq $tagName | Select-Object -First 1

            if (-not $tagMatch) {
                throw "Could not find scope tag with display name '$tagName'."
            }

            $tagIdMap[$tagName] = $tagMatch.id
            Write-Information "  Resolved '$tagName' -> $($tagIdMap[$tagName])" -InformationAction Continue
        }

        # --- Check for duplicates and build updated list ---
        $updatedTagIds = @() + $currentTagIds
        $results = @()

        foreach ($tagName in $ScopeTagNames) {
            $tId = $tagIdMap[$tagName]

            if ($currentTagIds -contains $tId) {
                Write-Information "  Scope tag '$tagName' ($tId) is already assigned." -InformationAction Continue
                $results += New-Object PSObject -Property @{
                    RoleName       = $RoleName
                    AssignmentName = $AssignmentName
                    ScopeTagName   = $tagName
                    ScopeTagId     = $tId
                    Action         = "ALREADY ASSIGNED"
                }
            }
            else {
                if ($WhatIfMode) {
                    Write-Information "WOULD ADD scope tag '$tagName' ($tId) to assignment '$AssignmentName'." -InformationAction Continue
                    $results += New-Object PSObject -Property @{
                        RoleName       = $RoleName
                        AssignmentName = $AssignmentName
                        ScopeTagName   = $tagName
                        ScopeTagId     = $tId
                        Action         = "WOULD ADD"
                    }
                }
                else {
                    $updatedTagIds += $tId
                    $results += New-Object PSObject -Property @{
                        RoleName       = $RoleName
                        AssignmentName = $AssignmentName
                        ScopeTagName   = $tagName
                        ScopeTagId     = $tId
                        Action         = "ADDED"
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
                if (-not $PSCmdlet.ShouldProcess("role assignment '$AssignmentName'", "Add $($updatedTagIds.Count - $currentTagIds.Count) scope tag(s)")) {
                    return
                }
                Write-Information "Patching assignment with $($updatedTagIds.Count) scope tag(s)..." -InformationAction Continue
                $patchBody = @{
                    roleScopeTagIds = @($updatedTagIds)
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
                Write-Information "No new scope tags to add." -InformationAction Continue
            }
        }
        else {
            Write-Information "WhatIfMode: No changes were made." -InformationAction Continue
        }

        # --- Output ---
        $results | Sort-Object Action, ScopeTagName | Format-Table RoleName, AssignmentName, ScopeTagName, ScopeTagId, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Scope tag assignment operation complete." -InformationAction Continue
    }

    end {
    }
}
