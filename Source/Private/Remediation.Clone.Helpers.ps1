# Private\Remediation.Clone.Helpers.ps1

if (-not (Test-Path function:\Get-AllPages)) {
    function Get-AllPages {
        param([Parameter(Mandatory)][string]$Uri)
        $items = @()
        $resp  = Invoke-MgGraphRequest -Method GET -Uri $Uri
        if ($resp.value) { $items += $resp.value } else { return ,$resp }
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            $items += $resp.value
        }
        return $items
    }
}

if (-not (Test-Path function:\Resolve-ScopeTags)) {
    function Resolve-ScopeTags {
        param(
            [Parameter(Mandatory)][string]  $SourceScopeTagName,
            [Parameter(Mandatory)][string[]]$DestinationScopeTagName
        )
        # Try v1 first, then beta
        try {
            $rv1 = Invoke-MgGraphRequest -Method GET -Uri "$script:GraphV1/deviceManagement/roleScopeTags?`$select=id,displayName&`$top=999" -ErrorAction Stop
            $tags = $rv1.value
        } catch {
            $rb  = Invoke-MgGraphRequest -Method GET -Uri "$script:GraphBeta/deviceManagement/roleScopeTags?`$select=id,displayName&`$top=999"
            $tags = $rb.value
        }
        if (-not $tags) { throw "No scope tags returned from Graph." }

        $src = $tags | Where-Object { $_.displayName -ieq $SourceScopeTagName }
        if (-not $src) { throw "Source scope tag '$SourceScopeTagName' not found." }

        $dstIds = foreach($dn in $DestinationScopeTagName){
            $m = $tags | Where-Object { $_.displayName -ieq $dn }
            if (-not $m) { throw "Destination scope tag '$dn' not found." }
            $m.id
        }

        @{
            SrcId  = $src.id
            AllIds = (@($src.id) + $dstIds | Select-Object -Unique)
        }
    }
}

