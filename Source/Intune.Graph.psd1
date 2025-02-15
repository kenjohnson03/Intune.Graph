#
# Module manifest for module 'Intune.Graph'
#
# Generated by: Ken Johnson
#
# Generated on: 2/5/2025
#

@{

# Script module or binary module file associated with this manifest.
RootModule = '.\Intune.Graph.psm1'

# Version number of this module.
ModuleVersion = '0.1.24'

# Supported PSEditions
CompatiblePSEditions = 'Desktop', 'Core'

# ID used to uniquely identify this module
GUID = '8115658a-f654-43b2-8ad6-c12d53d8a707'

# Author of this module
Author = 'Ken Johnson'

# Company or vendor of this module
CompanyName = 'Ken Johnson'

# Copyright statement for this module
Copyright = '(c) Ken Johnson. All rights reserved.'

# Description of the functionality provided by this module
Description = 'IntuneGraph is a PowerShell module that makes it easy to work with the Microsoft Graph API from PowerShell. It handles the HTTP connection, and provides an object-oriented wrapper around the Graph API endpoints. It also provides some additional functionality that makes working with Intune in the Graph API from PowerShell a breeze.'

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '5.1'

# Name of the PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# ClrVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
RequiredModules = @(@{ModuleName = 'Microsoft.Graph.Authentication'; RequiredVersion = '2.25.0'; })

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = 'Invoke-GraphBatchRequest', 'New-GraphBatchRequest', 
               'Add-IntuneCompliancePolicyAssignment', 
               'Backup-IntuneCompliancePolicy', 'Get-IntuneCompliancePolicy', 
               'Get-IntuneCompliancePolicyAssignments', 
               'New-IntuneCompliancePolicyAssignment', 
               'Remove-IntuneCompliancePolicyAssignment', 
               'Add-IntuneConfigurationProfileAssignment', 
               'Backup-IntuneConfigurationProfile', 
               'Compare-IntuneConfigurationProfileSettings', 
               'Get-IntuneConfigurationProfile', 
               'Get-IntuneConfigurationProfileAssignments', 
               'Get-IntuneConfigurationProfileSettings', 
               'New-IntuneConfigurationProfile', 
               'New-IntuneConfigurationProfileAssignment', 
               'Remove-IntuneConfigurationProfile', 
               'Remove-IntuneConfigurationProfileAssignment', 
               'Sync-IntuneConfigurationProfileSettings', 
               'Update-IntuneConfigurationProfile', 
               'Get-IntuneDeviceConfiguration', 
               'New-IntuneDeviceConfigurationWindows81TrustedRootCertificate', 
               'New-IntuneTrustedCertificate', 'Remove-IntuneDeviceConfiguration', 
               'Get-IntuneFilter', 'New-IntuneFilter', 'Remove-IntuneFilter', 
               'Set-PrimaryUser', 'Get-IntuneTag', 'New-IntuneTag', 'Remove-IntuneTag'

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
# VariablesToExport = @()

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    #Name of this module
    Name = 'Intune.Graph'

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = 'Intune','Graph','ConfigurationProfile','CompliancePolicy','PowerShell'

        # A URL to the license for this module.
        # LicenseUri = ''

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/kenjohnson03/Intune.Graph'

        # A URL to an icon representing this module.
        # IconUri = ''

        # ReleaseNotes of this module
        # ReleaseNotes = ''

        # Prerelease string of this module
        # Prerelease = ''

        # Flag to indicate whether the module requires explicit user acceptance for install/update/save
        # RequireLicenseAcceptance = $false

        # External dependent modules of this module
        # ExternalModuleDependencies = @()

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}

