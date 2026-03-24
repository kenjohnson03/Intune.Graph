function Remove-IntuneScopeTag {
<#
.SYNOPSIS
    Removes one or more Intune Role Scope Tags via Microsoft Graph, skipping built-in tags.

.DESCRIPTION
    Removes Intune Role Scope Tags by display name using Microsoft Graph; built-in scope tags (e.g., Default) are safely skipped.

.PARAMETER ScopeTagName
    The display names of the scope tags to remove.

.PARAMETER WhatIfMode
    When specified, shows what would be removed without making any changes.

.EXAMPLE
    # Preview which scope tags would be removed.
    Remove-IntuneScopeTag -ScopeTagName 'ZT-ClientA','ZT-ClientB' -WhatIfMode

.EXAMPLE
    # Permanently remove the specified scope tags.
    Remove-IntuneScopeTag -ScopeTagName 'ZT-ClientA','ZT-ClientB'
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ScopeTagName,

        [switch] $WhatIfMode
    )

    begin {
        $ErrorActionPreference = 'Stop'

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning 'Not connected to Microsoft Graph. Run Connect-MgGraph first.'
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementRBAC.ReadWrite.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementRBAC.ReadWrite.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementRBAC.ReadWrite.All"'
            $script:__SkipProcessBlock = $true
            return
        }
        $script:__SkipProcessBlock = $false

        switch ($context.Environment) {
            'USGov'    { $uri = 'https://graph.microsoft.us' }
            'USGovDoD' { $uri = 'https://dod-graph.microsoft.us' }
            Default    { $uri = 'https://graph.microsoft.com' }
        }

        Write-Verbose "Using Graph environment: $($context.Environment) -> $uri"

        $graphRoot = "$uri/beta"

        $tagsUri = "$graphRoot/deviceManagement/roleScopeTags"
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        Write-Information 'Loading existing scope tags...' -InformationAction Continue
        $existingTags = @()
        $requestUri = $tagsUri

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $existingTags += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)
        }
        catch {
            Write-Error "Failed to retrieve existing scope tags: $_"
            return
        }

        $results = foreach ($name in $ScopeTagName) {
            $match = $existingTags | Where-Object displayName -eq $name | Select-Object -First 1

            if (-not $match) {
                Write-Warning "Scope tag not found: $name"
                New-Object PSObject -Property @{
                    DisplayName = $name
                    TagId       = ''
                    Action      = 'NOT FOUND'
                }
                continue
            }

            $tagId = $match.id

            if ($match.isBuiltIn -eq $true -or $tagId -eq '0') {
                Write-Warning "Skipping built-in scope tag: $name (ID: $tagId)"
                New-Object PSObject -Property @{
                    DisplayName = $match.displayName
                    TagId       = $tagId
                    Action      = 'SKIPPED (BUILT-IN)'
                }
                continue
            }

            if ($WhatIfMode) {
                Write-Information "Would remove scope tag: $name (ID: $tagId)" -InformationAction Continue
                New-Object PSObject -Property @{
                    DisplayName = $match.displayName
                    TagId       = $tagId
                    Action      = 'WOULD REMOVE'
                }
                continue
            }

            if (-not $PSCmdlet.ShouldProcess("$name (ID: $tagId)", 'Remove scope tag')) { continue }

            try {
                Write-Information "Removing scope tag: $name (ID: $tagId)" -InformationAction Continue
                Invoke-MgGraphRequest -Method DELETE -Uri "$graphRoot/deviceManagement/roleScopeTags/$tagId" | Out-Null

                New-Object PSObject -Property @{
                    DisplayName = $match.displayName
                    TagId       = $tagId
                    Action      = 'REMOVED'
                }
            }
            catch {
                Write-Error "Failed to remove scope tag '$name' (ID: $tagId): $_"
            }
        }

        $results | Sort-Object Action, DisplayName | Format-Table DisplayName, TagId, Action -AutoSize

        Write-Information '' -InformationAction Continue
        Write-Information 'Scope tag removal complete.' -InformationAction Continue
    }

    end {
    }
}
