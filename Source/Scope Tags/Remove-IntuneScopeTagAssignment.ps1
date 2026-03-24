function Remove-IntuneScopeTagAssignment {
<#
.SYNOPSIS
    Removes one or more Azure AD group assignments from an Intune Role Scope Tag via Microsoft Graph.

.DESCRIPTION
    Reads the current assignments of a scope tag, filters out the specified groups, and POSTs the remaining assignments back using the assign endpoint.

.PARAMETER TagName
    The display name of the scope tag to modify.

.PARAMETER GroupNames
    The display names of the Azure AD groups whose assignments should be removed from the scope tag.

.PARAMETER WhatIfMode
    When specified, shows what would be removed without making any changes.

.EXAMPLE
    # Remove a single group assignment from a scope tag.
    Remove-IntuneScopeTagAssignment -TagName 'ZT-ClientA' -GroupNames 'SG-OldDevices'

.EXAMPLE
    # Preview removal of multiple group assignments without making changes.
    Remove-IntuneScopeTagAssignment -TagName 'ZT-ClientA' -GroupNames 'SG-OldDevices','SG-OldUsers' -WhatIfMode
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $TagName,

        [Parameter(Mandatory = $true)]
        [string[]] $GroupNames,

        [switch] $WhatIfMode
    )

    begin {
        $ErrorActionPreference = 'Stop'

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning 'Not connected to Microsoft Graph. Run Connect-MgGraph first.'
            $script:__SkipProcessBlock = $true
            return
        }
        $script:__SkipProcessBlock = $false

        switch ($context.Environment) {
            'USGov'    { $uri = 'https://graph.microsoft.us' }
            'USGovDoD' { $uri = 'https://dod-graph.microsoft.us' }
            Default    { $uri = 'https://graph.microsoft.com' }
        }
        $graphRoot = "$uri/beta"

        Write-Information "Connected to: $($context.Environment) ($uri)" -InformationAction Continue
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        # --- Resolve scope tag name to ID ---
        Write-Information "Resolving scope tag '$TagName'..." -InformationAction Continue
        $tagsUri = "$graphRoot/deviceManagement/roleScopeTags"
        $allTags = @()
        $requestUri = $tagsUri

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $allTags += $response.value
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

        $tag = $allTags | Where-Object displayName -eq $TagName | Select-Object -First 1
        if (-not $tag) {
            Write-Error "Scope tag '$TagName' not found."
            return
        }

        $tagId = $tag.id
        Write-Information "  Resolved '$TagName' -> ID $tagId" -InformationAction Continue

        # --- Get current assignments ---
        Write-Information "Retrieving current assignments for scope tag '$TagName'..." -InformationAction Continue
        $assignmentsUri = "$tagsUri/$tagId/assignments"
        $currentAssignments = @()
        $requestUri = $assignmentsUri

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $currentAssignments += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)
        }
        catch {
            Write-Error "Failed to retrieve assignments for scope tag '$TagName': $_"
            return
        }

        Write-Information "  Found $($currentAssignments.Count) existing assignment(s)." -InformationAction Continue

        # --- Resolve group names to IDs ---
        Write-Information 'Resolving group names to IDs...' -InformationAction Continue
        $groupIdMap = @{}

        foreach ($groupName in $GroupNames) {
            $filterUri = "$graphRoot/groups?`$filter=displayName eq '$groupName'&`$select=id,displayName"
            try {
                $groupResponse = Invoke-MgGraphRequest -Method GET -Uri $filterUri
            }
            catch {
                Write-Error "Failed to query group '$groupName': $_"
                return
            }

            if (-not $groupResponse.value -or $groupResponse.value.Count -eq 0) {
                Write-Warning "Group '$groupName' not found in Azure AD. Will report as NOT ASSIGNED."
                continue
            }

            $groupIdMap[$groupName] = $groupResponse.value[0].id
            Write-Information "  Resolved '$groupName' -> $($groupResponse.value[0].id)" -InformationAction Continue
        }

        # --- Build removal set and filtered assignment list ---
        $removeGroupIds = @()
        foreach ($gName in $GroupNames) {
            if ($groupIdMap.Keys -contains $gName) {
                $removeGroupIds += $groupIdMap[$gName]
            }
        }

        $filteredAssignments = @()
        $removedGroupIds = @()

        foreach ($assignment in $currentAssignments) {
            $targetGroupId = $assignment.target.groupId
            if ($removeGroupIds -contains $targetGroupId) {
                $removedGroupIds += $targetGroupId
            }
            else {
                $filteredAssignments += @{
                    target = @{
                        '@odata.type' = $assignment.target.'@odata.type'
                        groupId       = $targetGroupId
                    }
                }
            }
        }

        # --- Build results ---
        $results = @()

        foreach ($groupName in $GroupNames) {
            if (-not ($groupIdMap.Keys -contains $groupName)) {
                $results += New-Object PSObject -Property @{
                    TagName   = $TagName
                    GroupName = $groupName
                    Action    = 'NOT ASSIGNED'
                }
                continue
            }

            $gId = $groupIdMap[$groupName]

            if ($removedGroupIds -contains $gId) {
                if ($WhatIfMode) {
                    $results += New-Object PSObject -Property @{
                        TagName   = $TagName
                        GroupName = $groupName
                        Action    = 'WOULD REMOVE'
                    }
                }
                else {
                    $results += New-Object PSObject -Property @{
                        TagName   = $TagName
                        GroupName = $groupName
                        Action    = 'REMOVED'
                    }
                }
            }
            else {
                $results += New-Object PSObject -Property @{
                    TagName   = $TagName
                    GroupName = $groupName
                    Action    = 'NOT ASSIGNED'
                }
            }
        }

        # --- Apply changes ---
        if (-not $WhatIfMode) {
            $hasRemovals = $false
            foreach ($r in $results) {
                if ($r.Action -eq 'REMOVED') {
                    $hasRemovals = $true
                    break
                }
            }

            if ($hasRemovals) {
                if ($PSCmdlet.ShouldProcess($TagName, 'Update scope tag assignments (POST assign endpoint)')) {
                    Write-Information "Posting updated assignment list ($($filteredAssignments.Count) remaining assignment(s))..." -InformationAction Continue
                    $assignBody = @{
                        assignments = $filteredAssignments
                    } | ConvertTo-Json -Depth 10

                    try {
                        Invoke-MgGraphRequest -Method POST -Uri "$tagsUri/$tagId/assign" -Body $assignBody -ContentType 'application/json' | Out-Null
                        Write-Information '  Assignments updated successfully.' -InformationAction Continue
                    }
                    catch {
                        Write-Error "Failed to update assignments for scope tag '$TagName': $_"
                        return
                    }
                }
            }
            else {
                Write-Information 'No matching assignments to remove.' -InformationAction Continue
            }
        }
        else {
            Write-Information 'WhatIfMode: No changes were made.' -InformationAction Continue
        }

        # --- Output ---
        $results | Sort-Object Action, GroupName | Format-Table TagName, GroupName, Action -AutoSize

        Write-Information '' -InformationAction Continue
        Write-Information 'Scope tag assignment removal complete.' -InformationAction Continue
    }

    end { }
}
