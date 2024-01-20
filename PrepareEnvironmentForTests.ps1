$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

$ModuleManifestPath = "$scriptPath\Source\Intune.Graph.psd1"
$ModuleManifest = Import-PowerShellDataFile $ModuleManifestPath
$ModuleVersion = $ModuleManifest.ModuleVersion

foreach($modulePath in ($env:PSModulePath -split ";"))
{
    if(Test-Path -Path "$modulePath\Intune.Graph")
    {
        Remove-Item "$modulePath\Intune.Graph" -Recurse -Force | Out-Null
        break
    }
}
$modulePath = $env:PSModulePath.Split(';')[0] + '\Intune.Graph'
Remove-Module -Name Intune.Graph -Force -ErrorAction SilentlyContinue
$BuildPath = "$ModulePath\$ModuleVersion"
New-Item -ItemType Directory -Force -Path $BuildPath | Out-Null
Copy-Item -Path "$scriptPath\Source\*" -Recurse -Destination $BuildPath