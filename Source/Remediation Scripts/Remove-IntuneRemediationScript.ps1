function Remove-IntuneRemediationScript {
<#
.SYNOPSIS
    Deletes one or more Intune Remediation Scripts (deviceHealthScripts) via Microsoft Graph.

.DESCRIPTION
    Deletes one or more Intune Remediation Scripts by display name using Microsoft Graph, with environment auto-detection and WhatIf support.

.PARAMETER ScriptNames
    The display names of the remediation scripts to delete.

.PARAMETER WhatIfMode
    When specified, shows what would be deleted without making any changes.

.EXAMPLE
    # Preview which remediation scripts would be deleted.
    Remove-IntuneRemediationScript -ScriptNames @("Old Script 1","Old Script 2") -WhatIfMode

.EXAMPLE
    # Permanently delete the specified remediation scripts.
    Remove-IntuneRemediationScript -ScriptNames @("Old Script 1","Old Script 2")
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ScriptNames,

        [switch] $WhatIfMode
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

        Write-Information "Connected to: $($context.Environment) ($uri)" -InformationAction Continue

        $scriptsUri = "$graphRoot/deviceManagement/deviceHealthScripts"
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        Write-Information "Loading existing remediation scripts..." -InformationAction Continue
        $existingScripts = @()
        $requestUri = $scriptsUri

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $existingScripts += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)
        }
        catch {
            Write-Error "Failed to retrieve existing remediation scripts: $_"
            return
        }

        $results = foreach ($name in $ScriptNames) {
            $match = $existingScripts | Where-Object displayName -eq $name | Select-Object -First 1

            if (-not $match) {
                Write-Warning "Remediation script not found: $name"
                New-Object PSObject -Property @{
                    DisplayName = $name
                    ScriptId    = ""
                    Action      = "NOT FOUND"
                }
                continue
            }

            $scriptId = $match.id

            if ($WhatIfMode) {
                Write-Information "Would delete remediation script: $name (ID: $scriptId)" -InformationAction Continue
                New-Object PSObject -Property @{
                    DisplayName = $match.displayName
                    ScriptId    = $scriptId
                    Action      = "WOULD DELETE"
                }
                continue
            }

            if ($PSCmdlet.ShouldProcess($name, "Delete Intune remediation script (ID: $scriptId)")) {
                try {
                    Write-Information "Deleting remediation script: $name (ID: $scriptId)" -InformationAction Continue
                    Invoke-MgGraphRequest -Method DELETE -Uri "$graphRoot/deviceManagement/deviceHealthScripts/$scriptId" | Out-Null

                    New-Object PSObject -Property @{
                        DisplayName = $match.displayName
                        ScriptId    = $scriptId
                        Action      = "DELETED"
                    }
                }
                catch {
                    Write-Error "Failed to delete remediation script '$name' (ID: $scriptId): $_"
                }
            }
        }

        $results | Sort-Object Action, DisplayName | Format-Table DisplayName, ScriptId, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Remediation script removal complete." -InformationAction Continue
    }

    end { }
}
