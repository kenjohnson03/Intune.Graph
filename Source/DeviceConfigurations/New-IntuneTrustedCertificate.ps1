function New-IntuneTrustedCertificateConfiguration
{
    param(
        [Parameter(Mandatory, ParameterSetName="CertFilePath", Position=0)]
        [Parameter(Mandatory, ParameterSetName="CertProviderPath", Position=0)]
        [string]$Name,
        [Parameter(ParameterSetName="CertFilePath")]
        [Parameter(ParameterSetName="CertProviderPath")]
        [string]$Description,
        [ValidateSet(
            "windows10",
            "iOS",
            "androidEnterpriseFullyManaged",
            "macOS"    
        )]
        [string]$Platform="windows10",
        [Parameter(ParameterSetName="CertFilePath")]
        [string]$CertFilePath,
        [Parameter(ParameterSetName="CertProviderPath")]
        [string]$CertProviderPath,
        [Parameter(ParameterSetName="CertFilePath")]
        [Parameter(ParameterSetName="CertProviderPath")]
        [string]$CertFileName="cert.cer",
        [Parameter(ParameterSetName="CertFilePath")]
        [Parameter(ParameterSetName="CertProviderPath")]
        [ValidateSet("ComputerCertStoreRoot", "ComputerCertStoreIntermediate", "UserCertificateStoreIntermediate")]
        [string]$CertStore="ComputerCertStoreRoot",
        [Parameter(ParameterSetName="CertFilePath")]
        [Parameter(ParameterSetName="CertProviderPath")]
        [string[]]$RoleScopeTagIds=@("0"),
        [Parameter(ParameterSetName="CertFilePath")]
        [Parameter(ParameterSetName="CertProviderPath")]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global"
    )
    begin 
    {        
        switch ($Environment) {
            "USGov" { $uri = "https://graph.microsoft.us" }
            "USGovDoD" { $uri = "https://dod-graph.microsoft.us" }
            Default { $uri = "https://graph.microsoft.com" }
        }

        $graphVersion = "beta"
    }
    process 
    {
        $body = @{}
        if($Name)
        {
            $body.displayName = $Name
        }
        if($Description)
        {
            $body.description = $Description
        }
        if($RoleScopeTagIds)
        {
            $body.roleScopeTagIds = $RoleScopeTagIds
        }

        if(-not [string]::IsNullOrEmpty($CertFileName))
        {
            $body.certFileName = $CertFileName
        }
        else
        {
            $body.certFileName = "cert.cer"
        }

        switch($Platform)
        {
            "windows10" { $body["@odata.type"] = "#microsoft.graph.windows81TrustedRootCertificate" }
            "iOS" { $body["@odata.type"] = "#microsoft.graph.iosTrustedRootCertificate" }
            "androidEnterpriseFullyManaged" { $body["@odata.type"] = "#microsoft.graph.androidDeviceOwnerTrustedRootCertificate" }
            "macOS" { $body["@odata.type"] = "#microsoft.graph.macOSTrustedRootCertificate" }
        }

        if($Platform -eq "windows10")
        {
            switch($CertStore)
            {
                "ComputerCertStoreRoot" { $body.destinationStore = "computerCertStoreRoot" }
                "ComputerCertStoreIntermediate" { $body.destinationStore = "computerCertStoreIntermediate" }
                "UserCertificateStoreIntermediate" { $body.destinationStore = "userCertificateStoreIntermediate" }
            }
        }        

        if($CertFilePath)
        {
            if(-not (Test-Path $CertFilePath))
            {
                throw "CertFilePath does not exist"
            }
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate $CertFilePath
        }

        if($CertProviderPath)
        {
            if(-not (Test-Path $CertProviderPath))
            {
                throw "CertProviderPath does not exist"                
            }     
            $cert = Get-Item $CertProviderPath
        }

        $sb = [System.Text.StringBuilder]::new() 
        $sb.AppendLine("-----BEGIN CERTIFICATE-----") | Out-Null
        $sb.AppendLine( [System.Convert]::ToBase64String($cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))) | Out-Null
        $sb.AppendLine("-----END CERTIFICATE-----") | Out-Null
        $contentInBytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
        $certBase64 = [System.Convert]::ToBase64String($contentInBytes)

        $body.id = [Guid]::Empty.ToString()
        
        $body.trustedRootCertificate = $certBase64

        $response = Invoke-MgRestMethod -Method Post -Uri "$uri/$graphVersion/deviceManagement/deviceConfigurations" -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json
        return $response
    }
}