<#
.SYNOPSIS
Updates device extension attributes in Entra ID.

.DESCRIPTION
Updates device extension attributes in Entra ID.

.PARAMETER ObjectId
The object ID of the device to set the device extension attributes on.

.PARAMETER Environment
The environment to use for the request. Defaults to Global.

.PARAMETER Attributes
Hashtable containing the device extension attribute values to edit. Attributes are numbered 1-15, for example:
$attribs = @{
    1 = "Value for attribute 1"
    2 = "Value for attribute 2"
    15 = "Value for attribute 15"
}
Pass empty quotes to an extension attribute to clear the value.

.EXAMPLE
PS C:\> Update-DeviceExtensionAttributes -ObjectId '01234567-8901-2345-6789-012345678901' -Attributes $attribs -Environment USGov
#>
function Update-DeviceExtensionAttributes
{
    param(
            [Parameter(Mandatory = $true)]
            [string]$ObjectId,
            [ValidateSet("Global", "USGov", "USGovDoD")]
            [string]$Environment="Global",
            [Parameter(Mandatory = $true)]
            [hashtable]$Attributes            
    )
    begin {
        $scopes = @("Device.ReadWrite.All")
        if($false -eq (Initialize-IntuneAccess -Scopes $scopes -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
        {
            return
        }
        
        # Configure graph URI
        switch ($Environment) {
            "USGov" { $uri = "https://graph.microsoft.us" }
            "USGovDoD" { $uri = "https://dod-graph.microsoft.us" }
            Default { $uri = "https://graph.microsoft.com" }
        }
        
        #Use beta version of graph
        $graphVersion = "beta"

        # Initialize the body
        $body = @{
            extensionAttributes = @{}
        }
    }
    process {
        # Loop through the hashtable and add attributes dynamically
        ForEach ($key in $Attributes.Keys) {
            if ($key -match '^\d+$' -and [int]$key -ge 1 -and [int]$key -le 15) {
                $body.extensionAttributes["extensionAttribute$key"] = $Attributes[$key]
            } else {
                Write-Warning "Invalid attribute key: $key. Must be 1-15."
            }
        }

        # Convert body to JSON
        $json = $body | ConvertTo-Json -Depth 3

        #Build request URI
        $requestUri = "$uri/$graphVersion/devices/$ObjectId"

        Invoke-MgGraphRequest -Method PATCH -Body $json -Uri $requestUri
    }
}