# Write the comment-based HELP for Add-IntuneCompliancePolicyAssignment
<#
.SYNOPSIS
    Adds an Intune Compliance policy assignment.

.DESCRIPTION
    Adds an Intune compliance policy assignment.

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

.PARAMETER AssignmentObject
    The assignment object to add. Use New-IntunecompliancepolicyAssignment to create the object.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Add a compliance policy assignment.
    Add-IntunecompliancepolicyAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"

.EXAMPLE
    # Add a compliance policy assignment with a filter.
    Add-IntunecompliancepolicyAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include" -FilterId "00000000-0000-0000-0000-000000000000" -FilterType "include"

.EXAMPLE
    # Add a compliance policy assignment with an assignment object.
    $assignment = New-IntunecompliancepolicyAssignment -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"
    Add-IntunecompliancepolicyAssignment -Id "00000000-0000-0000-0000-000000000000" -AssignmentObject $assignment

.EXAMPLE
    # Add a compliance policy assignment with an assignment object in the USGov environment.
    $assignment = New-IntunecompliancepolicyAssignment -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"
    Add-IntunecompliancepolicyAssignment -Id "00000000-0000-0000-0000-000000000000" -AssignmentObject $assignment -Environment USGov

.EXAMPLE
    # Add a compliance policy assignment with a filter in the USGov environment.
    Add-IntunecompliancepolicyAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include" -FilterId "00000000-0000-0000-0000-000000000000" -FilterType "include" -Environment USGov

.EXAMPLE
    # Add a compliance policy assignment with an assignment object in the USGov environment.
    $assignment = New-IntunecompliancepolicyAssignment -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"
    Add-IntunecompliancepolicyAssignment -Id "00000000-0000-0000-0000-000000000000" -AssignmentObject $assignment -Environment USGov

.EXAMPLE
    # Add a compliance policy assignment with a filter in the USGov environment.
    Add-IntunecompliancepolicyAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include" -FilterId "00000000-0000-0000-0000-000000000000" -FilterType "include" -Environment USGov
#>
function Add-IntuneCompliancePolicyAssignment
{
    param (     
        [Parameter(Mandatory, ParameterSetName="Group", Position=0, HelpMessage="compliance policy Id")]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter", Position=0, HelpMessage="compliance policy Id")]
        [Parameter(Mandatory, ParameterSetName="PSObject", Position=0, HelpMessage="compliance policy Id")]
        [ValidateScript({$GUIDRegex = "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$";If ($_ -match $GUIDRegex){return $true}throw "'$_': This is not a valid GUID format"})]
        [string]$Id,   
        [Parameter(Mandatory, ParameterSetName="Group", Position=1)]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter", Position=1)]
        [ValidateScript({$GUIDRegex = "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$";If ($_ -match $GUIDRegex){return $true}throw "'$_': This is not a valid GUID format"})]
        [string]$GroupId,
        [Parameter(Mandatory, ParameterSetName="Group", Position=2)]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter", Position=2)]
        [ValidateSet("include", "exclude")]
        [string]$IncludeExcludeGroup,
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter")]
        [ValidateScript({$GUIDRegex = "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$";If ($_ -match $GUIDRegex){return $true}throw "'$_': This is not a valid GUID format"})]
        [string]$FilterId,
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter")]
        [ValidateSet("include","exclude")]
        [string]$FilterType,
        [Parameter(Mandatory, ParameterSetName="PSObject", Position=1, ValueFromPipeline=$true, ValueFromPipelineByPropertyName="id", HelpMessage="The new assignment object.")]
        [psobject[]]$AssignmentObject,        
        [Parameter(ParameterSetName="Group")]
        [Parameter(ParameterSetName="GroupAndFilter")]
        [Parameter(ParameterSetName="PSObject")]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global"
    )
    begin 
    {
        if($false -eq (Initialize-IntuneAccess -Scopes @("DeviceManagementConfiguration.ReadWrite.All") -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
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
        [array]$assignments = Get-IntuneCompliancePolicyAssignments -Id $Id -Environment $Environment

        if($PSBoundParameters.ContainsKey("AssignmentObject"))
        {
            $assignments += $AssignmentObject
        }
        elseif($PSBoundParameters.ContainsKey("FilterType"))
        {
            $assignments += New-IntuneCompliancePolicyAssignment -Id $Id -GroupId $GroupId -IncludeExcludeGroup $IncludeExcludeGroup -FilterId $FilterId -FilterType $FilterType
        }
        else 
        {
            $assignments += New-IntuneCompliancePolicyAssignment -id $Id -GroupId $GroupId -IncludeExcludeGroup $IncludeExcludeGroup 
        }

        $body = @{
            assignments = $assignments
        }

        $response = Invoke-MgRestMethod -Method POST -Uri "$uri/$graphVersion/deviceManagement/deviceCompliancePolicies('$Id')/assign" -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json
        return $response
    }
}