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