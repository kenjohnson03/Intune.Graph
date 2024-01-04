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