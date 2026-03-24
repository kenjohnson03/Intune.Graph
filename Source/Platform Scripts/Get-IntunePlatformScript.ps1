function Get-IntunePlatformScript {
<#
.SYNOPSIS
    Retrieves Intune platform scripts (deviceManagement/deviceManagementScripts).

.DESCRIPTION
    Gets one or all Intune platform scripts via Microsoft Graph, with optional filtering by name (partial match) or exact ID.

.PARAMETER Name
    The name to search for using a case-insensitive partial match.

.PARAMETER Id
    The exact ID of the platform script to retrieve.

.PARAMETER All
    Returns all platform scripts.

.EXAMPLE
    # Get all platform scripts.
    Get-IntunePlatformScript -All

.EXAMPLE
    # Find scripts whose name contains "Windows Update".
    Get-IntunePlatformScript -Name "Windows Update"
#>
    [CmdletBinding()]
    [OutputType([array])]
    param (
        [Parameter(Mandatory, ParameterSetName = "Name", Position = 0)]
        [string] $Name,

        [Parameter(Mandatory, ParameterSetName = "Id", Position = 1)]
        [string] $Id,

        [Parameter(ParameterSetName = "All")]
        [switch] $All
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

        if ($PSBoundParameters.Count -eq 0) {
            $All = $true
        }
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        if ($All) {
            $scripts = @()
            $requestUri = ($graphRoot + '/deviceManagement/deviceManagementScripts')
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $scripts += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)

            return $scripts
        }

        if ($Name) {
            $scripts = @()
            $requestUri = ($graphRoot + '/deviceManagement/deviceManagementScripts')
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $scripts += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)

            $scriptsFilteredByName = @()
            foreach ($script in $scripts) {
                $scriptName = if ($script.displayName) { $script.displayName } else { $script.name }
                if ($scriptName -like "*$Name*") {
                    $scriptsFilteredByName += $script
                }
            }

            return $scriptsFilteredByName
        }

        if ($Id) {
            $response = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + "/deviceManagement/deviceManagementScripts/$Id")
            return $response
        }
    }

    end {
    }
}
