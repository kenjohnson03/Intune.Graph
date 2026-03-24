function Remove-IntunePlatformScript {
<#
.SYNOPSIS
    Removes an Intune platform script.

.DESCRIPTION
    Deletes an Intune device management script from Microsoft Graph.
    Accepts the script by GUID or display name.

.PARAMETER Id
    The GUID of the platform script to remove.

.PARAMETER Name
    The display name of the platform script to remove.

.EXAMPLE
    Remove-IntunePlatformScript -Id "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    Remove-IntunePlatformScript -Name 'WDAC TOAST'
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ById')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ById',
                   Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [string]$Name
    )

    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
            $script:__SkipProcessBlock = $true
            return
        }
        $script:__SkipProcessBlock = $false

        switch ($context.Environment) {
            "USGov"    { $uri = "https://graph.microsoft.us" }
            "USGovDoD" { $uri = "https://dod-graph.microsoft.us" }
            Default    { $uri = "https://graph.microsoft.com" }
        }
        $graphRoot = "$uri/beta"
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        # Resolve display name to GUID
        $resolvedId = $Id
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $encoded = [System.Uri]::EscapeDataString("displayName eq '$Name'")
            $found   = Invoke-MgGraphRequest -Method GET `
                           -Uri "$graphRoot/deviceManagement/deviceManagementScripts?`$filter=$encoded"
            if (-not $found.value -or $found.value.Count -eq 0) {
                Write-Warning "Platform script '$Name' was not found."
                return
            }
            $resolvedId = $found.value[0].id
        }

        if ($PSCmdlet.ShouldProcess($resolvedId, "Delete Intune platform script")) {
            Invoke-MgGraphRequest -Method DELETE -Uri "$graphRoot/deviceManagement/deviceManagementScripts/$resolvedId" | Out-Null
        }
    }

    end { }
}
