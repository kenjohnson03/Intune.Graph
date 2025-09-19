# Write the comment-based HELP for Get-IntuneRemediationScript
<#
.SYNOPSIS
    Gets a list of Intune remediation scripts (device health scripts).

.DESCRIPTION
    Retrieves a single remediation script or a list of remediation scripts from Intune.

.PARAMETER Name
    The name of the remediation script to retrieve. This is case sensitive and uses the startswith filter operator.

.PARAMETER Id
    The id of the remediation script to retrieve.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.PARAMETER All
    Return all remediation scripts.

.EXAMPLE
    # Get all remediation scripts.
    Get-IntuneRemediationScript -All

.EXAMPLE
    # Get a remediation script by name.
    Get-IntuneRemediationScript -Name "My Remediation Script"

.EXAMPLE
    # Get a remediation script by id.
    Get-IntuneRemediationScript -Id "00000000-0000-0000-0000-000000000000"

.NOTES
    Required Graph scopes:
      - DeviceManagementScripts.Read.All
#>

function Get-IntuneRemediationScript{ 

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
        if($false -eq (Initialize-IntuneAccess -Scopes @("DeviceManagementScripts.Read.All") -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
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

    Process{

        if($All)
        {
            $scripts = @()
            $requestUri = "$uri/$graphVersion/deviceManagement/deviceHealthScripts"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $requestUri -OutputType Json | ConvertFrom-Json
                $scripts += $response.value
                $requestUri = $response.'@odata.nextLink'
            } 
            while ($null -ne $requestUri)            

            return $scripts
        }       

        if($Name)
        {

            $scripts = @()
            $requestUri = "$uri/$graphVersion/deviceManagement/deviceHealthScripts"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $requestUri -OutputType Json | ConvertFrom-Json
                $scripts += $response.value
                $requestUri = $response.'@odata.nextLink'
            } while ($null -ne $requestUri)
    
            $scriptsFilteredByName = @()
            ForEach($script in $scripts){

                If($script.displayName -like "$($Name)*"){
                    $requestUri = "$uri/$graphVersion/deviceManagement/deviceHealthScripts/$($script.id)"
                    $response = Invoke-MgRestMethod -Method Get -Uri $requestUri -OutputType Json | ConvertFrom-Json
                    $scriptsFilteredByName += $response
                } 
            }            

            return $scriptsFilteredByName
        }  
        
        if($Id)
        {
            $response = Invoke-MgRestMethod -Method Get -Uri "$uri/$graphVersion/deviceManagement/deviceHealthScripts/$($Id)" -OutputType Json | ConvertFrom-Json
            return $response
        }
    }

}
