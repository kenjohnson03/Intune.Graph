function Initialize-IntuneAccess
{
    param(
        [Parameter(Mandatory)]
        [string[]]$Scopes,
        [Parameter(Mandatory)]
        [string[]]$Modules,
        [Parameter(Mandatory)]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment    
    )

    $missingModules = $false
    foreach($module in $modules)
    {
        if(Get-Module -Name $module -ListAvailable)
        {
            Import-Module $module
        }
        else
        {
            Write-Host "Module $module not found. Please install it and try again." -ForegroundColor Yellow
            $missingModules = $true
        }
    }
    if($missingModules)
    {
        throw "Missing modules.`nInstall-Module $modules"
    }

    # Ensure we have a context
    $context = Get-MgContext
    if($null -eq $context)
    {
        throw "No context found. Please call Connect-MgGraph."
    }
    
    $missingScopes = $false
    foreach($scope in $scopes)
    {
        if($context.Scopes -notcontains $scope)
        {
            $missingScopes = $true
            Write-Host "Scope $scope not found. Please connect to the graph with the required scopes" -ForegroundColor Yellow
        }
    }
    if($missingScopes)
    {
        throw "Missing scopes.`nConnect-MgGraph -Scopes $scopes -Environment $Environment -UseDeviceCode"
    }

    return $true
}

<#
.SYNOPSIS
    Gets a list of Intune configuration profiles.

.DESCRIPTION
    Retrieves a single configuration profile or a list of configuration profiles from Intune.

.PARAMETER Name
    The name of the configuration profile to retrieve. This is case sensitive and uses the startswith filter operator.

.PARAMETER Id
    The id of the configuration profile to retrieve.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.PARAMETER All
    Return all configuration profiles.

.EXAMPLE
    # Get all configuration profiles.
    Get-IntuneConfigurationProfile -All

.EXAMPLE
    # Get a configuration profile by name.
    Get-IntuneConfigurationProfile -Name "MyConfigurationProfile"

.EXAMPLE
    # Get a configuration profile by id.
    Get-IntuneConfigurationProfile -Id "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Get all configuration profiles in the USGov environment.
    Get-IntuneConfigurationProfile -All -Environment USGov
#>
function Get-IntuneConfigurationProfile 
{
    param (
        [Parameter(Mandatory, ParameterSetName="Name", Position=0)]
        [string]$Name,
        [Parameter(Mandatory, ParameterSetName="Id", Position=1)]
        [string]$Id,
        [Parameter(ParameterSetName="Name")]
        [Parameter(ParameterSetName="Id")]
        [Parameter(ParameterSetName="All")]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global",
        [Parameter(ParameterSetName="All")]
        [switch]$All
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

        # No parameters specified, return all
        if($PSBoundParameters.Count -eq 0)
        {
            $All = $true
        }
    }
    process {
        
        if($All)
        {
            $configurations = @()
            $reqeustUri = "$uri/$graphVersion/deviceManagement/configurationPolicies"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $reqeustUri -OutputType Json | ConvertFrom-Json
                $configurations += $response.value
                $reqeustUri = $response.'@odata.nextLink'
            } 
            while ($null -ne $reqeustUri)            

            return $configurations
        }       

        if($Name)
        {

            $configurations = @()
            $reqeustUri = "$uri/$graphVersion/deviceManagement/configurationPolicies?`$Filter=startswith(name,'$Name')"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $reqeustUri -OutputType Json | ConvertFrom-Json
                $configurations += $response.value
                $reqeustUri = $response.'@odata.nextLink'
            } while ($null -ne $reqeustUri)            

            return $configurations
        }  
        
        if($Id)
        {
            $response = Invoke-MgRestMethod -Method Get -Uri "$uri/$graphVersion/deviceManagement/configurationPolicies/$Id" -OutputType Json | ConvertFrom-Json
            return $response
        }

        write-host "No parameters specified"
        return 
    }
}

# Write the comment-based HELP for New-IntuneConfigurationProfile
<#
.SYNOPSIS
    Creates a new Intune configuration profile.

.DESCRIPTION
    Creates a new Intune configuration profile.

