function New-IntuneRoleAssignment {
<#
.SYNOPSIS
    Creates a new Intune RBAC role assignment.

.DESCRIPTION
    Resolves a role definition, member groups, scope groups, and scope tags, then POSTs a new role assignment to Microsoft Graph.

.PARAMETER RoleName
    The display name of the role definition to assign.

.PARAMETER AssignmentName
    The display name for the new role assignment.

.PARAMETER MemberGroupNames
    The Azure AD group display names that define who receives the permissions.

.PARAMETER ScopeGroupNames
    The Azure AD group display names that define what the assignees can manage.

.PARAMETER ScopeTagNames
    The scope tag display names to associate with the assignment. Defaults to the Default tag (ID "0") when not specified.

.PARAMETER Description
    The description for the role assignment.

.PARAMETER WhatIfMode
    When specified, shows what would be created without making changes.

.EXAMPLE
    # Create a role assignment with the default scope tag.
    New-IntuneRoleAssignment -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -MemberGroupNames @("SG-HD-Admins") -ScopeGroupNames @("SG-ClientA-Devices")

.EXAMPLE
    # Preview a role assignment with a custom scope tag.
    New-IntuneRoleAssignment -RoleName "Help Desk Operator" -AssignmentName "HD-ClientA" -MemberGroupNames @("SG-HD-Admins") -ScopeGroupNames @("SG-ClientA-Devices") -ScopeTagNames @("ZT-ClientA") -WhatIfMode
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RoleName,

        [Parameter(Mandatory = $true)]
        [string] $AssignmentName,

        [Parameter(Mandatory = $true)]
        [string[]] $MemberGroupNames,

        [Parameter(Mandatory = $true)]
        [string[]] $ScopeGroupNames,

        [string[]] $ScopeTagNames,

        [string] $Description,

        [switch] $WhatIfMode
    )

    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementRBAC.ReadWrite.All","Group.Read.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementRBAC.ReadWrite.All","Group.Read.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementRBAC.ReadWrite.All","Group.Read.All"'
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

        # --- Resolve role definition name to ID ---
        Write-Information "Resolving role definition '$RoleName'..." -InformationAction Continue
        $allRoles = @()
        $requestUri = "$graphRoot/deviceManagement/roleDefinitions"

        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
            $allRoles += $response.value
            $nextLink = $null
            if ($response.Keys -contains '@odata.nextLink') {
                $nextLink = $response.'@odata.nextLink'
            }
            $requestUri = $nextLink
        } while ($null -ne $requestUri)

        $roleMatch = $allRoles | Where-Object displayName -eq $RoleName | Select-Object -First 1
        if (-not $roleMatch) {
            throw "Role definition '$RoleName' not found. Available roles: $(($allRoles | ForEach-Object { $_.displayName }) -join ', ')"
        }

        $roleDefId = $roleMatch.id
        Write-Information "  Resolved '$RoleName' -> $roleDefId" -InformationAction Continue

        # --- Resolve member group names to IDs ---
        Write-Information "Resolving member group names..." -InformationAction Continue
        $memberIds = @()

        foreach ($groupName in $MemberGroupNames) {
            $filterUri = "$graphRoot/groups?`$filter=displayName eq '$groupName'&`$select=id,displayName"
            $groupResponse = Invoke-MgGraphRequest -Method GET -Uri $filterUri

            if (-not $groupResponse.value -or $groupResponse.value.Count -eq 0) {
                throw "Could not find Azure AD group with display name '$groupName'."
            }

            $memberIds += $groupResponse.value[0].id
            Write-Information "  Resolved '$groupName' -> $($groupResponse.value[0].id)" -InformationAction Continue
        }

        # --- Resolve scope group names to IDs ---
        Write-Information "Resolving scope group names..." -InformationAction Continue
        $scopeGroupIds = @()

        foreach ($groupName in $ScopeGroupNames) {
            $filterUri = "$graphRoot/groups?`$filter=displayName eq '$groupName'&`$select=id,displayName"
            $groupResponse = Invoke-MgGraphRequest -Method GET -Uri $filterUri

            if (-not $groupResponse.value -or $groupResponse.value.Count -eq 0) {
                throw "Could not find Azure AD group with display name '$groupName'."
            }

            $scopeGroupIds += $groupResponse.value[0].id
            Write-Information "  Resolved '$groupName' -> $($groupResponse.value[0].id)" -InformationAction Continue
        }

        # --- Resolve scope tag names to IDs ---
        $scopeTagIds = @()

        if ($ScopeTagNames -and $ScopeTagNames.Count -gt 0) {
            Write-Information "Resolving scope tag names..." -InformationAction Continue
            $allTags = @()
            $requestUri = "$graphRoot/deviceManagement/roleScopeTags"

            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $allTags += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)

            foreach ($tagName in $ScopeTagNames) {
                $tagMatch = $allTags | Where-Object displayName -eq $tagName | Select-Object -First 1
                if (-not $tagMatch) {
                    throw "Scope tag '$tagName' not found. Available tags: $(($allTags | ForEach-Object { $_.displayName }) -join ', ')"
                }

                $scopeTagIds += $tagMatch.id
                Write-Information "  Resolved '$tagName' -> $($tagMatch.id)" -InformationAction Continue
            }
        }
        else {
            $scopeTagIds = @("0")
            Write-Information "No scope tags specified; using Default (ID: 0)" -InformationAction Continue
        }

        # --- Build assignment body ---
        $assignBody = @{
            displayName                    = $AssignmentName
            description                    = $Description
            members                        = @($memberIds)
            scopeMembers                   = @($scopeGroupIds)
            scopeType                      = "resourceScope"
            roleScopeTagIds                = @($scopeTagIds)
            "roleDefinition@odata.bind"    = "$graphRoot/deviceManagement/roleDefinitions('$roleDefId')"
        } | ConvertTo-Json -Depth 10

        $assignUri = "$graphRoot/deviceManagement/roleAssignments"

        # --- Create or preview ---
        $results = @()

        $membersDisplay   = ($MemberGroupNames -join ', ')
        $scopeDisplay     = ($ScopeGroupNames -join ', ')
        $scopeTagsDisplay = if ($ScopeTagNames -and $ScopeTagNames.Count -gt 0) { ($ScopeTagNames -join ', ') } else { "Default" }

        if ($WhatIfMode) {
            Write-Information "WOULD CREATE role assignment '$AssignmentName' for role '$RoleName'" -InformationAction Continue
            $results += New-Object PSObject -Property @{
                RoleName       = $RoleName
                AssignmentName = $AssignmentName
                Members        = $membersDisplay
                ScopeGroups    = $scopeDisplay
                ScopeTags      = $scopeTagsDisplay
                Action         = "WOULD CREATE"
            }
        }
        else {
            if (-not $PSCmdlet.ShouldProcess("role assignment '$AssignmentName' for role '$RoleName'", "Create")) {
                return
            }
            try {
                Write-Information "Creating role assignment '$AssignmentName' for role '$RoleName'..." -InformationAction Continue
                Invoke-MgGraphRequest -Method POST -Uri $assignUri -Body $assignBody -ContentType "application/json" | Out-Null
                Write-Information "Role assignment created successfully." -InformationAction Continue
                $results += New-Object PSObject -Property @{
                    RoleName       = $RoleName
                    AssignmentName = $AssignmentName
                    Members        = $membersDisplay
                    ScopeGroups    = $scopeDisplay
                    ScopeTags      = $scopeTagsDisplay
                    Action         = "CREATED"
                }
            }
            catch {
                Write-Error "Failed to create role assignment '$AssignmentName': $_"
                $results += New-Object PSObject -Property @{
                    RoleName       = $RoleName
                    AssignmentName = $AssignmentName
                    Members        = $membersDisplay
                    ScopeGroups    = $scopeDisplay
                    ScopeTags      = $scopeTagsDisplay
                    Action         = "FAILED"
                }
            }
        }

        $results | Format-Table RoleName, AssignmentName, Members, ScopeGroups, ScopeTags, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Role assignment operation complete." -InformationAction Continue
    }

    end {
    }
}
