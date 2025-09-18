<#
.SYNOPSIS
  Copy Intune Compliance Policies (deviceCompliancePolicies) that include a given source scope tag.
  The clones are created with only the specified destination scope tags.

.DESCRIPTION
  - Detects your Graph cloud from your MgGraph context (Commercial, GCC, DoD).
  - Uses Microsoft Graph beta endpoints for compliance policy and script operations.
  - Resolves role scope tags and validates connection permissions.
  - Lists only compliance policies that include the specified Source scope tag.
  - Clone via interactive picker or exact name(s) with -PolicyName.
  - Clones include custom compliance scripts and policy settings with basic scheduled actions.
  - Comprehensive duplicate name detection and input validation for production safety.

.PARAMETER SourceScopeTagName
  Display name of the scope tag to SEARCH for in existing compliance policies (e.g. "DEV"). Required.

.PARAMETER DestinationScopeTagName
  One or more destination scope tag display names to APPLY to the clone - you get exactly what you specify
  (e.g. "PRO" gets only PRO tag, "PRO","USA" gets both tags). Required.

.PARAMETER PolicyName
  Optional one or more compliance policy display names to clone directly (exact, case-insensitive).
  If omitted, you'll get an interactive picker of all compliance policies that contain the source tag.

.PARAMETER Environment
  Graph cloud to target. Valid values: Global, USGov, USGovDoD. Default: Global.

.PREREQUISITES
  - Windows PowerShell 5.1 or PowerShell 7+
  - Microsoft Graph PowerShell SDK:
      Install-Module Microsoft.Graph -Scope CurrentUser
  - Connect to Graph with sufficient permissions (and RBAC to apply tags):
      Connect-MgGraph -Environment <Global|USGov|USGovDoD> `
        -Scopes "DeviceManagementScripts.ReadWrite.All","DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.ReadWrite.All"
  - Your account must have rights to assign the destination scope tags.

.EXAMPLE
  # Interactive picker
  Copy-IntuneCompliancePolicy -SourceScopeTagName "DEV" -DestinationScopeTagName "PRO"

.EXAMPLE
  # Clone by name (skip picker)
  Copy-IntuneCompliancePolicy -SourceScopeTagName "DEV" -DestinationScopeTagName "PRO","USA" `
                               -PolicyName "DEV-WIN10-MIN-OS"
.EXAMPLE
  # Clone specific policy with WhatIf preview
  Copy-IntuneCompliancePolicy -SourceScopeTagName "DEV" -DestinationScopeTagName "PRO" -PolicyName "DEV-WIN10-MIN-OS" -WhatIf

.EXAMPLE
  # Clone with detailed verbose output for troubleshooting
  Copy-IntuneCompliancePolicy -SourceScopeTagName "DEV" -DestinationScopeTagName "PRO" -Verbose

.NOTES
  IMPORTANT FEATURES:
  - Supports -WhatIf for safe testing without making changes
  - Supports -Verbose for detailed progress output during troubleshooting
  - Comprehensive validation prevents duplicate names and invalid input
  
  IMPORTANT LIMITATIONS:
  - Uses basic scheduled action template (block immediately) - original scheduled actions not preserved
  - Custom compliance scripts are cloned without scope tags (scripts don't support roleScopeTagIds)
  - Cloned policies require manual assignment to groups/devices after creation

  Required Graph scopes:
    - DeviceManagementScripts.ReadWrite.All
    - DeviceManagementConfiguration.ReadWrite.All
    - DeviceManagementRBAC.ReadWrite.All
#>
function Copy-IntuneCompliancePolicy {
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
        [string[]]$PolicyName,

        [Parameter()]
        [ValidateSet("Global","USGov","USGovDoD")]
        [string]$Environment = "Global"
    )
    begin {
        # 1) Ensure Graph access
        if (Get-Command Initialize-IntuneAccess -ErrorAction SilentlyContinue) {
            if ($false -eq (Initialize-IntuneAccess -Scopes @(
                "DeviceManagementScripts.ReadWrite.All",
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
            Write-Host "No compliance policies found with source tag '$SourceScopeTagName'."
            return
        }

        # Build the existing-name set once per session to avoid collisions
        if (-not $script:_AllExistingNames) { $script:_AllExistingNames = Get-ExistingPolicyNames }
    }
    process {
        if ($PSCmdlet.ParameterSetName -eq "ByName") {
            foreach ($pn in $PolicyName) {
                $sel = $items | Where-Object { $_.Name -ieq $pn }
                if (-not $sel) { Write-Warning "No source-tagged policy found named '$pn'."; continue }

                $newName = Read-UniqueName -Default $sel.Name -ExistingNames $script:_AllExistingNames
                if ($PSCmdlet.ShouldProcess($sel.Name, "Clone as '$newName'")) {
                    try {
                        Clone-CompliancePolicy -Item $sel -NewName $newName -RoleScopeTagIds $tags.AllIds
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
                    Clone-CompliancePolicy -Item $sel -NewName $newName -RoleScopeTagIds $tags.AllIds
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
