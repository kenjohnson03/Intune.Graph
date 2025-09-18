# Private\CompliancePolicy.Clone.Helpers.ps1

function Get-AllPages {
    param([Parameter(Mandatory)][string]$Uri)
    $items = @()
    $resp = Invoke-MgGraphRequest -Method GET -Uri $Uri
    if ($resp.value) { $items += $resp.value } else { return ,$resp }
    while ($resp.'@odata.nextLink') {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
        $items += $resp.value
    }
    return $items
}

function Resolve-ScopeTags {
    param(
        [Parameter(Mandatory)][string]$SourceScopeTagName, 
        [Parameter(Mandatory)][string[]]$DestinationScopeTagName
    )
    
    $tags = Get-AllPages -Uri "$script:GraphBeta/deviceManagement/roleScopeTags?`$select=id,displayName&`$top=999"
    if (-not $tags) { throw "No scope tags found" }

    $src = $tags | Where-Object { $_.displayName -ieq $SourceScopeTagName }
    if (-not $src) { throw "Source scope tag '$SourceScopeTagName' not found" }

    $dstIds = foreach($dn in $DestinationScopeTagName) {
        $m = $tags | Where-Object { $_.displayName -ieq $dn }
        if (-not $m) { throw "Destination scope tag '$dn' not found" }
        $m.id
    }

    @{
        SrcId = $src.id
        AllIds = @($dstIds | Select-Object -Unique)
    }
}

