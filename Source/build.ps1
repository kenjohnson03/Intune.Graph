$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

# Update Module Manifest
$ModuleManifestPath = "$scriptPath\IntuneGraph.psd1"
$ModuleManifest = Import-PowerShellDataFile $ModuleManifestPath
$ModuleVersion = $ModuleManifest.ModuleVersion.Split(".")
$UpdatedModuleVersion = "{0}.{1}.{2}" -f $ModuleVersion[0],$ModuleVersion[1],([int]$ModuleVersion[2]+1)
Update-ModuleManifest -Path $ModuleManifestPath -ModuleVersion $UpdatedModuleVersion

# Run tests TODO

# Build module
New-Item -ItemType Directory -Force -Path "$scriptPath\bin"
$BuildPath = "$scriptPath\bin\IntuneGraph\$UpdatedModuleVersion"
New-Item -ItemType Directory -Force -Path $BuildPath
Copy-Item -Path "$scriptPath\IntuneGraph.psd1" -Destination $BuildPath
Copy-Item -Path "$scriptPath\IntuneGraph.psm1" -Destination $BuildPath

# Publish module
Publish-Module -Path $BuildPath -NuGetApiKey $env:NUGET_API_KEY -Repository PSGallery -Force