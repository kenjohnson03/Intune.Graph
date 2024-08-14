# Write the comment-based HELP for New-IntuneFilter
<#
.SYNOPSIS
    Creates a new Intune filter.

.DESCRIPTION
    Creates a new Intune filter.

.PARAMETER Name
    The name of the filter.

.PARAMETER Description
    The description of the filter.

.PARAMETER Platform
    The platform of the filter. Valid values are windows10AndLater, iOS, androidForWork, macOS, android, androidAOSP, androidMobileApplicationManagement, iOSMobileApplicationManagement.

.PARAMETER Rule
    The rule of the filter. This is a string that contains the OData filter expression.

.PARAMETER RoleScopeTagIds
    The role scope tags to assign to the filter.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Create a filter.
    New-IntuneFilter -Name "MyFilter" -Description "My Filter" -Platform "windows10AndLater" -Rule "system.deviceManufacturer -eq 'Dell'" -RoleScopeTagIds "0"

.EXAMPLE
    # Create a filter in the USGov environment.
    New-IntuneFilter -Name "MyFilter" -Description "My Filter" -Platform "windows10AndLater" -Rule "system.deviceManufacturer -eq 'Dell'" -RoleScopeTagIds "0" -Environment USGov

.EXAMPLE
    # Create a filter with multiple role scope tags.
    New-IntuneFilter -Name "MyFilter" -Description "My Filter" -Platform "windows10AndLater" -Rule "system.deviceManufacturer -eq 'Dell'" -RoleScopeTagIds "0","1"

.EXAMPLE
    # Create a filter with multiple role scope tags in the USGov environment.
    New-IntuneFilter -Name "MyFilter" -Description "My Filter" -Platform "windows10AndLater" -Rule "system.deviceManufacturer -eq 'Dell'" -RoleScopeTagIds "0","1" -Environment USGov
#>
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
        [string[]]$RoleScopeTagIds=@(0),
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