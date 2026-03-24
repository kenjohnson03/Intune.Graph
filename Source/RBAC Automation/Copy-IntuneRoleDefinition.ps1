function Copy-IntuneRoleDefinition {
<#
.SYNOPSIS
    Clones an Intune RBAC role definition into a new custom role.

.DESCRIPTION
    Copies all rolePermissions from an existing built-in or custom role definition (deviceManagement/roleDefinitions) into a newly created custom role.

.PARAMETER SourceRoleName
    The display name of the role definition to clone from.

.PARAMETER NewRoleName
    The display name for the new custom role. Defaults to "Copy of <SourceRoleName>".

.PARAMETER Description
    The description for the new role. Defaults to "Cloned from '<SourceRoleName>' on <date>".

.PARAMETER ScopeTagNames
    The scope tag display names to associate with the new role. Defaults to the source role's existing scope tags.

.PARAMETER WhatIfMode
    Previews what would be cloned without making any changes.

.EXAMPLE
    # Clone a built-in role using the default generated name.
    Copy-IntuneRoleDefinition -SourceRoleName "Help Desk Operator"

.EXAMPLE
    # Clone a role with a specific name and preview the result first.
    Copy-IntuneRoleDefinition -SourceRoleName "Help Desk Operator" -NewRoleName "Custom Help Desk" -WhatIfMode
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $SourceRoleName,

        [string] $NewRoleName,

        [string] $Description,

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
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        # --- Paginate role definitions and find source role ---
        Write-Information "Loading role definitions..." -InformationAction Continue
        $allRoles = @()
        $requestUri = "$graphRoot/deviceManagement/roleDefinitions"

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $allRoles += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)
        }
        catch {
            Write-Error "Failed to retrieve role definitions: $_"
            return
        }

        Write-Information "Found $($allRoles.Count) role definitions." -InformationAction Continue

        $sourceRole = $allRoles | Where-Object displayName -eq $SourceRoleName | Select-Object -First 1
        if (-not $sourceRole) {
            throw "Source role definition '$SourceRoleName' not found."
        }

        Write-Information "Found source role: $($sourceRole.displayName) (ID: $($sourceRole.id))" -InformationAction Continue

        # --- Get full details including rolePermissions ---
        Write-Information "Retrieving full role details..." -InformationAction Continue
        try {
            $sourceDetails = Invoke-MgGraphRequest -Method GET -Uri "$graphRoot/deviceManagement/roleDefinitions/$($sourceRole.id)"
        }
        catch {
            Write-Error "Failed to retrieve source role details: $_"
            return
        }

        # --- Determine new role name ---
        if (-not $NewRoleName) {
            $NewRoleName = "Copy of $SourceRoleName"
        }

        # --- Check if NewRoleName already exists, append timestamp if so ---
        $nameMatch = $allRoles | Where-Object displayName -eq $NewRoleName | Select-Object -First 1
        if ($nameMatch) {
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $NewRoleName = "$NewRoleName - $timestamp"
            Write-Information "Role named '$($nameMatch.displayName)' already exists. Using '$NewRoleName' instead." -InformationAction Continue
        }

        # --- Determine description ---
        if (-not $Description) {
            $Description = "Cloned from '$SourceRoleName' on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        }

        # --- Resolve scope tags ---
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
        elseif ($sourceDetails.roleScopeTagIds -and $sourceDetails.roleScopeTagIds.Count -gt 0) {
            $scopeTagIds = @($sourceDetails.roleScopeTagIds)
        }

        # --- Build POST body with rolePermissions copied from source ---
        if ($WhatIfMode) {
            Write-Information "WOULD CLONE role definition '$SourceRoleName' -> '$NewRoleName'" -InformationAction Continue
            $result = New-Object PSObject -Property @{
                SourceRole = $SourceRoleName
                NewRole    = $NewRoleName
                RoleId     = ""
                Action     = "WOULD CLONE"
            }
        }
        else {
            if (-not $PSCmdlet.ShouldProcess("role definition '$SourceRoleName' -> '$NewRoleName'", "Clone")) {
                return
            }
            try {
                Write-Information "Cloning role definition: $SourceRoleName -> $NewRoleName" -InformationAction Continue
                $body = @{
                    "@odata.type"   = "#microsoft.graph.roleDefinition"
                    displayName     = $NewRoleName
                    description     = $Description
                    roleScopeTagIds = $scopeTagIds
                    rolePermissions = @($sourceDetails.rolePermissions)
                } | ConvertTo-Json -Depth 10

                $created = Invoke-MgGraphRequest -Method POST -Uri "$graphRoot/deviceManagement/roleDefinitions" -Body $body -ContentType "application/json"

                $result = New-Object PSObject -Property @{
                    SourceRole = $SourceRoleName
                    NewRole    = $created.displayName
                    RoleId     = $created.id
                    Action     = "CLONED"
                }
            }
            catch {
                Write-Error "Failed to clone role definition '$SourceRoleName': $_"
                return
            }
        }

        $result | Format-Table SourceRole, NewRole, RoleId, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Role definition clone operation complete." -InformationAction Continue
    }

    end {
    }
}