.PARAMETER Name
    The name of the configuration profile to create.

.PARAMETER Description
    The description of the configuration profile to create.

.PARAMETER Platform
    The platform of the configuration profile to create. Valid values are windows10, iOS.

.PARAMETER Technologies
    The technologies of the configuration profile to create. Use Get-IntuneConfigurationProfile to get examples.

.PARAMETER Settings
    The settings of the configuration profile to create.

.PARAMETER RoleScopeTagIds
    The role scope tag ids of the configuration profile to create.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Create a configuration profile.
    New-IntuneConfigurationProfile -Name "MyConfigurationProfile" -Description "My Description" -Platform "windows10" -Technologies "mdm" -Settings @() -RoleScopeTagIds @("0")

.EXAMPLE
    # Create a configuration profile in the USGov environment.
    New-IntuneConfigurationProfile -Name "MyConfigurationProfile" -Description "My Description" -Platform "windows10" -Technologies "mdm" -Settings @() -RoleScopeTagIds @("0") -Environment USGov
#>
function New-IntuneConfigurationProfile
{
    param(
        [string]$Name,
        [string]$Description,
        [ValidateSet(
            "windows10",
            "iOS"          
        )]
        [string]$Platform,
        [string]$Technologies="mdm",        
        [psobject[]]$Settings,
        [string[]]$RoleScopeTagIds=@("0"),
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
        $body = @{}
        if($Name)
        {
            $body.name = $Name
        }
        if($Description)
        {
            $body.description = $Description
        }
        if($Platform)
        {
            $body.platforms = $Platform
        }
        if($Technologies)
        {
            $body.technologies = $Technologies
        }
        if($Settings)
        {
            $body.settings = $Settings
        }
        if($RoleScopeTagIds)
        {
            $body.roleScopeTagIds = $RoleScopeTagIds
        }

        $response = Invoke-MgRestMethod -Method Post -Uri "$uri/$graphVersion/deviceManagement/configurationPolicies" -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json
        return $response
    }
}

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
        

        $response = Invoke-MgRestMethod -Method Get -Uri "$uri/$graphVersion/deviceManagement/configurationPolicies('$Id')/settings" -OutputType Json | ConvertFrom-Json

        $settings = @()
        foreach($setting in $response.value)
        {            
            $newSetting = [PSCustomObject]@{                
                "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"  
                settingInstance = $setting.settingInstance                
            }
            $settings += $newSetting
        }
        return  $settings
    }
}

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
        $sourceConfiguration = Get-IntuneConfiguration -ConfigurationId $SourceConfigurationId -Environment $Environment
        
        # Get the destination configuration
        $destinationConfiguration = Get-IntuneConfiguration -ConfigurationId $DestinationConfigurationId -Environment $Environment

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
        $sourceSettings = Get-IntuneConfigurationSettings -ConfigurationId $SourceConfigurationId -Environment $Environment
        $sourceJson = $sourceSettings | ForEach-Object { $_.settingInstance | ConvertTo-Json -Depth 50 } 
        $sourceDefinitionIds = $sourceSettings | ForEach-Object { $_.settingInstance } | Select-Object -ExpandProperty settingDefinitionId

        # Get the destination configuration settings
        $destinationSettings = Get-IntuneConfigurationSettings -ConfigurationId $DestinationConfigurationId -Environment $Environment
        $destinationJson = $destinationSettings | ForEach-Object { $_.settingInstance | ConvertTo-Json -Depth 50 }
        $destinationDefinitionIds = $destinationSettings | ForEach-Object { $_.settingInstance } | Select-Object -ExpandProperty settingDefinitionId

        $settingsToCompare = @()

        # Compare the settings and remove any that are missing from the source configuration
        $settingsToAdd = @()
        # foreach($s in $sourceJson)
        # {
        #     if($destinationJson -notcontains $s)
        #     {
        #         $settingDefinitionId = $s | ConvertFrom-Json -Depth 50 | Select-Object -ExpandProperty settingDefinitionId
        #         $settingDefinition = $sourceSettings | Where-Object { $_.settingInstance.settingDefinitionId -eq $settingDefinitionId }
        #         $newSetting = [PSCustomObject]@{                
        #             "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"  
        #             settingInstance = $settingDefinition.settingInstance                
        #         }
        #         $settingsToAdd += $newSetting
        #     }
        # }
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
        # foreach($s in $destinationJson)
        # {
        #     if($sourceJson -notcontains $s)
        #     {
        #         $settingDefinitionId = $s | ConvertFrom-Json -Depth 50 | Select-Object -ExpandProperty settingDefinitionId
        #         $settingDefinition = $destinationSettings | Where-Object { $_.settingInstance.settingDefinitionId -eq $settingDefinitionId }
        #         $newSetting = [PSCustomObject]@{                
        #             "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"  
        #             settingInstance = $settingDefinition.settingInstance                
        #         }
        #         $settingsToAdd += $newSetting
        #     }
        # }
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
        $sourceConfiguration = Get-IntuneConfiguration -ConfigurationId $SourceConfigurationId -Environment $Environment
        
        # Get the destination configuration
        $destinationConfiguration = Get-IntuneConfiguration -ConfigurationId $DestinationConfigurationId -Environment $Environment

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

        $sourceSettings = Get-IntuneConfigurationSettings -ConfigurationId $SourceConfigurationId -Environment $Environment

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

