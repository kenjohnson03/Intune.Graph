# Write the comment-based HELP for Set-IntuneDevicePrimaryUser

<#
.SYNOPSIS
Sets the primary user of an Intune device.

.DESCRIPTION
Sets the primary user of an Intune device.

.PARAMETER DeviceId
The device ID of the device to set the primary user for.

.PARAMETER UserId
The user ID of the user to set as the primary user.

.PARAMETER Environment
The environment to use for the request. Defaults to Global.

.EXAMPLE
PS C:\> Set-IntuneDevicePrimaryUser -DeviceId "12345678-1234-1234-1234-123456789012" -UserId "12345678-1234-1234-1234-123456789012"
#>
function Set-IntuneDevicePrimaryUser
{
    param (
        [Parameter(Mandatory, Position=0)]
        [string]$DeviceId,
        [Parameter(Mandatory, Position=1)]
        [string]$UserId,
        [switch]$BatchRequestOutput,
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global"
    )
    begin {
        $scopes = @("DeviceManagementConfiguration.ReadWrite.All")
        if($false -eq (Initialize-IntuneAccess -Scopes $scopes -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
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
        $requestUri = "$uri/$graphVersion/deviceManagement/managedDevices('$DeviceId')/users/`$ref"

        $body = @{}
        $body.'@odata.id' = "$uri/$graphVersion/users/$UserId"

        if($BatchRequestOutput)
        {
            return New-GraphBatchRequest -Method POST -Uri "/deviceManagement/managedDevices('$DeviceId')/users/`$ref" -Body $body -Headers @{'Content-Type' = 'application/json'}
        }       
        else 
        {
            return Invoke-MgRestMethod -Method Post -Uri $requestUri -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json
        }        
    }
}