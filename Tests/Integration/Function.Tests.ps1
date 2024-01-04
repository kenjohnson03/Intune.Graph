#Requires -Version 5.0
#Requires -Modules Microsoft.Graph.Authentication, Pester


Describe 'New-IntuneConfigurationProfile' {
    $settingsJson = @"
    {
        "@odata.type": "#microsoft.graph.deviceManagementConfigurationSetting",
        "settingInstance": {
          "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
          "settingDefinitionId": "device_vendor_msft_policy_config_abovelock_allowcortanaabovelock",
          "settingInstanceTemplateReference": null,
          "choiceSettingValue": {
            "settingValueTemplateReference": null,
            "value": "device_vendor_msft_policy_config_abovelock_allowcortanaabovelock_1",
            "children": []
          }
        }
      }
"@
    $settings = ConvertFrom-Json $settingsJson
    It 'Creates a new configuration profile' {
        $newConfig = New-IntuneConfigurationProfile -Name "PesterTest" -Description "Desc" -Platform windows10 -Technologies "mdm" -RoleScopeTagIds @('0') -Settings @($settings) 
        $newConfig | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-IntuneConfigurationProfile' {
    It 'Gets all configuration profiles' {
        $Profiles = Get-IntuneConfigurationProfile -All
        $Profiles | Should -Not -BeNullOrEmpty
    }

    It 'Gets a specific configuration profile' {
        $Profile = Get-IntuneConfigurationProfile -Name "PesterTest"
        $Profile | Should -Not -BeNullOrEmpty
    }
}

Describe 'Remove-IntuneConfigurationProfile' {
    It 'Removes a configuration profile' {
        Get-IntuneConfigurationProfile -Name "PesterTest" | 
            ForEach-Object { Remove-IntuneConfigurationProfile -Id $_.id } | 
                Should -BeNullOrEmpty
    }
}
