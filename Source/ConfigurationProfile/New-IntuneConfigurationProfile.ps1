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
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Description,
        [ValidateSet(
            "windows10",
            "iOS"          
        )]
        [string]$Platform,
        [string]$Technologies="mdm", 
        [Parameter(Mandatory)]
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