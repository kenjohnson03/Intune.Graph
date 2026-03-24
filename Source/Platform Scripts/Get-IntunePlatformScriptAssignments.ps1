function Get-IntunePlatformScriptAssignments {
<#
.SYNOPSIS
    Retrieves group assignments for an Intune platform script.

.DESCRIPTION
    Gets all assignments for a platform script via Microsoft Graph.
    Accepts the script by GUID or display name. Resolves each assigned
    group's display name and assignment type (include/exclude) in the output.

.PARAMETER Id
    The GUID of the platform script.

.PARAMETER Name
    The display name of the platform script.

.EXAMPLE
    Get-IntunePlatformScriptAssignments -Id "b519a9d8-d0cd-4381-aeb3-352cdfe3bae4"

.EXAMPLE
    Get-IntunePlatformScriptAssignments -Name 'WDAC TOAST'

.EXAMPLE
    'b519a9d8-d0cd-4381-aeb3-352cdfe3bae4' | Get-IntunePlatformScriptAssignments
#>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById',
                   ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [ValidatePattern("^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$")]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [string]$Name
    )

    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementConfiguration.Read.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementConfiguration.Read.All"'
            $script:__SkipProcessBlock = $true
            return
        }
        $script:__SkipProcessBlock = $false

        switch ($context.Environment) {
            "USGov"    { $graphBase = "https://graph.microsoft.us" }
            "USGovDoD" { $graphBase = "https://dod-graph.microsoft.us" }
            Default    { $graphBase = "https://graph.microsoft.com" }
        }
        $graphRoot = "$graphBase/beta"

        Write-Information "Connected to: $($context.Environment) ($graphBase)" -InformationAction Continue
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        # Resolve display name to GUID (use a local variable to avoid ValidatePattern on $Id)
        $scriptId = $Id
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $encoded = [System.Uri]::EscapeDataString("displayName eq '$Name'")
            $found   = Invoke-MgGraphRequest -Method GET `
                           -Uri "$graphRoot/deviceManagement/deviceManagementScripts?`$filter=$encoded"
            if (-not $found.value -or $found.value.Count -eq 0) {
                Write-Warning "Platform script '$Name' was not found."
                return
            }
            $scriptId = $found.value[0].id
        }

        $response = Invoke-MgGraphRequest -Method GET `
                        -Uri "$graphRoot/deviceManagement/deviceManagementScripts('$scriptId')/assignments"

        if (-not $response.value -or $response.value.Count -eq 0) {
            $label = if ($Name) { $Name } else { $scriptId }
            Write-Warning "No assignments found for platform script '$label'."
            return
        }

        foreach ($assignment in $response.value) {
            $groupId   = $assignment.target.groupId
            $groupName = $null
            if ($groupId) {
                try {
                    $g         = Invoke-MgGraphRequest -Method GET -Uri "$graphRoot/groups/$groupId"
                    $groupName = $g.displayName
                } catch {
                    $groupName = "(unresolved)"
                }
            }

            $odataType      = $assignment.target.'@odata.type'
            $assignmentType = if ($odataType -match 'exclusion') { 'exclude' } else { 'include' }

            $out = [ordered]@{
                AssignmentId   = $assignment.id
                GroupId        = $groupId
                GroupName      = $groupName
                AssignmentType = $assignmentType
            }

            if ($assignment.target.deviceAndAppManagementAssignmentFilterId) {
                $out['FilterId']   = $assignment.target.deviceAndAppManagementAssignmentFilterId
                $out['FilterType'] = $assignment.target.deviceAndAppManagementAssignmentFilterType
            }

            [PSCustomObject]$out
        }
    }

    end {}
}