# Write the comment-based HELP for New-IntuneConfigurationProfileAssignment
<#
.SYNOPSIS
    Creates a new Intune configuration profile assignment.

.DESCRIPTION
    Creates a new Intune configuration profile assignment.

.PARAMETER Id
    The id of the configuration profile to assign.

.PARAMETER GroupId
    The id of the group to assign the configuration profile to.

.PARAMETER IncludeExcludeGroup
    The type of group assignment. Valid values are include, exclude.

.PARAMETER FilterId
    The id of the filter to assign the configuration profile to.

.PARAMETER FilterType
    The type of filter assignment. Valid values are include, exclude.

.EXAMPLE
    # Create a configuration profile assignment.
    New-IntuneConfigurationProfileAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"

.EXAMPLE
    # Create a configuration profile assignment with a filter.
    New-IntuneConfigurationProfileAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include" -FilterId "00000000-0000-0000-0000-000000000000" -FilterType "include"
#>
function New-IntuneConfigurationProfileAssignment
{
    param (
        [Parameter(Mandatory, ParameterSetName="Group", Position=0)]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter", Position=0)]
        [ValidatePattern("^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$", ErrorMessage="Must be a valid GUID")]
        [string]$GroupId,
        [Parameter(Mandatory, ParameterSetName="Group", Position=1)]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter", Position=1)]
        [ValidateSet("include", "exclude")]
        [string]$IncludeExcludeGroup,
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter")]
        [ValidatePattern("^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$", ErrorMessage="Must be a valid GUID")]
        [string]$FilterId,
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter")]
        [ValidateSet("include","exclude")]
        [string]$FilterType        
    )
    begin 
    {

    }
    process 
    {
        $type = $IncludeExcludeGroup -eq "include" ? "#microsoft.graph.groupAssignmentTarget" : "#microsoft.graph.exclusionGroupAssignmentTarget"
        $AssignedFilterType = [string]::IsNullOrEmpty($FilterType) ? "none" : $FilterType

        if([string]::IsNullOrEmpty($FilterId) -eq $false)
        {
            $newAssignment = [PSCustomObject]@{
                target = [PSCustomObject]@{
                    "@odata.type" = $type
                    deviceAndAppManagementAssignmentFilterId = $FilterId
                    deviceAndAppManagementAssignmentFilterType = $AssignedFilterType
                    groupId = $GroupId
                }
            }
            return $newAssignment
        }
        
        $newAssignment = [PSCustomObject]@{
            target = [PSCustomObject]@{
                "@odata.type" = $type
                groupId = $GroupId
            }
        }
        return $newAssignment
    }
}

# Write the comment-based HELP for Add-IntuneConfigurationProfileAssignment
<#
.SYNOPSIS
    Adds an Intune configuration profile assignment.

