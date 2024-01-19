# Write the comment-based HELP for Backup-IntuneConfigurationProfile
<#
.SYNOPSIS
    Backs up Intune configuration profiles.

.DESCRIPTION
    Backs up Intune configuration profiles.

.PARAMETER Name
    The name of the configuration profile to backup. This is case sensitive and uses the startswith filter operator.

.PARAMETER Id
    The id of the configuration profile to backup.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.PARAMETER All
    Backup all configuration profiles.

.PARAMETER IncludeTags
    Include role scope tags in the backup.

.EXAMPLE
    # Backup all configuration profiles.
    Backup-IntuneConfigurationProfile -All

.EXAMPLE
    # Backup a configuration profile by name.
    Backup-IntuneConfigurationProfile -Name "MyConfigurationProfile"

.EXAMPLE
    # Backup a configuration profile by id.
    Backup-IntuneConfigurationProfile -Id "12345678-1234-1234-1234-123456789012"

.EXAMPLE    
    # Backup a configuration profile by name in the USGov environment.
    Backup-IntuneConfigurationProfile -Name "MyConfigurationProfile" -Environment USGov

.EXAMPLE
    # Backup a configuration profile by id in the USGov environment.
    Backup-IntuneConfigurationProfile -Id "12345678-1234-1234-1234-123456789012" -Environment USGov

.EXAMPLE
    # Backup all configuration profiles with role scope tags.
    Backup-IntuneConfigurationProfile -All -IncludeTags

.EXAMPLE
    # Backup a configuration profile by name with role scope tags.
    Backup-IntuneConfigurationProfile -Name "MyConfigurationProfile" -IncludeTags

.EXAMPLE
    # Backup a configuration profile by id with role scope tags.
    Backup-IntuneConfigurationProfile -Id "12345678-1234-1234-1234-123456789012" -IncludeTags

.EXAMPLE
    # Backup a configuration profile by name with role scope tags in the USGov environment.
    Backup-IntuneConfigurationProfile -Name "MyConfigurationProfile" -IncludeTags -Environment USGov

.EXAMPLE
    # Backup a configuration profile by id with role scope tags in the USGov environment.
    Backup-IntuneConfigurationProfile -Id "12345678-1234-1234-1234-123456789012" -IncludeTags -Environment USGov
#>
function Backup-IntuneConfigurationProfile
{
    param(
        [Parameter(Mandatory, ParameterSetName="Name", Position=0)]
        [string]$Name,
        [Parameter(Mandatory, ParameterSetName="Id", Position=1)]
        [string]$Id,
        [Parameter(ParameterSetName="Name")]
        [Parameter(ParameterSetName="Id")]
        [Parameter(ParameterSetName="All")]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global",
        [Parameter(ParameterSetName="Name")]
        [Parameter(ParameterSetName="Id")]
        [Parameter(ParameterSetName="All")]
        [switch]$IncludeTags,
        [Parameter(ParameterSetName="All")]
        [switch]$All
    )

    begin {
        $scopes = @("DeviceManagementConfiguration.Read.All")
        if($IncludeTags)
        {
            $scopes += "DeviceManagementRBAC.Read.All"
        }
        if($false -eq (Initialize-IntuneAccess -Scopes $scopes -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
        {
            return
        }
    }
    process {
        $configurations = @()
        if($All)
        {
            $configurations += Get-IntuneConfigurationProfile -All -Environment $Environment
        }

        if($Name)
        {
            $configurations += Get-IntuneConfigurationProfile -Name $Name -Environment $Environment
        }

        if($Id)
        {
            $configurations += Get-IntuneConfigurationProfile -Id $Id -Environment $Environment
        }

        $backupConfigurations = @()

        foreach($configuration in $configurations)
        {
            $settings = Get-IntuneConfigurationProfileSettings -Id $configuration.id -Environment $Environment

            $assignments = Get-IntuneConfigurationProfileAssignments -Id $configuration.id -Environment $Environment

            $filters = @()
            foreach($assignment in $assignments)
            {
                if($null -ne $assignment.target.deviceAndAppManagementAssignmentFilterId)
                {
                    $filters += Get-IntuneFilter -Id $assignment.target.deviceAndAppManagementAssignmentFilterId -Environment $Environment
                }
            }

            $tags = @()
            if($IncludeTags)
            {
                foreach($roleScope in $configuration.roleScopeTagIds)
                {
                    $tags += Get-IntuneTag -Id $roleScope -Environment $Environment
                }
            }

            $backupConfiguration = [PSCustomObject]@{
                id = $configuration.id
                name = $configuration.name
                description = $configuration.description
                platforms = $configuration.platforms
                technologies = $configuration.technologies
                roleScopeTagIds = $configuration.roleScopeTagIds                
                templateReference = $configuration.templateReference
                settings = $settings
                assignments = $assignments
                filters = $filters
                tags = $tags
            }
            $backupConfigurations += $backupConfiguration
        }
        # TODO: Add Security Group Names to the backup

        $backup = [PSCustomObject]@{
            configurations = $backupConfigurations
            backupDate = Get-Date
        }
        return $backup
    }
}