$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$scripts = Get-ChildItem -Path $scriptPath -Filter *.ps1 -Recurse
foreach($script in $scripts)
{
    . $script.FullName
}
function Initialize-IntuneAccess
{
    param(
        [Parameter(Mandatory)]
        [string[]]$Scopes,
        [Parameter(Mandatory)]
        [string[]]$Modules,
        [Parameter(Mandatory)]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment    
    )

    $missingModules = $false
    foreach($module in $modules)
    {
        if(Get-Module -Name $module -ListAvailable)
        {
            Import-Module $module
        }
        else
        {
            Write-Host "Module $module not found. Please install it and try again." -ForegroundColor Yellow
            $missingModules = $true
        }
    }
    if($missingModules)
    {
        throw "Missing modules.`nInstall-Module $modules"
    }

    # Ensure we have a context
    $context = Get-MgContext
    if($null -eq $context)
    {
        throw "No context found. Please call Connect-MgGraph."
    }

    if($context.Environment -ne $Environment)
    {
        throw "Environment mismatch. Please connect to the graph with the required environment ($environment)"
    }
    
    $missingScopes = $false
    foreach($scope in $scopes)
    {
        if($context.Scopes -notcontains $scope)
        {
            $missingScopes = $true
            Write-Host "Scope $scope not found. Please connect to the graph with the required scopes" -ForegroundColor Yellow
        }
    }
    if($missingScopes)
    {
        throw "Missing scopes.`nConnect-MgGraph -Scopes $scopes -Environment $Environment -UseDeviceCode"
    }

    return $true
}

Export-ModuleMember -Function "Invoke-GraphBatchRequest",
"New-GraphBatchRequest",
"Add-IntuneCompliancePolicyAssignment",
"Backup-IntuneCompliancePolicy",
"Copy-IntuneCompliancePolicy",
"Get-IntuneCompliancePolicy",
"Get-IntuneCompliancePolicyAssignments",
"New-IntuneCompliancePolicyAssignment",
"Remove-IntuneCompliancePolicyAssignment",
"Add-IntuneConfigurationProfileAssignment",
"Backup-IntuneConfigurationProfile",
"Compare-IntuneConfigurationProfileSettings",
"Copy-IntuneConfigurationProfile",
"Get-IntuneConfigurationProfile",
"Get-IntuneConfigurationProfileAssignments",
"Get-IntuneConfigurationProfileSettings",
"New-IntuneConfigurationProfile",
"New-IntuneConfigurationProfileAssignment",
"Remove-IntuneConfigurationProfile",
"Remove-IntuneConfigurationProfileAssignment",
"Sync-IntuneConfigurationProfileSettings",
"Update-IntuneConfigurationProfile",
"Get-IntuneDeviceConfiguration",
"New-IntuneDeviceConfigurationWindows81TrustedRootCertificate",
"New-IntuneTrustedCertificate",
"Remove-IntuneDeviceConfiguration",
"Get-IntuneFilter",
"New-IntuneFilter",
"Remove-IntuneFilter",
"Set-PrimaryUser",
"Get-IntuneTag",
"New-IntuneTag",
"Remove-IntuneTag",
"Add-IntunePlatformScriptAssignment",
"Copy-IntunePlatformScript",
"Get-IntunePlatformScript",
"Get-IntunePlatformScriptAssignments",
"Remove-IntunePlatformScript",
"Remove-IntunePlatformScriptAssignment",
"Add-IntuneRoleAssignmentMember",
"Add-IntuneRoleAssignmentScopeGroup",
"Add-IntuneRoleAssignmentScopeTag",
"Add-IntuneRoleDefinitionPermission",
"Copy-IntuneRoleDefinition",
"Get-IntuneRoleAssignment",
"Get-IntuneRoleDefinition",
"Get-IntuneRoleDefinitionPermissions",
"New-IntuneRoleAssignment",
"New-IntuneRoleDefinition",
"Remove-IntuneRoleAssignment",
"Remove-IntuneRoleAssignmentMember",
"Remove-IntuneRoleAssignmentScopeGroup",
"Remove-IntuneRoleAssignmentScopeTag",
"Remove-IntuneRoleDefinition",
"Remove-IntuneRoleDefinitionPermission",
"Set-IntuneRoleDefinitionPermissions",
"Add-IntuneRemediationScriptAssignment",
"Copy-IntuneRemediationScript",
"Get-IntuneRemediationScript",
"Get-IntuneRemediationScriptAssignments",
"Remove-IntuneRemediationScript",
"Remove-IntuneRemediationScriptAssignment",
"Set-IntuneRemediationScriptDescription",
"Get-IntuneScopeTag",
"Get-IntuneScopeTagAssignment",
"New-IntuneScopeTag",
"Remove-IntuneScopeTag",
"Remove-IntuneScopeTagAssignment",
"Set-IntuneScopeTagAssignment",
"Set-IntuneScopeTagDescription"
    
    
