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

Export-ModuleMember -Function "Get-IntuneConfigurationProfile",
    "New-IntuneConfigurationProfile",
    "Remove-IntuneConfigurationProfile",
    "Get-IntuneConfigurationProfileSettings",
    "Compare-IntuneConfigurationProfileSettings",
    "Sync-IntuneConfigurationProfileSettings",
    "Get-IntuneConfigurationProfileAssignments",
    "New-IntuneConfigurationProfileAssignment",
    "Add-IntuneConfigurationProfileAssignment",
    "Get-IntuneFilter",
    "New-IntuneFilter",
    "Remove-IntuneFilter",
    "Get-IntuneTag",
    "New-IntuneTag",
    "Remove-IntuneTag",
    "Backup-IntuneConfigurationProfile",
    "Invoke-GraphBatchRequest"