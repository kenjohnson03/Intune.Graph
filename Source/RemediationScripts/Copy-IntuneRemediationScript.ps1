# Write the comment-based HELP for Copy-IntuneRemediationScript
<#
.SYNOPSIS
    Copy Intune Proactive Remediations (deviceHealthScripts) that include a given source scope tag.

.DESCRIPTION
    Discovers remediations tagged with -SourceScopeTagName, then clones the selected item(s) and
    applies the union of source + -DestinationScopeTagName tags. Prefers Graph v1.0 for
    deviceHealthScripts where available, falls back to beta. Supports Global, USGov, USGovDoD.

.PARAMETER SourceScopeTagName
    Display name of the scope tag to SEARCH for in existing remediations (e.g. "PRO").

.PARAMETER DestinationScopeTagName
    One or more destination scope tag display names to APPLY to the clone alongside the source tag
    (e.g. "PRO","CABN").

.PARAMETER RemediationName
    Optional remediation display name(s) to clone directly (exact, case-insensitive).
    If omitted, an interactive picker is shown.

.PARAMETER Environment
    Graph cloud to target. Valid values: Global, USGov, USGovDoD. Default: Global.

.EXAMPLE
    # Interactive picker
    Copy-IntuneRemediationScript -SourceScopeTagName "DEV" -DestinationScopeTagName "PRO","USA"

.EXAMPLE
    # Clone by name (skip picker)
    Copy-IntuneRemediationScript -SourceScopeTagName "DEV" -DestinationScopeTagName "PRO","USA" `
                                 -RemediationName "Windows 11 Remediation Script"

.EXAMPLE
    # Preview changes with WhatIf
    Copy-IntuneRemediationScript -SourceScopeTagName "DEV" -DestinationScopeTagName "PRO" -WhatIf

.NOTES
    Required Graph scopes:
      - DeviceManagementScripts.ReadWrite.All
      - DeviceManagementConfiguration.ReadWrite.All
      - DeviceManagementRBAC.ReadWrite.All
#>
function Copy-IntuneRemediationScript {
    [CmdletBinding(SupportsShouldProcess=$true, PositionalBinding=$true, DefaultParameterSetName="Interactive")]
    param(
        [Parameter(Mandatory, Position=0, ParameterSetName="Interactive")]
        [Parameter(Mandatory, Position=0, ParameterSetName="ByName")]
        [ValidateNotNullOrEmpty()]
        [string]$SourceScopeTagName,

        [Parameter(Mandatory, Position=1, ParameterSetName="Interactive")]
        [Parameter(Mandatory, Position=1, ParameterSetName="ByName")]
        [ValidateNotNullOrEmpty()]
        [string[]]$DestinationScopeTagName,

        [Parameter(Mandatory, Position=2, ParameterSetName="ByName")]
        [ValidateNotNullOrEmpty()]
        [string[]]$RemediationName,

        [Parameter()]
        [ValidateSet("Global","USGov","USGovDoD")]
        [string]$Environment = "Global"
    )
    begin {
        # 1) Ensure Graph access (matches the module pattern)
        if (Get-Command Initialize-IntuneAccess -ErrorAction SilentlyContinue) {
            if ($false -eq (Initialize-IntuneAccess -Scopes @(
                "DeviceManagementScripts.ReadWrite.All",
                "DeviceManagementConfiguration.ReadWrite.All",
                "DeviceManagementRBAC.ReadWrite.All"
            ) -Modules @("Microsoft.Graph.Authentication") -Environment $Environment)) {
                return
            }
        } else {
            if (-not (Get-MgContext)) {
                throw "Run Connect-MgGraph (with proper scopes) or include Initialize-IntuneAccess."
            }
        }

        # 2) Build cloud endpoints from -Environment
        switch ($Environment) {
            "USGov"    { $uri = "https://graph.microsoft.us" }
            "USGovDoD" { $uri = "https://dod-graph.microsoft.us" }
            default    { $uri = "https://graph.microsoft.com" }
        }
        $script:GraphV1   = "$uri/v1.0"
        $script:GraphBeta = "$uri/beta"

        # Prefer v1.0 for deviceHealthScripts; fallback to beta if listing is unavailable
        if (Test-DeviceHealthScriptsOn -Base $script:GraphV1) { $script:GraphApi = $script:GraphV1 } else { $script:GraphApi = $script:GraphBeta }
        Write-Host "Using Graph base for deviceHealthScripts: $script:GraphApi"

        # 3) Resolve scope tags & discover matching remediations
        $tags = Resolve-ScopeTags -SourceScopeTagName $SourceScopeTagName -DestinationScopeTagName $DestinationScopeTagName
        $list = Get-SourceTaggedRemediations -SourceTagId $tags.SrcId
        if (-not $list -or $list.Count -eq 0) {
            Write-Host "No remediations found with source tag '$SourceScopeTagName'." -ForegroundColor Yellow
            return
        }
    }
    process {
        if ($PSCmdlet.ParameterSetName -eq "ByName") {
            foreach ($rn in $RemediationName) {
                $sel = $list | Where-Object {
                    $nm = $_.displayName; if ([string]::IsNullOrWhiteSpace($nm)) { $nm = $_.name }
                    $nm -ieq $rn
                }
                if (-not $sel) { Write-Warning "No remediation found (with source tag '$SourceScopeTagName') named '$rn'."; continue }

                $defaultName = if ([string]::IsNullOrWhiteSpace($sel.displayName)) { $sel.name } else { $sel.displayName }
                $newName = Read-UniqueRemediationName -Default $defaultName

                if ($PSCmdlet.ShouldProcess($defaultName, "Clone as '$newName'")) {
                    try {
                        [void](Copy-OneRemediation -SourceListItem $sel -NewName $newName -RoleScopeTagIds $tags.AllIds -RoleScopeTagNamesText (($DestinationScopeTagName + $SourceScopeTagName | Select-Object -Unique) -join ", "))
                    } catch {
                        Write-Host "Clone failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
            }
            Write-Host "Done."
            return
        }

        # Interactive picker flow
        while ($true) {
            $sel = Select-RemediationByNumber -Items $list
            if ($null -eq $sel) { break }

            $resolvedName = if ([string]::IsNullOrWhiteSpace($sel.displayName)) { $sel.name } else { $sel.displayName }
            $newName = Read-UniqueRemediationName -Default $resolvedName

            if ($PSCmdlet.ShouldProcess($resolvedName, "Clone as '$newName'")) {
                try {
                    [void](Copy-OneRemediation -SourceListItem $sel -NewName $newName -RoleScopeTagIds $tags.AllIds -RoleScopeTagNamesText (($DestinationScopeTagName + $SourceScopeTagName | Select-Object -Unique) -join ", "))
                } catch {
                    Write-Host "Clone failed: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }

            $again = (Read-Host "Clone another? (y/n)").Trim().ToLowerInvariant()
            if ($again -notin @('y','yes')) { break }
        }

        Write-Host "Done."
    }
}
