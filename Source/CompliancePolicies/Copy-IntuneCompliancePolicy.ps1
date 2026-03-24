function Copy-IntuneCompliancePolicy {
<#
.SYNOPSIS
    Clones Intune device compliance policies with scope tag management.

.DESCRIPTION
    Discovers compliance policies tagged with exactly the source scope tag, then creates clones with the destination scope tags applied; supports interactive picker or direct name specification.

.PARAMETER SourceScopeTagName
    The display name of the scope tag used to find source policies (exact match).

.PARAMETER DestinationScopeTagName
    One or more scope tag display names to apply to the cloned policy.

.PARAMETER PolicyName
    One or more exact policy names to clone directly; if omitted, an interactive picker is shown.

.PARAMETER NewPolicyName
    The name for the cloned policy; if omitted, a unique name is auto-generated.

.EXAMPLE
    # Interactively select and clone a compliance policy.
    Copy-IntuneCompliancePolicy -SourceScopeTagName "Production" -DestinationScopeTagName "Development"

.EXAMPLE
    # Fully automated clone with a specified name and multiple destination tags.
    Copy-IntuneCompliancePolicy -SourceScopeTagName "Production" -DestinationScopeTagName "Development","Test" -PolicyName "OS Compliance Policy" -NewPolicyName "Dev OS Compliance Policy"
#>
    [CmdletBinding(PositionalBinding = $true, SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateCount(1, 1)]
        [string[]]$SourceScopeTagName,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [ValidateCount(1, 64)]
        [string[]]$DestinationScopeTagName,

        [Parameter()]
        [string[]]$PolicyName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$NewPolicyName
    )
    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
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

        function Get-AllPages {
            [CmdletBinding()]
            [OutputType([array])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$Uri
            )

            $items = @()
            $response = Invoke-MgGraphRequest -Method GET -Uri $Uri

            if ($response.value) {
                $items += $response.value
            } else {
                return , $response
            }

            while ($response.'@odata.nextLink') {
                $response = Invoke-MgGraphRequest -Method GET -Uri $response.'@odata.nextLink'
                if ($response.value) {
                    $items += $response.value
                }
            }

            return $items
        }

        function Resolve-ScopeTags {
            [CmdletBinding()]
            [OutputType([hashtable])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string[]]$SourceScopeTagName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string[]]$DestinationScopeTagName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$GraphRoot
            )

            Write-Verbose "Resolving scope tags from Graph..."
            $tags = Get-AllPages -Uri "$GraphRoot/deviceManagement/roleScopeTags?`$select=id,displayName&`$top=999"

            if (-not $tags) {
                throw "No scope tags returned from Graph."
            }

            $sourceIds = foreach ($displayName in $SourceScopeTagName) {
                $matchedTag = $tags | Where-Object { $_.displayName -ieq $displayName }

                if (-not $matchedTag) {
                    throw "Source scope tag '$displayName' not found."
                }

                Write-Verbose "Found source scope tag: $displayName (ID: $($matchedTag.id))"
                $matchedTag.id
            }

            $destinationIds = foreach ($displayName in $DestinationScopeTagName) {
                $matchedTag = $tags | Where-Object { $_.displayName -ieq $displayName }

                if (-not $matchedTag) {
                    throw "Destination scope tag '$displayName' not found."
                }

                Write-Verbose "Found destination scope tag: $displayName (ID: $($matchedTag.id))"
                $matchedTag.id
            }

            @{
                SrcIds = $sourceIds
                AllIds = $destinationIds
            }
        }

        function Get-SourceTaggedPolicies {
            [CmdletBinding()]
            [OutputType([array])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string[]]$SourceTagIds,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$GraphRoot
            )

            Write-Verbose "Querying compliance policies..."
            $policies = Get-AllPages -Uri "$GraphRoot/deviceManagement/deviceCompliancePolicies?`$select=id,displayName,roleScopeTagIds&`$top=999"

            $filtered = @()
            foreach ($policy in $policies) {
                if ($policy -and $policy.id -and $policy.displayName -and $policy.roleScopeTagIds) {
                    if ($policy.roleScopeTagIds.Count -eq $SourceTagIds.Count) {
                        $allMatch = $true
                        foreach ($tagId in $SourceTagIds) {
                            if ($policy.roleScopeTagIds -notcontains $tagId) {
                                $allMatch = $false
                                break
                            }
                        }
                        if ($allMatch) {
                            $filtered += $policy
                        }
                    }
                }
            }

            Write-Verbose "Found $($filtered.Count) compliance policies with exact source tag match."
            $filtered
        }

        function Select-ByNumber {
            [CmdletBinding()]
            [OutputType([object])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                $Items
            )

            if (-not $Items -or $Items.Count -eq 0) {
                throw "No matching policies found."
            }

            $ordered = $Items | Sort-Object displayName
            Write-Information "" -InformationAction Continue
            Write-Information "Matching compliance policies:" -InformationAction Continue

            for ($i = 0; $i -lt $ordered.Count; $i++) {
                $number = $i + 1
                $name = if ([string]::IsNullOrWhiteSpace($ordered[$i].displayName)) {
                    "[Unnamed Policy - ID: $($ordered[$i].id)]"
                } else {
                    $ordered[$i].displayName
                }
                Write-Information ("{0,3}. {1}" -f $number, $name) -InformationAction Continue
            }

            Write-Information "" -InformationAction Continue

            while ($true) {
                $choice = Read-Host ("Enter number 1-{0} (or Enter to cancel)" -f $ordered.Count)

                if ([string]::IsNullOrWhiteSpace($choice)) {
                    return $null
                }

                if ($choice -as [int]) {
                    $number = [int]$choice

                    if ($number -ge 1 -and $number -le $ordered.Count) {
                        return $ordered[$number - 1]
                    }
                }

                Write-Warning "Invalid selection."
            }
        }

        function ConvertTo-SanitizedPolicyName {
            [CmdletBinding()]
            [OutputType([string])]
            param (
                [Parameter(Mandatory = $true)]
                [AllowEmptyString()]
                [string]$String
            )

            if ($null -eq $String) {
                return ""
            }

            $String = $String.Trim()
            $String = $String -replace '[\x00-\x1F\x7F-\x9F]', ''
            $String = $String.Substring(0, [Math]::Min($String.Length, 255))
            $String.Trim()
        }

        function Get-ExistingPolicyNames {
            [CmdletBinding()]
            [OutputType([System.Collections.Generic.HashSet[string]])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$GraphRoot
            )

            Write-Verbose "Building list of existing compliance policy names..."
            $names = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

            $allPolicies = Get-AllPages -Uri "$GraphRoot/deviceManagement/deviceCompliancePolicies?`$select=id,displayName&`$top=999"

            foreach ($policy in $allPolicies) {
                if ($policy.displayName) {
                    $null = $names.Add($policy.displayName)
                }
            }

            Write-Verbose "Found $($names.Count) existing compliance policy names."
            return $names
        }

        function New-UniqueCloneName {
            [CmdletBinding()]
            [OutputType([string])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$BaseName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                [System.Collections.Generic.HashSet[string]]$ExistingNames
            )

            $candidateName = "Copy of $BaseName"
            $counter = 2

            while ($ExistingNames.Contains($candidateName)) {
                $candidateName = "Copy of $BaseName ($counter)"
                $counter++
            }

            Write-Verbose "Auto-generated unique name: $candidateName"
            $null = $ExistingNames.Add($candidateName)
            return $candidateName
        }

        function Read-UniqueName {
            [CmdletBinding()]
            [OutputType([string])]
            param (
                [Parameter()]
                [string]$Default = "",

                [Parameter()]
                [System.Collections.Generic.HashSet[string]]$ExistingNames
            )

            if (-not $ExistingNames) {
                $ExistingNames = Get-ExistingPolicyNames -GraphRoot $graphRoot
            }

            while ($true) {
                $promptSuffix = if ($Default) { " [Default: $Default]" } else { "" }
                $name = Read-Host ("Enter NEW name for the clone{0}" -f $promptSuffix)

                if ([string]::IsNullOrWhiteSpace($name)) {
                    $name = $Default
                }

                $name = ConvertTo-SanitizedPolicyName -String $name

                if ([string]::IsNullOrWhiteSpace($name)) {
                    Write-Warning "Name cannot be blank."
                    continue
                }

                if ($ExistingNames.Contains($name)) {
                    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $uniqueName = "$name - $timestamp"
                    Write-Information "A policy named '$name' already exists. Using '$uniqueName' instead." -InformationAction Continue
                    return $uniqueName
                }

                return $name
            }
        }

        function Copy-ComplianceScript {
            [CmdletBinding()]
            [OutputType([string])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$OriginalScriptId,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$PolicyName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$GraphRoot
            )

            Write-Verbose "Cloning compliance script..."

            $original = Invoke-MgGraphRequest -Method GET -Uri "$GraphRoot/deviceManagement/deviceComplianceScripts/$OriginalScriptId"

            $cloneBody = @{
                displayName = "$($original.displayName) - Clone for $PolicyName"
                description = "Cloned from '$($original.displayName)' for policy '$PolicyName'"
                detectionScriptContent = $original.detectionScriptContent
                runAsAccount = $original.runAsAccount
            } | ConvertTo-Json -Depth 100

            $newScript = Invoke-MgGraphRequest -Method POST -Uri "$GraphRoot/deviceManagement/deviceComplianceScripts" -Body $cloneBody -ContentType "application/json"

            Write-Information "    Script cloned: '$($newScript.displayName)' (ID: $($newScript.id))" -InformationAction Continue
            return $newScript.id
        }

        function Copy-CompliancePolicy {
            [CmdletBinding()]
            [OutputType([void])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                $SourcePolicy,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$NewName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                [string[]]$ScopeTagIds,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$GraphRoot
            )

            Write-Verbose "Cloning policy: $($SourcePolicy.displayName)"

            $full = Invoke-MgGraphRequest -Method GET -Uri "$GraphRoot/deviceManagement/deviceCompliancePolicies/$($SourcePolicy.id)?`$expand=scheduledActionsForRule"
            if ($full -is [hashtable]) {
                $fullProps = $full
            } else {
                $fullProps = @{}
                foreach ($prop in $full.PSObject.Properties) {
                    $fullProps[$prop.Name] = $prop.Value
                }
            }

            $newScriptRef = $null
            if ($fullProps['deviceCompliancePolicyScript']) {
                Write-Information "  Policy has custom compliance script" -InformationAction Continue
                try {
                    $newScriptId = Copy-ComplianceScript -OriginalScriptId $fullProps['deviceCompliancePolicyScript']['deviceComplianceScriptId'] -PolicyName $NewName -GraphRoot $GraphRoot
                    $newScriptRef = @{
                        deviceComplianceScriptId = $newScriptId
                        rulesContent = $fullProps['deviceCompliancePolicyScript']['rulesContent']
                    }
                } catch {
                    Write-Warning "Script clone failed: $($_.Exception.Message)"
                }
            }

            $drop = @('id', 'createdDateTime', 'lastModifiedDateTime', 'version', 'assignments', '@odata.context', '@odata.etag', 'deviceCompliancePolicyScript', 'scheduledActionsForRule')

            $bodyObj = [ordered]@{
                displayName = $NewName
                description = "Cloned from '$($fullProps['displayName'])' on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                roleScopeTagIds = @($ScopeTagIds | ForEach-Object { [string]$_ })
            }

            $alsoSkip = @('displayName', 'roleScopeTagIds', 'description')
            foreach ($key in $fullProps.Keys) {
                if ($drop -contains $key) {
                    continue
                }
                if ($alsoSkip -contains $key) {
                    continue
                }
                if ($key -like '@*' -and $key -ne '@odata.type') {
                    continue
                }
                if ($null -ne $fullProps[$key]) {
                    $bodyObj[$key] = $fullProps[$key]
                }
            }

            if ($newScriptRef) {
                Write-Verbose "Including cloned script reference in policy"
                $bodyObj['deviceCompliancePolicyScript'] = $newScriptRef
            }

            Write-Verbose "Using basic scheduled action template"
            $bodyObj['scheduledActionsForRule'] = @(@{
                ruleName = 'passwordRequired'
                scheduledActionConfigurations = @(@{
                    actionType = 'block'
                    gracePeriodHours = 0
                })
            })

            Write-Verbose "Final scope tags: $($bodyObj.roleScopeTagIds -join ', ')"
            Write-Verbose "Final display name: '$($bodyObj.displayName)'"

            $body = $bodyObj | ConvertTo-Json -Depth 100

            $newPolicy = Invoke-MgGraphRequest -Method POST -Uri "$GraphRoot/deviceManagement/deviceCompliancePolicies" -Body $body -ContentType "application/json"

            Write-Information ("Cloned Compliance Policy: '{0}' -> '{1}' (tags: {2})" -f $SourcePolicy.displayName, $newPolicy.displayName, ($ScopeTagIds -join ", ")) -InformationAction Continue
        }
    }
    process {
        if ($script:__SkipProcessBlock) { return }

        $tags = Resolve-ScopeTags -SourceScopeTagName $SourceScopeTagName -DestinationScopeTagName $DestinationScopeTagName -GraphRoot $graphRoot
        $policies = Get-SourceTaggedPolicies -SourceTagIds $tags.SrcIds -GraphRoot $graphRoot

        if (-not $policies -or $policies.Count -eq 0) {
            Write-Information "No compliance policies found with exact source tag match '$($SourceScopeTagName -join ', ')'." -InformationAction Continue
            return
        }

        if (-not $script:_AllExistingNames) {
            $script:_AllExistingNames = Get-ExistingPolicyNames -GraphRoot $graphRoot
        }

        if ($PolicyName) {
            if ($NewPolicyName -and $PolicyName.Count -gt 1) {
                Write-Warning "NewPolicyName can only be used when cloning a single policy. Ignoring NewPolicyName parameter."
                $NewPolicyName = $null
            }

            foreach ($policyName in $PolicyName) {
                # Trim whitespace from both the search term and policy names for comparison
                $trimmedPolicyName = $policyName.Trim()
                $selectedItem = $policies | Where-Object { $_.displayName.Trim() -ieq $trimmedPolicyName }

                if (-not $selectedItem) {
                    Write-Warning "No source-tagged compliance policy found named '$policyName'."
                    continue
                }

                if ($NewPolicyName) {
                    $allCurrent = Get-AllPages -Uri "$graphRoot/deviceManagement/deviceCompliancePolicies?`$select=id,displayName&`$top=999"
                    $existingNames = $allCurrent | Where-Object { $_.displayName } | ForEach-Object { $_.displayName }

                    if ($existingNames -contains $NewPolicyName) {
                        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                        $newName = "$NewPolicyName - $timestamp"
                        Write-Verbose "Policy named '$NewPolicyName' already exists. Using '$newName' instead."
                    } else {
                        $newName = $NewPolicyName
                    }
                } else {
                    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $newName = "Copy of $($selectedItem.displayName) - $timestamp"
                }

                try {
                    if ($PSCmdlet.ShouldProcess($newName, "Clone compliance policy and apply scope tags")) {
                        Copy-CompliancePolicy -SourcePolicy $selectedItem -NewName $newName -ScopeTagIds $tags.AllIds -GraphRoot $graphRoot
                    }
                } catch {
                    Write-Warning "Clone failed: $($_.Exception.Message)"
                }
            }

            Write-Information "Done." -InformationAction Continue
            return
        }

        while ($true) {
            $selectedItem = Select-ByNumber -Items $policies

            if ($null -eq $selectedItem) {
                break
            }

            $currentExisting = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
            $allPolicies = Get-AllPages -Uri "$graphRoot/deviceManagement/deviceCompliancePolicies?`$select=id,displayName&`$top=999"
            foreach ($p in $allPolicies) {
                if ($p.displayName) { $null = $currentExisting.Add($p.displayName) }
            }

            $newName = Read-UniqueName -Default $selectedItem.displayName -ExistingNames $currentExisting

            try {
                if ($PSCmdlet.ShouldProcess($newName, "Clone compliance policy and apply scope tags")) {
                    Copy-CompliancePolicy -SourcePolicy $selectedItem -NewName $newName -ScopeTagIds $tags.AllIds -GraphRoot $graphRoot
                }
            } catch {
                Write-Warning "Clone failed: $($_.Exception.Message)"
            }

            $again = (Read-Host "Clone another? (y/n)").Trim().ToLowerInvariant()

            if ($again -notin @('y', 'yes')) {
                break
            }
        }

        Write-Information "Done." -InformationAction Continue
    }
    end {
    }
}
