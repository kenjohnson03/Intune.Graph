function Copy-IntuneRemediationScript {
<#
.SYNOPSIS
    Clones Intune Proactive Remediation scripts from one scope tag to another.

.DESCRIPTION
    Discovers remediation scripts (deviceHealthScripts) tagged with exactly the source scope tag, then clones them with the destination scope tags applied.

.PARAMETER SourceScopeTagName
    The display name of the scope tag used to find source remediation scripts. Scripts must have exactly this tag to be matched.

.PARAMETER DestinationScopeTagName
    One or more scope tag display names to apply to the cloned remediation scripts.

.PARAMETER ScriptName
    The exact name(s) of remediation scripts to clone; if omitted, an interactive picker is shown.

.PARAMETER NewScriptName
    The new name for the cloned remediation; if omitted, a unique name is auto-generated with a timestamp.

.PARAMETER WhatIfMode
    Previews what would be cloned without making any changes.

.EXAMPLE
    # Interactive mode - pick from a numbered list of scripts tagged with "Production".
    Copy-IntuneRemediationScript -SourceScopeTagName "Production" -DestinationScopeTagName "Development"

.EXAMPLE
    # Fully automated mode - clone a named script with a specific destination name.
    Copy-IntuneRemediationScript -SourceScopeTagName "Production" -DestinationScopeTagName "Development" -ScriptName "Send Compliance Log" -NewScriptName "New Send Compliance Log"
#>
    [CmdletBinding(PositionalBinding = $true, SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateCount(1, 1)]
        [string[]] $SourceScopeTagName,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [ValidateCount(1, 64)]
        [string[]] $DestinationScopeTagName,

        [string[]] $ScriptName,

        [string] $NewScriptName,

        [switch] $WhatIfMode
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

        Write-Information "Connected to: $($context.Environment) ($uri)" -InformationAction Continue

        # --- Helper: Paginate Graph requests ---
        function Get-AllPages {
            param(
                [Parameter(Mandatory = $true)]
                [string] $Uri
            )
            $items = @()
            $requestUri = $Uri
            do {
                $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
                if ($response.value) {
                    $items += $response.value
                }
                else {
                    return , $response
                }
                $requestUri = $null
                if ($response.Keys -contains '@odata.nextLink') {
                    $requestUri = $response.'@odata.nextLink'
                }
            } while ($null -ne $requestUri)
            return $items
        }

        # --- Helper: Resolve scope tag names to IDs ---
        function Resolve-ScopeTags {
            param(
                [Parameter(Mandatory = $true)]
                [string[]] $SourceScopeTagName,

                [Parameter(Mandatory = $true)]
                [string[]] $DestinationScopeTagName,

                [Parameter(Mandatory = $true)]
                [string] $GraphRoot
            )

            Write-Information "Resolving scope tags..." -InformationAction Continue
            $allTags = @()
            $tagsRequestUri = "$GraphRoot/deviceManagement/roleScopeTags?`$select=id,displayName&`$top=999"
            do {
                $tagsResponse = Invoke-MgGraphRequest -Method GET -Uri $tagsRequestUri
                $allTags += $tagsResponse.value
                $tagsRequestUri = $null
                if ($tagsResponse.Keys -contains '@odata.nextLink') {
                    $tagsRequestUri = $tagsResponse.'@odata.nextLink'
                }
            } while ($null -ne $tagsRequestUri)

            if (-not $allTags) {
                throw "No scope tags returned from Graph."
            }

            $sourceIds = @()
            foreach ($displayName in $SourceScopeTagName) {
                $matchedTag = $allTags | Where-Object { $_.displayName -ieq $displayName } | Select-Object -First 1
                if (-not $matchedTag) {
                    throw "Source scope tag '$displayName' not found."
                }
                Write-Information "  Source scope tag: $displayName (ID: $($matchedTag.id))" -InformationAction Continue
                $sourceIds += $matchedTag.id
            }

            $destinationIds = @()
            foreach ($displayName in $DestinationScopeTagName) {
                $matchedTag = $allTags | Where-Object { $_.displayName -ieq $displayName } | Select-Object -First 1
                if (-not $matchedTag) {
                    throw "Destination scope tag '$displayName' not found."
                }
                Write-Information "  Destination scope tag: $displayName (ID: $($matchedTag.id))" -InformationAction Continue
                $destinationIds += $matchedTag.id
            }

            return @{
                SrcIds = $sourceIds
                AllIds = $destinationIds
            }
        }

        # --- Helper: Get remediation scripts with EXACT source tag match ---
        function Get-SourceTaggedRemediations {
            param(
                [Parameter(Mandatory = $true)]
                [string[]] $SourceTagIds,

                [Parameter(Mandatory = $true)]
                [string] $GraphRoot
            )

            Write-Information "Loading remediation scripts..." -InformationAction Continue
            $allRemediations = Get-AllPages -Uri "$GraphRoot/deviceManagement/deviceHealthScripts?`$top=999"

            $filtered = @()
            foreach ($rem in $allRemediations) {
                $tags = @($rem.roleScopeTagIds)
                if ($tags.Count -eq $SourceTagIds.Count) {
                    $allMatch = $true
                    foreach ($tagId in $SourceTagIds) {
                        if ($tags -notcontains $tagId) {
                            $allMatch = $false
                            break
                        }
                    }
                    if ($allMatch) {
                        $filtered += $rem
                    }
                }
            }

            Write-Information "Found $($filtered.Count) remediation scripts with exact source tag match." -InformationAction Continue
            return , $filtered
        }

        # --- Helper: Interactive numbered picker ---
        function Select-ByNumber {
            param(
                [Parameter(Mandatory = $true)]
                $Items
            )

            if (-not $Items -or $Items.Count -eq 0) {
                throw "No matching remediation scripts found."
            }

            $view = @()
            foreach ($item in $Items) {
                $displayNameVal = if ($item -is [hashtable]) { $item['displayName'] } else { $item.displayName }
                $nameVal = if ($item -is [hashtable]) { $item['name'] } else { $item.name }
                $idVal = if ($item -is [hashtable]) { $item['id'] } else { $item.id }

                $resolvedName = $displayNameVal
                if (-not $resolvedName -or $resolvedName.Trim() -eq "") { $resolvedName = $nameVal }

                $entry = @{
                    Id   = $idVal
                    Name = $resolvedName
                    Raw  = $item
                }
                $view += $entry
            }

            $ordered = @($view | Sort-Object { $_['Name'] })
            Write-Information "" -InformationAction Continue
            Write-Information "Remediation Scripts:" -InformationAction Continue

            for ($i = 0; $i -lt $ordered.Count; $i++) {
                $number = $i + 1
                Write-Information ("{0,3}. {1}" -f $number, $ordered[$i]['Name']) -InformationAction Continue
            }

            Write-Information "" -InformationAction Continue

            while ($true) {
                $choice = Read-Host ("Enter number 1-{0} (or Enter to cancel)" -f $ordered.Count)

                if (-not $choice -or $choice.Trim() -eq "") {
                    return $null
                }

                if ($choice -as [int]) {
                    $number = [int]$choice
                    if ($number -ge 1 -and $number -le $ordered.Count) {
                        return $ordered[$number - 1]['Raw']
                    }
                }

                Write-Warning "Invalid selection."
            }
        }

        # --- Helper: Normalize name string ---
        function ConvertTo-NormalizedName {
            param(
                [Parameter(Mandatory = $true)]
                [AllowEmptyString()]
                [string] $String
            )

            if ($null -eq $String) {
                return ""
            }

            $String = $String -replace "[\u2010\u2011\u2012\u2013\u2014\u2212]", "-"
            $String = $String -replace "[\u00A0]", " "
            $String = $String -replace "\s+", " "
            $String = $String.Trim()

            if ($String.Length -ge 2 -and (
                ($String.StartsWith("'") -and $String.EndsWith("'")) -or
                ($String.StartsWith('"') -and $String.EndsWith('"')))) {
                $String = $String.Substring(1, $String.Length - 2)
            }

            $String.Trim()
        }

        # --- Helper: Get all existing remediation script names ---
        function Get-ExistingRemediationNames {
            param(
                [Parameter(Mandatory = $true)]
                [string] $GraphRoot
            )

            Write-Information "Loading existing remediation script names..." -InformationAction Continue
            $names = @()
            $allRemediations = Get-AllPages -Uri "$GraphRoot/deviceManagement/deviceHealthScripts?`$top=999"

            foreach ($remediation in $allRemediations) {
                $name = $remediation.displayName
                if (-not $name -or $name.Trim() -eq "") { $name = $remediation.name }
                if ($name) {
                    if ($names -inotcontains $name) {
                        $names += $name
                    }
                }
            }

            Write-Information "Found $($names.Count) existing remediation script names." -InformationAction Continue
            return , $names
        }

        # --- Helper: Generate unique clone name ---
        function New-UniqueCloneName {
            param(
                [Parameter(Mandatory = $true)]
                [string] $BaseName,

                [Parameter(Mandatory = $true)]
                [array] $ExistingNames
            )

            $candidateName = "Copy of $BaseName"
            $counter = 2

            while ($ExistingNames -icontains $candidateName) {
                $candidateName = "Copy of $BaseName ($counter)"
                $counter++
            }

            Write-Information "Auto-generated unique name: $candidateName" -InformationAction Continue
            return $candidateName
        }

        # --- Helper: Prompt user for unique name (interactive mode) ---
        function Read-UniqueName {
            param(
                [string] $Default = "",
                [array] $ExistingNames
            )

            if (-not $ExistingNames) {
                $ExistingNames = Get-ExistingRemediationNames -GraphRoot $graphRoot
            }

            while ($true) {
                $promptSuffix = if ($Default) { " [Default: $Default]" } else { "" }
                $name = Read-Host ("Enter NEW name for the clone{0}" -f $promptSuffix)

                if (-not $name -or $name.Trim() -eq "") {
                    $name = $Default
                }

                $name = ConvertTo-NormalizedName -String $name

                if (-not $name -or $name.Trim() -eq "") {
                    Write-Warning "Name cannot be blank."
                    continue
                }

                if ($ExistingNames -icontains $name) {
                    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $uniqueName = "$name - $timestamp"
                    Write-Information "A remediation named '$name' already exists. Using '$uniqueName' instead." -InformationAction Continue
                    return $uniqueName
                }

                return $name
            }
        }
    }

    process {
        if ($script:__SkipProcessBlock) { return }

        $results = @()

        try {
            $tags = Resolve-ScopeTags -SourceScopeTagName $SourceScopeTagName -DestinationScopeTagName $DestinationScopeTagName -GraphRoot $graphRoot
        }
        catch {
            Write-Error "Failed to resolve scope tags: $_"
            return
        }

        try {
            $remediations = Get-SourceTaggedRemediations -SourceTagIds $tags.SrcIds -GraphRoot $graphRoot
        }
        catch {
            Write-Error "Failed to retrieve remediation scripts: $_"
            return
        }

        if (-not $remediations -or $remediations.Count -eq 0) {
            Write-Information "No remediation scripts found with exact source tag match '$($SourceScopeTagName -join ', ')'." -InformationAction Continue
            return
        }

        # --- Named script mode (semi-automated or fully automated) ---
        if ($ScriptName) {
            if ($NewScriptName -and $ScriptName.Count -gt 1) {
                Write-Warning "NewScriptName can only be used when cloning a single script. Ignoring NewScriptName parameter."
                $NewScriptName = $null
            }

            foreach ($sName in $ScriptName) {
                $trimmedName = $sName.Trim()
                $selectedItem = $remediations | Where-Object {
                    $n = $_.displayName
                    if (-not $n -or $n.Trim() -eq "") { $n = $_.name }
                    $n.Trim() -ieq $trimmedName
                }

                if (-not $selectedItem) {
                    Write-Warning "No source-tagged remediation script found named '$sName'."
                    $results += @{
                        SourceScript = $sName
                        NewScript    = ""
                        Action       = "NOT FOUND"
                    }
                    continue
                }

                $sourceName = $selectedItem.displayName
                if (-not $sourceName -or $sourceName.Trim() -eq "") { $sourceName = $selectedItem.name }

                if ($NewScriptName) {
                    $allCurrent = Get-AllPages -Uri "$graphRoot/deviceManagement/deviceHealthScripts?`$top=999"
                    $existingNames = @()
                    foreach ($r in $allCurrent) {
                        $nm = $r.displayName
                        if (-not $nm -or $nm.Trim() -eq "") { $nm = $r.name }
                        if ($nm -and ($existingNames -inotcontains $nm)) { $existingNames += $nm }
                    }

                    if ($existingNames -icontains $NewScriptName) {
                        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                        $newName = "$NewScriptName - $timestamp"
                        Write-Information "Remediation named '$NewScriptName' already exists. Using '$newName' instead." -InformationAction Continue
                    }
                    else {
                        $newName = $NewScriptName
                    }
                }
                else {
                    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $newName = "Copy of $sourceName - $timestamp"
                }

                if ($WhatIfMode) {
                    Write-Information "WOULD CLONE remediation: '$sourceName' -> '$newName'" -InformationAction Continue
                    $results += @{
                        SourceScript = $sourceName
                        NewScript    = $newName
                        Action       = "WOULD CLONE"
                    }
                }
                else {
                    if ($PSCmdlet.ShouldProcess($newName, "Clone remediation script and apply scope tags")) {
                        try {
                            Write-Information "Cloning remediation: $sourceName -> $newName" -InformationAction Continue

                            $full = Invoke-MgGraphRequest -Method GET -Uri "$graphRoot/deviceManagement/deviceHealthScripts/$($selectedItem.id)"

                            $body = @{
                                displayName              = $newName
                                description              = ("Cloned from '{0}' on {1}" -f $sourceName, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
                                detectionScriptContent   = $full.detectionScriptContent
                                remediationScriptContent = $full.remediationScriptContent
                                roleScopeTagIds          = $tags.AllIds
                            } | ConvertTo-Json -Depth 10

                            $newRemediation = Invoke-MgGraphRequest -Method POST -Uri "$graphRoot/deviceManagement/deviceHealthScripts" -Body $body -ContentType "application/json"

                            if (-not $newRemediation.roleScopeTagIds -or @($tags.AllIds | Where-Object { $_ -notin $newRemediation.roleScopeTagIds }).Count -gt 0) {
                                Write-Information "Patching scope tags on remediation script..." -InformationAction Continue
                                $patch = @{ roleScopeTagIds = $tags.AllIds } | ConvertTo-Json
                                Invoke-MgGraphRequest -Method PATCH -Uri "$graphRoot/deviceManagement/deviceHealthScripts/$($newRemediation.id)" -Body $patch -ContentType "application/json" | Out-Null
                            }

                            $results += @{
                                SourceScript = $sourceName
                                NewScript    = $newName
                                Action       = "CLONED"
                            }
                        }
                        catch {
                            Write-Warning "Clone failed for '$sourceName': $($_.Exception.Message)"
                            $results += @{
                                SourceScript = $sourceName
                                NewScript    = $newName
                                Action       = "FAILED"
                            }
                        }
                    }
                }
            }

            $results | ForEach-Object {
                Write-Information ("  {0,-40} -> {1,-40}  [{2}]" -f $_['SourceScript'], $_['NewScript'], $_['Action']) -InformationAction Continue
            }
            Write-Information "" -InformationAction Continue
            Write-Information "Remediation script clone operation complete." -InformationAction Continue
            return
        }

        # --- Interactive mode ---
        while ($true) {
            try {
                $selectedItem = Select-ByNumber -Items $remediations
            }
            catch {
                Write-Warning "$($_.Exception.Message)"
                break
            }

            if ($null -eq $selectedItem) {
                break
            }

            $defaultName = $selectedItem.displayName
            if (-not $defaultName -or $defaultName.Trim() -eq "") { $defaultName = $selectedItem.name }

            $currentExisting = Get-ExistingRemediationNames -GraphRoot $graphRoot

            if ($WhatIfMode) {
                $candidateName = New-UniqueCloneName -BaseName $defaultName -ExistingNames $currentExisting
                Write-Information "WOULD CLONE remediation: '$defaultName' -> '$candidateName'" -InformationAction Continue
                $results += @{
                    SourceScript = $defaultName
                    NewScript    = $candidateName
                    Action       = "WOULD CLONE"
                }
            }
            else {
                $newName = Read-UniqueName -Default $defaultName -ExistingNames $currentExisting

                if ($PSCmdlet.ShouldProcess($newName, "Clone remediation script and apply scope tags")) {
                    try {
                        Write-Information "Cloning remediation: $defaultName -> $newName" -InformationAction Continue

                        $full = Invoke-MgGraphRequest -Method GET -Uri "$graphRoot/deviceManagement/deviceHealthScripts/$($selectedItem.id)"

                        $body = @{
                            displayName              = $newName
                            description              = ("Cloned from '{0}' on {1}" -f $defaultName, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
                            detectionScriptContent   = $full.detectionScriptContent
                            remediationScriptContent = $full.remediationScriptContent
                            roleScopeTagIds          = $tags.AllIds
                        } | ConvertTo-Json -Depth 10

                        $newRemediation = Invoke-MgGraphRequest -Method POST -Uri "$graphRoot/deviceManagement/deviceHealthScripts" -Body $body -ContentType "application/json"

                        if (-not $newRemediation.roleScopeTagIds -or @($tags.AllIds | Where-Object { $_ -notin $newRemediation.roleScopeTagIds }).Count -gt 0) {
                            Write-Information "Patching scope tags on remediation script..." -InformationAction Continue
                            $patch = @{ roleScopeTagIds = $tags.AllIds } | ConvertTo-Json
                            Invoke-MgGraphRequest -Method PATCH -Uri "$graphRoot/deviceManagement/deviceHealthScripts/$($newRemediation.id)" -Body $patch -ContentType "application/json" | Out-Null
                        }

                        $results += @{
                            SourceScript = $defaultName
                            NewScript    = $newName
                            Action       = "CLONED"
                        }
                    }
                    catch {
                        Write-Warning "Clone failed for '$defaultName': $($_.Exception.Message)"
                        $results += @{
                            SourceScript = $defaultName
                            NewScript    = $newName
                            Action       = "FAILED"
                        }
                    }
                }
            }

            $again = (Read-Host "Clone another? (y/n)").Trim().ToLowerInvariant()
            if ($again -notin @('y', 'yes')) {
                break
            }
        }

        if ($results.Count -gt 0) {
            $results | ForEach-Object {
                Write-Information ("  {0,-40} -> {1,-40}  [{2}]" -f $_['SourceScript'], $_['NewScript'], $_['Action']) -InformationAction Continue
            }
        }

        Write-Information "" -InformationAction Continue
        Write-Information "Remediation script clone operation complete." -InformationAction Continue
    }

    end {
    }
}
