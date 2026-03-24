function Remove-IntuneRoleDefinition {
<#
.SYNOPSIS
    Deletes one or more custom Intune Role Definitions via Microsoft Graph, skipping built-in roles.

.DESCRIPTION
    Deletes custom Intune Role Definitions by display name using Microsoft Graph; built-in role definitions are safely skipped.

.PARAMETER RoleNames
    The display names of the custom role definitions to delete.

.PARAMETER WhatIfMode
    When specified, shows what would be deleted without making any changes.

.EXAMPLE
    # Preview which role definitions would be deleted.
    Remove-IntuneRoleDefinition -RoleNames @("HelpDesk Reader","App Manager") -WhatIfMode

.EXAMPLE
    # Permanently delete the specified custom role definitions.
    Remove-IntuneRoleDefinition -RoleNames @("HelpDesk Reader","App Manager")
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $RoleNames,

        [switch] $WhatIfMode
    )

    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementRBAC.ReadWrite.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementRBAC.ReadWrite.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementRBAC.ReadWrite.All"'
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

        $rolesUri = "$graphRoot/deviceManagement/roleDefinitions"
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        Write-Information "Loading existing role definitions..." -InformationAction Continue
        $existingRoles = @()
        $requestUri = $rolesUri

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $existingRoles += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)
        }
        catch {
            Write-Error "Failed to retrieve existing role definitions: $_"
            return
        }

        $results = foreach ($name in $RoleNames) {
            $match = $existingRoles | Where-Object displayName -eq $name | Select-Object -First 1

            if (-not $match) {
                Write-Warning "Role definition not found: $name"
                New-Object PSObject -Property @{
                    DisplayName = $name
                    RoleId      = ""
                    Action      = "NOT FOUND"
                }
                continue
            }

            $roleId = $match.id

            if ($match.isBuiltIn -eq $true -or $match.isBuiltInRoleDefinition -eq $true) {
                Write-Warning "Skipping built-in role definition: $name (ID: $roleId)"
                New-Object PSObject -Property @{
                    DisplayName = $match.displayName
                    RoleId      = $roleId
                    Action      = "SKIPPED (BUILT-IN)"
                }
                continue
            }

            if ($WhatIfMode) {
                Write-Information "Would delete role definition: $name (ID: $roleId)" -InformationAction Continue
                New-Object PSObject -Property @{
                    DisplayName = $match.displayName
                    RoleId      = $roleId
                    Action      = "WOULD DELETE"
                }
                continue
            }

            if (-not $PSCmdlet.ShouldProcess("role definition '$name' (ID: $roleId)", "Delete")) {
                continue
            }

            try {
                Write-Information "Deleting role definition: $name (ID: $roleId)" -InformationAction Continue
                Invoke-MgGraphRequest -Method DELETE -Uri "$graphRoot/deviceManagement/roleDefinitions/$roleId" | Out-Null

                New-Object PSObject -Property @{
                    DisplayName = $match.displayName
                    RoleId      = $roleId
                    Action      = "DELETED"
                }
            }
            catch {
                Write-Error "Failed to delete role definition '$name' (ID: $roleId): $_"
            }
        }

        $results | Sort-Object Action, DisplayName | Format-Table DisplayName, RoleId, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Role definition removal complete." -InformationAction Continue
    }

    end {
    }
}