.DESCRIPTION
    Adds an Intune configuration profile assignment.

.PARAMETER Id
    The id of the configuration profile to assign.

.PARAMETER GroupId
    The id of the group to assign the configuration profile to.

.PARAMETER IncludeExcludeGroup
    The type of group assignment. Valid values are include, exclude.

.PARAMETER FilterId
    The id of the filter to assign the configuration profile to.

.PARAMETER FilterType
    The type of filter assignment. Valid values are include, exclude.

.PARAMETER AssignmentObject
    The assignment object to add. Use New-IntuneConfigurationProfileAssignment to create the object.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Add a configuration profile assignment.
    Add-IntuneConfigurationProfileAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"

.EXAMPLE
    # Add a configuration profile assignment with a filter.
    Add-IntuneConfigurationProfileAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include" -FilterId "00000000-0000-0000-0000-000000000000" -FilterType "include"

.EXAMPLE
    # Add a configuration profile assignment with an assignment object.
    $assignment = New-IntuneConfigurationProfileAssignment -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"
    Add-IntuneConfigurationProfileAssignment -Id "00000000-0000-0000-0000-000000000000" -AssignmentObject $assignment

.EXAMPLE
    # Add a configuration profile assignment with an assignment object in the USGov environment.
    $assignment = New-IntuneConfigurationProfileAssignment -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"
    Add-IntuneConfigurationProfileAssignment -Id "00000000-0000-0000-0000-000000000000" -AssignmentObject $assignment -Environment USGov

.EXAMPLE
    # Add a configuration profile assignment with a filter in the USGov environment.
    Add-IntuneConfigurationProfileAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include" -FilterId "00000000-0000-0000-0000-000000000000" -FilterType "include" -Environment USGov

.EXAMPLE
    # Add a configuration profile assignment with an assignment object in the USGov environment.
    $assignment = New-IntuneConfigurationProfileAssignment -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include"
    Add-IntuneConfigurationProfileAssignment -Id "00000000-0000-0000-0000-000000000000" -AssignmentObject $assignment -Environment USGov

.EXAMPLE
    # Add a configuration profile assignment with a filter in the USGov environment.
    Add-IntuneConfigurationProfileAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000" -IncludeExcludeGroup "include" -FilterId "00000000-0000-0000-0000-000000000000" -FilterType "include" -Environment USGov
#>
function Add-IntuneConfigurationProfileAssignment
{
    param (     
        [Parameter(Mandatory, ParameterSetName="Group", Position=0, HelpMessage="Configuration Profile Id")]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter", Position=0, HelpMessage="Configuration Profile Id")]
        [Parameter(Mandatory, ParameterSetName="PSObject", Position=0, HelpMessage="Configuration Profile Id")]
        [ValidatePattern("^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$", ErrorMessage="Must be a valid GUID")]
        [string]$Id,   
        [Parameter(Mandatory, ParameterSetName="Group", Position=1)]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter", Position=1)]
        [ValidatePattern("^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$", ErrorMessage="Must be a valid GUID")]
        [string]$GroupId,
        [Parameter(Mandatory, ParameterSetName="Group", Position=2)]
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter", Position=2)]
        [ValidateSet("include", "exclude")]
        [string]$IncludeExcludeGroup,
        [Parameter(Mandatory, ParameterSetName="GroupAndFilter")]
        [ValidatePattern("^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$", ErrorMessage="Must be a valid GUID")]
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
        [array]$assignments = Get-IntuneConfigurationProfileAssignments -Id $Id -Environment $Environment

        if($PSBoundParameters.ContainsKey("AssignmentObject"))
        {
            $assignments += $AssignmentObject
        }
        elseif($PSBoundParameters.ContainsKey("FilterType"))
        {
            $assignments += New-IntuneConfigurationProfileAssignment -GroupId $GroupId -IncludeExcludeGroup $IncludeExcludeGroup -FilterId $FilterId -FilterType $FilterType
        }
        else 
        {
            $assignments += New-IntuneConfigurationProfileAssignment -GroupId $GroupId -IncludeExcludeGroup $IncludeExcludeGroup 
        }

        $body = @{
            assignments = $assignments
        }

        $response = Invoke-MgRestMethod -Method POST -Uri "$uri/$graphVersion/deviceManagement/configurationPolicies('$Id')/assign" -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json
        return $response
    }
}

