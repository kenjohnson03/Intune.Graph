# Write the comment-based HELP for Get-IntuneConfigurationProfileAssignments
<#
.SYNOPSIS
    Gets a list of Intune configuration profile assignments.

.DESCRIPTION
    Retrieves a list of configuration profile assignments from Intune.

.PARAMETER Id
    The id of the configuration profile to retrieve assignments for.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Get all configuration profile assignments.
    Get-IntuneConfigurationProfileAssignments -Id "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Get all configuration profile assignments in the USGov environment.
    Get-IntuneConfigurationProfileAssignments -Id "00000000-0000-0000-0000-000000000000" -Environment USGov
#>
function Get-IntuneConfigurationProfileAssignments
{
    param(
        [Parameter(Mandatory, ValueFromPipeline=$true, ValueFromPipelineByPropertyName="id", Position=0)]
        [string]$Id,
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global"
    )
    begin {
        if($false -eq (Initialize-IntuneAccess -Scopes @("DeviceManagementConfiguration.Read.All") -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
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
        $response = Invoke-MgRestMethod -Method Get -Uri "$uri/$graphVersion/deviceManagement/configurationPolicies('$Id')/assignments" -OutputType Json | ConvertFrom-Json
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

        return $assignments
    }
}