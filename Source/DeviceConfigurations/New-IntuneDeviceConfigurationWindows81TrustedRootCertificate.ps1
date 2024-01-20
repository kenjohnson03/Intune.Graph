
function New-IntuneDeviceConfigurationWindows81TrustedRootCertificate
{
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Description,
        [Parameter(Mandatory)]
        [string]$Base64TrustedRootCertificate,
        [string]$DestinationStore="computerCertStoreRoot",
        [string]$FileName,
        [string[]]$RoleScopeTagIds=@("0"),
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
        $resource = "deviceManagement/deviceConfigurations"
    }
    process 
    {
        $body = @{}
        $body.'@odata.type' = "#microsoft.graph.windows81TrustedRootCertificate"
        $body.trustedRootCertificate = $Base64TrustedRootCertificate
        $body.displayName = $Name
        $body.destinationStore = $DestinationStore

        if($FileName)
        {
            $body.fileName = $FileName
        }
        
        if($RoleScopeTagIds)
        {
            $body.roleScopeTagIds = $RoleScopeTagIds
        }

        $response = Invoke-MgRestMethod -Method Post -Uri "$uri/$graphVersion/$resource" -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json -Depth 50
        return $response
    }
}