<#
 .Synopsis
  Gets a list of Intune filters.

 .Description
  Retrieves a single filter or a list of filters from Intune.

 .Parameter Name
  The name of the filter to retrieve. This is case sensitive and uses the startswith filter operator.

 .Parameter Id
 The id of the filter to retrieve.

 .Parameter Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

 .Parameter All
    Return all filters.

 .EXAMPLE
   # Get all filters.
   Get-IntuneFilter -All

 .EXAMPLE
   # Get a filter by name.
   Get-IntuneFilter -Name "MyFilter"

 .EXAMPLE
    # Get a filter by id.
    Get-IntuneFilter -Id "12345678-1234-1234-1234-123456789012"

 .EXAMPLE
    # Get a filter by name in the USGov environment.
    Get-IntuneFilter -Name "MyFilter" -Environment USGov
#>
function Get-IntuneFilter
{
    param(
        [Parameter(Mandatory, ParameterSetName="Name", Position=0)]
        [string]$Name,
        [Parameter(Mandatory, ParameterSetName="Id", Position=1)]
        [string]$Id,
        [Parameter(ParameterSetName="Name")]
        [Parameter(ParameterSetName="Id")]
        [Parameter(ParameterSetName="All")]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global",
        [Parameter(ParameterSetName="All")]
        [switch]$All
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

        if($PSBoundParameters.Count -eq 0)
        {
            $All = $true
        }
    }
    process 
    {
        if($All)
        {
            $filters = @()
            $reqeustUri = "$uri/$graphVersion/deviceManagement/assignmentFilters"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $reqeustUri -OutputType Json | ConvertFrom-Json
                $filters += $response.value
                $reqeustUri = $response.'@odata.nextLink'
            }
            while ($null -ne $reqeustUri)

            return $filters
        }

        if($Name)
        {
            $filters = @()
            $reqeustUri = "$uri/$graphVersion/deviceManagement/assignmentFilters?`$Filter=startswith(name,'$Name')"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $reqeustUri -OutputType Json | ConvertFrom-Json
                $filters += $response.value
                $reqeustUri = $response.'@odata.nextLink'
            }
            while ($null -ne $reqeustUri)

            return $filters
        }

        if($Id)
        {
            $filters = @()
            $response = Invoke-MgRestMethod -Method Get -Uri "$uri/$graphVersion/deviceManagement/assignmentFilters/$Id" -OutputType Json | ConvertFrom-Json
            $filters += $response
            return $filters
        }

        write-host "No parameters specified"
        return
    }
}

# Write the comment-based HELP for New-IntuneFilter
<#
.SYNOPSIS
    Creates a new Intune filter.

.DESCRIPTION
    Creates a new Intune filter.

.PARAMETER Name
    The name of the filter.

.PARAMETER Description
    The description of the filter.

.PARAMETER Platform
    The platform of the filter. Valid values are windows10AndLater, iOS, androidForWork, macOS, android, androidAOSP, androidMobileApplicationManagement, iOSMobileApplicationManagement.

.PARAMETER Rule
    The rule of the filter. This is a string that contains the OData filter expression.

.PARAMETER RoleScopeTagIds
    The role scope tags to assign to the filter.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Create a filter.
    New-IntuneFilter -Name "MyFilter" -Description "My Filter" -Platform "windows10AndLater" -Rule "system.deviceManufacturer -eq 'Dell'" -RoleScopeTagIds "0"

.EXAMPLE
    # Create a filter in the USGov environment.
    New-IntuneFilter -Name "MyFilter" -Description "My Filter" -Platform "windows10AndLater" -Rule "system.deviceManufacturer -eq 'Dell'" -RoleScopeTagIds "0" -Environment USGov

