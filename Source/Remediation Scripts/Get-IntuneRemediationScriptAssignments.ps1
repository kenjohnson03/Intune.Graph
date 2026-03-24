function Get-IntuneRemediationScriptAssignments {
<#
.SYNOPSIS
    Retrieves group assignments for an Intune Remediation Script.

.DESCRIPTION
    Gets all assignments for an Intune Remediation Script (deviceManagement/deviceHealthScripts/{id}/assignments) and resolves each group ID to its display name.

.PARAMETER ScriptName
    The exact display name of the remediation script whose assignments to retrieve.

.EXAMPLE
    # Get all assignments for a remediation script by name.
    Get-IntuneRemediationScriptAssignments -ScriptName "Windows 11 Remediation"
#>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ScriptName
    )

    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All","Group.Read.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementConfiguration.Read.All","Group.Read.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementConfiguration.Read.All","Group.Read.All"'
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

        # --- Resolve script name to ID ---
        Write-Information "Resolving remediation script '$ScriptName'..." -InformationAction Continue
        $allScripts = @()
        $requestUri = ($graphRoot + '/deviceManagement/deviceHealthScripts')

        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
            $allScripts += $response.value
            $nextLink = $null
            if ($response.Keys -contains '@odata.nextLink') {
                $nextLink = $response.'@odata.nextLink'
            }
            $requestUri = $nextLink
        } while ($null -ne $requestUri)

        $matchedScript = $allScripts | Where-Object displayName -eq $ScriptName | Select-Object -First 1

        if (-not $matchedScript) {
            throw "Remediation script '$ScriptName' not found. Verify the name and try again."
        }

        $scriptId = $matchedScript.id
        Write-Information "Found remediation script '$ScriptName' (ID: $scriptId)" -InformationAction Continue

        # --- Retrieve assignments ---
        Write-Information "Retrieving assignments for '$ScriptName'..." -InformationAction Continue
        $assignmentResponse = $null
        try {
            $assignmentResponse = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + "/deviceManagement/deviceHealthScripts('$scriptId')/assignments")
        }
        catch {
            Write-Error "Failed to retrieve assignments for '$ScriptName': $_"
            return
        }

        $assignments = $assignmentResponse.value

        if (-not $assignments -or $assignments.Count -eq 0) {
            Write-Information "No assignments found for remediation script '$ScriptName'." -InformationAction Continue
            return
        }

        Write-Information "Found $($assignments.Count) assignment(s). Resolving details..." -InformationAction Continue

        # --- Build results with group name resolution ---
        $results = foreach ($assignment in $assignments) {
            $odataType = $assignment.target.'@odata.type'
            $groupId = $assignment.target.groupId

            # Determine assignment type from @odata.type
            $assignmentType = "Include"
            if ($odataType -and $odataType -like "*exclusionGroupAssignment*") {
                $assignmentType = "Exclude"
            }

            # Resolve group display name
            $groupName = $null
            if ($groupId) {
                try {
                    $groupResponse = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + "/groups/$($groupId)?`$select=id,displayName")
                    $groupName = $groupResponse.displayName
                }
                catch {
                    Write-Warning "Could not resolve group ID '$groupId': $_"
                    $groupName = "(unresolved: $groupId)"
                }
            }

            New-Object PSObject -Property @{
                ScriptName     = $ScriptName
                GroupName      = $groupName
                GroupId        = $groupId
                AssignmentType = $assignmentType
            }
        }

        $results | Format-Table ScriptName, GroupName, GroupId, AssignmentType -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Assignment retrieval complete." -InformationAction Continue
    }

    end {
    }
}
