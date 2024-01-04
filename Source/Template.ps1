
# Write the comment-based HELP for New-IntuneConfigurationProfile

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