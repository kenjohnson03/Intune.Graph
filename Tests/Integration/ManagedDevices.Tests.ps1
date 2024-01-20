Describe "Set-PrimaryUser" {
    It "Fails to set primary user if Device and User is not a GUID" {
        {
            Set-PrimaryUser -DeviceId "DeviceId" -UserId "UserId"
        } | Should -Throw
    }
}

