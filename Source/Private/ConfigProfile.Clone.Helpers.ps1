# Private\ConfigProfile.Clone.Helpers.ps1

function Get-AllPages {
  param([Parameter(Mandatory)][string]$Uri)
  $items=@()
  $resp = Invoke-MgGraphRequest -Method GET -Uri $Uri
  if ($resp.value){ $items += $resp.value } else { return ,$resp }
  while ($resp.'@odata.nextLink') {
    $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
    $items += $resp.value
  }
  $items
}

function Resolve-ScopeTags {
  param(
    [Parameter(Mandatory)][string]  $SourceScopeTagName,
    [Parameter(Mandatory)][string[]]$DestinationScopeTagName
  )
  $tags = Get-AllPages -Uri "$script:GraphBeta/deviceManagement/roleScopeTags?`$select=id,displayName&`$top=999"
  if (-not $tags){ throw "No scope tags returned from Graph." }

  $src = $tags | Where-Object { $_.displayName -ieq $SourceScopeTagName }
  if (-not $src){ throw "Source scope tag '$SourceScopeTagName' not found." }

  $dstIds = foreach($dn in $DestinationScopeTagName){
    $m = $tags | Where-Object { $_.displayName -ieq $dn }
    if (-not $m){ throw "Destination scope tag '$dn' not found." }
    $m.id
  }

  @{ SrcId = $src.id; AllIds = (@($src.id) + $dstIds | Select-Object -Unique) }
}

function Get-SourceTaggedItems {
  param([Parameter(Mandatory)][string]$SourceTagId)

  $sc = Get-AllPages -Uri "$script:GraphBeta/deviceManagement/configurationPolicies?`$select=id,name,roleScopeTagIds,platforms,technologies,templateReference&`$expand=settings&`$top=999"
  $scHit = $sc | Where-Object { $_.roleScopeTagIds -contains $SourceTagId } |
    ForEach-Object {
      $_ | Select-Object `
        @{n='Type';e={'SC'}},
        @{n='Name';e={$_.name}},
        @{n='Id';e={$_.id}},
        @{n='Raw';e={$_}}
    }

  $intents = Get-AllPages -Uri "$script:GraphBeta/deviceManagement/intents?`$select=id,displayName,roleScopeTagIds,templateId&`$top=999"
  $intHit  = $intents | Where-Object { $_.roleScopeTagIds -contains $SourceTagId } |
    ForEach-Object {
      $_ | Select-Object `
        @{n='Type';e={'INTENT'}},
        @{n='Name';e={$_.displayName}},
        @{n='Id';e={$_.id}},
        @{n='Raw';e={$_}}
    }

  @($scHit + $intHit)
}

function Select-ByNumber {
  param([Parameter(Mandatory)]$Items)
  if (-not $Items -or $Items.Count -eq 0){ throw "No matching policies found." }

  $ordered = $Items | Sort-Object Name, Type
  Write-Host ""
  Write-Host "Matching policies:"
  for ($i=0; $i -lt $ordered.Count; $i++){ $n=$i+1; Write-Host ("{0,3}. {1}" -f $n, $ordered[$i].Name) }
  Write-Host ""

  while ($true) {
    $choice = Read-Host ("Enter number 1-{0} (or Enter to cancel)" -f $ordered.Count)
    if ([string]::IsNullOrWhiteSpace($choice)){ return $null }
    if ($choice -as [int]) {
      $n = [int]$choice
      if ($n -ge 1 -and $n -le $ordered.Count){ return $ordered[$n-1] }
    }
    Write-Host "Invalid selection." -ForegroundColor Yellow
  }
}

function Normalize-Name([string]$s){
  if ($null -eq $s){ return "" }
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

  (Get-AllPages -Uri "$script:GraphBeta/deviceManagement/configurationPolicies?`$select=id,name&`$top=999") |
    ForEach-Object { if ($_.name){ $null = $names.Add($_.name) } }

  (Get-AllPages -Uri "$script:GraphBeta/deviceManagement/intents?`$select=id,displayName&`$top=999") |
    ForEach-Object { if ($_.displayName){ $null = $names.Add($_.displayName) } }

  $names
}

function Read-UniqueName {
  param(
    [string]$Default = "",
    [System.Collections.Generic.HashSet[string]]$ExistingNames
  )
  if (-not $ExistingNames){ $ExistingNames = Get-ExistingPolicyNames }

  while ($true) {
    $nm = Read-Host ("Enter NEW name for the clone{0}" -f ($(if ($Default){ " [Default: $Default]" } else { "" })))
    if ([string]::IsNullOrWhiteSpace($nm)){ $nm = $Default }
    $nm = Normalize-Name $nm
    if ([string]::IsNullOrWhiteSpace($nm)){ Write-Host "Name cannot be blank."; continue }

    if ($ExistingNames.Contains($nm)) {
      Write-Host "A policy named '$nm' already exists. Choose another." -ForegroundColor Yellow
      continue
    }

    $null = $ExistingNames.Add($nm)
    return $nm
  }
}

function Clone-Sc {
  param($Item,[string]$NewName,[string[]]$RoleScopeTagIds)
  $p = $Item.Raw
  $body = [ordered]@{
    name              = $NewName
    description       = ("Cloned from '{0}' ({1}) on {2:u}" -f $p.name, $p.id, (Get-Date))
    platforms         = $p.platforms
    technologies      = $p.technologies
    roleScopeTagIds   = $RoleScopeTagIds
    templateReference = $p.templateReference
    settings          = $p.settings
  } | ConvertTo-Json -Depth 100

  $new = Invoke-MgGraphRequest -Method POST -Uri "$script:GraphBeta/deviceManagement/configurationPolicies" -Body $body -ContentType "application/json"
  Write-Host ("Cloned: '{0}' - '{1}' (tags: {2})" -f $p.name, $new.name, ($RoleScopeTagIds -join ", "))
}

function Clone-Intent {
  param($Item,[string]$NewName,[string[]]$RoleScopeTagIds)
  $p = $Item.Raw

  $copyUri  = "$script:GraphBeta/deviceManagement/intents/$($p.id)/createCopy"
  $copyBody = @{ displayName = $NewName; description = ("Cloned from '{0}' ({1}) on {2:u}" -f $p.displayName, $p.id, (Get-Date)) } | ConvertTo-Json
  $new = Invoke-MgGraphRequest -Method POST -Uri $copyUri -Body $copyBody -ContentType "application/json"
  if (-not $new.id){ throw "createCopy did not return a new intent id." }

  $patchBody = @{ roleScopeTagIds = $RoleScopeTagIds } | ConvertTo-Json
  Invoke-MgGraphRequest -Method PATCH -Uri "$script:GraphBeta/deviceManagement/intents/$($new.id)" -Body $patchBody -ContentType "application/json" | Out-Null

  Write-Host ("Cloned: '{0}' - '{1}' (tags: {2})" -f $p.displayName, $NewName, ($RoleScopeTagIds -join ", "))
}
