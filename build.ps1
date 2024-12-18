param (
    [Parameter(Mandatory, ParameterSetName="Publish", HelpMessage="NuGet API Key")]
    [string]$NUGET_API_KEY,
    [Parameter(Mandatory, ParameterSetName="SkipReadMe", HelpMessage="Skip updating README.md")]
    [Parameter(ParameterSetName="SkipPublishModule", HelpMessage="Skip updating README.md")]
    [Parameter(ParameterSetName="Publish", HelpMessage="Skip updating README.md")]
    [switch]$SkipReadMe,
    [Parameter(Mandatory, ParameterSetName="SkipPublishModule", HelpMessage="Skip publishing module to PSGallery")]
    [Parameter(ParameterSetName="SkipReadMe", HelpMessage="Skip publishing module to PSGallery")]
    [switch]$SkipPublishModule,
    [Parameter(ParameterSetName="SkipPublishModule", HelpMessage="Keep output")]
    [switch]$KeepOutput
)

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
import-module PowerShellGet -MinimumVersion 2.0.0 -Force
Import-PackageProvider -Name PowerShellGet -MinimumVersion 2.0.0 -Force

# Update Module Manifest
$ModuleManifestPath = "$scriptPath\Source\Intune.Graph.psd1"
$ModuleManifest = Import-PowerShellDataFile $ModuleManifestPath
$ModuleVersion = $ModuleManifest.ModuleVersion.Split(".")
$UpdatedModuleVersion = "{0}.{1}.{2}" -f $ModuleVersion[0],$ModuleVersion[1],([int]$ModuleVersion[2]+1)
Update-ModuleManifest -Path $ModuleManifestPath -ModuleVersion $UpdatedModuleVersion
Update-ModuleManifest -Path $ModuleManifestPath -Author "Ken Johnson"
Update-ModuleManifest -Path $ModuleManifestPath -CompanyName "Ken Johnson"
Update-ModuleManifest -Path $ModuleManifestPath -Description "IntuneGraph is a PowerShell module that makes it easy to work with the Microsoft Graph API from PowerShell. It handles the HTTP connection, and provides an object-oriented wrapper around the Graph API endpoints. It also provides some additional functionality that makes working with Intune in the Graph API from PowerShell a breeze."
#Update-ModuleManifest -Path $ModuleManifestPath -RequiredModules @()
Update-ModuleManifest -Path $ModuleManifestPath -Tags 'Intune','Graph','ConfigurationProfile','CompliancePolicy','PowerShell'
Update-ModuleManifest -Path $ModuleManifestPath -ProjectUri "https://github.com/kenjohnson03/Intune.Graph"
Update-ModuleManifest -Path $ModuleManifestPath -ReleaseNotes ""

if($false -eq $SkipReadMe)
{
    # Update README.md
    $ReadmePath = "$scriptPath\README.md"
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
Copy-Item -Path "$scriptPath\Source\*" -Recurse -Destination $BuildPath

if($false -eq $SkipPublishModule)
{
    $ModuleManifest = Import-PowerShellDataFile $ModuleManifestPath
    $PublishData = $ModuleManifest.PrivateData
    $PublishParameters = @{
        Path = $BuildPath
        NuGetApiKey = $NUGET_API_KEY
        Repository = "PSGallery"
        Tags = $PublishData.PSData.Tags
        ProjectUri = $PublishData.PSData.ProjectUri
    }
    # Publish module
    Publish-Module @PublishParameters 
}

if($KeepOutput -eq $false)
{
    # Remove build directory
    Remove-Item -Path "$scriptpath\bin" -Recurse -Force
}
