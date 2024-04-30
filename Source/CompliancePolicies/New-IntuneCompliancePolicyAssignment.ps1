# Write the comment-based HELP for New-IntuneCompliancePolicyAssignment
<#
.SYNOPSIS
    Creates a new Intune compliance policy assignment.

.DESCRIPTION
    Creates a new Intune compliance policy assignment.

.PARAMETER Id
    The id of the compliance policy to assign.

.PARAMETER GroupId
    The id of the group to assign the compliance policy to.

.PARAMETER IncludeExcludeGroup
    The type of group assignment. Valid values are include, exclude.

.PARAMETER FilterId
    The id of the filter to assign the compliance policy to.

.PARAMETER FilterType
    The type of filter assignment. Valid values are include, exclude.

.EXAMPLE
    # Create a compliance policy assignment.
    New-IntuneConfigurationProfileAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"

.EXAMPLE
    # Create a compliance policy assignment with a filter.
    New-IntuneConfigurationProfileAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include" -FilterId "00000000-0000-0000-0000-000000000000" -FilterType "include"
#>
function New-IntuneCompliancePolicyAssignment
{
    param (
        [Parameter(Mandatory, ParameterSetName="Group", Position=0, HelpMessage="compliance policy Id")]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter", Position=0, HelpMessage="compliance policy Id")]
        [Parameter(Mandatory, ParameterSetName="PSObject", Position=0, HelpMessage="compliance policy Id")]
        [ValidateScript({$GUIDRegex = "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$";If ($_ -match $GUIDRegex){return $true}throw "'$_': This is not a valid GUID format"})]
        [string]$Id,
        [Parameter(Mandatory, ParameterSetName="Group", Position=0)]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter", Position=0)]
        [ValidateScript({$GUIDRegex = "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$";If ($_ -match $GUIDRegex){return $true}throw "'$_': This is not a valid GUID format"})]
        [string]$GroupId,
        [Parameter(Mandatory, ParameterSetName="Group", Position=1)]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter", Position=1)]
        [ValidateSet("include", "exclude")]
        [string]$IncludeExcludeGroup,
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter")]
        [ValidateScript({$GUIDRegex = "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$";If ($_ -match $GUIDRegex){return $true}throw "'$_': This is not a valid GUID format"})]
        [string]$FilterId,
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter")]
        [ValidateSet("include","exclude")]
        [string]$FilterType        
    )
    begin 
    {

    }
    process 
    {
        If ($IncludeExcludeGroup -eq "include"){
            $type = "#microsoft.graph.groupAssignmentTarget"
        }else{
            $type = "#microsoft.graph.exclusionGroupAssignmentTarget"
        }

        if([string]::IsNullOrEmpty($FilterType))
        {
            $AssignedFilterType = "none"
        }else {
            $AssignedFilterType = $FilterType
        }

        if([string]::IsNullOrEmpty($FilterId) -eq $false)
        {
            $newAssignment = [PSCustomObject]@{
                target = [PSCustomObject]@{
                    "@odata.type" = $type
                    deviceAndAppManagementAssignmentFilterId = $FilterId
                    deviceAndAppManagementAssignmentFilterType = $AssignedFilterType
                    groupId = $GroupId
                }
            }
            return $newAssignment
        }
        
        $newAssignment = [PSCustomObject]@{
            target = [PSCustomObject]@{
                "@odata.type" = $type
                groupId = $GroupId
            }
        }
        return $newAssignment
    }
}