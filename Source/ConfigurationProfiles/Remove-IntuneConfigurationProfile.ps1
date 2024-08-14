# Write the comment-based HELP for Remove-IntuneConfigurationProfile
<#
.SYNOPSIS
    Removes an Intune configuration profile.

.DESCRIPTION
    Removes an Intune configuration profile.

.PARAMETER Id
    The id of the configuration profile to remove.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Remove a configuration profile.
    Remove-IntuneConfigurationProfile -Id "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Remove a configuration profile in the USGov environment.
    Remove-IntuneConfigurationProfile -Id "00000000-0000-0000-0000-000000000000" -Environment USGov
#>
function Remove-IntuneConfigurationProfile
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
        Invoke-MgRestMethod -Method Delete -Uri "$uri/$graphVersion/deviceManagement/configurationPolicies/$Id" -OutputType Json | ConvertFrom-Json
    }
}