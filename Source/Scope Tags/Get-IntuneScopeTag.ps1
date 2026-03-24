function Get-IntuneScopeTag {
<#
.SYNOPSIS
    Lists or searches Intune role scope tags.

.DESCRIPTION
    Retrieves Intune role scope tags from Microsoft Graph, with optional filtering by name or ID.

.PARAMETER TagName
    The display name of the scope tag to filter by.

.PARAMETER TagId
    The ID of the scope tag to retrieve.

.EXAMPLE
    # List all scope tags.
    Get-IntuneScopeTag

.EXAMPLE
    # Find a specific scope tag by name.
    Get-IntuneScopeTag -TagName 'ZT-ClientA'
#>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string] $TagName,
        [string] $TagId
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

        $graphRoot = "$uri/beta"

        Write-Information "Connected to: $($context.Environment) ($uri)" -InformationAction Continue
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        if ($TagId) {
            Write-Information "Getting scope tag ID: $TagId" -InformationAction Continue
            try {
                $tag = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + "/deviceManagement/roleScopeTags/$TagId")
                $results = @(
                    New-Object PSObject -Property @{
                        Id          = $tag.id
                        DisplayName = $tag.displayName
                        Description = $tag.description
                        IsBuiltIn   = $tag.isBuiltIn
                    }
                )
            }
            catch {
                Write-Error "Failed to get scope tag ID '$TagId': $_"
                return
            }
        }
        else {
            Write-Information 'Loading scope tags...' -InformationAction Continue
            $allTags = @()
            $requestUri = ($graphRoot + '/deviceManagement/roleScopeTags')

            try {
                do {
                    $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                    $allTags += $response.value
                    $nextLink = $null
                    if ($response.Keys -contains '@odata.nextLink') {
                        $nextLink = $response.'@odata.nextLink'
                    }
                    $requestUri = $nextLink
                } while ($null -ne $requestUri)
            }
            catch {
                Write-Error "Failed to retrieve scope tags: $_"
                return
            }

            if ($TagName) {
                $allTags = $allTags | Where-Object displayName -eq $TagName
            }

            $results = foreach ($tag in $allTags) {
                New-Object PSObject -Property @{
                    Id          = $tag.id
                    DisplayName = $tag.displayName
                    Description = $tag.description
                    IsBuiltIn   = $tag.isBuiltIn
                }
            }
        }

        if (-not $results -or $results.Count -eq 0) {
            Write-Information 'No scope tags found.' -InformationAction Continue
        }
        else {
            Write-Information "Found $($results.Count) scope tag(s)." -InformationAction Continue
            $results | Sort-Object Id | Format-Table Id, DisplayName, Description, IsBuiltIn -AutoSize
        }
    }

    end {
    }
}