function Get-SourceTaggedItems {
    param([Parameter(Mandatory)][string]$SourceTagId)
    
    $policies = Get-AllPages -Uri "$script:GraphBeta/deviceManagement/deviceCompliancePolicies?`$select=id,displayName,roleScopeTagIds&`$top=999"
    
    $filtered = @()
    foreach ($policy in $policies) {
        if ($policy -and $policy.id -and $policy.displayName -and $policy.roleScopeTagIds) {
            if ($policy.roleScopeTagIds -contains $SourceTagId) {
                $filtered += $policy | Select-Object `
                    @{n='Type';e={'COMPLIANCE'}},
                    @{n='Name';e={$_.displayName}},
                    @{n='Id';e={$_.id}},
                    @{n='Raw';e={$_}}
            }
        }
    }
    
    return $filtered
}

function Select-ByNumber {
    param([Parameter(Mandatory)]$Items)
    if (-not $Items -or $Items.Count -eq 0) { throw "No matching compliance policies found." }

    $ordered = $Items | Sort-Object Name
    Write-Host ""
    Write-Host "Matching compliance policies:"
    for ($i = 0; $i -lt $ordered.Count; $i++) { 
        $n = $i + 1
        Write-Host ("{0,3}. {1}" -f $n, $ordered[$i].Name) 
    }
    Write-Host ""

    while ($true) {
        $choice = Read-Host ("Enter number 1-{0} (or Enter to cancel)" -f $ordered.Count)
        if ([string]::IsNullOrWhiteSpace($choice)) { return $null }
        if ($choice -as [int]) {
            $n = [int]$choice
            if ($n -ge 1 -and $n -le $ordered.Count) { return $ordered[$n-1] }
        }
        Write-Host "Invalid selection." -ForegroundColor Yellow
    }
}

function Normalize-Name([string]$s) {
    if ($null -eq $s) { return "" }
    $s = $s.Trim()
    if ($s.Length -ge 2 -and (
            ($s.StartsWith("'") -and $s.EndsWith("'")) -or
            ($s.StartsWith('"') -and $s.EndsWith('"')))) {
        $s = $s.Substring(1, $s.Length-2)
    }
    $s.Trim()
}

function Get-ExistingPolicyNames {
    $names = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    (Get-AllPages -Uri "$script:GraphBeta/deviceManagement/deviceCompliancePolicies?`$select=id,displayName&`$top=999") |
        ForEach-Object { if ($_.displayName) { $null = $names.Add($_.displayName) } }

    $names
}

function Read-UniqueName {
    param(
        [string]$Default = "",
        [System.Collections.Generic.HashSet[string]]$ExistingNames
    )
    if (-not $ExistingNames) { $ExistingNames = Get-ExistingPolicyNames }

    while ($true) {
        $nm = Read-Host ("Enter NEW name for the clone{0}" -f ($(if ($Default) { " [Default: $Default]" } else { "" })))
        if ([string]::IsNullOrWhiteSpace($nm)) { $nm = $Default }
        $nm = Normalize-Name $nm
        if ([string]::IsNullOrWhiteSpace($nm)) { Write-Host "Name cannot be blank."; continue }

        if ($ExistingNames.Contains($nm)) {
            Write-Host "A policy named '$nm' already exists. Choose another." -ForegroundColor Yellow
            continue
        }

        $null = $ExistingNames.Add($nm)
        return $nm
    }
}

function Clone-ComplianceScript {
    param($OriginalScriptId, $PolicyName, [string[]]$TargetScopeTagIds)
    
    Write-Verbose "  Cloning compliance script..."
    
    # Get original script
    $original = Invoke-MgGraphRequest -Method GET -Uri "$script:GraphBeta/deviceManagement/deviceComplianceScripts/$OriginalScriptId"
    
    # Create clone
    $cloneBody = @{
        displayName = "$($original.displayName) - Clone for $PolicyName"
        description = "Cloned from '$($original.displayName)' for policy '$PolicyName'"
        detectionScriptContent = $original.detectionScriptContent
        runAsAccount = $original.runAsAccount
    } | ConvertTo-Json -Depth 100
    
    $newScript = Invoke-MgGraphRequest -Method POST -Uri "$script:GraphBeta/deviceManagement/deviceComplianceScripts" -Body $cloneBody -ContentType "application/json"
    
    Write-Host "    Script cloned: '$($newScript.displayName)' (ID: $($newScript.id))" -ForegroundColor Green
    return $newScript.id
}

function Clone-CompliancePolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param($Item, [string]$NewName, [string[]]$RoleScopeTagIds)
    
    $sourcePolicy = $Item.Raw
    Write-Verbose "$(if($WhatIfPreference){'WHATIF: Would clone'}else{'Cloning'}) policy: $($sourcePolicy.displayName)"
    
    # Get full policy details with scheduled actions expanded
    $full = Invoke-MgGraphRequest -Method GET -Uri "$script:GraphBeta/deviceManagement/deviceCompliancePolicies/$($sourcePolicy.id)?`$expand=scheduledActionsForRule"
    if ($full -is [hashtable]) { $full = [pscustomobject]$full }
    
    # Handle custom compliance script
    $newScriptRef = $null
    if ($full.deviceCompliancePolicyScript) {
        if ($WhatIfPreference) {
            Write-Host "  WHATIF: Policy has custom compliance script" -ForegroundColor Cyan
            $scriptId = $full.deviceCompliancePolicyScript.deviceComplianceScriptId
            try {
                $script = Invoke-MgGraphRequest -Method GET -Uri "$script:GraphBeta/deviceManagement/deviceComplianceScripts/$scriptId"
                Write-Host "  WHATIF: Would clone script '$($script.displayName)' (scripts don't get scope tags)" -ForegroundColor Yellow
            } catch {
                Write-Host "  WHATIF: Would clone script $scriptId (scripts don't get scope tags)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Policy has custom compliance script" -ForegroundColor Cyan
            try {
                $newScriptId = Clone-ComplianceScript -OriginalScriptId $full.deviceCompliancePolicyScript.deviceComplianceScriptId -PolicyName $NewName -TargetScopeTagIds $RoleScopeTagIds
                $newScriptRef = @{
                    deviceComplianceScriptId = $newScriptId
                    rulesContent = $full.deviceCompliancePolicyScript.rulesContent
                }
            } catch {
                Write-Host "    Script clone failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } elseif ($WhatIfPreference) {
        Write-Host "  WHATIF: Would create policy '$NewName' with scope tags: $($RoleScopeTagIds -join ', ')" -ForegroundColor Cyan
        Write-Host "  WHATIF: No custom compliance script" -ForegroundColor Gray
        return
    }
    
    # Build policy body (exclude read-only fields)
    $drop = @('id','createdDateTime','lastModifiedDateTime','version','assignments','@odata.context','@odata.etag','deviceCompliancePolicyScript','scheduledActionsForRule')
    
    $bodyObj = [ordered]@{
        displayName = $NewName
        description = "Cloned from '$($full.displayName)' on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        roleScopeTagIds = @($RoleScopeTagIds | ForEach-Object { [string]$_ })
    }
    
    # Copy compliance settings (but exclude displayName and roleScopeTagIds since we set those explicitly)
    $alsoSkip = @('displayName', 'roleScopeTagIds', 'description')
    foreach($prop in $full.PSObject.Properties) {
        if ($drop -contains $prop.Name) { continue }
        if ($alsoSkip -contains $prop.Name) { continue }
        if ($prop.Name -like '@*' -and $prop.Name -ne '@odata.type') { continue }
        if ($null -ne $prop.Value) {
            $bodyObj[$prop.Name] = $prop.Value
        }
    }
    
    # Add cloned script reference if we have one (before scheduledActions)
    if ($newScriptRef) {
        Write-Host "  Including cloned script reference in policy" -ForegroundColor Yellow
        $bodyObj['deviceCompliancePolicyScript'] = $newScriptRef
    }
    
    # Add REQUIRED scheduledActionsForRule (compliance policies must have this)
    Write-Verbose "  Using basic scheduled action template"
    $bodyObj['scheduledActionsForRule'] = @(@{
        ruleName = 'passwordRequired'
        scheduledActionConfigurations = @(@{
            actionType = 'block'
            gracePeriodHours = 0
        })
    })
    
    Write-Verbose "  Final scope tags being sent: $($bodyObj.roleScopeTagIds -join ', ')"
    Write-Verbose "  Final display name: '$($bodyObj.displayName)'"
    
    # Check for existing policy with same name (both WhatIf and real mode)
    Write-Verbose "  Checking for existing policy with name '$NewName'..."
    try {
        $allPolicies = Get-AllPages -Uri "$script:GraphBeta/deviceManagement/deviceCompliancePolicies?`$select=id,displayName"
        $existing = $allPolicies | Where-Object { $_.displayName -eq $NewName }
        if ($existing) {
            Write-Host "  $(if($WhatIfPreference){'WHATIF: '}else{''})ERROR: Policy with name '$NewName' already exists (ID: $($existing.id))" -ForegroundColor Red
            if ($WhatIfPreference) {
                Write-Host "  WHATIF: Would fail with duplicate name error" -ForegroundColor Red
                return
            } else {
                throw "Cannot create duplicate policy. A policy named '$NewName' already exists."
            }
        }
    } catch {
        Write-Host "  Warning: Could not check for duplicate names: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if ($WhatIfPreference) {
        Write-Host "  WHATIF: Would create policy with basic scheduled action template" -ForegroundColor Cyan
        if ($full.deviceCompliancePolicyScript) {
            Write-Host "  WHATIF: Would create policy '$NewName' with custom compliance" -ForegroundColor Cyan
            Write-Host "  WHATIF: Policy blocks access immediately (0 grace period)" -ForegroundColor Yellow
        } else {
            Write-Host "  WHATIF: Policy blocks access immediately (0 grace period)" -ForegroundColor Yellow
        }
        return
    }
    
    $body = $bodyObj | ConvertTo-Json -Depth 100
    
    # Create policy via beta endpoint
    $new = Invoke-MgGraphRequest -Method POST -Uri "$script:GraphBeta/deviceManagement/deviceCompliancePolicies" -Body $body -ContentType "application/json"
    
    Write-Host "SUCCESS: Policy '$($new.displayName)' created!" -ForegroundColor Green
    Write-Host "  ID: $($new.id)" -ForegroundColor Gray
    Write-Host "  Scope Tags: $($new.roleScopeTagIds -join ', ')" -ForegroundColor Gray
    if ($newScriptRef) {
        Write-Host "  Custom Compliance: YES (cloned script)" -ForegroundColor Green
    }
}
