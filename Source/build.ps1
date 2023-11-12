param (
    [Parameter(Mandatory, ParameterSetName="Publish", HelpMessage="NuGet API Key")]
    [string]$NUGET_API_KEY,
    [Parameter(Mandatory, ParameterSetName="SkipReadMe", HelpMessage="Skip updating README.md")]
    [Parameter(ParameterSetName="SkipPublishModule", HelpMessage="Skip updating README.md")]
    [switch]$SkipReadMe,
    [Parameter(Mandatory, ParameterSetName="SkipPublishModule", HelpMessage="Skip publishing module to PSGallery")]
    [Parameter(ParameterSetName="SkipReadMe", HelpMessage="Skip publishing module to PSGallery")]
    [switch]$SkipPublishModule
)

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

# Update Module Manifest
$ModuleManifestPath = "$scriptPath\Intune.Graph.psd1"
$ModuleManifest = Import-PowerShellDataFile $ModuleManifestPath
$ModuleVersion = $ModuleManifest.ModuleVersion.Split(".")
$UpdatedModuleVersion = "{0}.{1}.{2}" -f $ModuleVersion[0],$ModuleVersion[1],([int]$ModuleVersion[2]+1)
Update-ModuleManifest -Path $ModuleManifestPath -ModuleVersion $UpdatedModuleVersion

if($false -eq $SkipReadMe)
{
    # Update README.md
    $ReadmePath = "$scriptPath\..\README.md"
    $Readme = Get-Content $ReadmePath
    $Readme[0] = "# Intune.Graph"
    $Readme[1] = "Last Updated: $((Get-Date).ToString('MM/dd/yyyy')) <br/>"
    $Readme[2] = "Last Updated By: $(git log -1 --pretty=%an) <br/>"
    $Readme | Set-Content $ReadmePath
}

# Run tests TODO

# Build module
$BuildPath = "$scriptPath\bin\Intune.Graph\$UpdatedModuleVersion"
New-Item -ItemType Directory -Force -Path $BuildPath | Out-Null
Copy-Item -Path "$scriptPath\Intune.Graph.psd1" -Destination $BuildPath
Copy-Item -Path "$scriptPath\Intune.Graph.psm1" -Destination $BuildPath

if($false -eq $SkipPublishModule)
{
    # Publish module
    Publish-Module -Path $BuildPath -NuGetApiKey $NUGET_API_KEY -Repository PSGallery -Force
}