function Test-DeviceHealthScriptsOn {
    param([Parameter(Mandatory)][string]$Base)
    try {
        $null = Invoke-MgGraphRequest -Method GET -Uri "$Base/deviceManagement/deviceHealthScripts?`$top=1" -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-SourceTaggedRemediations {
    param([Parameter(Mandatory)][string]$SourceTagId)
    $all = Get-AllPages -Uri "$script:GraphApi/deviceManagement/deviceHealthScripts?`$top=999"
    $all | Where-Object {
        $tags = @($_.roleScopeTagIds) | Where-Object { $_ }
        $tags -contains $SourceTagId
    }
}

function Get-RemediationById {
    param([Parameter(Mandatory)][string]$Id)
    $full = Invoke-MgGraphRequest -Method GET -Uri "$script:GraphApi/deviceManagement/deviceHealthScripts/$Id"
    if (-not $full.detectionScriptContent -and $script:GraphApi -ne $script:GraphBeta) {
        try { $full = Invoke-MgGraphRequest -Method GET -Uri "$script:GraphBeta/deviceManagement/deviceHealthScripts/$Id" } catch {}
    }
    return $full
}

function Normalize-ComparableName([string]$s){
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    $s = $s -replace "[\u2010\u2011\u2012\u2013\u2014\u2212]", "-"
    $s = $s -replace "[\u00A0]", " "
    $s = $s -replace "\s+", " "
    $s = $s.Trim()
    return $s.ToLowerInvariant()
}

function Get-ExistingRemediationNames {
    $all = Get-AllPages -Uri "$script:GraphApi/deviceManagement/deviceHealthScripts?`$top=999"
    $all | ForEach-Object {
        $nm = $_.displayName; if ([string]::IsNullOrWhiteSpace($nm)) { $nm = $_.name }
        $nm
    }
}

function Name-Exists {
    param([Parameter(Mandatory)][string]$Name)
    $probe = Normalize-ComparableName $Name
    $existing = Get-ExistingRemediationNames | ForEach-Object { Normalize-ComparableName $_ }
    return ($existing -contains $probe)
}

function Read-UniqueRemediationName {
    param([string]$Default = "")
    while ($true) {
        $nm = Read-Host ("Enter NEW name for the clone{0}" -f ($(if ($Default) { " [Default: $Default]" } else { "" })))
        if ([string]::IsNullOrWhiteSpace($nm)) { $nm = $Default }
        $nm = $nm.Trim('"', "'")
        if ([string]::IsNullOrWhiteSpace($nm)) { Write-Host "Name cannot be blank."; continue }
        if (Name-Exists -Name $nm) {
            Write-Host "A remediation named '$nm' already exists. Choose another." -ForegroundColor Yellow
            continue
        }
        return $nm
    }
}

function Copy-OneRemediation {
    param(
        [Parameter(Mandatory)] $SourceListItem,
        [Parameter(Mandatory)] [string] $NewName,
        [Parameter(Mandatory)] [string[]] $RoleScopeTagIds,
        [string] $RoleScopeTagNamesText = ""
    )

    $full = Get-RemediationById -Id $SourceListItem.id
    $srcName = if ([string]::IsNullOrWhiteSpace($full.displayName)) { $full.name } else { $full.displayName }

    $body = @{
        displayName              = $NewName
        description              = ("Cloned from '{0}' on {1:u}" -f $srcName, (Get-Date))
        detectionScriptContent   = $full.detectionScriptContent
        remediationScriptContent = $full.remediationScriptContent
        roleScopeTagIds          = $RoleScopeTagIds
    } | ConvertTo-Json -Depth 10

    try {
        $new = Invoke-MgGraphRequest -Method POST -Uri "$script:GraphApi/deviceManagement/deviceHealthScripts" -Body $body -ContentType "application/json" -ErrorAction Stop
    } catch {
        if ($script:GraphApi -ne $script:GraphBeta) {
            $new = Invoke-MgGraphRequest -Method POST -Uri "$script:GraphBeta/deviceManagement/deviceHealthScripts" -Body $body -ContentType "application/json"
        } else { throw }
    }

    if (-not $new.roleScopeTagIds -or @($RoleScopeTagIds | Where-Object { $_ -notin $new.roleScopeTagIds }).Count -gt 0) {
        $patch = @{ roleScopeTagIds = $RoleScopeTagIds } | ConvertTo-Json
        Invoke-MgGraphRequest -Method PATCH -Uri "$script:GraphBeta/deviceManagement/deviceHealthScripts/$($new.id)" -Body $patch -ContentType "application/json" | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace($RoleScopeTagNamesText)) { $RoleScopeTagNamesText = ($RoleScopeTagIds -join ",") }
    Write-Host ("Cloned: '{0}' - '{1}' (tags: {2})" -f $srcName, $NewName, $RoleScopeTagNamesText)
    return $new
}

function Select-RemediationByNumber {
    param([Parameter(Mandatory)]$Items)
    if (-not $Items -or $Items.Count -eq 0) { throw "No matching remediations found." }

    $view = $Items | ForEach-Object {
        $nm = $_.displayName; if ([string]::IsNullOrWhiteSpace($nm)) { $nm = $_.name }
        $_ | Select-Object `
            @{n='Id';e={$_.id}},
            @{n='Name';e={$nm}},
            @{n='Description';e={$_.description}},
            @{n='Raw';e={$_}}
    }

    $ordered = $view | Sort-Object Name
    Write-Host ""
    Write-Host "Remediations:"
    for ($i=0; $i -lt $ordered.Count; $i++) {
        $num = $i + 1
        Write-Host ("{0,3}. {1}" -f $num, $ordered[$i].Name)
    }
    Write-Host ""

    while ($true) {
        $choice = Read-Host ("Enter number 1-{0} (or Enter to cancel)" -f $ordered.Count)
        if ([string]::IsNullOrWhiteSpace($choice)) { return $null }
        if ($choice -as [int]) {
            $n = [int]$choice
            if ($n -ge 1 -and $n -le $ordered.Count) { return $ordered[$n-1].Raw }
        }
        Write-Host "Invalid selection."
    }
}
