# Write the comment-based HELP for Copy-IntuneConfigurationProfile
<#
.SYNOPSIS
    Clones Intune Settings Catalog profiles and Endpoint Security intents that include a given source scope tag.

.DESCRIPTION
    Discovers policies/intents tagged with -SourceScopeTagName, then clones the selected item(s) and
    applies the union of source + -DestinationScopeTagName tags. Supports Global, USGov, USGovDoD.

.PARAMETER SourceScopeTagName
    Display name of the source scope tag to search for (e.g., "DEV").

.PARAMETER DestinationScopeTagName
    One or more scope tag display names to apply to the clone (e.g., "PRO","USA").

.PARAMETER ProfileName
    Exact policy/intent name(s) to clone directly (skip the picker). If omitted, an interactive picker is shown.

.PARAMETER Environment
    Graph cloud to target. Valid values: Global, USGov, USGovDoD. Default: Global.

.EXAMPLE
    # Interactive picker
    Copy-IntuneConfigurationProfile -SourceScopeTagName "DEV" -DestinationScopeTagName "PRO","USA"

.EXAMPLE
    # Clone by name (skip picker)
    Copy-IntuneConfigurationProfile -SourceScopeTagName "DEV" -DestinationScopeTagName "PRO" -ProfileName "USA-PRO-AV POLICY"

.EXAMPLE
    # Preview changes with WhatIf
    Copy-IntuneConfigurationProfile -SourceScopeTagName "DEV" -DestinationScopeTagName "PRO" -WhatIf

.NOTES
    Required Graph scopes:
      - DeviceManagementConfiguration.ReadWrite.All
      - DeviceManagementRBAC.ReadWrite.All
#>
function Copy-IntuneConfigurationProfile {
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
        [string[]]$ProfileName,

        [Parameter()]
        [ValidateSet("Global","USGov","USGovDoD")]
        [string]$Environment = "Global"
    )
    begin {
        # 1) Ensure Graph access
        if (Get-Command Initialize-IntuneAccess -ErrorAction SilentlyContinue) {
            if ($false -eq (Initialize-IntuneAccess -Scopes @(
                "DeviceManagementConfiguration.ReadWrite.All",
                "DeviceManagementRBAC.ReadWrite.All"
            ) -Modules @("Microsoft.Graph.Authentication") -Environment $Environment)) {
                return
            }
        } else {
            # Fallback: require existing connection
            if (-not (Get-MgContext)) {
                throw "Run Connect-MgGraph (with proper scopes) or include Initialize-IntuneAccess."
            }
        }

        # 2) Pick Graph endpoint from -Environment
        switch ($Environment) {
            "USGov"     { $uri = "https://graph.microsoft.us" }
            "USGovDoD"  { $uri = "https://dod-graph.microsoft.us" }
            default     { $uri = "https://graph.microsoft.com" }
        }
        $graphVersion = "beta"
        $GraphBeta    = "$uri/$graphVersion"

        # Make Graph base available to your helpers that reference $GraphBeta
        $script:GraphBeta = $GraphBeta

        # 3) Resolve tags & candidate items up front (fast fail if none)
        $tags  = Resolve-ScopeTags -SourceScopeTagName $SourceScopeTagName -DestinationScopeTagName $DestinationScopeTagName
        $items = Get-SourceTaggedItems -SourceTagId $tags.SrcId
        if (-not $items -or $items.Count -eq 0) {
            Write-Host "No policies found with source tag '$SourceScopeTagName'."
            return
        }

        # Build the existing-name set once per session to avoid collisions
        if (-not $script:_AllExistingNames) { $script:_AllExistingNames = Get-ExistingPolicyNames }
    }
    process {
        if ($PSCmdlet.ParameterSetName -eq "ByName") {
            foreach ($pn in $ProfileName) {
                $sel = $items | Where-Object { $_.Name -ieq $pn }
                if (-not $sel) { Write-Warning "No source-tagged policy found named '$pn'."; continue }

                $newName = Read-UniqueName -Default $sel.Name -ExistingNames $script:_AllExistingNames
                if ($PSCmdlet.ShouldProcess($sel.Name, "Clone as '$newName'")) {
                    try {
                        if     ($sel.Type -eq 'SC')     { Clone-Sc     -Item $sel -NewName $newName -RoleScopeTagIds $tags.AllIds }
                        elseif ($sel.Type -eq 'INTENT') { Clone-Intent -Item $sel -NewName $newName -RoleScopeTagIds $tags.AllIds }
                    } catch {
                        Write-Host "Clone failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
            }
            Write-Host "Done."; return
        }

        # Interactive picker loop
        while ($true) {
            $sel = Select-ByNumber -Items $items
            if ($null -eq $sel) { break }

            $newName = Read-UniqueName -Default $sel.Name -ExistingNames $script:_AllExistingNames
            if ($PSCmdlet.ShouldProcess($sel.Name, "Clone as '$newName'")) {
                try {
                    if     ($sel.Type -eq 'SC')     { Clone-Sc     -Item $sel -NewName $newName -RoleScopeTagIds $tags.AllIds }
                    elseif ($sel.Type -eq 'INTENT') { Clone-Intent -Item $sel -NewName $newName -RoleScopeTagIds $tags.AllIds }
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
