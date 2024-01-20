Describe "Get-IntuneDeviceConfiguration" {
    It "Gets all device configurations" {        
        {
            Get-IntuneDeviceConfiguration -All | 
            Should -Not -BeNullOrEmpty
        } | Should -Not -Throw
    }
}

Describe "New-IntuneDeviceConfigurationWindows81TrustedRootCertificate" {
    It "Creates a new device configuration" {
        { 
            $cert = "MIIC+DCCAeCgAwIBAgIQJmYfQaRgoplLJuJgBa2qGTANBgkqhkiG9w0BAQsFADAPMQ0wCwYDVQQDDARUZXN0MB4XDTI0MDEyMDE2Mzg1MVoXDTI1MDEyMDE2NTg1MVowDzENMAsGA1UEAwwEVGVzdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOuZuGEnjrAR3xZ4z4AqyKeVheNayTpjR9QhyH+mMi6Sfk0f9a4J0HaW9grXDB9/v3Z9E55uTTum6hZJYfEjvoWQs3rV5DG/e6yz3V49PZTtsCdZiS8A9rSk3yCRIDdSFaZrVWHqVqpuKr4MT0Cjh9NdpsVq7Glpk8qaHtvp08pAid+FHME5DZhEqq6k6DgQv1NnDtUMjCu8GzPz9NwzF8iQYgreA0zs7Bfo7EHVrT69ShYeuopy/aMJpoLJ5hgngNHM/d4C+AvmlGdbPgwvpfkgte1MR6GS2HsC450zIzz8lVail36T5H4jBE/8EY2197+AIO6hloPRT/0xZQnThAECAwEAAaNQME4wDgYDVR0PAQH/BAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMCBggrBgEFBQcDATAdBgNVHQ4EFgQUdvNQU3LWOLoepxujUrYVCC36zywwDQYJKoZIhvcNAQELBQADggEBAMdNS0ElBXpLuyvX384sO8CgMqz3PTAt1NSSJuFNpjoRn9OzQZ++hphzR0OphQ5ttQzsBh80mGzJ3bUS88K6IMeauNgbpwyv4wFZn7F4FU9cBwW/jTeAF6Ft4YCvHrTx8DQK5Jr8CqV37D94da9IzXG5GRZGrV5plPrmuDMGJDAdavogiypn40oiyMp5vjjSIMlWNcAHYEkKe4yend9ffb1S08nLvppfE71FTFU4lMlelf+K9PMTeUejs6FdVU1LLcOrRzZir4DssaFVw/ndJFnqVbagOPN8Sb/CcxFNjZovtz/iIsSITBZNHQEGTWs1lihx7RQFNjl2zPO+k/53Kik="
            $newConfig = New-IntuneDeviceConfigurationWindows81TrustedRootCertificate -Name "PesterTest" -Base64TrustedRootCertificate $cert -DestinationStore "computerCertStoreRoot" -FileName "FileName" -RoleScopeTagIds @('0')
            $newConfig | Should -Not -BeNullOrEmpty
        } | Should -Not -Throw
    }
}