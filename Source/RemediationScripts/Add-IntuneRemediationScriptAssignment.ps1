# Write the comment-based HELP for Add-IntuneRemediationScriptAssignment
<#
.SYNOPSIS
    Adds an Intune remediation script assignment.

.DESCRIPTION
    Adds an Intune remediation script assignment. You can either specify group and filter parameters
    directly (recommended for most use cases) or provide pre-built assignment objects.

.PARAMETER Id
    The id of the remediation script to assign.

.PARAMETER Name
    The name of the remediation script to assign.

.PARAMETER GroupId
    The id of the group to assign the remediation script to.

.PARAMETER IncludeExcludeGroup
    The type of group assignment. Valid values are include, exclude.

.PARAMETER FilterId
    The id of the filter to assign the remediation script to.

.PARAMETER FilterType
    The type of filter assignment. Valid values are include, exclude.

.PARAMETER AssignmentObject
    The assignment object to add. Use New-IntuneRemediationScriptAssignment to create the object.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Add a remediation script assignment by ID.
    Add-IntuneRemediationScriptAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"

.EXAMPLE
    # Add a remediation script assignment by name (recommended approach).
    Add-IntuneRemediationScriptAssignment -Name "Set Extension Attribute" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"

.EXAMPLE
    # Add a remediation script assignment with a filter.
    Add-IntuneRemediationScriptAssignment -Name "Set Extension Attribute" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include" -FilterId "00000000-0000-0000-0000-000000000000" -FilterType "include"

.EXAMPLE
    # Exclude a group from receiving the remediation script.
    Add-IntuneRemediationScriptAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "exclude"

.EXAMPLE
    # Advanced: Add multiple assignments using pre-built objects.
    $assignment1 = New-IntuneRemediationScriptAssignment -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"
    $assignment2 = New-IntuneRemediationScriptAssignment -GroupId "11111111-1111-1111-1111-111111111111" -IncludeExcludeGroup "exclude"
    Add-IntuneRemediationScriptAssignment -Id "00000000-0000-0000-0000-000000000000" -AssignmentObject @($assignment1, $assignment2)

.NOTES
    Required Graph scopes:
      - DeviceManagementScripts.ReadWrite.All
