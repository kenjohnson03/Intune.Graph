function Add-IntunePlatformScriptAssignment {
<#
.SYNOPSIS
    Adds a group assignment to an existing Intune platform script.

.DESCRIPTION
    Adds an include or exclude group assignment to an Intune platform script via Microsoft Graph,
    reading existing assignments and POSTing the full updated list back.
    Accepts the script and group by GUID or display name.

.PARAMETER Id
    The GUID of the platform script to assign.

.PARAMETER Name
    The display name of the platform script to assign.

.PARAMETER GroupId
    The GUID of the group to assign the script to.

.PARAMETER GroupName
    The display name of the group to assign the script to.

.PARAMETER IncludeExcludeGroup
    The type of group assignment. Valid values are include, exclude.

.PARAMETER FilterId
    The ID of the assignment filter to apply.

.PARAMETER FilterType
    The type of filter assignment. Valid values are include, exclude.

.PARAMETER AssignmentObject
    A pre-built assignment object to add directly, accepted from the pipeline.

.EXAMPLE
    Add-IntunePlatformScriptAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"

.EXAMPLE
    Add-IntunePlatformScriptAssignment -Name 'WDAC TOAST' -GroupName 'Test-Devices' -IncludeExcludeGroup 'include'

.EXAMPLE
    Add-IntunePlatformScriptAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupName 'Test-Devices' -IncludeExcludeGroup 'include'

.EXAMPLE
    Add-IntunePlatformScriptAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include" -FilterId "00000000-0000-0000-0000-000000000000" -FilterType "include"
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        # Script by GUID
        [Parameter(Mandatory, ParameterSetName="Group",              Position=0, HelpMessage="platform script Id")]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter",     Position=0, HelpMessage="platform script Id")]
        [Parameter(Mandatory, ParameterSetName="PSObject",           Position=0, HelpMessage="platform script Id")]
        [Parameter(Mandatory, ParameterSetName="ByGroupName",        Position=0, HelpMessage="platform script Id")]
        [ValidatePattern("^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$")]
        [string]$Id,

        # Script by display name
        [Parameter(Mandatory, ParameterSetName="ByScriptName",        Position=0)]
        [Parameter(Mandatory, ParameterSetName="ByScriptAndGroupName",Position=0)]
        [string]$Name,

        # Group by GUID
        [Parameter(Mandatory, ParameterSetName="Group",         Position=1)]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter",Position=1)]
        [Parameter(Mandatory, ParameterSetName="ByScriptName",  Position=1)]
        [ValidatePattern("^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$")]
        [string]$GroupId,

        # Group by display name
        [Parameter(Mandatory, ParameterSetName="ByGroupName",          Position=1)]
        [Parameter(Mandatory, ParameterSetName="ByScriptAndGroupName", Position=1)]
        [string]$GroupName,

        # Include/exclude - required in all non-PSObject sets
        [Parameter(Mandatory, ParameterSetName="Group",                Position=2)]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter",       Position=2)]
        [Parameter(Mandatory, ParameterSetName="ByGroupName",          Position=2)]
        [Parameter(Mandatory, ParameterSetName="ByScriptName",         Position=2)]
        [Parameter(Mandatory, ParameterSetName="ByScriptAndGroupName", Position=2)]
        [ValidateSet("include", "exclude")]
        [string]$IncludeExcludeGroup,

        # Filter (GUID-based sets only)
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter")]
        [ValidatePattern("^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$")]
        [string]$FilterId,

        [Parameter(Mandatory, ParameterSetName="GroupAndFilter")]
        [ValidateSet("include","exclude")]
        [string]$FilterType,

        # Pre-built object via pipeline
        [Parameter(Mandatory, ParameterSetName="PSObject", Position=1,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName="id",
                   HelpMessage="The new assignment object.")]
        [psobject[]]$AssignmentObject
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
        if ($PSCmdlet.ParameterSetName -in @('ByScriptName', 'ByScriptAndGroupName')) {
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
        if ($PSCmdlet.ParameterSetName -in @('ByGroupName', 'ByScriptAndGroupName')) {
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

        # Rebuild existing assignments as hashtables (strip read-only id, source, sourceId)
        $assignments = @()
        foreach ($existing in $rawAssignments) {
            $target      = $existing.target
            $cleanTarget = @{
                "@odata.type" = $target.'@odata.type'
                groupId       = $target.groupId
            }
            if ($target.deviceAndAppManagementAssignmentFilterId) {
                $cleanTarget["deviceAndAppManagementAssignmentFilterId"]   = $target.deviceAndAppManagementAssignmentFilterId
                $cleanTarget["deviceAndAppManagementAssignmentFilterType"] = $target.deviceAndAppManagementAssignmentFilterType
            }
            $assignments += @{ target = $cleanTarget }
        }

        if ($PSBoundParameters.Keys -contains "AssignmentObject") {
            $assignments += $AssignmentObject
        }
        elseif ($PSBoundParameters.Keys -contains "FilterType") {
            $type               = if ($IncludeExcludeGroup -eq "include") { "#microsoft.graph.groupAssignmentTarget" } else { "#microsoft.graph.exclusionGroupAssignmentTarget" }
            $assignedFilterType = if ([string]::IsNullOrEmpty($FilterType)) { "none" } else { $FilterType }
            $assignments += @{
                target = @{
                    "@odata.type"                              = $type
                    deviceAndAppManagementAssignmentFilterId   = $FilterId
                    deviceAndAppManagementAssignmentFilterType = $assignedFilterType
                    groupId                                    = $resolvedGroupId
                }
            }
        }
        else {
            $type = if ($IncludeExcludeGroup -eq "include") { "#microsoft.graph.groupAssignmentTarget" } else { "#microsoft.graph.exclusionGroupAssignmentTarget" }
            $assignments += @{
                target = @{
                    "@odata.type" = $type
                    groupId       = $resolvedGroupId
                }
            }
        }

        $body = @{
            deviceManagementScriptAssignments = $assignments
        }

        if ($PSCmdlet.ShouldProcess("script '$resolvedId'", "Add assignment for group '$resolvedGroupId'")) {
            $response = Invoke-MgGraphRequest -Method POST `
                            -Uri "$graphRoot/deviceManagement/deviceManagementScripts('$resolvedId')/assign" `
                            -Body ($body | ConvertTo-Json -Depth 50) `
                            -ContentType "application/json"
            return $response
        }
    }

    end { }
}
