# Write the comment-based HELP for Compare-IntuneConfigurationProfileSettings
<#
.SYNOPSIS
    Compares two Intune configuration profiles.

.DESCRIPTION
    Compares two Intune configuration profiles.

.PARAMETER SourceConfigurationId
    The id of the source configuration profile to compare.

.PARAMETER DestinationConfigurationId
    The id of the destination configuration profile to compare.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Compare two configuration profiles.
    Compare-IntuneConfigurationProfileSettings -SourceConfigurationId "00000000-0000-0000-0000-000000000000" -DestinationConfigurationId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Compare two configuration profiles in the USGov environment.
    Compare-IntuneConfigurationProfileSettings -SourceConfigurationId "00000000-0000-0000-0000-000000000000" -DestinationConfigurationId "00000000-0000-0000-0000-000000000000" -Environment USGov
#>
function Compare-IntuneConfigurationProfileSettings 
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
        if($false -eq (Initialize-IntuneAccess -Scopes @("DeviceManagementConfiguration.Read.All") -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
        {
            return
        }
    }
    process {
        # Get the settings from the source configuration
        $sourceConfiguration = Get-IntuneConfigurationProfile -Id $SourceConfigurationId -Environment $Environment
        
        # Get the destination configuration
        $destinationConfiguration = Get-IntuneConfigurationProfile -Id $DestinationConfigurationId -Environment $Environment

        # Check that the technologies match
        if($sourceConfiguration.technologies -ne $destinationConfiguration.technologies)
        {
            Write-Host "Technologies do not match. Cannot compare settings"
            return
        }

        # Check that the platforms match
        if($sourceConfiguration.platforms -ne $destinationConfiguration.platforms)
        {
            Write-Host "Platforms do not match. Cannot compare settings"
            return
        }

        # Get the settings from the source configuration
        $sourceSettings = Get-IntuneConfigurationProfileSettings -Id $SourceConfigurationId -Environment $Environment
        $sourceJson = $sourceSettings | ForEach-Object { $_.settingInstance | ConvertTo-Json -Depth 50 } 
        $sourceDefinitionIds = $sourceSettings | ForEach-Object { $_.settingInstance } | Select-Object -ExpandProperty settingDefinitionId

        # Get the destination configuration settings
        $destinationSettings = Get-IntuneConfigurationProfileSettings -Id $DestinationConfigurationId -Environment $Environment
        $destinationJson = $destinationSettings | ForEach-Object { $_.settingInstance | ConvertTo-Json -Depth 50 }
        $destinationDefinitionIds = $destinationSettings | ForEach-Object { $_.settingInstance } | Select-Object -ExpandProperty settingDefinitionId

        $settingsToCompare = @()

        # Compare the settings and remove any that are missing from the source configuration
        $settingsToAdd = @()

        foreach($s in $sourceDefinitionIds)
        {
            if($destinationDefinitionIds -notcontains $s)
            {                
                $settingDefinition = $sourceSettings | Where-Object { $_.settingInstance.settingDefinitionId -eq $s }
                $newSetting = [PSCustomObject]@{                
                    "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"  
                    settingInstance = $settingDefinition.settingInstance                
                }
                $settingsToAdd += $newSetting
            }
            else 
            {
                $settingDefinition = $sourceSettings | Where-Object { $_.settingInstance.settingDefinitionId -eq $s }
                $newSetting = [PSCustomObject]@{                
                    "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"  
                    settingInstance = $settingDefinition.settingInstance                
                }
                $settingsToCompare += $newSetting
            }
        }


        $settingsToRemove = @()

        foreach($s in $destinationDefinitionIds)
        {
            if($sourceDefinitionIds -notcontains $s)
            {                
                $settingDefinition = $destinationSettings | Where-Object { $_.settingInstance.settingDefinitionId -eq $s }
                $newSetting = [PSCustomObject]@{                
                    "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"  
                    settingInstance = $settingDefinition.settingInstance                
                }
                $settingsToRemove += $newSetting
            }
        }

        $settingsToUpdate = @()
        $settingsMatch = @()

        foreach($s in $settingsToCompare)
        {
            $sourceJson = $sourceSettings | Where-Object { $_.settingInstance.settingDefinitionId -eq $s.settingInstance.settingDefinitionId } | Select-Object -ExpandProperty settingInstance | ConvertTo-Json -Depth 50
            $destinationJson = $destinationSettings | Where-Object { $_.settingInstance.settingDefinitionId -eq $s.settingInstance.settingDefinitionId } | Select-Object -ExpandProperty settingInstance | ConvertTo-Json -Depth 50
            if($sourceJson -ne $destinationJson)
            {                
                $settingsToUpdate += $s
            }
            else 
            {
                $settingsMatch += $s
            }
        }

        $result = [PSCustomObject]@{
            settingsToAdd = $settingsToAdd
            settingsToRemove = $settingsToRemove
            settingsToUpdate = $settingsToUpdate
            settingsMatch = $settingsMatch            
        }
        return $result
    }

}