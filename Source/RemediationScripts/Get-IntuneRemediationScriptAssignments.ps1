# Write the comment-based HELP for Get-IntuneRemediationScriptAssignments
<#
.SYNOPSIS
    Gets a list of Intune remediation script assignments.

.DESCRIPTION
    Retrieves a list of remediation script assignments from Intune.

.PARAMETER Id
    The id of the remediation script to retrieve assignments for.

.PARAMETER Name
    The name of the remediation script to retrieve assignments for.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Get all remediation script assignments by ID.
    Get-IntuneRemediationScriptAssignments -Id "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Get all remediation script assignments by name.
    Get-IntuneRemediationScriptAssignments -Name "Set Extension Attribute"

.NOTES
    Required Graph scopes:
      - DeviceManagementScripts.Read.All
      - Group.Read.All
    
    The function shows only groups with explicit assignments to the remediation script:
      - AssignmentType "Include" = Groups assigned to receive the script
      - AssignmentType "Exclude" = Groups explicitly excluded from receiving the script
    
    Groups not assigned to the script are not displayed.
#>
function Get-IntuneRemediationScriptAssignments
{
    param(
        [Parameter(Mandatory, ParameterSetName="ById", ValueFromPipeline=$true, ValueFromPipelineByPropertyName="id", Position=0)]
        [string]$Id,
        [Parameter(Mandatory, ParameterSetName="ByName", Position=0)]
        [string]$Name,
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global"
    )
    begin {
        if($false -eq (Initialize-IntuneAccess -Scopes @("DeviceManagementScripts.Read.All") -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
        {
            return
        }
        
        switch ($Environment) {
            "USGov" { $uri = "https://graph.microsoft.us" }
            "USGovDoD" { $uri = "https://dod-graph.microsoft.us" }
            Default { $uri = "https://graph.microsoft.com" }
        }

        $graphVersion = "beta"
    }
    process {
        # If Name is provided, resolve to ID first
        if ($PSCmdlet.ParameterSetName -eq "ByName") {
            try {
                $script = Get-IntuneRemediationScript -Name $Name -Environment $Environment
                if (-not $script) {
                    Write-Error "No remediation script found with name: $Name"
                    return
                }
                if ($script.Count -gt 1) {
                    Write-Error "Multiple scripts found with name '$Name'. Use -Id parameter with specific script ID instead."
                    return
                }
                $Id = $script.id
                Write-Verbose "Resolved '$Name' to ID: $Id"
            } catch {
                Write-Error "Failed to resolve script name '$Name': $($_.Exception.Message)"
                return
            }
        }
        $response = Invoke-MgRestMethod -Method Get -Uri "$uri/$graphVersion/deviceManagement/deviceHealthScripts('$Id')/assignments" -OutputType Json | ConvertFrom-Json
        $assignments = @()
        foreach($assignment in $response.value)
        {
            if([string]::IsNullOrEmpty($assignment.target.deviceAndAppManagementAssignmentFilterId))
            {
                $newAssignment = [PSCustomObject]@{
                    id = $assignment.id
                    target = [PSCustomObject]@{
                        "@odata.type" = $assignment.target.'@odata.type'
                        groupId = $assignment.target.groupId
                    }
                }
            }
            else {
                $newAssignment = [PSCustomObject]@{
                    id = $assignment.id
                    target = [PSCustomObject]@{
                        "@odata.type" = $assignment.target.'@odata.type'
                        deviceAndAppManagementAssignmentFilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
                        deviceAndAppManagementAssignmentFilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                        groupId = $assignment.target.groupId
                    }
                }
            }
            
            $assignments += $newAssignment
        }

        # Return user-friendly format with group names
        $expandedAssignments = @()
        foreach($assignment in $assignments) {
            try {
                $group = Get-MgGroup -GroupId $assignment.target.groupId -Property DisplayName,Id -ErrorAction Stop
                $isIncluded = $assignment.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget'
                $expandedAssignment = [PSCustomObject]@{
                    GroupId = $assignment.target.groupId
                    GroupName = $group.DisplayName
                    AssignmentType = if($isIncluded) { 'Include' } else { 'Exclude' }
                }
                
                # Only add filter info if there's an actual filter being used
                if ($assignment.target.deviceAndAppManagementAssignmentFilterId -and 
                    $assignment.target.deviceAndAppManagementAssignmentFilterId -ne '00000000-0000-0000-0000-000000000000' -and
                    $assignment.target.deviceAndAppManagementAssignmentFilterType -ne 'none') {
                    $expandedAssignment | Add-Member -NotePropertyName 'FilterId' -NotePropertyValue $assignment.target.deviceAndAppManagementAssignmentFilterId
                    $expandedAssignment | Add-Member -NotePropertyName 'FilterType' -NotePropertyValue $assignment.target.deviceAndAppManagementAssignmentFilterType
                }
                $expandedAssignments += $expandedAssignment
            } catch {
                Write-Warning "Could not resolve group name for ID: $($assignment.target.groupId)"
                $isIncluded = $assignment.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget'
                $expandedAssignment = [PSCustomObject]@{
                    GroupId = $assignment.target.groupId
                    GroupName = "Unknown (ID: $($assignment.target.groupId))"
                    AssignmentType = if($isIncluded) { 'Include' } else { 'Exclude' }
                }
                
                # Only add filter info if there's an actual filter being used
                if ($assignment.target.deviceAndAppManagementAssignmentFilterId -and 
                    $assignment.target.deviceAndAppManagementAssignmentFilterId -ne '00000000-0000-0000-0000-000000000000' -and
                    $assignment.target.deviceAndAppManagementAssignmentFilterType -ne 'none') {
                    $expandedAssignment | Add-Member -NotePropertyName 'FilterId' -NotePropertyValue $assignment.target.deviceAndAppManagementAssignmentFilterId
                    $expandedAssignment | Add-Member -NotePropertyName 'FilterType' -NotePropertyValue $assignment.target.deviceAndAppManagementAssignmentFilterType
                }
                $expandedAssignments += $expandedAssignment
            }
        }
        return $expandedAssignments
    }
}
