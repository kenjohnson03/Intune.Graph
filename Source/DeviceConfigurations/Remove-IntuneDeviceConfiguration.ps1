function Remove-IntuneDeviceConfiguration {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Id
    )
    
    $uri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$Id"
    
    try {
        Invoke-MgRestMethod -Uri $uri -Method Delete -OutputType Json | ConvertFrom-Json -Depth 50
        Write-Host "Device configuration with ID $Id has been deleted."
    }
    catch {
        Write-Host "Failed to delete device configuration with ID $Id. Error: $($_.Exception.Message)"
    }
}