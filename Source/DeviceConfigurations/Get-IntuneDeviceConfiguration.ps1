function Get-IntuneDeviceConfiguration
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
            $reqeustUri = "$uri/$graphVersion/deviceManagement/deviceConfigurations"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $reqeustUri -OutputType Json | ConvertFrom-Json -Depth 50
                $configurations += $response.value
                $reqeustUri = $response.'@odata.nextLink'
            } 
            while ($null -ne $reqeustUri)            

            return $configurations
        }       

        if($Name)
        {

            $configurations = @()
            $reqeustUri = "$uri/$graphVersion/deviceManagement/deviceConfigurations?`$filter=startswith(displayName,'$Name')"
            do 
            {
                $response = Invoke-MgRestMethod -Method Get -Uri $reqeustUri -OutputType Json | ConvertFrom-Json -Depth 50
                $configurations += $response.value
                $reqeustUri = $response.'@odata.nextLink'
            } while ($null -ne $reqeustUri)            

            return $configurations
        }  
        
        if($Id)
        {
            $response = Invoke-MgRestMethod -Method Get -Uri "$uri/$graphVersion/$resource/$Id" -OutputType Json | ConvertFrom-Json -Depth 50
            return $response
        }

        write-host "No parameters specified"
        return 
    }
}