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
        return $response.value
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
        [string[]]$RoleScopeTags=@(0),
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

function New-IntuneTag
{
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Name,
        [Parameter(Position=1)]
        [string]$TagDescription,
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
            description = $TagDescription
        }

        $response = Invoke-MgRestMethod -Method Post -Uri "$uri/$graphVersion/deviceManagement/roleScopeTags" -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json
        return $response
    }
}

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
    "Get-IntuneFilter",
    "New-IntuneFilter",
    "Remove-IntuneFilter",
    "Get-IntuneTag",
    "New-IntuneTag",
    "Remove-IntuneTag",
    "Backup-IntuneConfigurationProfile"