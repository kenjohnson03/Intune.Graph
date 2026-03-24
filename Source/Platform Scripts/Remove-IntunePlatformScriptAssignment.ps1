function Remove-IntunePlatformScriptAssignment {
<#
.SYNOPSIS
    Removes a group assignment from an Intune platform script.

.DESCRIPTION
    Reads current assignments for a platform script, removes the specified group,
    and POSTs the remaining assignments back via Microsoft Graph.
    Accepts the script and group by GUID or display name.

.PARAMETER Id
    The GUID of the platform script to remove the assignment from.

.PARAMETER Name
    The display name of the platform script to remove the assignment from.

.PARAMETER GroupId
    The GUID of the group whose assignment should be removed.

.PARAMETER GroupName
    The display name of the group whose assignment should be removed.

.EXAMPLE
    Remove-IntunePlatformScriptAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    Remove-IntunePlatformScriptAssignment -Name 'WDAC TOAST' -GroupName 'Test-Devices'

.EXAMPLE
    Remove-IntunePlatformScriptAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupName 'Test-Devices'

.EXAMPLE
    Remove-IntunePlatformScriptAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -WhatIf
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        # Script by GUID
        [Parameter(Mandatory, ParameterSetName="ByIdByGroupId",  Position=0)]
        [Parameter(Mandatory, ParameterSetName="ByIdByGroupName",Position=0)]
        [ValidatePattern("^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$")]
        [string]$Id,

        # Script by display name
        [Parameter(Mandatory, ParameterSetName="ByNameByGroupId",  Position=0)]
        [Parameter(Mandatory, ParameterSetName="ByNameByGroupName",Position=0)]
        [string]$Name,

        # Group by GUID
        [Parameter(Mandatory, ParameterSetName="ByIdByGroupId",  Position=1)]
        [Parameter(Mandatory, ParameterSetName="ByNameByGroupId",Position=1)]
        [ValidatePattern("^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$")]
        [string]$GroupId,

        # Group by display name
        [Parameter(Mandatory, ParameterSetName="ByIdByGroupName",  Position=1)]
        [Parameter(Mandatory, ParameterSetName="ByNameByGroupName",Position=1)]
        [string]$GroupName
    )

    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementConfiguration.ReadWrite.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementConfiguration.ReadWrite.All"'
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

        # Resolve script display name to GUID (use local var to avoid ValidatePattern on $Id)
        $resolvedId = $Id
        if ($PSCmdlet.ParameterSetName -in @('ByNameByGroupId', 'ByNameByGroupName')) {
            $encoded     = [System.Uri]::EscapeDataString("displayName eq '$Name'")
            $scriptFound = Invoke-MgGraphRequest -Method GET `
                               -Uri "$graphRoot/deviceManagement/deviceManagementScripts?`$filter=$encoded"
            if (-not $scriptFound.value -or $scriptFound.value.Count -eq 0) {
                Write-Warning "Platform script '$Name' was not found."
                return
            }
            $resolvedId = $scriptFound.value[0].id
        }

        # Resolve group display name to GUID (use local var to avoid ValidatePattern on $GroupId)
        $resolvedGroupId = $GroupId
        if ($PSCmdlet.ParameterSetName -in @('ByIdByGroupName', 'ByNameByGroupName')) {
            $encoded    = [System.Uri]::EscapeDataString("displayName eq '$GroupName'")
            $groupFound = Invoke-MgGraphRequest -Method GET `
                              -Uri "$graphRoot/groups?`$filter=$encoded"
            if (-not $groupFound.value -or $groupFound.value.Count -eq 0) {
                Write-Warning "Group '$GroupName' was not found."
                return
            }
            $resolvedGroupId = $groupFound.value[0].id
        }

        # --- Get current assignments ---
        $rawAssignments = @()
        $requestUri = "$graphRoot/deviceManagement/deviceManagementScripts('$resolvedId')/assignments"

        do {
            $response       = Invoke-MgGraphRequest -Method GET -Uri $requestUri
            $rawAssignments += $response.value
            $nextLink        = $null
            if ($response.Keys -contains '@odata.nextLink') {
                $nextLink = $response.'@odata.nextLink'
            }
            $requestUri = $nextLink
        } while ($null -ne $requestUri)

        # Rebuild remaining assignments excluding the target group (strip read-only id, source, sourceId)
        $updatedAssignmentArray = @()

        foreach ($assignment in $rawAssignments) {
            if ($assignment.target.groupId -eq $resolvedGroupId) {
                continue
            }

            $cleanTarget = @{
                "@odata.type" = $assignment.target.'@odata.type'
                groupId       = $assignment.target.groupId
            }
            if (-not [string]::IsNullOrEmpty($assignment.target.deviceAndAppManagementAssignmentFilterType)) {
                $cleanTarget["deviceAndAppManagementAssignmentFilterId"]   = $assignment.target.deviceAndAppManagementAssignmentFilterId
                $cleanTarget["deviceAndAppManagementAssignmentFilterType"] = $assignment.target.deviceAndAppManagementAssignmentFilterType
            }

            $updatedAssignmentArray += @{ target = $cleanTarget }
        }

        $body = @{
            deviceManagementScriptAssignments = $updatedAssignmentArray
        }

        if ($PSCmdlet.ShouldProcess("script '$resolvedId'", "Remove assignment for group '$resolvedGroupId'")) {
            $response = Invoke-MgGraphRequest -Method POST `
                            -Uri "$graphRoot/deviceManagement/deviceManagementScripts('$resolvedId')/assign" `
                            -Body ($body | ConvertTo-Json -Depth 50) `
                            -ContentType "application/json"
            return $response
        }
    }

    end { }
}
