# Write the comment-based HELP for Sync-IntuneConfigurationProfileSettings
<#
.SYNOPSIS
    Syncs two Intune configuration profiles.

.DESCRIPTION
    Syncs two Intune configuration profiles.

.PARAMETER SourceConfigurationId
    The id of the source configuration profile to sync.

.PARAMETER DestinationConfigurationId
    The id of the destination configuration profile to sync.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Sync two configuration profiles.
    Sync-IntuneConfigurationProfileSettings -SourceConfigurationId "00000000-0000-0000-0000-000000000000" -DestinationConfigurationId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Sync two configuration profiles in the USGov environment.
    Sync-IntuneConfigurationProfileSettings -SourceConfigurationId "00000000-0000-0000-0000-000000000000" -DestinationConfigurationId "00000000-0000-0000-0000-000000000000" -Environment USGov
#>
function Sync-IntuneConfigurationProfileSettings
{
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$SourceConfigurationId,
        [Parameter(Mandatory, Position=1)]
        [string]$DestinationConfigurationId,
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
        # Get the settings from the source configuration
        $sourceConfiguration = Get-IntuneConfigurationProfile -Id $SourceConfigurationId -Environment $Environment
        
        # Get the destination configuration
        $destinationConfiguration = Get-IntuneConfigurationProfile -Id $DestinationConfigurationId -Environment $Environment

        # Check that the technologies match
        if($sourceConfiguration.technologies -ne $destinationConfiguration.technologies)
        {
            Write-Host "Technologies do not match. Cannot sync settings"
            return
        }

        # Check that the platforms match
        if($sourceConfiguration.platforms -ne $destinationConfiguration.platforms)
        {
            Write-Host "Platforms do not match. Cannot sync settings"
            return
        }

        $sourceSettings = Get-IntuneConfigurationProfileSettings -Id $SourceConfigurationId -Environment $Environment

        $updatedSettings = @()
        foreach($setting in $sourceSettings)
        {
            
            $newSetting = [PSCustomObject]@{                
                "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"  
                settingInstance = $setting.settingInstance                
            }
            $updatedSettings += $newSetting
        }

        $updatedConfig = @{
            creationSource = $null
            name = $destinationConfiguration.name
            description = $destinationConfiguration.description            
            platforms = $destinationConfiguration.platforms
            technologies = $destinationConfiguration.technologies
            roleScopeTagIds = $destinationConfiguration.roleScopeTagIds
            settings = $updatedSettings
            templateReference = $sourceConfiguration.templateReference
        }

        # /deviceManagement/configurationPolicies/{deviceManagementConfigurationPolicyId}/settings
        Invoke-MgRestMethod -Method PUT -Uri "$uri/$graphVersion/deviceManagement/configurationPolicies('$DestinationConfigurationId')" -Body ($updatedConfig | ConvertTo-Json -Depth 50) -ContentType "application/json"  
    }
}