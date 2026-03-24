function Set-IntuneRemediationScriptDescription {
<#
.SYNOPSIS
    Updates the description of an existing Intune Remediation Script via Microsoft Graph.

.DESCRIPTION
    PATCHes the description field on an existing Intune Remediation Script
    (deviceManagement/deviceHealthScripts) using Microsoft Graph, with no-change
    detection and WhatIf support.

.PARAMETER ScriptName
    The exact display name of the remediation script to update.

.PARAMETER Description
    The new description text to set on the remediation script.

.PARAMETER WhatIfMode
    When specified, shows what would change without applying the update.

.EXAMPLE
    # Update the description of a remediation script.
    Set-IntuneRemediationScriptDescription -ScriptName 'CFA 5' -Description 'Remediates CFA control 5 compliance settings'

.EXAMPLE
    # Preview what would change without applying the update.
    Set-IntuneRemediationScriptDescription -ScriptName 'CFA 5' -Description 'Updated description' -WhatIfMode
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ScriptName,

        [Parameter(Mandatory = $true)]
        [string] $Description,

        [switch] $WhatIfMode
    )

    begin {
        $ErrorActionPreference = 'Stop'

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning 'Not connected to Microsoft Graph. Run Connect-MgGraph first.'
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementConfiguration.ReadWrite.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementConfiguration.ReadWrite.All"'
            $script:__SkipProcessBlock = $true
            return
        }
        $script:__SkipProcessBlock = $false

        switch ($context.Environment) {
            'USGov'    { $uri = 'https://graph.microsoft.us' }
            'USGovDoD' { $uri = 'https://dod-graph.microsoft.us' }
            Default    { $uri = 'https://graph.microsoft.com' }
        }
        $graphRoot = "$uri/beta"

        Write-Information "Connected to: $($context.Environment) ($uri)" -InformationAction Continue
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        Write-Information "Resolving remediation script '$ScriptName'..." -InformationAction Continue
        $allScripts = @()
        $requestUri = "$graphRoot/deviceManagement/deviceHealthScripts"

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $allScripts += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)
        }
        catch {
            Write-Error "Failed to retrieve remediation scripts: $_"
            return
        }

        $match = $allScripts | Where-Object displayName -eq $ScriptName | Select-Object -First 1

        if (-not $match) {
            throw "Remediation script '$ScriptName' not found. Verify the name and try again."
        }

        $scriptId     = $match.id
        $oldDescription = $match.description

        if ($oldDescription -eq $Description) {
            $result = New-Object PSObject -Property ([ordered]@{
                ScriptName     = $ScriptName
                ScriptId       = $scriptId
                OldDescription = $oldDescription
                NewDescription = $Description
                Action         = 'NO CHANGE'
            })
        }
        elseif ($WhatIfMode) {
            Write-Information "WOULD UPDATE description for '$ScriptName' (ID: $scriptId)" -InformationAction Continue
            $result = New-Object PSObject -Property ([ordered]@{
                ScriptName     = $ScriptName
                ScriptId       = $scriptId
                OldDescription = $oldDescription
                NewDescription = $Description
                Action         = 'WOULD UPDATE'
            })
        }
        else {
            if ($PSCmdlet.ShouldProcess($ScriptName, 'Update remediation script description (PATCH)')) {
                try {
                    Write-Information "Updating description for '$ScriptName' (ID: $scriptId)..." -InformationAction Continue
                    $body = @{ description = $Description } | ConvertTo-Json

                    Invoke-MgGraphRequest -Method PATCH -Uri "$graphRoot/deviceManagement/deviceHealthScripts/$scriptId" -Body $body -ContentType 'application/json' | Out-Null

                    $result = New-Object PSObject -Property ([ordered]@{
                        ScriptName     = $ScriptName
                        ScriptId       = $scriptId
                        OldDescription = $oldDescription
                        NewDescription = $Description
                        Action         = 'UPDATED'
                    })
                }
                catch {
                    Write-Error "Failed to update description for '$ScriptName': $_"
                    return
                }
            }
        }

        $result | Format-Table ScriptName, ScriptId, OldDescription, NewDescription, Action -AutoSize

        Write-Information '' -InformationAction Continue
        Write-Information 'Remediation script description update complete.' -InformationAction Continue
    }

    end { }
}
