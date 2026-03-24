function Copy-IntunePlatformScript {
<#
.SYNOPSIS
    Clones Intune platform scripts with scope tag management.

.DESCRIPTION
    Discovers platform scripts tagged with exactly the source scope tag, then creates clones with the destination scope tags applied; supports interactive picker or direct name specification.

.PARAMETER SourceScopeTagName
    The display name of the scope tag used to find source scripts (exact match).

.PARAMETER DestinationScopeTagName
    One or more scope tag display names to apply to the cloned script.

.PARAMETER ScriptName
    One or more exact script names to clone directly; if omitted, an interactive picker is shown.

.PARAMETER NewScriptName
    The name for the cloned script; if omitted, a unique name is auto-generated.

.EXAMPLE
    # Interactively select and clone a platform script.
    Copy-IntunePlatformScript -SourceScopeTagName "Production" -DestinationScopeTagName "Development"

.EXAMPLE
    # Fully automated clone with a specified new name.
    Copy-IntunePlatformScript -SourceScopeTagName "Production" -DestinationScopeTagName "Development" -ScriptName "Send Compliance Log" -NewScriptName "New Send Compliance Log"
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
        [string[]]$ScriptName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$NewScriptName
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

        function Get-SourceTaggedPlatforms {
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

            Write-Verbose "Querying platform scripts..."
            $allScripts = Get-AllPages -Uri "$GraphRoot/deviceManagement/deviceManagementScripts?`$top=999"

            $filtered = @()
            foreach ($script in $allScripts) {
                $tags = @($script.roleScopeTagIds)
                if ($tags.Count -eq $SourceTagIds.Count) {
                    $allMatch = $true
                    foreach ($tagId in $SourceTagIds) {
                        if ($tags -notcontains $tagId) {
                            $allMatch = $false
                            break
                        }
                    }
                    if ($allMatch) {
                        $filtered += $script
                    }
                }
            }

            Write-Verbose "Found $($filtered.Count) platform scripts with exact source tag match."
            return ,$filtered
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
                throw "No matching platform scripts found."
            }

            $view = @()
            foreach ($item in $Items) {
                $displayNameVal = if ($item -is [hashtable]) { $item['displayName'] } else { $item.displayName }
                $nameVal = if ($item -is [hashtable]) { $item['name'] } else { $item.name }
                $idVal = if ($item -is [hashtable]) { $item['id'] } else { $item.id }

                $name = if ([string]::IsNullOrWhiteSpace($displayNameVal)) { $nameVal } else { $displayNameVal }

                $entry = @{
                    Id  = $idVal
                    Name = $name
                    Raw = $item
                }
                $view += $entry
            }

            $ordered = @($view | Sort-Object { $_['Name'] })
            Write-Information "" -InformationAction Continue
            Write-Information "Platform Scripts:" -InformationAction Continue

            for ($i = 0; $i -lt $ordered.Count; $i++) {
                $number = $i + 1
                Write-Information ("{0,3}. {1}" -f $number, $ordered[$i]['Name']) -InformationAction Continue
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
                        return $ordered[$number - 1]['Raw']
                    }
                }

                Write-Warning "Invalid selection."
            }
        }

        function ConvertTo-NormalizedName {
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

        function Get-ExistingPlatformNames {
            [CmdletBinding()]
            [OutputType([System.Collections.Generic.HashSet[string]])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$GraphRoot
            )

            Write-Verbose "Building list of existing platform script names..."
            $names = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

            $allScripts = Get-AllPages -Uri "$GraphRoot/deviceManagement/deviceManagementScripts?`$top=999"

            if ($allScripts) {
                foreach ($script in $allScripts) {
                    $name = if ([string]::IsNullOrWhiteSpace($script.displayName)) {
                        $script.name
                    } else {
                        $script.displayName
                    }

                    if ($name) {
                        $null = $names.Add($name)
                    }
                }
            }

            Write-Verbose "Found $($names.Count) existing platform script names."
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
                $ExistingNames = Get-ExistingPlatformNames -GraphRoot $graphRoot
            }

            while ($true) {
                $promptSuffix = if ($Default) { " [Default: $Default]" } else { "" }
                $name = Read-Host ("Enter NEW name for the clone{0}" -f $promptSuffix)

                if ([string]::IsNullOrWhiteSpace($name)) {
                    $name = $Default
                }

                $name = ConvertTo-NormalizedName -String $name

                if ([string]::IsNullOrWhiteSpace($name)) {
                    Write-Warning "Name cannot be blank."
                    continue
                }

                if ($ExistingNames.Contains($name)) {
                    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $uniqueName = "$name - $timestamp"
                    Write-Information "A platform script named '$name' already exists. Using '$uniqueName' instead." -InformationAction Continue
                    return $uniqueName
                }

                return $name
            }
        }

        function Copy-PlatformScript {
            [CmdletBinding()]
            [OutputType([void])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                $SourceScript,

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

            $sourceName = if ([string]::IsNullOrWhiteSpace($SourceScript.displayName)) {
                $SourceScript.name
            } else {
                $SourceScript.displayName
            }

            Write-Verbose "Cloning platform script: $sourceName"

            $full = Invoke-MgGraphRequest -Method GET -Uri "$GraphRoot/deviceManagement/deviceManagementScripts/$($SourceScript.id)?`$select=scriptContent,displayName,description,enforceSignatureCheck,runAsAccount,fileName"

            if ([string]::IsNullOrWhiteSpace($full.scriptContent)) {
                throw "The source platform script does not contain 'scriptContent'. (Permissions issue or script is empty.)"
            }

            $body = @{
                displayName           = $NewName
                description           = ("Cloned from '{0}' on {1:u}" -f $sourceName, (Get-Date))
                fileName              = if ($full.fileName) { $full.fileName } else { "$NewName.ps1" }
                scriptContent         = $full.scriptContent
                runAsAccount          = $full.runAsAccount
                enforceSignatureCheck = [bool]$full.enforceSignatureCheck
                roleScopeTagIds       = $ScopeTagIds
            } | ConvertTo-Json -Depth 10

            Write-Verbose "Creating platform script: $NewName"
            $newScript = Invoke-MgGraphRequest -Method POST -Uri "$GraphRoot/deviceManagement/deviceManagementScripts" -Body $body -ContentType "application/json"

            if (-not $newScript.roleScopeTagIds -or @($ScopeTagIds | Where-Object { $_ -notin $newScript.roleScopeTagIds }).Count -gt 0) {
                Write-Verbose "Patching scope tags on platform script"
                $patch = @{ roleScopeTagIds = $ScopeTagIds } | ConvertTo-Json
                Invoke-MgGraphRequest -Method PATCH -Uri "$GraphRoot/deviceManagement/deviceManagementScripts/$($newScript.id)" -Body $patch -ContentType "application/json" | Out-Null
            }

            Write-Information ("Cloned Platform Script: '{0}' -> '{1}' (tags: {2})" -f $sourceName, $NewName, ($ScopeTagIds -join ", ")) -InformationAction Continue
        }
    }
    process {
        if ($script:__SkipProcessBlock) { return }

        $tags = Resolve-ScopeTags -SourceScopeTagName $SourceScopeTagName -DestinationScopeTagName $DestinationScopeTagName -GraphRoot $graphRoot
        $scripts = Get-SourceTaggedPlatforms -SourceTagIds $tags.SrcIds -GraphRoot $graphRoot

        if (-not $scripts -or $scripts.Count -eq 0) {
            Write-Information "No platform scripts found with exact source tag match '$($SourceScopeTagName -join ', ')'." -InformationAction Continue
            return
        }

        if (-not $script:_AllExistingNames) {
            Write-Verbose "Building list of existing platform script names..."
            $script:_AllExistingNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

            $allScripts = Get-AllPages -Uri "$graphRoot/deviceManagement/deviceManagementScripts?`$top=999"

            if ($allScripts) {
                foreach ($s in $allScripts) {
                    $name = if ([string]::IsNullOrWhiteSpace($s.displayName)) { $s.name } else { $s.displayName }
                    if ($name) {
                        $null = $script:_AllExistingNames.Add($name)
                    }
                }
            }

            Write-Verbose "Found $($script:_AllExistingNames.Count) existing platform script names."
        }

        if ($ScriptName) {
            if ($NewScriptName -and $ScriptName.Count -gt 1) {
                Write-Warning "NewScriptName can only be used when cloning a single script. Ignoring NewScriptName parameter."
                $NewScriptName = $null
            }

            foreach ($name in $ScriptName) {
                $trimmedName = $name.Trim()
                $selectedItem = $scripts | Where-Object {
                    $scriptDisplayName = if ([string]::IsNullOrWhiteSpace($_.displayName)) { $_.name } else { $_.displayName }
                    $scriptDisplayName.Trim() -ieq $trimmedName
                }

                if (-not $selectedItem) {
                    Write-Warning "No source-tagged platform script found named '$name'."
                    continue
                }

                if ($NewScriptName) {
                    $allCurrentScripts = Get-AllPages -Uri "$graphRoot/deviceManagement/deviceManagementScripts?`$top=999"
                    $existingNames = $allCurrentScripts | ForEach-Object {
                        if ([string]::IsNullOrWhiteSpace($_.displayName)) { $_.name } else { $_.displayName }
                    }

                    if ($existingNames -contains $NewScriptName) {
                        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                        $newName = "$NewScriptName - $timestamp"
                        Write-Verbose "Script named '$NewScriptName' already exists. Using '$newName' instead."
                    } else {
                        $newName = $NewScriptName
                    }
                } else {
                    $baseName = if ([string]::IsNullOrWhiteSpace($selectedItem.displayName)) {
                        $selectedItem.name
                    } else {
                        $selectedItem.displayName
                    }

                    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $newName = "Copy of $baseName - $timestamp"
                }

                try {
                    if ($PSCmdlet.ShouldProcess($newName, "Clone platform script and apply scope tags")) {
                        Copy-PlatformScript -SourceScript $selectedItem -NewName $newName -ScopeTagIds $tags.AllIds -GraphRoot $graphRoot
                    }
                } catch {
                    Write-Warning "Clone failed: $($_.Exception.Message)"
                }
            }

            Write-Information "Done." -InformationAction Continue
            return
        }

        while ($true) {
            $selectedItem = Select-ByNumber -Items $scripts

            if ($null -eq $selectedItem) {
                break
            }

            $defaultName = if ([string]::IsNullOrWhiteSpace($selectedItem.displayName)) {
                $selectedItem.name
            } else {
                $selectedItem.displayName
            }

            $currentExisting = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
            $allScripts = Get-AllPages -Uri "$graphRoot/deviceManagement/deviceManagementScripts?`$top=999"
            foreach ($s in $allScripts) {
                $nm = if ([string]::IsNullOrWhiteSpace($s.displayName)) { $s.name } else { $s.displayName }
                if ($nm) { $null = $currentExisting.Add($nm) }
            }

            $newName = Read-UniqueName -Default $defaultName -ExistingNames $currentExisting

            try {
                if ($PSCmdlet.ShouldProcess($newName, "Clone platform script and apply scope tags")) {
                    Copy-PlatformScript -SourceScript $selectedItem -NewName $newName -ScopeTagIds $tags.AllIds -GraphRoot $graphRoot
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
