function Add-IntuneRemediationScriptAssignment {
<#
.SYNOPSIS
    Adds a group assignment to an existing Intune remediation script.

.DESCRIPTION
    Adds an Azure AD group as an include or exclude assignment to an Intune remediation script via Microsoft Graph, reading existing assignments and POSTing the full updated list back.

.PARAMETER ScriptName
    The display name of the remediation script to assign.

.PARAMETER GroupName
    The display name of the Azure AD group to assign.

.PARAMETER IncludeExclude
    Whether the group is an include or exclude assignment. Valid values are include, exclude.

.EXAMPLE
    # Add a group as an include assignment to a remediation script.
    Add-IntuneRemediationScriptAssignment -ScriptName "Remediate-StaleProfiles" -GroupName "SG-AllWorkstations" -IncludeExclude "include"

.EXAMPLE
    # Preview an exclude assignment without making changes.
    Add-IntuneRemediationScriptAssignment -ScriptName "Remediate-StaleProfiles" -GroupName "SG-Excluded" -IncludeExclude "exclude" -WhatIf
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ScriptName,

        [Parameter(Mandatory = $true)]
        [string] $GroupName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("include", "exclude")]
        [string] $IncludeExclude
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

        # --- Check if group is already assigned ---
        $alreadyAssigned = $false
        foreach ($a in $currentAssignments) {
            if ($a.target.groupId -eq $groupId) {
                $alreadyAssigned = $true
                break
            }
        }

        if ($alreadyAssigned) {
            Write-Information "  Group '$GroupName' ($groupId) is already assigned to '$ScriptName'." -InformationAction Continue
            return
        }

        # --- Rebuild existing assignments as hashtables (preserve filter properties) ---
        $assignmentArray = @()

        foreach ($a in $currentAssignments) {
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
            $assignmentArray += @{ target = $targetHash }
        }

        # --- Build new assignment entry ---
        $odataType = if ($IncludeExclude -eq "include") {
            "#microsoft.graph.groupAssignmentTarget"
        }
        else {
            "#microsoft.graph.exclusionGroupAssignmentTarget"
        }

        $newAssignment = @{
            target = @{
                "@odata.type" = $odataType
                groupId       = $groupId
            }
        }

        $assignmentArray += $newAssignment

        # --- POST assignments ---
        if ($PSCmdlet.ShouldProcess("script '$ScriptName'", "Add assignment for group '$GroupName'")) {
            Write-Information "Posting $($assignmentArray.Count) assignment(s) to '$ScriptName'..." -InformationAction Continue
            $postBody = @{
                deviceHealthScriptAssignments = $assignmentArray
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
