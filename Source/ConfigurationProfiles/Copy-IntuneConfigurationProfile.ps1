function Copy-IntuneConfigurationProfile {
<#
.SYNOPSIS
    Clones Intune configuration profiles with scope tag management.

.DESCRIPTION
    Discovers Settings Catalog, Endpoint Security, Administrative Template, and OMA-URI profiles tagged with the source scope tag, then creates clones with destination scope tags applied; supports interactive picker or direct name specification.

.PARAMETER SourceScopeTagName
    One or more display names of the scope tags used to find source profiles.

.PARAMETER DestinationScopeTagName
    One or more scope tag display names to apply to the cloned profile.

.PARAMETER ProfileName
    One or more exact profile names to clone directly; if omitted, an interactive picker is shown.

.PARAMETER NewProfileName
    The name for the cloned profile; if omitted, a unique name is auto-generated.

.PARAMETER ExactMatch
    When specified, only profiles whose scope tags match the source tag(s) exactly are returned; by default any profile containing the source tag(s) is matched.

.PARAMETER MaxRetries
    The maximum number of retries for throttled (HTTP 429) Graph API requests. Default is 5.

.EXAMPLE
    # Interactively select and clone a configuration profile.
    Copy-IntuneConfigurationProfile -SourceScopeTagName "Production" -DestinationScopeTagName "Development"

.EXAMPLE
    # Fully automated clone with a specified name and multiple destination tags.
    Copy-IntuneConfigurationProfile -SourceScopeTagName "Production" -DestinationScopeTagName "Development","Test" -ProfileName "AV Policy" -NewProfileName "New AV Policy"
#>
    [CmdletBinding(PositionalBinding = $true, SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateCount(1, 64)]
        [string[]]$SourceScopeTagName,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [ValidateCount(1, 64)]
        [string[]]$DestinationScopeTagName,

        [Parameter()]
        [string[]]$ProfileName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$NewProfileName,

        [Parameter()]
        [switch]$ExactMatch,

        [Parameter()]
        [ValidateRange(0, 20)]
        [int]$MaxRetries = 5
    )
    begin {
        $ErrorActionPreference = "Stop"

        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph first."
            Write-Warning '  Commercial: Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.ReadWrite.All"'
            Write-Warning '  GCC:        Connect-MgGraph -Environment USGov -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.ReadWrite.All"'
            Write-Warning '  DoD:        Connect-MgGraph -Environment USGovDoD -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.ReadWrite.All"'
            $script:__SkipProcessBlock = $true
            return
        }
        $script:__SkipProcessBlock = $false
        
        switch ($context.Environment) {
            "USGov" { $uri = "https://graph.microsoft.us" }
            "USGovDoD" { $uri = "https://dod-graph.microsoft.us" }
            Default { $uri = "https://graph.microsoft.com" }
        }
        
        Write-Verbose "Using Graph environment: $($context.Environment) -> $uri"

        $graphRoot = "$uri/beta"

        # ── Retry-aware Graph request wrapper ──────────────────────────────
        # Handles HTTP 429 throttling with Retry-After header support and
        # exponential backoff with jitter. All other errors are thrown immediately.
        function Invoke-MgGraphRequestWithRetry {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
                [string]$Method,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$Uri,

                [Parameter()]
                [string]$Body,

                [Parameter()]
                [string]$ContentType,

                [Parameter()]
                [int]$MaxRetries = 5
            )

            $attempt = 0

            while ($true) {
                try {
                    $params = @{
                        Method = $Method
                        Uri    = $Uri
                    }
                    if ($Body) { $params['Body'] = $Body }
                    if ($ContentType) { $params['ContentType'] = $ContentType }

                    return (Invoke-MgGraphRequest @params)
                }
                catch {
                    $isThrottled = $false
                    $retryAfterSeconds = $null

                    # Inspect the exception for HTTP 429 status
                    $statusCode = $null
                    if ($_.Exception.Response) {
                        $statusCode = [int]$_.Exception.Response.StatusCode
                    }
                    # Fallback: check the error message for 429 indication
                    if ($statusCode -eq 429) {
                        $isThrottled = $true
                    }
                    elseif ($_.Exception.Message -match '429' -or ($_.ErrorDetails.Message -and $_.ErrorDetails.Message -match 'throttl')) {
                        $isThrottled = $true
                    }

                    if (-not $isThrottled -or $attempt -ge $MaxRetries) {
                        throw
                    }

                    # Parse Retry-After header if available
                    if ($_.Exception.Response.Headers) {
                        $retryHeader = $null
                        try {
                            $retryHeader = $_.Exception.Response.Headers | Where-Object { $_.Key -ieq 'Retry-After' }
                            if ($retryHeader) {
                                $headerValue = if ($retryHeader.Value -is [array]) { $retryHeader.Value[0] } else { $retryHeader.Value }
                                if ($headerValue -as [int]) {
                                    $retryAfterSeconds = [int]$headerValue
                                }
                            }
                        }
                        catch {
                            # Header parsing failed; fall through to exponential backoff
                        }
                    }

                    # Calculate wait time: Retry-After header or exponential backoff with jitter
                    if ($null -eq $retryAfterSeconds -or $retryAfterSeconds -le 0) {
                        # Exponential backoff: 2^attempt seconds + random jitter (0-1s)
                        $backoff = [math]::Pow(2, $attempt)
                        $jitter = Get-Random -Minimum 0 -Maximum 1000
                        $retryAfterSeconds = [math]::Min($backoff + ($jitter / 1000), 120)
                    }
                    else {
                        # Cap server-requested wait at 120 seconds
                        $retryAfterSeconds = [math]::Min($retryAfterSeconds, 120)
                    }

                    $attempt++
                    Write-Warning ("Graph API throttled (429). Retry {0}/{1} in {2:N1}s - {3} {4}" -f $attempt, $MaxRetries, $retryAfterSeconds, $Method, $Uri)
                    Start-Sleep -Milliseconds ([int]($retryAfterSeconds * 1000))
                }
            }
        }

        function Get-AllPages {
            [CmdletBinding()]
            [OutputType([array])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$Uri
            )

            $items = @()
            $response = Invoke-MgGraphRequestWithRetry -Method GET -Uri $Uri -MaxRetries $MaxRetries

            if ($null -eq $response.value) {
                # No .value property at all — return the raw response (single-object endpoint)
                return , $response
            }

            if ($response.value.Count -eq 0) {
                # .value exists but is empty — return empty array
                return , @()
            }

            $items += $response.value

            while ($response.'@odata.nextLink') {
                $response = Invoke-MgGraphRequestWithRetry -Method GET -Uri $response.'@odata.nextLink' -MaxRetries $MaxRetries
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
            $tags = Get-AllPages -Uri ($GraphRoot + '/deviceManagement/roleScopeTags?$select=id,displayName&$top=999')

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

        function Get-SourceTaggedItems {
            [CmdletBinding()]
            [OutputType([array])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string[]]$SourceTagIds,

                [Parameter()]
                [switch]$ExactMatch,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$GraphRoot
            )

            # Shared filter: contains = profile has at least the source tags; exact = has only those tags
            $matchFilter = {
                param($PolicyTagIds)
                if ($ExactMatch -and $PolicyTagIds.Count -ne $SourceTagIds.Count) { return $false }
                foreach ($tagId in $SourceTagIds) {
                    if ($PolicyTagIds -notcontains $tagId) { return $false }
                }
                return $true
            }

            Write-Verbose "Querying Settings Catalog policies..."
            $settingsCatalogPolicies = Get-AllPages -Uri ($GraphRoot + '/deviceManagement/configurationPolicies?$select=id,name,description,roleScopeTagIds,platforms,technologies,templateReference&$expand=settings&$top=999')
            $settingsCatalogHits = $settingsCatalogPolicies | Where-Object {
                & $matchFilter $_.roleScopeTagIds
            } | ForEach-Object {
                $_ | Select-Object `
                    @{ n = 'Type'; e = { 'SC' } },
                    @{ n = 'Name'; e = { $_.name } },
                    @{ n = 'Id'; e = { $_.id } },
                    @{ n = 'Raw'; e = { $_ } }
            }

            Write-Verbose "Querying Endpoint Security intents..."
            $intents = Get-AllPages -Uri ($GraphRoot + '/deviceManagement/intents?$select=id,displayName,roleScopeTagIds,templateId&$top=999')
            $intentHits = $intents | Where-Object {
                & $matchFilter $_.roleScopeTagIds
            } | ForEach-Object {
                $_ | Select-Object `
                    @{ n = 'Type'; e = { 'INTENT' } },
                    @{ n = 'Name'; e = { $_.displayName } },
                    @{ n = 'Id'; e = { $_.id } },
                    @{ n = 'Raw'; e = { $_ } }
            }

            Write-Verbose "Querying Custom Device Configurations (OMA-URI)..."
            $customConfigs = Get-AllPages -Uri ($GraphRoot + '/deviceManagement/deviceConfigurations?$select=id,displayName,roleScopeTagIds&$top=999')
            Write-Verbose "Found $($customConfigs.Count) total device configurations"
            $customHits = $customConfigs | Where-Object {
                if ($_.'@odata.type' -notlike '*windows10CustomConfiguration') { return $false }
                & $matchFilter $_.roleScopeTagIds
            } | ForEach-Object {
                $_ | Select-Object `
                    @{ n = 'Type'; e = { 'CUSTOM' } },
                    @{ n = 'Name'; e = { $_.displayName } },
                    @{ n = 'Id'; e = { $_.id } },
                    @{ n = 'Raw'; e = { $_ } }
            }

            Write-Verbose "Querying Administrative Templates (ADMX-backed)..."
            $admxConfigs = Get-AllPages -Uri ($GraphRoot + '/deviceManagement/groupPolicyConfigurations?$select=id,displayName,description,roleScopeTagIds&$top=999')
            Write-Verbose "Found $($admxConfigs.Count) total Administrative Template configurations"
            $admxHits = $admxConfigs | Where-Object {
                & $matchFilter $_.roleScopeTagIds
            } | ForEach-Object {
                $_ | Select-Object `
                    @{ n = 'Type'; e = { 'ADMX' } },
                    @{ n = 'Name'; e = { $_.displayName } },
                    @{ n = 'Id'; e = { $_.id } },
                    @{ n = 'Raw'; e = { $_ } }
            }

            $allItems = @()
            if ($settingsCatalogHits) { $allItems += @($settingsCatalogHits) }
            if ($intentHits) { $allItems += @($intentHits) }
            if ($customHits) { $allItems += @($customHits) }
            if ($admxHits) { $allItems += @($admxHits) }
            Write-Verbose "Found $($allItems.Count) policies/intents/custom configs/admin templates with source tag match."
            $allItems
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

            $ordered = $Items | Sort-Object Name, Type
            Write-Information "" -InformationAction Continue
            Write-Information "Matching policies:" -InformationAction Continue

            for ($i = 0; $i -lt $ordered.Count; $i++) {
                $number = $i + 1
                $typeLabel = switch ($ordered[$i].Type) {
                    'SC'     { 'Settings Catalog' }
                    'INTENT' { 'Endpoint Security' }
                    'CUSTOM' { 'OMA-URI' }
                    'ADMX'   { 'Admin Template' }
                    Default  { $ordered[$i].Type }
                }
                Write-Information ("{0,3}. [{1}] {2}" -f $number, $typeLabel, $ordered[$i].Name) -InformationAction Continue
            }

            Write-Information "" -InformationAction Continue

            while ($true) {
                $choice = Read-Host ("Enter number 1-{0} (or Enter to cancel)" -f $ordered.Count)

                if (-not $choice -or $choice -match '^\s*$') {
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

            $String = $String.Trim()

            if ($String.Length -ge 2 -and (
                ($String.StartsWith("'") -and $String.EndsWith("'")) -or
                ($String.StartsWith('"') -and $String.EndsWith('"')))) {
                $String = $String.Substring(1, $String.Length - 2)
            }

            $String.Trim()
        }

        function Read-UniqueName {
            [CmdletBinding()]
            [OutputType([string])]
            param (
                [Parameter(Mandatory = $true)]
                $ExistingNames,

                [Parameter()]
                [string]$Default = ""
            )

            while ($true) {
                $promptSuffix = if ($Default) { " [Default: $Default]" } else { "" }
                $name = Read-Host ("Enter NEW name for the clone{0}" -f $promptSuffix)

                if (-not $name -or $name -match '^\s*$') {
                    $name = $Default
                }

                $name = ConvertTo-NormalizedName -String $name

                if (-not $name -or $name -match '^\s*$') {
                    Write-Warning "Name cannot be blank."
                    continue
                }

                if ($ExistingNames.ContainsKey($name.ToLower())) {
                    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $uniqueName = "$name - $timestamp"
                    Write-Information "A policy named '$name' already exists. Using '$uniqueName' instead." -InformationAction Continue
                    return $uniqueName
                }

                return $name
            }
        }

        function Copy-SettingsCatalogPolicy {
            [CmdletBinding()]
            [OutputType([void])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                $Item,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$NewName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                [string[]]$RoleScopeTagIds,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$GraphRoot
            )

            $policy = $Item.Raw
            $cloneStamp = "Cloned from '{0}' ({1}) on {2:u}" -f $policy.name, $policy.id, (Get-Date)
            $originalDesc = $policy.description
            $newDescription = if ($originalDesc) { "$cloneStamp`n`n$originalDesc" } else { $cloneStamp }
            $body = @{
                name = $NewName
                description = $newDescription
                platforms = $policy.platforms
                technologies = $policy.technologies
                roleScopeTagIds = $RoleScopeTagIds
                templateReference = $policy.templateReference
                settings = $policy.settings
            } | ConvertTo-Json -Depth 100

            Write-Verbose "Creating Settings Catalog policy: $NewName"
            $newPolicy = Invoke-MgGraphRequestWithRetry -Method POST -Uri ($GraphRoot + '/deviceManagement/configurationPolicies') -Body $body -ContentType "application/json" -MaxRetries $MaxRetries
            Write-Information ("Cloned Settings Catalog: '{0}' -> '{1}' (tags: {2})" -f $policy.name, $newPolicy.name, ($RoleScopeTagIds -join ", ")) -InformationAction Continue
        }

        function Copy-IntentPolicy {
            [CmdletBinding()]
            [OutputType([void])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                $Item,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$NewName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                [string[]]$RoleScopeTagIds,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$GraphRoot
            )

            $policy = $Item.Raw

            $copyUri = $GraphRoot + "/deviceManagement/intents/$($policy.id)/createCopy"
            $cloneStamp = "Cloned from '{0}' ({1}) on {2:u}" -f $policy.displayName, $policy.id, (Get-Date)
            $originalDesc = $policy.description
            $newDescription = if ($originalDesc) { "$cloneStamp`n`n$originalDesc" } else { $cloneStamp }
            $copyBody = @{
                displayName = $NewName
                description = $newDescription
            } | ConvertTo-Json

            Write-Verbose "Creating copy of intent: $NewName"
            $newIntent = Invoke-MgGraphRequestWithRetry -Method POST -Uri $copyUri -Body $copyBody -ContentType "application/json" -MaxRetries $MaxRetries

            if (-not $newIntent.id) {
                throw "createCopy did not return a new intent id."
            }

            Write-Verbose "Applying scope tags to intent: $($newIntent.id)"
            $patchBody = @{ roleScopeTagIds = $RoleScopeTagIds } | ConvertTo-Json
            Invoke-MgGraphRequestWithRetry -Method PATCH -Uri ($GraphRoot + "/deviceManagement/intents/$($newIntent.id)") -Body $patchBody -ContentType "application/json" -MaxRetries $MaxRetries | Out-Null

            Write-Information ("Cloned Intent: '{0}' -> '{1}' (tags: {2})" -f $policy.displayName, $NewName, ($RoleScopeTagIds -join ", ")) -InformationAction Continue
        }

        function Copy-CustomPolicy {
            [CmdletBinding()]
            [OutputType([void])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                $Item,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$NewName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                [string[]]$RoleScopeTagIds,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$GraphRoot
            )

            $sourcePolicy = Invoke-MgGraphRequestWithRetry -Method GET -Uri ($GraphRoot + "/deviceManagement/deviceConfigurations/$($Item.Id)") -MaxRetries $MaxRetries
            
            $cleanedOmaSettings = @()
            foreach ($setting in $sourcePolicy.omaSettings) {
                $cleanSetting = @{
                    '@odata.type' = $setting.'@odata.type'
                    displayName = $setting.displayName
                    description = $setting.description
                    omaUri = $setting.omaUri
                }

                # Determine if the value needs to be fetched from the secret store
                # Graph masks encrypted values as "****"; secretReferenceValueId holds the key to retrieve them
                $needsSecretFetch = $false
                if ($setting.secretReferenceValueId) {
                    $needsSecretFetch = $true
                }
                elseif ($setting.isEncrypted) {
                    $needsSecretFetch = $true
                }

                if ($setting.'@odata.type' -eq '#microsoft.graph.omaSettingStringXml') {
                    $cleanSetting['fileName'] = $setting.fileName

                    if ($needsSecretFetch) {
                        Write-Verbose "  OMA-URI '$($setting.displayName)': fetching XML from secret reference"
                        $refId = if ($setting.secretReferenceValueId) { $setting.secretReferenceValueId } else { $setting.value }
                        try {
                            $xmlResponse = Invoke-MgGraphRequestWithRetry -Method GET -Uri ($GraphRoot + "/deviceManagement/deviceConfigurations/$($Item.Id)/getOmaSettingPlainTextValue(secretReferenceValueId='$refId')") -MaxRetries $MaxRetries
                            $xmlText = if ($xmlResponse -is [hashtable]) { $xmlResponse.value } else { $xmlResponse }
                        }
                        catch {
                            Write-Warning "  FAILED to retrieve XML value for '$($setting.displayName)' ($($setting.omaUri)): $($_.Exception.Message)"
                            continue
                        }
                        if (-not $xmlText) {
                            Write-Warning "  FAILED to retrieve XML value for '$($setting.displayName)' ($($setting.omaUri)): Graph returned empty content"
                            continue
                        }
                        # CLM-safe base64 encoding via certutil (avoids restricted .NET method calls)
                        $tempIn = Join-Path $env:TEMP "intune_xml_in_$(Get-Random).tmp"
                        $tempOut = Join-Path $env:TEMP "intune_xml_out_$(Get-Random).tmp"
                        try {
                            # Write as UTF-8. On PS 5.1 this adds a BOM; on PS 7+ utf8NoBOM avoids it.
                            if ($PSVersionTable.PSVersion.Major -ge 6) {
                                Set-Content -Path $tempIn -Value $xmlText -NoNewline -Encoding utf8NoBOM
                            }
                            else {
                                Set-Content -Path $tempIn -Value $xmlText -NoNewline -Encoding UTF8
                                # Strip BOM (EF BB BF) that PS 5.1 adds, so certutil encodes clean bytes
                                $rawBytes = Get-Content -Path $tempIn -Encoding Byte -Raw
                                if ($rawBytes.Count -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) {
                                    $noBomBytes = $rawBytes[3..($rawBytes.Count - 1)]
                                    Set-Content -Path $tempIn -Value $noBomBytes -Encoding Byte
                                }
                            }
                            & certutil -encode $tempIn $tempOut 2>&1 | Out-Null
                            $base64Lines = Get-Content -Path $tempOut | Where-Object { $_ -notmatch 'CERTIFICATE' -and $_ -ne '' }
                            $cleanSetting['value'] = $base64Lines -join ''
                        }
                        finally {
                            Remove-Item -Path $tempIn, $tempOut -Force -ErrorAction SilentlyContinue
                        }
                    }
                    else {
                        $cleanSetting['value'] = $setting.value
                    }
                }
                elseif ($setting.'@odata.type' -eq '#microsoft.graph.omaSettingBase64' -and $needsSecretFetch) {
                    $cleanSetting['fileName'] = $setting.fileName
                    Write-Verbose "  OMA-URI '$($setting.displayName)': fetching base64 value from secret store"
                    $refId = if ($setting.secretReferenceValueId) { $setting.secretReferenceValueId } else { $setting.value }
                    try {
                        $b64Response = Invoke-MgGraphRequestWithRetry -Method GET -Uri ($GraphRoot + "/deviceManagement/deviceConfigurations/$($Item.Id)/getOmaSettingPlainTextValue(secretReferenceValueId='$refId')") -MaxRetries $MaxRetries
                        $fetchedValue = if ($b64Response -is [hashtable]) { $b64Response.value } else { $b64Response }
                    }
                    catch {
                        Write-Warning "  FAILED to retrieve base64 value for '$($setting.displayName)' ($($setting.omaUri)): $($_.Exception.Message)"
                        continue
                    }
                    if (-not $fetchedValue) {
                        Write-Warning "  FAILED to retrieve base64 value for '$($setting.displayName)' ($($setting.omaUri)): Graph returned empty content"
                        continue
                    }
                    # getOmaSettingPlainTextValue returns the base64 string directly — no re-encoding needed
                    $cleanSetting['value'] = $fetchedValue
                }
                elseif ($setting.'@odata.type' -eq '#microsoft.graph.omaSettingBase64' -and -not $needsSecretFetch) {
                    $cleanSetting['fileName'] = $setting.fileName
                    $cleanSetting['value'] = $setting.value
                }
                elseif ($needsSecretFetch) {
                    Write-Verbose "  OMA-URI '$($setting.displayName)': fetching encrypted value from secret store"
                    $refId = if ($setting.secretReferenceValueId) { $setting.secretReferenceValueId } else { $setting.value }
                    try {
                        $plainResponse = Invoke-MgGraphRequestWithRetry -Method GET -Uri ($GraphRoot + "/deviceManagement/deviceConfigurations/$($Item.Id)/getOmaSettingPlainTextValue(secretReferenceValueId='$refId')") -MaxRetries $MaxRetries
                        $fetchedValue = if ($plainResponse -is [hashtable]) { $plainResponse.value } else { $plainResponse }
                    }
                    catch {
                        Write-Warning "  FAILED to retrieve value for '$($setting.displayName)' ($($setting.omaUri)): $($_.Exception.Message)"
                        continue
                    }
                    if (-not $fetchedValue) {
                        Write-Warning "  FAILED to retrieve value for '$($setting.displayName)' ($($setting.omaUri)): Graph returned empty content"
                        continue
                    }
                    $cleanSetting['value'] = $fetchedValue
                }
                else {
                    $cleanSetting['value'] = $setting.value
                }

                $cleanedOmaSettings += $cleanSetting
            }
            
            $cloneStamp = "Cloned from '{0}' ({1}) on {2:u}" -f $sourcePolicy.displayName, $sourcePolicy.id, (Get-Date)
            $originalDesc = $sourcePolicy.description
            $newDescription = if ($originalDesc) { "$cloneStamp`n`n$originalDesc" } else { $cloneStamp }
            $body = @{
                '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
                displayName = $NewName
                description = $newDescription
                roleScopeTagIds = $RoleScopeTagIds
                omaSettings = $cleanedOmaSettings
            } | ConvertTo-Json -Depth 100

            Write-Verbose "Creating Custom Device Configuration: $NewName"
            $newPolicy = Invoke-MgGraphRequestWithRetry -Method POST -Uri ($GraphRoot + '/deviceManagement/deviceConfigurations') -Body $body -ContentType "application/json" -MaxRetries $MaxRetries
            Write-Information ("Cloned Custom (OMA-URI): '{0}' -> '{1}' (tags: {2})" -f $sourcePolicy.displayName, $newPolicy.displayName, ($RoleScopeTagIds -join ", ")) -InformationAction Continue
        }

        # ── Administrative Template (ADMX-backed) clone ───────────────────
        # groupPolicyConfigurations require a multi-step clone:
        #   1. Create the empty configuration shell
        #   2. Retrieve all definitionValues from the source (with presentationValues expanded)
        #   3. Recreate each definitionValue on the clone with its presentationValues
        function Copy-AdmxPolicy {
            [CmdletBinding()]
            [OutputType([void])]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                $Item,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$NewName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                [string[]]$RoleScopeTagIds,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$GraphRoot
            )

            $sourceId = $Item.Id
            $sourceName = $Item.Name

            # Fetch full source configuration for description
            $sourcePolicy = Invoke-MgGraphRequestWithRetry -Method GET -Uri ($GraphRoot + "/deviceManagement/groupPolicyConfigurations/$sourceId") -MaxRetries $MaxRetries

            $cloneStamp = "Cloned from '{0}' ({1}) on {2:u}" -f $sourceName, $sourceId, (Get-Date)
            $originalDesc = $sourcePolicy.description
            $newDescription = if ($originalDesc) { "$cloneStamp`n`n$originalDesc" } else { $cloneStamp }

            # Step 1: Create the new empty Administrative Template configuration
            $createBody = @{
                displayName     = $NewName
                description     = $newDescription
                roleScopeTagIds = $RoleScopeTagIds
            } | ConvertTo-Json

            Write-Verbose "Creating Administrative Template configuration: $NewName"
            $newConfig = Invoke-MgGraphRequestWithRetry -Method POST -Uri ($GraphRoot + '/deviceManagement/groupPolicyConfigurations') -Body $createBody -ContentType "application/json" -MaxRetries $MaxRetries

            if (-not $newConfig.id) {
                throw "Failed to create Administrative Template configuration - no id returned."
            }

            $newConfigId = $newConfig.id
            Write-Verbose "Created Administrative Template shell: $newConfigId"

            # Step 2: Retrieve all definitionValues from the source
            # GCC/DoD Graph limits $expand depth to 1, so we cannot nest presentationValues($expand=presentation).
            # Instead, fetch definitionValues with definition only, then fetch presentationValues per item.
            $definitionValues = Get-AllPages -Uri ($GraphRoot + "/deviceManagement/groupPolicyConfigurations/$sourceId/definitionValues?`$expand=definition&`$top=999")

            if (-not $definitionValues -or $definitionValues.Count -eq 0) {
                Write-Verbose "Source Administrative Template has no configured settings."
                Write-Information ("Cloned Admin Template (empty): '{0}' -> '{1}' (tags: {2})" -f $sourceName, $NewName, ($RoleScopeTagIds -join ", ")) -InformationAction Continue
                return
            }

            Write-Verbose "Found $($definitionValues.Count) definition values to clone."

            # For each definitionValue, fetch its presentationValues (with presentation expanded) separately
            foreach ($defVal in $definitionValues) {
                try {
                    $pvUri = $GraphRoot + "/deviceManagement/groupPolicyConfigurations/$sourceId/definitionValues/$($defVal.id)/presentationValues?`$expand=presentation"
                    $pvResults = Get-AllPages -Uri $pvUri
                    if ($pvResults -and @($pvResults).Count -gt 0) {
                        $firstItem = @($pvResults)[0]
                        if ($firstItem -is [hashtable] -and ($firstItem.ContainsKey('@odata.type') -or $firstItem.ContainsKey('presentation'))) {
                            $defVal | Add-Member -NotePropertyName presentationValues -NotePropertyValue @($pvResults) -Force
                        }
                    }
                }
                catch {
                    Write-Verbose "  Could not fetch presentationValues for definitionValue $($defVal.id): $($_.Exception.Message)"
                }
            }

            # Step 3: Recreate each definitionValue on the new configuration
            $clonedCount = 0
            $failedCount = 0

            foreach ($defVal in $definitionValues) {
                # Build the definitionValue payload
                # Only use definition@odata.bind (not a nested definition object) for GCC compatibility
                $defValBody = @{
                    enabled = $defVal.enabled
                    'definition@odata.bind' = ($GraphRoot + "/deviceManagement/groupPolicyDefinitions('$($defVal.definition.id)')")
                }

                # Rebuild presentationValues if present
                if ($defVal.presentationValues -and $defVal.presentationValues.Count -gt 0) {
                    $presValues = @()

                    foreach ($pv in $defVal.presentationValues) {
                        $presVal = @{
                            '@odata.type' = $pv.'@odata.type'
                            'presentation@odata.bind' = ($GraphRoot + "/deviceManagement/groupPolicyDefinitions('$($defVal.definition.id)')/presentations('$($pv.presentation.id)')")
                        }

                        # Copy the value property based on the presentation type
                        # Different @odata.type values use different value property names
                        # IMPORTANT: Only copy clean name/value pairs for list types (strip read-only properties)
                        switch -Wildcard ($pv.'@odata.type') {
                            '*#microsoft.graph.groupPolicyPresentationValueText' {
                                $presVal['value'] = $pv.value
                            }
                            '*#microsoft.graph.groupPolicyPresentationValueDecimal' {
                                $presVal['value'] = $pv.value
                            }
                            '*#microsoft.graph.groupPolicyPresentationValueBoolean' {
                                $presVal['value'] = $pv.value
                            }
                            '*#microsoft.graph.groupPolicyPresentationValueLongDecimal' {
                                $presVal['value'] = $pv.value
                            }
                            '*#microsoft.graph.groupPolicyPresentationValueList' {
                                # Clean list values to only name + value (strip createdDateTime, lastModifiedDateTime, etc.)
                                $cleanValues = @()
                                foreach ($listItem in $pv.values) {
                                    $cleanValues += @{ name = $listItem.name; value = $listItem.value }
                                }
                                $presVal['values'] = $cleanValues
                            }
                            '*#microsoft.graph.groupPolicyPresentationValueMultiText' {
                                $presVal['values'] = $pv.values
                            }
                            Default {
                                # Fallback: copy 'value' if it exists, then 'values'
                                if ($null -ne $pv.value) { $presVal['value'] = $pv.value }
                                if ($null -ne $pv.values) { $presVal['values'] = $pv.values }
                            }
                        }

                        $presValues += $presVal
                    }

                    $defValBody['presentationValues'] = $presValues
                }

                $defValJson = $defValBody | ConvertTo-Json -Depth 50

                try {
                    Write-Verbose "  Posting definitionValue for '$($defVal.definition.displayName)' ($($defValJson.Length) bytes)"
                    Invoke-MgGraphRequestWithRetry -Method POST -Uri ($GraphRoot + "/deviceManagement/groupPolicyConfigurations/$newConfigId/definitionValues") -Body $defValJson -ContentType "application/json" -MaxRetries $MaxRetries | Out-Null
                    $clonedCount++
                }
                catch {
                    $failedCount++
                    $settingName = if ($defVal.definition.displayName) { $defVal.definition.displayName } else { $defVal.definition.id }
                    Write-Warning "  Failed to clone ADMX setting '$settingName': $($_.Exception.Message)"
                }
            }

            $summary = "Cloned Admin Template: '{0}' -> '{1}' ({2}/{3} settings, tags: {4})" -f $sourceName, $NewName, $clonedCount, ($clonedCount + $failedCount), ($RoleScopeTagIds -join ", ")
            if ($failedCount -gt 0) {
                Write-Warning $summary
            } else {
                Write-Information $summary -InformationAction Continue
            }
        }

        # ── Clone dispatch helper ─────────────────────────────────────────
        # Centralizes the type-based dispatch and error handling used by
        # both automated and interactive modes.
        function Invoke-CloneOperation {
            [CmdletBinding()]
            param ($SelectedItem, [string]$NewName, [string[]]$TagIds, [string]$Root)

            try {
                if ($WhatIfPreference) {
                    Write-Information "What if: Would clone '$($SelectedItem.Name)' as '$NewName' (Type: $($SelectedItem.Type), Tags: $($TagIds -join ', '))" -InformationAction Continue
                }
                elseif ($SelectedItem.Type -eq 'SC') {
                    Copy-SettingsCatalogPolicy -Item $SelectedItem -NewName $NewName -RoleScopeTagIds $TagIds -GraphRoot $Root
                } elseif ($SelectedItem.Type -eq 'INTENT') {
                    Copy-IntentPolicy -Item $SelectedItem -NewName $NewName -RoleScopeTagIds $TagIds -GraphRoot $Root
                } elseif ($SelectedItem.Type -eq 'CUSTOM') {
                    Copy-CustomPolicy -Item $SelectedItem -NewName $NewName -RoleScopeTagIds $TagIds -GraphRoot $Root
                } elseif ($SelectedItem.Type -eq 'ADMX') {
                    Copy-AdmxPolicy -Item $SelectedItem -NewName $NewName -RoleScopeTagIds $TagIds -GraphRoot $Root
                }
            } catch {
                $errMsg = $_.Exception.Message
                if ($_.ErrorDetails.Message) { $errMsg += "`n  Detail: $($_.ErrorDetails.Message)" }
                Write-Warning "Clone failed: $errMsg"
            }
        }
    }
    process {
        if ($script:__SkipProcessBlock) { return }

        $tags = Resolve-ScopeTags -SourceScopeTagName $SourceScopeTagName -DestinationScopeTagName $DestinationScopeTagName -GraphRoot $graphRoot
        $items = Get-SourceTaggedItems -SourceTagIds $tags.SrcIds -ExactMatch:$ExactMatch -GraphRoot $graphRoot

        if (-not $items -or $items.Count -eq 0) {
            $matchType = if ($ExactMatch) { "exact" } else { "contains" }
            Write-Information "No policies found with $matchType source tag match '$($SourceScopeTagName -join ', ')'." -InformationAction Continue
            return
        }

        if ($ProfileName) {
            if ($NewProfileName -and $ProfileName.Count -gt 1) {
                Write-Warning "NewProfileName can only be used when cloning a single profile. Ignoring NewProfileName parameter."
                $effectiveNewName = $null
            }
            else {
                $effectiveNewName = $NewProfileName
            }

            foreach ($policyName in $ProfileName) {
                $trimmedPolicyName = $policyName.Trim()
                $selectedItem = $items | Where-Object { $_.Name.Trim() -ieq $trimmedPolicyName }

                if (-not $selectedItem) {
                    Write-Warning "No source-tagged policy found named '$policyName'."
                    continue
                }

                if ($effectiveNewName) {
                    $allCurrent = Get-AllPages -Uri ($graphRoot + '/deviceManagement/configurationPolicies?$select=id,name&$top=999')
                    $allCurrentIntents = Get-AllPages -Uri ($graphRoot + '/deviceManagement/intents?$select=id,displayName&$top=999')
                    $allCurrentCustom = Get-AllPages -Uri ($graphRoot + '/deviceManagement/deviceConfigurations?$select=id,displayName&$top=999')
                    $allCurrentAdmx = Get-AllPages -Uri ($graphRoot + '/deviceManagement/groupPolicyConfigurations?$select=id,displayName&$top=999')
                    $existingNames = @($allCurrent | ForEach-Object { $_.name }) + @($allCurrentIntents | ForEach-Object { $_.displayName }) + @($allCurrentCustom | ForEach-Object { $_.displayName }) + @($allCurrentAdmx | ForEach-Object { $_.displayName })
                    
                    if ($existingNames -contains $effectiveNewName) {
                        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                        $newName = "$effectiveNewName - $timestamp"
                        Write-Verbose "Policy named '$effectiveNewName' already exists. Using '$newName' instead."
                    } else {
                        $newName = $effectiveNewName
                    }
                } else {
                    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $newName = "Copy of $($selectedItem.Name) - $timestamp"
                }

                Invoke-CloneOperation -SelectedItem $selectedItem -NewName $newName -TagIds $tags.AllIds -Root $graphRoot
            }

            Write-Information "Done." -InformationAction Continue
            return
        }

        while ($true) {
            $selectedItem = Select-ByNumber -Items $items

            if ($null -eq $selectedItem) {
                break
            }

            $currentExisting = @{}
            
            $allSettingsCatalog = Get-AllPages -Uri ($graphRoot + '/deviceManagement/configurationPolicies?$select=id,name&$top=999')
            foreach ($p in $allSettingsCatalog) {
                if ($p.name) { $currentExisting[$p.name.ToLower()] = $true }
            }
            
            $allIntents = Get-AllPages -Uri ($graphRoot + '/deviceManagement/intents?$select=id,displayName&$top=999')
            foreach ($i in $allIntents) {
                if ($i.displayName) { $currentExisting[$i.displayName.ToLower()] = $true }
            }
            
            $allCustom = Get-AllPages -Uri ($graphRoot + '/deviceManagement/deviceConfigurations?$select=id,displayName&$top=999')
            foreach ($c in $allCustom) {
                if ($c.displayName) { $currentExisting[$c.displayName.ToLower()] = $true }
            }

            $allAdmx = Get-AllPages -Uri ($graphRoot + '/deviceManagement/groupPolicyConfigurations?$select=id,displayName&$top=999')
            foreach ($a in $allAdmx) {
                if ($a.displayName) { $currentExisting[$a.displayName.ToLower()] = $true }
            }

            $newName = Read-UniqueName -Default $selectedItem.Name -ExistingNames $currentExisting

            Invoke-CloneOperation -SelectedItem $selectedItem -NewName $newName -TagIds $tags.AllIds -Root $graphRoot

            $again = (Read-Host "Clone another? (y/n)").Trim().ToLower()

            if ($again -notin @('y', 'yes')) {
                break
            }
        }

        Write-Information "Done." -InformationAction Continue
    }
}
