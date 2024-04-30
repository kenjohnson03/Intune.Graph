<#
.SYNOPSIS
    Gets a list of Intune compliance policies.

.DESCRIPTION
    Retrieves a single compliance policy or a list of compliance policies from Intune.

.PARAMETER Name
    The name of the compliance policy to retrieve. This is case sensitive and uses the startswith filter operator.

.PARAMETER Id
    The id of the compliance policy to retrieve.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.PARAMETER All
    Return all compliance policies.

.EXAMPLE
    # Get all compliance policies.
    Get-IntuneCompliancepolicy -All

.EXAMPLE
    # Get a compliance policy by name.
    Get-IntuneCompliancepolicy -Name "Mycompliancepolicy"

.EXAMPLE
    # Get a compliance policy by id.
    Get-IntuneCompliancepolicy -Id "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Get all compliance policies in the USGov environment.
    Get-IntuneCompliancepolicy -All -Environment USGov
#>

function Get-IntuneCompliancePolicy{ 

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
            [Parameter(ParameterSetName="Name")]
            [Parameter(ParameterSetName="Id")]
            [Parameter(ParameterSetName="All")]
            [switch]$includeScheduledActionsForRule,
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

    Process{

        if($All)
        {
            $policies = @()
            $reqeustUri = "$uri/$graphVersion/deviceManagement/deviceCompliancePolicies?`$expand=ScheduledActionsForRule(`$expand=scheduledActionConfigurations)"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $reqeustUri -OutputType Json | ConvertFrom-Json
                $policies += $response.value
                $reqeustUri = $response.'@odata.nextLink'
            } 
            while ($null -ne $reqeustUri)            

            return $policies
        }       

        if($Name)
        {

            $policies = @()
            $reqeustUri = "$uri/$graphVersion/deviceManagement/deviceCompliancePolicies"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $reqeustUri -OutputType Json | ConvertFrom-Json
                $policies += $response.value
                $reqeustUri = $response.'@odata.nextLink'
            } while ($null -ne $reqeustUri)
    
            $policiesFilterByName = @()
            ForEach($policy in $policies){

                If($policy.displayName -like "$($name)*"){
                    $reqeustUri = "$uri/$graphVersion/deviceManagement/deviceCompliancePolicies/$($policy.id)?`$expand=ScheduledActionsForRule(`$expand=scheduledActionConfigurations)"
                    $response = Invoke-MgRestMethod -Method Get -Uri $reqeustUri -OutputType Json | ConvertFrom-Json
                    $policiesFilterByName += $response
                } 
            }            

            return $policiesFilterByName
        }  
        
        if($Id)
        {
            $response = Invoke-MgRestMethod -Method Get -Uri "$uri/$graphVersion/deviceManagement/deviceCompliancePolicies/$($Id)?`$expand=ScheduledActionsForRule(`$expand=scheduledActionConfigurations)" -OutputType Json | ConvertFrom-Json
            return $response
        }
    }

}


