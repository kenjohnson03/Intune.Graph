function Get-IntuneRemediationScript {
<#
.SYNOPSIS
    Lists or searches Intune Remediation Scripts (Proactive Remediations).

.DESCRIPTION
    Retrieves Intune Remediation Scripts (deviceManagement/deviceHealthScripts) via Microsoft Graph, with optional filtering by exact display name.

.PARAMETER ScriptName
    The exact display name of the remediation script to filter by.

.EXAMPLE
    # List all remediation scripts.
    Get-IntuneRemediationScript

.EXAMPLE
    # Find a specific remediation script by exact name.
    Get-IntuneRemediationScript -ScriptName "Windows 11 Remediation"
#>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string] $ScriptName
    )

    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementConfiguration.Read.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementConfiguration.Read.All"'
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
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        Write-Information "Loading remediation scripts..." -InformationAction Continue
        $allScripts = @()
        $requestUri = ($graphRoot + '/deviceManagement/deviceHealthScripts')

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

        if ($ScriptName) {
            $allScripts = $allScripts | Where-Object displayName -eq $ScriptName
        }

        # Resolve all scope tag IDs to display names in one call
        $scopeTagMap = @{}
        try {
            $tagResponse = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + '/deviceManagement/roleScopeTags?$select=id,displayName&$top=999')
            foreach ($tag in $tagResponse.value) {
                $scopeTagMap[$tag.id] = $tag.displayName
            }
        }
        catch {
            Write-Warning "Could not resolve scope tag names: $_"
        }

        $results = foreach ($script in $allScripts) {
            $tagNames = ($script.roleScopeTagIds | ForEach-Object {
                if ($scopeTagMap.ContainsKey($_)) { $scopeTagMap[$_] } else { $_ }
            }) -join ', '

            New-Object PSObject -Property ([ordered]@{
                DisplayName = $script.displayName
                ScopeTag    = $tagNames
                Id          = $script.id
                Description = $script.description
            })
        }

        if (-not $results -or $results.Count -eq 0) {
            Write-Information "No remediation scripts found." -InformationAction Continue
        }
        else {
            Write-Information "Found $($results.Count) remediation script(s)." -InformationAction Continue
            $results | Sort-Object DisplayName | Format-Table DisplayName, ScopeTag, Id, Description -AutoSize
        }
    }

    end {
    }
}
