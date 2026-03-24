function Get-IntuneRoleAssignment {
<#
.SYNOPSIS
    Retrieves role assignments for an Intune RBAC role definition.

.DESCRIPTION
    Gets all role assignments for a role definition (deviceManagement/roleDefinitions/{id}/roleAssignments) and resolves member groups, scope groups, and scope tags to their display names.

.PARAMETER RoleName
    The exact display name of the role definition whose assignments to retrieve.

.EXAMPLE
    # Get all role assignments for a named role.
    Get-IntuneRoleAssignment -RoleName "Help Desk Operator"

.EXAMPLE
    # Export role assignments to CSV.
    Get-IntuneRoleAssignment -RoleName "Help Desk Operator" | Export-Csv -Path .\roleassignments.csv -NoTypeInformation
#>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RoleName
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

        # --- Resolve role name to role definition ID ---
        Write-Information "Resolving role definition '$RoleName'..." -InformationAction Continue
        $allRoles = @()
        $requestUri = ($graphRoot + '/deviceManagement/roleDefinitions')

        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
            $allRoles += $response.value
            $nextLink = $null
            if ($response.Keys -contains '@odata.nextLink') {
                $nextLink = $response.'@odata.nextLink'
            }
            $requestUri = $nextLink
        } while ($null -ne $requestUri)

        $matchedRole = $allRoles | Where-Object displayName -eq $RoleName | Select-Object -First 1

        if (-not $matchedRole) {
            throw "Role definition '$RoleName' not found. Verify the name and try again."
        }

        $roleDefId = $matchedRole.id
        Write-Information "Found role definition '$RoleName' (ID: $roleDefId)" -InformationAction Continue

        # --- Retrieve role assignments ---
        Write-Information "Retrieving role assignments for '$RoleName'..." -InformationAction Continue
        $roleAssignments = @()
        $requestUri = ($graphRoot + "/deviceManagement/roleDefinitions/$roleDefId/roleAssignments")

        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
            $roleAssignments += $response.value
            $nextLink = $null
            if ($response.Keys -contains '@odata.nextLink') {
                $nextLink = $response.'@odata.nextLink'
            }
            $requestUri = $nextLink
        } while ($null -ne $requestUri)

        if ($roleAssignments.Count -eq 0) {
            Write-Information "No role assignments found for role definition '$RoleName'." -InformationAction Continue
            return
        }

        Write-Information "Found $($roleAssignments.Count) assignment(s). Resolving details..." -InformationAction Continue

        # --- Build results with name resolution ---
        $results = foreach ($roleAssignment in $roleAssignments) {
            $assignmentId = $roleAssignment.id

            # Retrieve the full assignment details
            $fullAssignment = $null
            try {
                $fullAssignment = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + "/deviceManagement/roleAssignments/$assignmentId")
            }
            catch {
                Write-Warning "Could not retrieve full assignment details for '$assignmentId': $_"
                continue
            }

            $assignmentName = $fullAssignment.displayName

            # Resolve member group IDs to display names
            $memberNames = @()
            if ($fullAssignment.members -and $fullAssignment.members.Count -gt 0) {
                foreach ($groupId in $fullAssignment.members) {
                    try {
                        $groupResponse = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + "/groups/$($groupId)?`$select=id,displayName")
                        $memberNames += $groupResponse.displayName
                    }
                    catch {
                        Write-Warning "Could not resolve member group ID '$groupId': $_"
                        $memberNames += "(unresolved: $groupId)"
                    }
                }
            }

            # Resolve resource scope group IDs to display names
            $scopeGroupNames = @()
            if ($fullAssignment.resourceScopes -and $fullAssignment.resourceScopes.Count -gt 0) {
                foreach ($groupId in $fullAssignment.resourceScopes) {
                    try {
                        $groupResponse = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + "/groups/$($groupId)?`$select=id,displayName")
                        $scopeGroupNames += $groupResponse.displayName
                    }
                    catch {
                        Write-Warning "Could not resolve scope group ID '$groupId': $_"
                        $scopeGroupNames += "(unresolved: $groupId)"
                    }
                }
            }

            # Resolve scope tag IDs to display names
            $scopeTagNames = @()
            if ($fullAssignment.roleScopeTagIds -and $fullAssignment.roleScopeTagIds.Count -gt 0) {
                foreach ($tagId in $fullAssignment.roleScopeTagIds) {
                    try {
                        $tagResponse = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + "/deviceManagement/roleScopeTags/$tagId")
                        $scopeTagNames += $tagResponse.displayName
                    }
                    catch {
                        Write-Warning "Could not resolve scope tag ID '$tagId': $_"
                        $scopeTagNames += "(unresolved: $tagId)"
                    }
                }
            }

            $scopeType = $fullAssignment.scopeType
            if (-not $scopeType) { $scopeType = $fullAssignment.'@odata.type' }

            New-Object PSObject -Property @{
                RoleName       = $RoleName
                AssignmentName = $assignmentName
                AssignmentId   = $assignmentId
                Members        = ($memberNames -join ", ")
                ScopeGroups    = ($scopeGroupNames -join ", ")
                ScopeTags      = ($scopeTagNames -join ", ")
                ScopeType      = $scopeType
            }
        }

        $results | Format-Table RoleName, AssignmentName, AssignmentId, Members, ScopeGroups, ScopeTags, ScopeType -Wrap

        Write-Information "" -InformationAction Continue
        Write-Information "Role assignment retrieval complete." -InformationAction Continue
    }

    end {
    }
}
