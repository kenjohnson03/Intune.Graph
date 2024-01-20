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