.EXAMPLE
    # Create a filter with multiple role scope tags.
    New-IntuneFilter -Name "MyFilter" -Description "My Filter" -Platform "windows10AndLater" -Rule "system.deviceManufacturer -eq 'Dell'" -RoleScopeTagIds "0","1"

.EXAMPLE
    # Create a filter with multiple role scope tags in the USGov environment.
    New-IntuneFilter -Name "MyFilter" -Description "My Filter" -Platform "windows10AndLater" -Rule "system.deviceManufacturer -eq 'Dell'" -RoleScopeTagIds "0","1" -Environment USGov
#>
function New-IntuneFilter
{
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Name,
        [Parameter(Position=1)]
        [string]$Description,
        [Parameter(Mandatory)]
        [ValidateSet(
            "windows10AndLater",
            "iOS",
            "androidForWork",
            "macOS",
            "android",
            "androidAOSP",            
            "androidMobileApplicationManagement",            
            "iOSMobileApplicationManagement"            
        )]
        [string]$Platform,
        [Parameter(Mandatory)]
        [string]$Rule,
        [string[]]$RoleScopeTagIds=@(0),
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
        $body = @{
            displayName = $Name
            description = $Description
            platform = $Platform
            rule = $Rule
            roleScopeTags = $RoleScopeTags
        }

        $response = Invoke-MgRestMethod -Method Post -Uri "$uri/$graphVersion/deviceManagement/assignmentFilters" -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json
        return $response
    }
}

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

# Write the comment-based HELP for Get-IntuneTag
<#
.SYNOPSIS
    Gets a list of Intune tags.

.DESCRIPTION
    Retrieves a single tag or a list of tags from Intune.

.PARAMETER Name
    The name of the tag to retrieve. This is case sensitive and uses the startswith filter operator.

.PARAMETER Id
    The id of the tag to retrieve.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.PARAMETER All
    Return all tags.

.EXAMPLE
    # Get all tags.
    Get-IntuneTag -All

.EXAMPLE
    # Get a tag by name.
    Get-IntuneTag -Name "MyTag"

.EXAMPLE
    # Get a tag by id.
    Get-IntuneTag -Id "12345678-1234-1234-1234-123456789012"

.EXAMPLE
    # Get a tag by name in the USGov environment.
    Get-IntuneTag -Name "MyTag" -Environment USGov

.EXAMPLE
    # Get a tag by id in the USGov environment.
    Get-IntuneTag -Id "12345678-1234-1234-1234-123456789012" -Environment USGov
#>
function Get-IntuneTag 
{
    param(
        [Parameter(Mandatory, ParameterSetName="Name", Position=0)]
        [string]$Name,
        [Parameter(Mandatory, ParameterSetName="Id", Position=1)]
        [string]$Id,
        [Parameter(ParameterSetName="Name")]
        [Parameter(ParameterSetName="Id")]
        [Parameter(ParameterSetName="All")]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global",
        [Parameter(ParameterSetName="All")]
        [switch]$All
    )
    begin 
    {
        if($false -eq (Initialize-IntuneAccess -Scopes @("DeviceManagementRBAC.Read.All") -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
        {
            return
        }
        
        switch ($Environment) {
            "USGov" { $uri = "https://graph.microsoft.us" }
            "USGovDoD" { $uri = "https://dod-graph.microsoft.us" }
            Default { $uri = "https://graph.microsoft.com" }
        }

        $graphVersion = "beta"

        if($PSBoundParameters.Count -eq 0)
        {
            $All = $true
        }
    }
    process 
    {
        if($All)
        {
            $tags = @()
            $reqeustUri = "$uri/$graphVersion/deviceManagement/roleScopeTags"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $reqeustUri -OutputType Json | ConvertFrom-Json
                $tags += $response.value
                $reqeustUri = $response.'@odata.nextLink'
            } 
            while ($null -ne $reqeustUri)

            return $tags
        }

        if($Name)
        {
            $tags = @()
            $reqeustUri = "$uri/$graphVersion/deviceManagement/roleScopeTags?`$Filter=startswith(displayName,'$Name')"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $reqeustUri -OutputType Json | ConvertFrom-Json
                $tags += $response.value
                $reqeustUri = $response.'@odata.nextLink'
            } 
            while ($null -ne $reqeustUri)

            return $tags
        }

        if($Id)
        {
            $tags = @()
            $response = Invoke-MgRestMethod -Method Get -Uri "$uri/$graphVersion/deviceManagement/roleScopeTags/$Id" -OutputType Json | ConvertFrom-Json
            $tags += $response
            return $tags
        }

        write-host "No parameters specified"
        return
    }
}

