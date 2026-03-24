function New-IntuneScopeTag {
<#
.SYNOPSIS
    Creates Intune role scope tags with auto-generated descriptions.

.DESCRIPTION
    Creates one or more Intune role scope tags via Microsoft Graph, skipping any tags that already exist.

.PARAMETER ScopeTagName
    The display names of the scope tags to create.

.PARAMETER DescriptionPrefix
    The text prepended to each tag name to form the description in the format "<DescriptionPrefix>: <TagName>". Defaults to "Automated scope tag".

.PARAMETER WhatIfMode
    When specified, shows what would be created without making changes.

.EXAMPLE
    # Create multiple scope tags.
    New-IntuneScopeTag -ScopeTagName 'ZT-ClientA','ZT-ClientB'

.EXAMPLE
    # Create a scope tag with a custom description prefix.
    New-IntuneScopeTag -ScopeTagName 'ZT-ClientA' -DescriptionPrefix 'Zero Trust'
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ScopeTagName,

        [string] $DescriptionPrefix = 'Automated scope tag',

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

        Write-Information "Found $($existingTags.Count) existing scope tags." -InformationAction Continue

        $results = foreach ($name in $ScopeTagName) {
            $desiredDescription = "${DescriptionPrefix}: $name"
            $match = $existingTags | Where-Object displayName -eq $name | Select-Object -First 1

            if (-not $match) {
                if ($WhatIfMode) {
                    New-Object PSObject -Property @{
                        DisplayName = $name
                        TagId       = ''
                        Action      = 'WOULD CREATE'
                        Description = $desiredDescription
                    }
                    continue
                }

                if (-not $PSCmdlet.ShouldProcess($name, 'Create scope tag')) { continue }

                try {
                    Write-Information "Creating scope tag: $name" -InformationAction Continue
                    $body = @{
                        displayName = $name
                        description = $desiredDescription
                    } | ConvertTo-Json

                    $created = Invoke-MgGraphRequest -Method POST -Uri $tagsUri -Body $body -ContentType 'application/json'

                    New-Object PSObject -Property @{
                        DisplayName = $created.displayName
                        TagId       = $created.id
                        Action      = 'CREATED'
                        Description = $created.description
                    }
                }
                catch {
                    Write-Error "Failed to create scope tag '$name': $_"
                }
                continue
            }

            New-Object PSObject -Property @{
                DisplayName = $match.displayName
                TagId       = $match.id
                Action      = 'NO CHANGE'
                Description = $match.description
            }
        }

        $results | Sort-Object Action, DisplayName | Format-Table DisplayName, TagId, Action, Description -AutoSize

        Write-Information '' -InformationAction Continue
        Write-Information 'Scope tag operation complete.' -InformationAction Continue
    }

    end {
    }
}
