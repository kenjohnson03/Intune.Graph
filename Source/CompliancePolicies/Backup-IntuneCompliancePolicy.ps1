# Write the comment-based HELP for Backup-IntuneCompliancePolicy
<#
.SYNOPSIS
    Backs up Intune compliance policies.

.DESCRIPTION
    Backs up Intune compliance policies.

.PARAMETER Name
    The name of the compliance policy to backup. This is case sensitive and uses the startswith filter operator.

.PARAMETER Id
    The id of the compliance policy to backup.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.PARAMETER All
    Backup all compliance policies.

.PARAMETER IncludeTags
    Include role scope tags in the backup.

.EXAMPLE
    # Backup all configuration profiles.
    Backup-IntuneCompliancePolicy -All

.EXAMPLE
    # Backup a compliance policy by name.
    Backup-IntuneCompliancePolicy -Name "MyCompliancePolicy"

.EXAMPLE
    # Backup a compliance policy by id.
    Backup-IntuneCompliancePolicy -Id "12345678-1234-1234-1234-123456789012"

.EXAMPLE    
    # Backup a compliance policy by name in the USGov environment.
    Backup-IntuneCompliancePolicy -Name "MyConfigurationProfile" -Environment USGov

.EXAMPLE
    # Backup a compliance policy by id in the USGov environment.
    Backup-IntuneCompliancePolicy -Id "12345678-1234-1234-1234-123456789012" -Environment USGov

#>
function Backup-IntuneCompliancePolicy
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
        $policies = @()
        if($All)
        {
            $policies += Get-IntuneCompliancePolicy -All -Environment $Environment
        }

        if($Name)
        {
            $policies += Get-IntuneCompliancePolicy -Name $Name -Environment $Environment
        }

        if($Id)
        {
            $policies += Get-IntuneCompliancePolicy -Id $Id -Environment $Environment
        }

        $backupPolicies = @()

        foreach($policy in $policies)
        {

            $assignments = Get-IntuneCompliancePolicyAssignments -Id $policy.id -Environment $Environment

            $filters = @()
            foreach($assignment in $assignments)
            {
                if($null -ne $assignment.target.deviceAndAppManagementAssignmentFilterId)
                {
                    $filters += Get-IntuneFilter -Id $assignment.target.deviceAndAppManagementAssignmentFilterId -Environment $Environment
                }
            }

            $policy | Add-Member -MemberType NoteProperty -Name assignments -value $assignments
            $policy | Add-Member -MemberType NoteProperty -Name filters -value $filters

            $backupPolicies += $policy

        }

        # TODO: Add Security Group Names to the backup

        $backup = [PSCustomObject]@{
            configurations = $backupPolicies
            backupDate = Get-Date
        }

        return $backup
    }
}