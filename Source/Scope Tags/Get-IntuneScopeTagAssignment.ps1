function Get-IntuneScopeTagAssignment {
<#
.SYNOPSIS
    Retrieves group assignments for an Intune scope tag.

.DESCRIPTION
    Retrieves group assignments for an Intune role scope tag from Microsoft Graph and resolves each group ID to its display name.

.PARAMETER TagName
    The display name of the scope tag whose assignments to retrieve.

.EXAMPLE
    # Retrieve all group assignments for a scope tag.
    Get-IntuneScopeTagAssignment -TagName 'ZT-ClientA'

.EXAMPLE
    # Export scope tag assignments to a CSV file.
    Get-IntuneScopeTagAssignment -TagName 'ZT-ClientB' | Export-Csv -Path .\assignments.csv -NoTypeInformation
#>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $TagName
    )

    begin {
        $ErrorActionPreference = 'Stop'

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning 'Not connected to Microsoft Graph. Run Connect-MgGraph first.'
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementRBAC.ReadWrite.All","Group.Read.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementRBAC.ReadWrite.All","Group.Read.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementRBAC.ReadWrite.All","Group.Read.All"'
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

        # --- Resolve scope tag name to ID ---
        Write-Information "Resolving scope tag '$TagName'..." -InformationAction Continue
        $allTags = @()
        $requestUri = ($graphRoot + '/deviceManagement/roleScopeTags')

        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
            $allTags += $response.value
            $nextLink = $null
            if ($response.Keys -contains '@odata.nextLink') {
                $nextLink = $response.'@odata.nextLink'
            }
            $requestUri = $nextLink
        } while ($null -ne $requestUri)

        $matchedTag = $allTags | Where-Object displayName -eq $TagName | Select-Object -First 1

        if (-not $matchedTag) {
            throw "Scope tag '$TagName' not found. Verify the name and try again."
        }

        $tagId = $matchedTag.id
        Write-Information "Found scope tag '$TagName' (ID: $tagId)" -InformationAction Continue

        # --- Retrieve assignments ---
        Write-Information "Retrieving assignments for scope tag '$TagName'..." -InformationAction Continue
        $assignments = @()
        $requestUri = ($graphRoot + "/deviceManagement/roleScopeTags/$tagId/assignments")

        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
            $assignments += $response.value
            $nextLink = $null
            if ($response.Keys -contains '@odata.nextLink') {
                $nextLink = $response.'@odata.nextLink'
            }
            $requestUri = $nextLink
        } while ($null -ne $requestUri)

        if ($assignments.Count -eq 0) {
            Write-Information "No group assignments found for scope tag '$TagName'." -InformationAction Continue
            return
        }

        Write-Information "Found $($assignments.Count) assignment(s). Resolving group names..." -InformationAction Continue

        # --- Build results with group name resolution ---
        $results = foreach ($assignment in $assignments) {
            $groupId = $assignment.target.groupId
            $assignmentId = $assignment.id
            $groupDisplayName = '(unable to resolve)'

            try {
                $groupResponse = Invoke-MgGraphRequest -Method GET -Uri ($graphRoot + "/groups/$($groupId)?`$select=id,displayName")
                $groupDisplayName = $groupResponse.displayName
            }
            catch {
                Write-Warning "Could not resolve group ID '$groupId': $_"
                $groupDisplayName = "(unresolved: $groupId)"
            }

            New-Object PSObject -Property @{
                TagName          = $TagName
                TagId            = $tagId
                GroupDisplayName = $groupDisplayName
                GroupId          = $groupId
                AssignmentId     = $assignmentId
            }
        }

        $results | Format-Table TagName, TagId, GroupDisplayName, GroupId, AssignmentId -AutoSize

        Write-Information '' -InformationAction Continue
        Write-Information 'Scope tag assignment retrieval complete.' -InformationAction Continue
    }

    end {
    }
}
