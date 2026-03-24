function Remove-IntuneRoleAssignment {
<#
.SYNOPSIS
    Deletes one or more Intune RBAC role assignments by display name via Microsoft Graph.

.DESCRIPTION
    Resolves a role definition by display name, then deletes each matching role assignment by display name with optional WhatIf support.

.PARAMETER RoleName
    The display name of the role definition.

.PARAMETER AssignmentNames
    The display names of the role assignments to delete.

.PARAMETER WhatIfMode
    When specified, shows what would be deleted without making any changes.

.EXAMPLE
    # Delete a role assignment from a specific role.
    Remove-IntuneRoleAssignment -RoleName "Help Desk Operator" -AssignmentNames @("HD-OldClient")

.EXAMPLE
    # Preview what would be deleted without making changes.
    Remove-IntuneRoleAssignment -RoleName "Help Desk Operator" -AssignmentNames @("HD-OldClient") -WhatIfMode
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RoleName,

        [Parameter(Mandatory = $true)]
        [string[]] $AssignmentNames,

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

        # --- Resolve role definition name to ID ---
        Write-Information "Resolving role definition '$RoleName'..." -InformationAction Continue
        $rolesUri = "$graphRoot/deviceManagement/roleDefinitions"
        $allRoles = @()
        $requestUri = $rolesUri

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

        $role = $allRoles | Where-Object displayName -eq $RoleName | Select-Object -First 1
        if (-not $role) {
            Write-Error "Role definition '$RoleName' not found."
            return
        }

        $roleId = $role.id
        Write-Information "  Resolved '$RoleName' -> ID $roleId" -InformationAction Continue

        # --- Get assignments for this role ---
        Write-Information "Retrieving assignments for role '$RoleName'..." -InformationAction Continue
        $assignmentsUri = "$graphRoot/deviceManagement/roleDefinitions/$roleId/roleAssignments"
        $allAssignments = @()
        $requestUri = $assignmentsUri

        try {
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                $allAssignments += $response.value
                $nextLink = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $nextLink = $response.'@odata.nextLink'
                }
                $requestUri = $nextLink
            } while ($null -ne $requestUri)
        }
        catch {
            Write-Error "Failed to retrieve role assignments for '$RoleName': $_"
            return
        }

        Write-Information "  Found $($allAssignments.Count) assignment(s)." -InformationAction Continue

        # --- Process each requested assignment name ---
        $results = @()

        foreach ($assignmentName in $AssignmentNames) {
            $match = $allAssignments | Where-Object displayName -eq $assignmentName | Select-Object -First 1

            if (-not $match) {
                Write-Warning "Assignment '$assignmentName' not found for role '$RoleName'."
                $results += New-Object PSObject -Property @{
                    RoleName       = $RoleName
                    AssignmentName = $assignmentName
                    AssignmentId   = ""
                    Action         = "NOT FOUND"
                }
                continue
            }

            $assignmentId = $match.id

            if ($WhatIfMode) {
                Write-Information "  WhatIf: Would delete assignment '$assignmentName' (ID: $assignmentId)" -InformationAction Continue
                $results += New-Object PSObject -Property @{
                    RoleName       = $RoleName
                    AssignmentName = $assignmentName
                    AssignmentId   = $assignmentId
                    Action         = "WOULD DELETE"
                }
            }
            else {
                if (-not $PSCmdlet.ShouldProcess("role assignment '$assignmentName' (ID: $assignmentId)", "Delete")) {
                    continue
                }
                Write-Information "  Deleting assignment '$assignmentName' (ID: $assignmentId)..." -InformationAction Continue
                try {
                    Invoke-MgGraphRequest -Method DELETE -Uri "$graphRoot/deviceManagement/roleAssignments/$assignmentId" | Out-Null
                    $results += New-Object PSObject -Property @{
                        RoleName       = $RoleName
                        AssignmentName = $assignmentName
                        AssignmentId   = $assignmentId
                        Action         = "DELETED"
                    }
                    Write-Information "    Deleted successfully." -InformationAction Continue
                }
                catch {
                    Write-Error "Failed to delete assignment '$assignmentName' (ID: $assignmentId): $_"
                    return
                }
            }
        }

        # --- Output ---
        $results | Sort-Object Action, AssignmentName | Format-Table RoleName, AssignmentName, AssignmentId, Action -AutoSize

        Write-Information "" -InformationAction Continue
        Write-Information "Role assignment deletion complete." -InformationAction Continue
    }

    end {
    }
}