#>
function Add-IntuneRemediationScriptAssignment
{
    param (     
        [Parameter(Mandatory, ParameterSetName="ById", Position=0, HelpMessage="Remediation Script Id")]
        [Parameter(Mandatory, ParameterSetName="ByIdAndFilter", Position=0, HelpMessage="Remediation Script Id")]
        [ValidateScript({$GUIDRegex = "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$";If ($_ -match $GUIDRegex){return $true}throw "'$_': This is not a valid GUID format"})]
        [string]$Id,   
        [Parameter(Mandatory, ParameterSetName="ByName", Position=0)]
        [Parameter(Mandatory, ParameterSetName="ByNameAndFilter", Position=0)]
        [string]$Name,
        [Parameter(Mandatory, ParameterSetName="ById", Position=1)]
        [Parameter(Mandatory, ParameterSetName="ByIdAndFilter", Position=1)]
        [Parameter(Mandatory, ParameterSetName="ByName", Position=1)]
        [Parameter(Mandatory, ParameterSetName="ByNameAndFilter", Position=1)]
        [ValidateScript({$GUIDRegex = "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$";If ($_ -match $GUIDRegex){return $true}throw "'$_': This is not a valid GUID format"})]
        [string]$GroupId,
        [Parameter(Mandatory, ParameterSetName="ById", Position=2)]
        [Parameter(Mandatory, ParameterSetName="ByIdAndFilter", Position=2)]
        [Parameter(Mandatory, ParameterSetName="ByName", Position=2)]
        [Parameter(Mandatory, ParameterSetName="ByNameAndFilter", Position=2)]
        [ValidateSet("include", "exclude")]
        [string]$IncludeExcludeGroup,
        [Parameter(Mandatory, ParameterSetName="ByIdAndFilter")]
        [Parameter(Mandatory, ParameterSetName="ByNameAndFilter")]
        [ValidateScript({$GUIDRegex = "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$";If ($_ -match $GUIDRegex){return $true}throw "'$_': This is not a valid GUID format"})]
        [string]$FilterId,
        [Parameter(Mandatory, ParameterSetName="ByIdAndFilter")]
        [Parameter(Mandatory, ParameterSetName="ByNameAndFilter")]
        [ValidateSet("include","exclude")]
        [string]$FilterType,
        [Parameter(Mandatory, ParameterSetName="PSObject", Position=1, ValueFromPipeline=$true, ValueFromPipelineByPropertyName="id", HelpMessage="The new assignment object.")]
        [psobject[]]$AssignmentObject,        
        [Parameter(ParameterSetName="ById")]
        [Parameter(ParameterSetName="ByIdAndFilter")]
        [Parameter(ParameterSetName="ByName")]
        [Parameter(ParameterSetName="ByNameAndFilter")]
        [Parameter(ParameterSetName="PSObject")]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global"
    )
    begin 
    {
        if($false -eq (Initialize-IntuneAccess -Scopes @("DeviceManagementScripts.ReadWrite.All") -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
        {
            return
        }
        
        if($PSBoundParameters.ContainsKey("GroupId"))
        {
            $groupId = $GroupId
        }
        else 
        {
            $groupId = $Id
        }

        switch ($Environment) {
            "USGov" { $uri = "https://graph.microsoft.us" }
            "USGovDoD" { $uri = "https://dod-graph.microsoft.us" }
            Default { $uri = "https://graph.microsoft.com" }
        }
        $graphVersion = "beta"
    }
    process 
    {
        # If Name is provided, resolve to ID first
        if ($PSCmdlet.ParameterSetName -eq "ByName" -or $PSCmdlet.ParameterSetName -eq "ByNameAndFilter") {
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
        # Get raw assignments directly from API (not the user-friendly format)
        $response = Invoke-MgRestMethod -Method Get -Uri "$uri/$graphVersion/deviceManagement/deviceHealthScripts('$Id')/assignments" -OutputType Json | ConvertFrom-Json
        $assignments = @()
        foreach($assignment in $response.value) {
            if([string]::IsNullOrEmpty($assignment.target.deviceAndAppManagementAssignmentFilterId)) {
                $newAssignment = [PSCustomObject]@{
                    id = $assignment.id
                    target = [PSCustomObject]@{
                        "@odata.type" = $assignment.target.'@odata.type'
                        groupId = $assignment.target.groupId
                    }
                    runRemediationScript = $assignment.runRemediationScript
                    runSchedule = $assignment.runSchedule
                }
            } else {
                $newAssignment = [PSCustomObject]@{
                    id = $assignment.id
                    target = [PSCustomObject]@{
                        "@odata.type" = $assignment.target.'@odata.type'
                        deviceAndAppManagementAssignmentFilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
                        deviceAndAppManagementAssignmentFilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                        groupId = $assignment.target.groupId
                    }
                    runRemediationScript = $assignment.runRemediationScript
                    runSchedule = $assignment.runSchedule
                }
            }
            $assignments += $newAssignment
        }

        if($PSBoundParameters.ContainsKey("AssignmentObject"))
        {
            $assignments += $AssignmentObject
        }
        elseif($PSBoundParameters.ContainsKey("FilterType"))
        {
            $newAssignment = New-IntuneRemediationScriptAssignment -Id $Id -GroupId $GroupId -IncludeExcludeGroup $IncludeExcludeGroup -FilterId $FilterId -FilterType $FilterType
            # Add remediation script specific properties
            $newAssignment | Add-Member -NotePropertyName 'runRemediationScript' -NotePropertyValue $true
            $newAssignment | Add-Member -NotePropertyName 'runSchedule' -NotePropertyValue @{
                "@odata.type" = "#microsoft.graph.deviceHealthScriptDailySchedule"
                "interval" = 1
                "time" = "9:0:0"
                "useUtc" = $false
            }
            $assignments += $newAssignment
        }
        else 
        {
            $newAssignment = New-IntuneRemediationScriptAssignment -id $Id -GroupId $GroupId -IncludeExcludeGroup $IncludeExcludeGroup
            # Add remediation script specific properties
            $newAssignment | Add-Member -NotePropertyName 'runRemediationScript' -NotePropertyValue $true
            $newAssignment | Add-Member -NotePropertyName 'runSchedule' -NotePropertyValue @{
                "@odata.type" = "#microsoft.graph.deviceHealthScriptDailySchedule"
                "interval" = 1
                "time" = "9:0:0"
                "useUtc" = $false
            }
            $assignments += $newAssignment
        }

        $body = @{
            deviceHealthScriptAssignments = $assignments
        }

        $response = Invoke-MgRestMethod -Method POST -Uri "$uri/$graphVersion/deviceManagement/deviceHealthScripts('$Id')/assign" -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json
        return $response
    }
}
