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