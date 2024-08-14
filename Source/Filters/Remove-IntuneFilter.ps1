# Write the comment-based HELP for Remove-IntuneFilter
<#
.SYNOPSIS
    Removes an Intune filter.

.DESCRIPTION
    Removes an Intune filter.

.PARAMETER Id
    The id of the filter to remove.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Remove a filter.
    Remove-IntuneFilter -Id "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Remove a filter in the USGov environment.
    Remove-IntuneFilter -Id "00000000-0000-0000-0000-000000000000" -Environment USGov
#>
function Remove-IntuneFilter
{
    param (
        [Parameter(Mandatory, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName="id")]
        [string]$Id,
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global"
    )
    begin {
        if($false -eq (Initialize-IntuneAccess -Scopes @("DeviceManagementConfiguration.ReadWrite.All") -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
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
        Invoke-MgRestMethod -Method Delete -Uri "$uri/$graphVersion/deviceManagement/assignmentFilters/$Id" -OutputType Json | ConvertFrom-Json
    }
}