# Write the comment-based HELP for New-IntuneTag
<#
.SYNOPSIS
    Creates a new Intune tag.

.DESCRIPTION
    Creates a new Intune tag.

.PARAMETER Name
    The name of the tag.

.PARAMETER Description
    The description of the tag.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE   
    # Create a tag.
    New-IntuneTag -Name "MyTag" -TagDescription "My Tag"

.EXAMPLE
    # Create a tag in the USGov environment.
    New-IntuneTag -Name "MyTag" -TagDescription "My Tag" -Environment USGov

.EXAMPLE
    # Create a tag with a description.
    New-IntuneTag -Name "MyTag" -TagDescription "My Tag"
#>
function New-IntuneTag
{
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Name,
        [Parameter(Position=1)]
        [string]$Description,
        [Parameter(Position=2)]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global"
    )
    begin 
    {
        if($false -eq (Initialize-IntuneAccess -Scopes @("DeviceManagementRBAC.ReadWrite.All") -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
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
        $body = @{
            displayName = $Name
            description = $Description
        }

        $response = Invoke-MgRestMethod -Method Post -Uri "$uri/$graphVersion/deviceManagement/roleScopeTags" -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json
        return $response
    }
}

# Write the comment-based HELP for Remove-IntuneTag
<#
.SYNOPSIS
    Removes an Intune tag.

.DESCRIPTION
    Removes an Intune tag.

.PARAMETER Id
    The id of the tag to remove.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Remove a tag.
    Remove-IntuneTag -Id "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Remove a tag in the USGov environment.
    Remove-IntuneTag -Id "00000000-0000-0000-0000-000000000000" -Environment USGov
#>
function Remove-IntuneTag
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
        Invoke-MgRestMethod -Method Delete -Uri "$uri/$graphVersion/deviceManagement/roleScopeTags/$Id" -OutputType Json | ConvertFrom-Json
    }
}

# Write the comment-based HELP for Backup-IntuneConfigurationProfile
<#
.SYNOPSIS
    Backs up Intune configuration profiles.

.DESCRIPTION
    Backs up Intune configuration profiles.

.PARAMETER Name
    The name of the configuration profile to backup. This is case sensitive and uses the startswith filter operator.

.PARAMETER Id
    The id of the configuration profile to backup.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.PARAMETER All
    Backup all configuration profiles.

.PARAMETER IncludeTags
    Include role scope tags in the backup.

.EXAMPLE
    # Backup all configuration profiles.
    Backup-IntuneConfigurationProfile -All

.EXAMPLE
    # Backup a configuration profile by name.
    Backup-IntuneConfigurationProfile -Name "MyConfigurationProfile"

.EXAMPLE
    # Backup a configuration profile by id.
    Backup-IntuneConfigurationProfile -Id "12345678-1234-1234-1234-123456789012"

.EXAMPLE    
    # Backup a configuration profile by name in the USGov environment.
    Backup-IntuneConfigurationProfile -Name "MyConfigurationProfile" -Environment USGov

.EXAMPLE
    # Backup a configuration profile by id in the USGov environment.
    Backup-IntuneConfigurationProfile -Id "12345678-1234-1234-1234-123456789012" -Environment USGov

.EXAMPLE
    # Backup all configuration profiles with role scope tags.
    Backup-IntuneConfigurationProfile -All -IncludeTags

.EXAMPLE
    # Backup a configuration profile by name with role scope tags.
    Backup-IntuneConfigurationProfile -Name "MyConfigurationProfile" -IncludeTags

.EXAMPLE
    # Backup a configuration profile by id with role scope tags.
    Backup-IntuneConfigurationProfile -Id "12345678-1234-1234-1234-123456789012" -IncludeTags

