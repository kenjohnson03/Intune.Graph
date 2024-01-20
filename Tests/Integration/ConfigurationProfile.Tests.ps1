#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Pester

Describe 'New-IntuneConfigurationProfile' {
    
    It 'Creates a new configuration profile' {
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
        $newConfig = New-IntuneConfigurationProfile -Name "PesterTest" -Description "Desc" -Platform windows10 -Technologies "mdm" -RoleScopeTagIds @('0') -Settings @($settings) 
        $newConfig | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-IntuneConfigurationProfile' {
    It 'Gets all configuration profiles' {
        Get-IntuneConfigurationProfile -All | 
            Should -Not -BeNullOrEmpty
    }

    It 'Gets a specific configuration profile' {
        Get-IntuneConfigurationProfile -Name "PesterTest" | 
            Should -Not -BeNullOrEmpty
    }
}

Describe 'Remove-IntuneConfigurationProfile' {
    It 'Removes a configuration profile' {
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
        $newConfig = New-IntuneConfigurationProfile -Name "PesterTest" -Description "Desc" -Platform windows10 -Technologies "mdm" -RoleScopeTagIds @('0') -Settings @($settings) 
        
        { Get-IntuneConfigurationProfile -Name "PesterTest" | 
            ForEach-Object { Remove-IntuneConfigurationProfile -Id $_.id  } } | 
                Should -Not -Throw
                
    }
}

Describe 'Compare-IntuneConfigurationProfileSettings' {
    
    It 'Compares two configuration profiles' {
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
        $newConfig = New-IntuneConfigurationProfile -Name "PesterTest" -Description "Desc" -Platform windows10 -Technologies "mdm" -RoleScopeTagIds @('0') -Settings @($settings) 
        $newConfig2 = New-IntuneConfigurationProfile -Name "PesterTest2" -Description "Desc" -Platform windows10 -Technologies "mdm" -RoleScopeTagIds @('0') -Settings @($settings) 

         { Compare-IntuneConfigurationProfileSettings -SourceConfigurationId $newConfig.id -DestinationConfigurationId $newConfig2.id | 
            Should -not -BeNullOrEmpty } | 
                Should -Not -Throw
    }
}

Describe "Backup-IntuneConfigurationProfile" {
    It "Backs up a configuration profile" {
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
        $newConfig = New-IntuneConfigurationProfile -Name "PesterTest" -Description "Desc" -Platform windows10 -Technologies "mdm" -RoleScopeTagIds @('0') -Settings @($settings) 

        { Backup-IntuneConfigurationProfile -Name "PesterTest" | 
            Should -Not -BeNullOrEmpty } | 
                Should -Not -Throw
    }
}

Describe "Sync-IntuneConfigurationProfileSettings" {
    It "Syncs two configuration profiles" {
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
        $newConfig = New-IntuneConfigurationProfile -Name "PesterTest" -Description "Desc" -Platform windows10 -Technologies "mdm" -RoleScopeTagIds @('0') -Settings @($settings) 
        $newConfig2 = New-IntuneConfigurationProfile -Name "PesterTest2" -Description "Desc" -Platform windows10 -Technologies "mdm" -RoleScopeTagIds @('0') -Settings @($settings) 

        { Sync-IntuneConfigurationProfileSettings -SourceConfigurationId $newConfig.id -DestinationConfigurationId $newConfig2.id | 
            Should -BeNullOrEmpty } | 
                Should -Not -Throw
    }
}