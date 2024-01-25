# Write the comment-based HELP for Get-IntuneConfigurationProfileSettings
<#
.SYNOPSIS
    Gets a list of Intune configuration profile settings.

.DESCRIPTION
    Retrieves a list of configuration profile settings from Intune.

.PARAMETER Id
    The id of the configuration profile to retrieve settings for.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Get all configuration profile settings.
    Get-IntuneConfigurationProfileSettings -Id "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Get all configuration profile settings in the USGov environment.
    Get-IntuneConfigurationProfileSettings -Id "00000000-0000-0000-0000-000000000000" -Environment USGov
#>
function Get-IntuneConfigurationProfileSettings
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

        $settings = @()
        $uri = "$uri/$graphVersion/deviceManagement/configurationPolicies('$Id')/settings"
        do 
        {
            $response = Invoke-MgRestMethod -Method Get -Uri $uri -OutputType Json | ConvertFrom-Json
            $uri = $response.'@odata.nextLink'

            foreach($setting in $response.value)
            {            
                $newSetting = [PSCustomObject]@{                
                    "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"  
                    settingInstance = $setting.settingInstance                
                }
                $settings += $newSetting
            }
        } while ($null -ne $uri)
        
        return  $settings
    }
}