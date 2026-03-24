function Set-IntuneScopeTagDescription {
<#
.SYNOPSIS
    Updates the description of an existing Intune Role Scope Tag via Microsoft Graph.

.DESCRIPTION
    PATCHes the description field on an existing Intune Role Scope Tag using Microsoft Graph, with no-change detection and WhatIf support.

.PARAMETER TagName
    The display name of the scope tag to update.

.PARAMETER Description
    The new description text to set on the scope tag.

.PARAMETER WhatIfMode
    When specified, shows what would change without applying the update.

.EXAMPLE
    # Update the description of a scope tag.
    Set-IntuneScopeTagDescription -TagName 'ZT-ClientA' -Description 'Zero Trust tag for Client A devices'

.EXAMPLE
    # Preview what would change without applying the update.
    Set-IntuneScopeTagDescription -TagName 'ZT-ClientA' -Description 'Updated description' -WhatIfMode
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $TagName,

        [Parameter(Mandatory = $true)]
        [string] $Description,

        [switch] $WhatIfMode
    )

    begin {
        $ErrorActionPreference = 'Stop'

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning 'Not connected to Microsoft Graph. Run Connect-MgGraph first.'
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

        Write-Information 'Loading existing scope tags...' -InformationAction Continue
        $existingTags = @()
        $requestUri = "$graphRoot/deviceManagement/roleScopeTags"

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

        $match = $existingTags | Where-Object displayName -eq $TagName | Select-Object -First 1

        if (-not $match) {
            throw "Scope tag '$TagName' not found."
        }

        $tagId = $match.id
        $oldDescription = $match.description

        if ($oldDescription -eq $Description) {
            $result = New-Object PSObject -Property @{
                TagName        = $TagName
                TagId          = $tagId
                OldDescription = $oldDescription
                NewDescription = $Description
                Action         = 'NO CHANGE'
            }
        }
        elseif ($WhatIfMode) {
            Write-Information "WOULD UPDATE description for scope tag '$TagName' (ID: $tagId)" -InformationAction Continue
            $result = New-Object PSObject -Property @{
                TagName        = $TagName
                TagId          = $tagId
                OldDescription = $oldDescription
                NewDescription = $Description
                Action         = 'WOULD UPDATE'
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($TagName, 'Update scope tag description (PATCH)')) {
                try {
                    Write-Information "Updating description for scope tag '$TagName' (ID: $tagId)..." -InformationAction Continue
                    $body = @{
                        description = $Description
                    } | ConvertTo-Json

                    Invoke-MgGraphRequest -Method PATCH -Uri "$graphRoot/deviceManagement/roleScopeTags/$tagId" -Body $body -ContentType 'application/json' | Out-Null

                    $result = New-Object PSObject -Property @{
                        TagName        = $TagName
                        TagId          = $tagId
                        OldDescription = $oldDescription
                        NewDescription = $Description
                        Action         = 'UPDATED'
                    }
                }
                catch {
                    Write-Error "Failed to update scope tag '$TagName': $_"
                    return
                }
            }
        }

        $result | Format-Table TagName, TagId, OldDescription, NewDescription, Action -AutoSize

        Write-Information '' -InformationAction Continue
        Write-Information 'Scope tag description operation complete.' -InformationAction Continue
    }

    end { }
}
