# Write the comment-based HELP for Update-IntuneConfigurationProfile
<#
.SYNOPSIS
    Updates an Intune configuration profile.

.DESCRIPTION
    Updates an Intune configuration profile.

.PARAMETER Id
    The id of the configuration profile to update.

.PARAMETER Name
    The name of the configuration profile to update.

.PARAMETER Description
    The description of the configuration profile to update.

.PARAMETER RoleScopeTagIds
    The role scope tag ids of the configuration profile to update.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Update a configuration profile.
    Update-IntuneConfigurationProfile -Id "00000000-0000-0000-0000-000000000000" -Name "MyConfigurationProfile" -Description "My Description" -RoleScopeTagIds @("0")

.EXAMPLE
    # Update a configuration profile in the USGov environment.
    Update-IntuneConfigurationProfile -Id "00000000-0000-0000-0000-000000000000" -Name "MyConfigurationProfile" -Description "My Description" -RoleScopeTagIds @("0") -Environment USGov
#>
function Update-IntuneConfigurationProfile
{
    param (
        [Parameter(Mandatory, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName="id")]
        [string]$Id,
        [string]$Name,
        [string]$Description,
        [string[]]$RoleScopeTagIds,
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global"
    )
    begin 
    {
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
    process 
    {
        $currentConfig = Get-IntuneConfigurationProfile -Id $Id -Environment $Environment

        $body = @{}
        # Only update the name if it was sent
        if($Name)
        {
            $body.name = $Name
        }
        else 
        {
            $body.name = $currentConfig.name
        }

        # Only update the description if it was sent
        if($Description)
        {
            $body.description = $Description
        }
        else 
        {
            $body.description = $currentConfig.description
        }

        # Only update the roleScopeTagIds if it was sent
        if($RoleScopeTagIds)
        {
            $body.roleScopeTagIds = $RoleScopeTagIds
        }
        else 
        {
            $body.roleScopeTagIds = $currentConfig.roleScopeTagIds
        }

        $response = Invoke-MgRestMethod -Method Patch -Uri "$uri/$graphVersion/deviceManagement/configurationPolicies('$Id')" -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json
        return $response
    }
}