.EXAMPLE
    # Backup a configuration profile by name with role scope tags in the USGov environment.
    Backup-IntuneConfigurationProfile -Name "MyConfigurationProfile" -IncludeTags -Environment USGov

.EXAMPLE
    # Backup a configuration profile by id with role scope tags in the USGov environment.
    Backup-IntuneConfigurationProfile -Id "12345678-1234-1234-1234-123456789012" -IncludeTags -Environment USGov
#>
function Backup-IntuneConfigurationProfile
{
    param(
        [Parameter(Mandatory, ParameterSetName="Name", Position=0)]
        [string]$Name,
        [Parameter(Mandatory, ParameterSetName="Id", Position=1)]
        [string]$Id,
        [Parameter(ParameterSetName="Name")]
        [Parameter(ParameterSetName="Id")]
        [Parameter(ParameterSetName="All")]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global",
        [Parameter(ParameterSetName="Name")]
        [Parameter(ParameterSetName="Id")]
        [Parameter(ParameterSetName="All")]
        [switch]$IncludeTags,
        [Parameter(ParameterSetName="All")]
        [switch]$All
    )

    begin {
        $scopes = @("DeviceManagementConfiguration.Read.All")
        if($IncludeTags)
        {
            $scopes += "DeviceManagementRBAC.Read.All"
        }
        if($false -eq (Initialize-IntuneAccess -Scopes $scopes -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
        {
            return
        }
    }
    process {
        $configurations = @()
        if($All)
        {
            $configurations += Get-IntuneConfigurationProfile -All -Environment $Environment
        }

        if($Name)
        {
            $configurations += Get-IntuneConfigurationProfile -ConfigurationName $Name -Environment $Environment
        }

        if($Id)
        {
            $configurations += Get-IntuneConfigurationProfile -ConfigurationId $Id -Environment $Environment
        }

        $backupConfigurations = @()

        foreach($configuration in $configurations)
        {
            $settings = Get-IntuneConfigurationProfileSettings -Id $configuration.id -Environment $Environment

            $assignments = Get-IntuneConfigurationProfileAssignments -Id $configuration.id -Environment $Environment

            $filters = @()
            foreach($assignment in $assignments)
            {
                if($null -ne $assignment.target.deviceAndAppManagementAssignmentFilterId)
                {
                    $filters += Get-IntuneFilter -Id $assignment.target.deviceAndAppManagementAssignmentFilterId -Environment $Environment
                }
            }

            $tags = @()
            if($IncludeTags)
            {
                foreach($roleScope in $configuration.roleScopeTagIds)
                {
                    $tags += Get-IntuneTag -Id $roleScope -Environment $Environment
                }
            }

            $backupConfiguration = [PSCustomObject]@{
                id = $configuration.id
                name = $configuration.name
                description = $configuration.description
                platforms = $configuration.platforms
                technologies = $configuration.technologies
                roleScopeTagIds = $configuration.roleScopeTagIds                
                templateReference = $configuration.templateReference
                settings = $settings
                assignments = $assignments
                filters = $filters
                tags = $tags
            }
            $backupConfigurations += $backupConfiguration
        }

        $backup = [PSCustomObject]@{
            configurations = $backupConfigurations
            backupDate = Get-Date
        }
        return $backup
    }
}

Export-ModuleMember -Function "Get-IntuneConfigurationProfile",
    "New-IntuneConfigurationProfile",
    "Remove-IntuneConfigurationProfile",
    "Get-IntuneConfigurationProfileSettings",
    "Compare-IntuneConfigurationProfileSettings",
    "Sync-IntuneConfigurationProfileSettings",
    "Get-IntuneConfigurationProfileAssignments",
    "New-IntuneConfigurationProfileAssignment",
    "Add-IntuneConfigurationProfileAssignment",
    "Get-IntuneFilter",
    "New-IntuneFilter",
    "Remove-IntuneFilter",
    "Get-IntuneTag",
    "New-IntuneTag",
    "Remove-IntuneTag",
    "Backup-IntuneConfigurationProfile"