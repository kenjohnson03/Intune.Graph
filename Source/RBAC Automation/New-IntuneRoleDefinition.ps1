function New-IntuneRoleDefinition {
<#
.SYNOPSIS
    Creates a custom Intune role definition with specified permissions.

.DESCRIPTION
    Creates a custom Intune role definition via Microsoft Graph, skipping creation if a role with the same name already exists.

.PARAMETER RoleName
    The display name of the custom role definition to create.

.PARAMETER Description
    The description for the role definition.

.PARAMETER Permissions
    The Intune RBAC permission action strings to grant to the role.

.PARAMETER ScopeTagNames
    The scope tag display names to associate with the role definition. Defaults to the Default scope tag ("0") when not specified.

.PARAMETER WhatIfMode
    When specified, shows what would be created without making changes.

.EXAMPLE
    # Create a custom role with a single permission.
    New-IntuneRoleDefinition -RoleName "HelpDesk Reader" -Permissions @("microsoft.intune_deviceConfigurations_read")

.EXAMPLE
    # Preview creating a role with multiple permissions scoped to a specific tag.
    New-IntuneRoleDefinition -RoleName "App Manager" -Permissions @("microsoft.intune_managedApps_assign","microsoft.intune_managedApps_read") -ScopeTagNames @("ZT-ClientA") -WhatIfMode
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RoleName,

        [string] $Description = "",

        [Parameter(Mandatory = $true)]
        [string[]] $Permissions,

        [string[]] $ScopeTagNames,

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

        Write-Information "Found $($existingRoles.Count) existing role definitions." -InformationAction Continue

        $match = $existingRoles | Where-Object displayName -eq $RoleName | Select-Object -First 1

        if ($match) {
            $result = New-Object PSObject -Property @{
                DisplayName = $match.displayName
                RoleId      = $match.id
                Action      = "NO CHANGE"
                Description = $match.description
            }

            $result | Format-Table DisplayName, RoleId, Action, Description -AutoSize

            Write-Information "" -InformationAction Continue
            Write-Information "Role definition operation complete." -InformationAction Continue
            return
        }

        # Resolve scope tag IDs
        $scopeTagIds = @("0")
        if ($ScopeTagNames -and $ScopeTagNames.Count -gt 0) {
            Write-Information "Resolving scope tags..." -InformationAction Continue
            $existingTags = @()
            $tagsRequestUri = "$graphRoot/deviceManagement/roleScopeTags"

            try {
                do {
                    $tagsResponse = Invoke-MgGraphRequest -Method GET -Uri $tagsRequestUri
                    $existingTags += $tagsResponse.value
                    $tagsNextLink = $null
                    if ($tagsResponse.Keys -contains '@odata.nextLink') {
                        $tagsNextLink = $tagsResponse.'@odata.nextLink'
                    }
                    $tagsRequestUri = $tagsNextLink
                } while ($null -ne $tagsRequestUri)
            }
            catch {
                Write-Error "Failed to retrieve scope tags: $_"
                return
            }

            $scopeTagIds = @()
            foreach ($tagName in $ScopeTagNames) {
                $tagMatch = $existingTags | Where-Object displayName -eq $tagName | Select-Object -First 1
                if (-not $tagMatch) {
                    Write-Warning "Scope tag not found: $tagName - skipping."
                    continue
                }
                $scopeTagIds += $tagMatch.id
            }

            if ($scopeTagIds.Count -eq 0) {
                Write-Warning "No valid scope tags resolved. Defaulting to Default tag (0)."
                $scopeTagIds = @("0")
            }
        }

        if ($WhatIfMode) {
            $result = New-Object PSObject -Property @{
                DisplayName = $RoleName
                RoleId      = ""
                Action      = "WOULD CREATE"
                Description = $Description
            }

            $result | Format-Table DisplayName, RoleId, Action, Description -AutoSize

            Write-Information "" -InformationAction Continue
            Write-Information "Role definition operation complete." -InformationAction Continue
            return
        }

        if (-not $PSCmdlet.ShouldProcess("role definition '$RoleName'", "Create")) {
            return
        }

        try {
            Write-Information "Creating role definition: $RoleName" -InformationAction Continue
            $body = @{
                "@odata.type"    = "#microsoft.graph.roleDefinition"
                displayName      = $RoleName
                description      = $Description
                roleScopeTagIds  = $scopeTagIds
                rolePermissions  = @(
                    @{
                        resourceActions = @(
                            @{
                                allowedResourceActions = $Permissions
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 10

            $created = Invoke-MgGraphRequest -Method POST -Uri $rolesUri -Body $body -ContentType "application/json"

            $result = New-Object PSObject -Property @{
                DisplayName = $created.displayName
                RoleId      = $created.id
                Action      = "CREATED"
                Description = $created.description
            }
        }
        catch {
            Write-Error "Failed to create role definition '$RoleName': $_"
            return
        }

        $result | Format-Table DisplayName, RoleId, Action, Description -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Role definition operation complete." -InformationAction Continue
    }

    end {
    }
}
