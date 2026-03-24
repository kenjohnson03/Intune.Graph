function Remove-IntuneRemediationScriptAssignment {
<#
.SYNOPSIS
    Removes an Azure AD group assignment from an Intune remediation script via Microsoft Graph.

.DESCRIPTION
    Reads the current assignments of an Intune remediation script, filters out the specified group, and POSTs the remaining assignments back.

.PARAMETER ScriptName
    The display name of the remediation script.

.PARAMETER GroupName
    The display name of the Azure AD group to remove from the assignment.

.EXAMPLE
    # Remove a specific group assignment from a remediation script.
    Remove-IntuneRemediationScriptAssignment -ScriptName "Remediate-StaleProfiles" -GroupName "SG-AllWorkstations"

.EXAMPLE
    # Preview the removal without making changes using the built-in -WhatIf switch.
    Remove-IntuneRemediationScriptAssignment -ScriptName "Remediate-StaleProfiles" -GroupName "SG-AllWorkstations" -WhatIf
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ScriptName,

        [Parameter(Mandatory = $true)]
        [string] $GroupName
    )

    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
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

        # --- Resolve remediation script name to ID ---
        Write-Information "Resolving remediation script '$ScriptName'..." -InformationAction Continue
        $allScripts = @()
        $requestUri = "$graphRoot/deviceManagement/deviceHealthScripts"

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $allScripts += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)
        }
        catch {
            Write-Error "Failed to retrieve remediation scripts: $_"
            return
        }

        $scriptMatch = $allScripts | Where-Object displayName -eq $ScriptName | Select-Object -First 1
        if (-not $scriptMatch) {
            throw "Remediation script '$ScriptName' not found. Available scripts: $(($allScripts | ForEach-Object { $_.displayName }) -join ', ')"
        }

        $scriptId = $scriptMatch.id
        Write-Information "  Resolved '$ScriptName' -> $scriptId" -InformationAction Continue

        # --- Resolve group name to ID ---
        Write-Information "Resolving group '$GroupName'..." -InformationAction Continue
        $filterUri = "$graphRoot/groups?`$filter=displayName eq '$GroupName'&`$select=id,displayName"

        try {
            $groupResponse = Invoke-MgGraphRequest -Method GET -Uri $filterUri
        }
        catch {
            Write-Error "Failed to query group '$GroupName': $_"
            return
        }

        if (-not $groupResponse.value -or $groupResponse.value.Count -eq 0) {
            throw "Could not find Azure AD group with display name '$GroupName'."
        }

        $groupId = $groupResponse.value[0].id
        Write-Information "  Resolved '$GroupName' -> $groupId" -InformationAction Continue

        # --- Get current assignments ---
        Write-Information "Retrieving current assignments for '$ScriptName'..." -InformationAction Continue
        $assignmentsUri = "$graphRoot/deviceManagement/deviceHealthScripts('$scriptId')/assignments"
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
            Write-Error "Failed to retrieve current assignments: $_"
            return
        }

        Write-Information "  Found $($currentAssignments.Count) existing assignment(s)." -InformationAction Continue

        # --- Check if group is actually assigned ---
        $foundAssignment = $false
        foreach ($a in $currentAssignments) {
            if ($a.target.groupId -eq $groupId) {
                $foundAssignment = $true
                break
            }
        }

        if (-not $foundAssignment) {
            Write-Information "  Group '$GroupName' ($groupId) is not assigned to '$ScriptName'." -InformationAction Continue
            return
        }

        # --- Rebuild assignments excluding the target group (preserve filter properties) ---
        $filteredAssignments = @()

        foreach ($a in $currentAssignments) {
            if ($a.target.groupId -eq $groupId) {
                continue
            }
            $targetHash = @{
                "@odata.type" = $a.target.'@odata.type'
                groupId       = $a.target.groupId
            }
            if ($a.target.deviceAndAppManagementAssignmentFilterId) {
                $targetHash["deviceAndAppManagementAssignmentFilterId"] = $a.target.deviceAndAppManagementAssignmentFilterId
            }
            if ($a.target.deviceAndAppManagementAssignmentFilterType) {
                $targetHash["deviceAndAppManagementAssignmentFilterType"] = $a.target.deviceAndAppManagementAssignmentFilterType
            }
            $filteredAssignments += @{ target = $targetHash }
        }

        # --- POST remaining assignments ---
        if ($PSCmdlet.ShouldProcess("script '$ScriptName'", "Remove assignment for group '$GroupName'")) {
            Write-Information "Posting $($filteredAssignments.Count) remaining assignment(s) to '$ScriptName'..." -InformationAction Continue
            $postBody = @{
                deviceHealthScriptAssignments = $filteredAssignments
            } | ConvertTo-Json -Depth 50

            try {
                Invoke-MgGraphRequest -Method POST -Uri "$graphRoot/deviceManagement/deviceHealthScripts('$scriptId')/assign" -Body $postBody -ContentType "application/json" | Out-Null
                Write-Information "  Assignment updated successfully." -InformationAction Continue
            }
            catch {
                Write-Error "Failed to update assignments for '$ScriptName': $_"
            }
        }
    }

    end { }
}
