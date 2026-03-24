function Set-IntuneScopeTagAssignment {
<#
.SYNOPSIS
    Assigns an Intune Role Scope Tag to one or more Azure AD groups via Microsoft Graph.

.DESCRIPTION
    Resolves the scope tag and group display names to IDs, then POSTs an assignment to the scope tag's assign endpoint.

.PARAMETER TagName
    The display name of the scope tag to assign.

.PARAMETER GroupNames
    The display names of the Azure AD groups to assign the scope tag to.

.PARAMETER WhatIfMode
    When specified, shows what would be assigned without making any changes.

.EXAMPLE
    # Assign a scope tag to one or more groups.
    Set-IntuneScopeTagAssignment -TagName 'ZT-ClientA' -GroupNames 'SG-ClientA-Devices','SG-ClientA-Users'

.EXAMPLE
    # Preview the assignment without making changes.
    Set-IntuneScopeTagAssignment -TagName 'ZT-ClientA' -GroupNames 'SG-ClientA-Devices' -WhatIfMode
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
        $allTags = @()
        $requestUri = "$graphRoot/deviceManagement/roleScopeTags"

        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
            $allTags += $response.value
            $nextLink = $null
            if ($response.Keys -contains '@odata.nextLink') {
                $nextLink = $response.'@odata.nextLink'
            }
            $requestUri = $nextLink
        } while ($null -ne $requestUri)

        $tagMatch = $allTags | Where-Object displayName -eq $TagName | Select-Object -First 1
        if (-not $tagMatch) {
            throw "Scope tag '$TagName' not found. Available tags: $(($allTags | ForEach-Object { $_.displayName }) -join ', ')"
        }

        $tagId = $tagMatch.id
        Write-Information "  Resolved '$TagName' -> $tagId" -InformationAction Continue

        # --- Resolve group names to IDs ---
        Write-Information 'Resolving group names...' -InformationAction Continue
        $groupMap = @{}

        foreach ($groupName in $GroupNames) {
            $filterUri = "$graphRoot/groups?`$filter=displayName eq '$groupName'&`$select=id,displayName"
            $groupResponse = Invoke-MgGraphRequest -Method GET -Uri $filterUri

            if (-not $groupResponse.value -or $groupResponse.value.Count -eq 0) {
                throw "Could not find Azure AD group with display name '$groupName'."
            }

            $groupMap[$groupName] = $groupResponse.value[0].id
            Write-Information "  Resolved '$groupName' -> $($groupMap[$groupName])" -InformationAction Continue
        }

        # --- Build assignment body ---
        $assignmentTargets = @()
        foreach ($gName in $GroupNames) {
            $assignmentTargets += @{
                target = @{
                    '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                    groupId       = $groupMap[$gName]
                }
            }
        }

        $assignBody = @{ assignments = $assignmentTargets } | ConvertTo-Json -Depth 10
        $assignUri = "$graphRoot/deviceManagement/roleScopeTags/$tagId/assign"

        # --- Assign or preview ---
        $results = @()

        foreach ($gName in $GroupNames) {
            if ($WhatIfMode) {
                Write-Information "WOULD ASSIGN scope tag '$TagName' (ID: $tagId) to group '$gName' (ID: $($groupMap[$gName]))" -InformationAction Continue
                $results += New-Object PSObject -Property @{
                    TagName   = $TagName
                    TagId     = $tagId
                    GroupName = $gName
                    GroupId   = $groupMap[$gName]
                    Action    = 'WOULD ASSIGN'
                }
            }
            else {
                $results += New-Object PSObject -Property @{
                    TagName   = $TagName
                    TagId     = $tagId
                    GroupName = $gName
                    GroupId   = $groupMap[$gName]
                    Action    = 'ASSIGNED'
                }
            }
        }

        if (-not $WhatIfMode) {
            if ($PSCmdlet.ShouldProcess($TagName, "Assign scope tag to $($GroupNames.Count) group(s)")) {
                try {
                    Write-Information "Assigning scope tag '$TagName' to $($GroupNames.Count) group(s)..." -InformationAction Continue
                    Invoke-MgGraphRequest -Method POST -Uri $assignUri -Body $assignBody -ContentType 'application/json' | Out-Null
                    Write-Information 'Assignment successful.' -InformationAction Continue
                }
                catch {
                    Write-Error "Failed to assign scope tag '$TagName': $_"
                    foreach ($r in $results) {
                        $r.Action = 'FAILED'
                    }
                }
            }
        }

        $results | Format-Table TagName, TagId, GroupName, GroupId, Action -AutoSize

        Write-Information '' -InformationAction Continue
        Write-Information 'Scope tag assignment operation complete.' -InformationAction Continue
    }

    end { }
}
