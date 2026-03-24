#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Pester v5 tests for Intune RBAC Automation functions.

.DESCRIPTION
    Tests all RBAC automation functions by mocking Get-MgContext and
    Invoke-MgGraphRequest so no live Graph connection is required.
#>

BeforeAll {
    Get-ChildItem -Path "$PSScriptRoot\..\..\Source" -Filter "*.ps1" -Recurse |
        ForEach-Object { . $_.FullName }

    # --- Shared mock data ---
    $script:MockContext = [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }

    $script:MockRole = @{
        id                      = 'role-id-1'
        displayName             = 'HelpDesk Reader'
        description             = 'Test custom role'
        isBuiltIn               = $false
        isBuiltInRoleDefinition = $false
        roleScopeTagIds         = @('0')
        rolePermissions         = @(
            @{
                resourceActions = @(
                    @{
                        allowedResourceActions = @('microsoft.intune_deviceConfigurations_read')
                    }
                )
            }
        )
    }

    $script:MockBuiltInRole = @{
        id                      = 'builtin-id-1'
        displayName             = 'Help Desk Operator'
        description             = 'Built-in role'
        isBuiltIn               = $true
        isBuiltInRoleDefinition = $true
        rolePermissions         = @(
            @{
                resourceActions = @(
                    @{
                        allowedResourceActions = @('microsoft.intune_remoteTask_initiateDeviceAction')
                    }
                )
            }
        )
    }

    $script:MockRolesResponse          = @{ value = @($script:MockRole) }
    $script:MockBuiltInRolesResponse   = @{ value = @($script:MockBuiltInRole) }

    $script:MockAssignment = @{
        id              = 'assign-id-1'
        displayName     = 'HD-ClientA'
        members         = @('member-group-id-1')
        resourceScopes  = @('scope-group-id-1')
        roleScopeTagIds = @('tag-id-1')
        scopeType       = 'resourceScope'
    }

    $script:MockAssignmentsResponse = @{ value = @($script:MockAssignment) }

    $script:MockMemberGroup    = @{ id = 'member-group-id-1'; displayName = 'SG-HelpDeskTeam' }
    $script:MockNewMemberGroup = @{ id = 'member-group-id-2'; displayName = 'SG-NewTeam' }
    $script:MockScopeGroup     = @{ id = 'scope-group-id-1'; displayName = 'SG-ClientA-Devices' }
    $script:MockNewScopeGroup  = @{ id = 'scope-group-id-2'; displayName = 'SG-NewDevices' }
    $script:MockScopeTag       = @{ id = 'tag-id-1'; displayName = 'ZT-ClientA' }
    $script:MockNewScopeTag    = @{ id = 'tag-id-2'; displayName = 'ZT-NewTag' }

    $script:MockScopeTagsResponse = @{ value = @($script:MockScopeTag) }

    $script:MockCreatedRole = @{
        id          = 'new-role-id-1'
        displayName = 'HelpDesk Reader'
        description = 'Test custom role'
    }
}

# ===========================================================================
#  Get-IntuneRoleDefinition
# ===========================================================================
Describe 'Get-IntuneRoleDefinition' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Get-IntuneRoleDefinition 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - list all roles' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
        }

        It 'calls GET on roleDefinitions' {
            Get-IntuneRoleDefinition
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'GET' }
        }
    }

    Context 'when connected - filter by RoleName' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
        }

        It 'returns results when RoleName matches' {
            Get-IntuneRoleDefinition -RoleName 'HelpDesk Reader'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'GET' }
        }

        It 'does not throw when RoleName does not match' {
            { Get-IntuneRoleDefinition -RoleName 'NonExistent' } | Should -Not -Throw
        }
    }

    Context 'when connected - retrieve by RoleId' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRole }
        }

        It 'calls GET with the specific role ID in the URI' {
            Get-IntuneRoleDefinition -RoleId 'role-id-1'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'GET' -and $Uri -match 'role-id-1'
            }
        }
    }

    Context 'parameter validation' {
        It 'does not throw when called with no parameters' {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
            { Get-IntuneRoleDefinition } | Should -Not -Throw
        }
    }
}

# ===========================================================================
#  New-IntuneRoleDefinition
# ===========================================================================
Describe 'New-IntuneRoleDefinition' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = New-IntuneRoleDefinition -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_deviceConfigurations_read' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - role already exists' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
        }

        It 'reports NO CHANGE and does not POST' {
            New-IntuneRoleDefinition -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_deviceConfigurations_read'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'when connected - role does not exist' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET') { return @{ value = @() } }
                if ($Method -eq 'POST') { return $script:MockCreatedRole }
            }
        }

        It 'creates the role via POST' {
            New-IntuneRoleDefinition -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_deviceConfigurations_read'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { @{ value = @() } }
        }

        It 'does not POST when -WhatIfMode is specified' {
            New-IntuneRoleDefinition -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_deviceConfigurations_read' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command New-IntuneRoleDefinition
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }

        It 'Permissions is mandatory' {
            $cmd = Get-Command New-IntuneRoleDefinition
            $cmd.Parameters['Permissions'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Copy-IntuneRoleDefinition
# ===========================================================================
Describe 'Copy-IntuneRoleDefinition' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Copy-IntuneRoleDefinition -SourceRoleName 'HelpDesk Reader' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - happy path' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$') { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions/role-id-1$') { return $script:MockRole }
                if ($Method -eq 'POST') { return $script:MockCreatedRole }
                return @{ value = @() }
            }
        }

        It 'POSTs the cloned role definition' {
            Copy-IntuneRoleDefinition -SourceRoleName 'HelpDesk Reader' -NewRoleName 'Copy of HelpDesk Reader'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$') { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions/role-id-1') { return $script:MockRole }
                return @{ value = @() }
            }
        }

        It 'does not POST when -WhatIfMode is specified' {
            Copy-IntuneRoleDefinition -SourceRoleName 'HelpDesk Reader' -NewRoleName 'Copy of HelpDesk Reader' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'when source role is not found' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { @{ value = @() } }
        }

        It 'throws when the source role does not exist' {
            { Copy-IntuneRoleDefinition -SourceRoleName 'NonExistent' } | Should -Throw
        }
    }

    Context 'parameter validation' {
        It 'SourceRoleName is mandatory' {
            $cmd = Get-Command Copy-IntuneRoleDefinition
            $cmd.Parameters['SourceRoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Remove-IntuneRoleDefinition
# ===========================================================================
Describe 'Remove-IntuneRoleDefinition' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Remove-IntuneRoleDefinition -RoleNames 'HelpDesk Reader' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - role exists and is custom' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET')    { return $script:MockRolesResponse }
                if ($Method -eq 'DELETE') { return $null }
            }
        }

        It 'deletes the role via DELETE' {
            Remove-IntuneRoleDefinition -RoleNames 'HelpDesk Reader'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    Context 'when role is built-in' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockBuiltInRolesResponse }
        }

        It 'skips built-in roles and does not DELETE' {
            Remove-IntuneRoleDefinition -RoleNames 'Help Desk Operator'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    Context 'when role does not exist' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { @{ value = @() } }
        }

        It 'reports NOT FOUND and does not DELETE' {
            Remove-IntuneRoleDefinition -RoleNames 'NonExistent'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
        }

        It 'does not DELETE when -WhatIfMode is specified' {
            Remove-IntuneRoleDefinition -RoleNames 'HelpDesk Reader' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    Context 'parameter validation' {
        It 'RoleNames is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleDefinition
            $cmd.Parameters['RoleNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Get-IntuneRoleDefinitionPermissions
# ===========================================================================
Describe 'Get-IntuneRoleDefinitionPermissions' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Get-IntuneRoleDefinitionPermissions -RoleName 'HelpDesk Reader' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - by role name' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
        }

        It 'retrieves permissions by role name' {
            Get-IntuneRoleDefinitionPermissions -RoleName 'HelpDesk Reader'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'GET' }
        }
    }

    Context 'when connected - by role ID' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRole }
        }

        It 'retrieves permissions by role ID' {
            Get-IntuneRoleDefinitionPermissions -RoleId 'role-id-1'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'GET' -and $Uri -match 'role-id-1'
            }
        }
    }

    Context 'when role is not found' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { @{ value = @() } }
        }

        It 'throws when the role does not exist' {
            { Get-IntuneRoleDefinitionPermissions -RoleName 'NonExistent' } | Should -Throw
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory in ByName parameter set' {
            $cmd = Get-Command Get-IntuneRoleDefinitionPermissions
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }

        It 'RoleId is mandatory in ById parameter set' {
            $cmd = Get-Command Get-IntuneRoleDefinitionPermissions
            $cmd.Parameters['RoleId'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Add-IntuneRoleDefinitionPermission
# ===========================================================================
Describe 'Add-IntuneRoleDefinitionPermission' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Add-IntuneRoleDefinitionPermission -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_managedApps_read' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - permission not yet present' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET')   { return $script:MockRolesResponse }
                if ($Method -eq 'PATCH') { return $null }
            }
        }

        It 'PATCHes the role definition with the new permission' {
            Add-IntuneRoleDefinitionPermission -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_managedApps_read'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'when connected - permission already present' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
        }

        It 'reports NO CHANGE and does not PATCH' {
            Add-IntuneRoleDefinitionPermission -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_deviceConfigurations_read'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'when role is built-in' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockBuiltInRolesResponse }
        }

        It 'skips built-in role and does not PATCH' {
            Add-IntuneRoleDefinitionPermission -RoleName 'Help Desk Operator' -Permissions 'microsoft.intune_managedApps_read'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
        }

        It 'does not PATCH when -WhatIfMode is specified' {
            Add-IntuneRoleDefinitionPermission -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_managedApps_read' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command Add-IntuneRoleDefinitionPermission
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }

        It 'Permissions is mandatory' {
            $cmd = Get-Command Add-IntuneRoleDefinitionPermission
            $cmd.Parameters['Permissions'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Remove-IntuneRoleDefinitionPermission
# ===========================================================================
Describe 'Remove-IntuneRoleDefinitionPermission' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Remove-IntuneRoleDefinitionPermission -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_deviceConfigurations_read' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - permission present' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET')   { return $script:MockRolesResponse }
                if ($Method -eq 'PATCH') { return $null }
            }
        }

        It 'PATCHes the role definition to remove the permission' {
            Remove-IntuneRoleDefinitionPermission -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_deviceConfigurations_read'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'when connected - permission not present' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
        }

        It 'reports NO CHANGE and does not PATCH' {
            Remove-IntuneRoleDefinitionPermission -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_managedApps_read'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
        }

        It 'does not PATCH when -WhatIfMode is specified' {
            Remove-IntuneRoleDefinitionPermission -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_deviceConfigurations_read' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleDefinitionPermission
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }

        It 'Permissions is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleDefinitionPermission
            $cmd.Parameters['Permissions'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Set-IntuneRoleDefinitionPermissions
# ===========================================================================
Describe 'Set-IntuneRoleDefinitionPermissions' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Set-IntuneRoleDefinitionPermissions -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_managedApps_read' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - permissions differ' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET')   { return $script:MockRolesResponse }
                if ($Method -eq 'PATCH') { return $null }
            }
        }

        It 'PATCHes the role definition with the new permission set' {
            Set-IntuneRoleDefinitionPermissions -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_managedApps_read','microsoft.intune_managedDevices_read'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'when connected - permissions unchanged' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
        }

        It 'does not PATCH when permissions are identical' {
            Set-IntuneRoleDefinitionPermissions -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_deviceConfigurations_read'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { $script:MockRolesResponse }
        }

        It 'does not PATCH when -WhatIfMode is specified' {
            Set-IntuneRoleDefinitionPermissions -RoleName 'HelpDesk Reader' -Permissions 'microsoft.intune_managedApps_read' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command Set-IntuneRoleDefinitionPermissions
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }

        It 'Permissions is mandatory' {
            $cmd = Get-Command Set-IntuneRoleDefinitionPermissions
            $cmd.Parameters['Permissions'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Get-IntuneRoleAssignment
# ===========================================================================
Describe 'Get-IntuneRoleAssignment' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Get-IntuneRoleAssignment -RoleName 'HelpDesk Reader' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - happy path' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Uri -match 'roleDefinitions$')                       { return $script:MockRolesResponse }
                if ($Uri -match 'roleDefinitions/role-id-1/roleAssignments') { return $script:MockAssignmentsResponse }
                if ($Uri -match 'roleAssignments/assign-id-1')             { return $script:MockAssignment }
                if ($Uri -match 'groups/')                                  { return $script:MockMemberGroup }
                if ($Uri -match 'roleScopeTags/')                           { return $script:MockScopeTag }
                return @{ value = @() }
            }
        }

        It 'resolves the role and retrieves assignments' {
            Get-IntuneRoleAssignment -RoleName 'HelpDesk Reader'
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter {
                $Method -eq 'GET' -and $Uri -match 'roleAssignments'
            }
        }
    }

    Context 'when role does not exist' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest { @{ value = @() } }
        }

        It 'throws when the role definition is not found' {
            { Get-IntuneRoleAssignment -RoleName 'NonExistent' } | Should -Throw
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command Get-IntuneRoleAssignment
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  New-IntuneRoleAssignment
# ===========================================================================
Describe 'New-IntuneRoleAssignment' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = New-IntuneRoleAssignment -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -MemberGroupNames 'SG-HelpDeskTeam' -ScopeGroupNames 'SG-ClientA-Devices' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - happy path' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')  { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')           { return @{ value = @($script:MockMemberGroup) } }
                if ($Method -eq 'POST')                                       { return $null }
                return @{ value = @() }
            }
        }

        It 'POSTs the new role assignment' {
            New-IntuneRoleAssignment -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -MemberGroupNames 'SG-HelpDeskTeam' -ScopeGroupNames 'SG-ClientA-Devices'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')  { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')           { return @{ value = @($script:MockMemberGroup) } }
                return @{ value = @() }
            }
        }

        It 'does not POST when -WhatIfMode is specified' {
            New-IntuneRoleAssignment -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -MemberGroupNames 'SG-HelpDeskTeam' -ScopeGroupNames 'SG-ClientA-Devices' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command New-IntuneRoleAssignment
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'AssignmentName is mandatory' {
            $cmd = Get-Command New-IntuneRoleAssignment
            $cmd.Parameters['AssignmentName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'MemberGroupNames is mandatory' {
            $cmd = Get-Command New-IntuneRoleAssignment
            $cmd.Parameters['MemberGroupNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'ScopeGroupNames is mandatory' {
            $cmd = Get-Command New-IntuneRoleAssignment
            $cmd.Parameters['ScopeGroupNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Remove-IntuneRoleAssignment
# ===========================================================================
Describe 'Remove-IntuneRoleAssignment' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Remove-IntuneRoleAssignment -RoleName 'HelpDesk Reader' -AssignmentNames 'HD-ClientA' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - happy path' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'DELETE')                                             { return $null }
                return @{ value = @() }
            }
        }

        It 'deletes the assignment via DELETE' {
            Remove-IntuneRoleAssignment -RoleName 'HelpDesk Reader' -AssignmentNames 'HD-ClientA'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    Context 'when assignment does not exist' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Uri -match 'roleDefinitions$') { return $script:MockRolesResponse }
                return @{ value = @() }
            }
        }

        It 'reports NOT FOUND and does not DELETE' {
            Remove-IntuneRoleAssignment -RoleName 'HelpDesk Reader' -AssignmentNames 'NonExistent'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Uri -match 'roleDefinitions$') { return $script:MockRolesResponse }
                if ($Uri -match 'roleAssignments$') { return $script:MockAssignmentsResponse }
                return @{ value = @() }
            }
        }

        It 'does not DELETE when -WhatIfMode is specified' {
            Remove-IntuneRoleAssignment -RoleName 'HelpDesk Reader' -AssignmentNames 'HD-ClientA' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleAssignment
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'AssignmentNames is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleAssignment
            $cmd.Parameters['AssignmentNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Add-IntuneRoleAssignmentMember
# ===========================================================================
Describe 'Add-IntuneRoleAssignmentMember' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Add-IntuneRoleAssignmentMember -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -MemberGroupNames 'SG-NewTeam' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - group is new' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                   { return @{ value = @($script:MockNewMemberGroup) } }
                if ($Method -eq 'PATCH')                                              { return $null }
                return @{ value = @() }
            }
        }

        It 'PATCHes the assignment with the new member group' {
            Add-IntuneRoleAssignmentMember -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -MemberGroupNames 'SG-NewTeam'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'when connected - group already assigned' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                   { return @{ value = @($script:MockMemberGroup) } }
                return @{ value = @() }
            }
        }

        It 'reports ALREADY ASSIGNED and does not PATCH' {
            Add-IntuneRoleAssignmentMember -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -MemberGroupNames 'SG-HelpDeskTeam'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                   { return @{ value = @($script:MockNewMemberGroup) } }
                return @{ value = @() }
            }
        }

        It 'does not PATCH when -WhatIfMode is specified' {
            Add-IntuneRoleAssignmentMember -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -MemberGroupNames 'SG-NewTeam' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command Add-IntuneRoleAssignmentMember
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'AssignmentName is mandatory' {
            $cmd = Get-Command Add-IntuneRoleAssignmentMember
            $cmd.Parameters['AssignmentName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'MemberGroupNames is mandatory' {
            $cmd = Get-Command Add-IntuneRoleAssignmentMember
            $cmd.Parameters['MemberGroupNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Remove-IntuneRoleAssignmentMember
# ===========================================================================
Describe 'Remove-IntuneRoleAssignmentMember' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Remove-IntuneRoleAssignmentMember -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -MemberGroupNames 'SG-HelpDeskTeam' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - happy path' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                   { return @{ value = @($script:MockMemberGroup) } }
                if ($Method -eq 'PATCH')                                              { return $null }
                return @{ value = @() }
            }
        }

        It 'PATCHes the assignment to remove the member group' {
            Remove-IntuneRoleAssignmentMember -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -MemberGroupNames 'SG-HelpDeskTeam'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                   { return @{ value = @($script:MockMemberGroup) } }
                return @{ value = @() }
            }
        }

        It 'does not PATCH when -WhatIfMode is specified' {
            Remove-IntuneRoleAssignmentMember -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -MemberGroupNames 'SG-HelpDeskTeam' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleAssignmentMember
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'AssignmentName is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleAssignmentMember
            $cmd.Parameters['AssignmentName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'MemberGroupNames is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleAssignmentMember
            $cmd.Parameters['MemberGroupNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Add-IntuneRoleAssignmentScopeGroup
# ===========================================================================
Describe 'Add-IntuneRoleAssignmentScopeGroup' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Add-IntuneRoleAssignmentScopeGroup -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeGroupNames 'SG-NewDevices' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - scope group is new' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                   { return @{ value = @($script:MockNewScopeGroup) } }
                if ($Method -eq 'PATCH')                                              { return $null }
                return @{ value = @() }
            }
        }

        It 'PATCHes the assignment with the new scope group' {
            Add-IntuneRoleAssignmentScopeGroup -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeGroupNames 'SG-NewDevices'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'when connected - scope group already assigned' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                   { return @{ value = @($script:MockScopeGroup) } }
                return @{ value = @() }
            }
        }

        It 'reports ALREADY ASSIGNED and does not PATCH' {
            Add-IntuneRoleAssignmentScopeGroup -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeGroupNames 'SG-ClientA-Devices'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                   { return @{ value = @($script:MockNewScopeGroup) } }
                return @{ value = @() }
            }
        }

        It 'does not PATCH when -WhatIfMode is specified' {
            Add-IntuneRoleAssignmentScopeGroup -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeGroupNames 'SG-NewDevices' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command Add-IntuneRoleAssignmentScopeGroup
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'AssignmentName is mandatory' {
            $cmd = Get-Command Add-IntuneRoleAssignmentScopeGroup
            $cmd.Parameters['AssignmentName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'ScopeGroupNames is mandatory' {
            $cmd = Get-Command Add-IntuneRoleAssignmentScopeGroup
            $cmd.Parameters['ScopeGroupNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Remove-IntuneRoleAssignmentScopeGroup
# ===========================================================================
Describe 'Remove-IntuneRoleAssignmentScopeGroup' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Remove-IntuneRoleAssignmentScopeGroup -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeGroupNames 'SG-ClientA-Devices' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - happy path' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                   { return @{ value = @($script:MockScopeGroup) } }
                if ($Method -eq 'PATCH')                                              { return $null }
                return @{ value = @() }
            }
        }

        It 'PATCHes the assignment to remove the scope group' {
            Remove-IntuneRoleAssignmentScopeGroup -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeGroupNames 'SG-ClientA-Devices'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                   { return @{ value = @($script:MockScopeGroup) } }
                return @{ value = @() }
            }
        }

        It 'does not PATCH when -WhatIfMode is specified' {
            Remove-IntuneRoleAssignmentScopeGroup -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeGroupNames 'SG-ClientA-Devices' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleAssignmentScopeGroup
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'AssignmentName is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleAssignmentScopeGroup
            $cmd.Parameters['AssignmentName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'ScopeGroupNames is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleAssignmentScopeGroup
            $cmd.Parameters['ScopeGroupNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Add-IntuneRoleAssignmentScopeTag
# ===========================================================================
Describe 'Add-IntuneRoleAssignmentScopeTag' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Add-IntuneRoleAssignmentScopeTag -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeTagNames 'ZT-NewTag' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - scope tag is new' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'roleScopeTags$')              { return @{ value = @($script:MockNewScopeTag) } }
                if ($Method -eq 'PATCH')                                              { return $null }
                return @{ value = @() }
            }
        }

        It 'PATCHes the assignment with the new scope tag' {
            Add-IntuneRoleAssignmentScopeTag -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeTagNames 'ZT-NewTag'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'when connected - scope tag already assigned' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'roleScopeTags$')              { return $script:MockScopeTagsResponse }
                return @{ value = @() }
            }
        }

        It 'reports ALREADY ASSIGNED and does not PATCH' {
            Add-IntuneRoleAssignmentScopeTag -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeTagNames 'ZT-ClientA'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'roleScopeTags$')              { return @{ value = @($script:MockNewScopeTag) } }
                return @{ value = @() }
            }
        }

        It 'does not PATCH when -WhatIfMode is specified' {
            Add-IntuneRoleAssignmentScopeTag -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeTagNames 'ZT-NewTag' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command Add-IntuneRoleAssignmentScopeTag
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'AssignmentName is mandatory' {
            $cmd = Get-Command Add-IntuneRoleAssignmentScopeTag
            $cmd.Parameters['AssignmentName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'ScopeTagNames is mandatory' {
            $cmd = Get-Command Add-IntuneRoleAssignmentScopeTag
            $cmd.Parameters['ScopeTagNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Remove-IntuneRoleAssignmentScopeTag
# ===========================================================================
Describe 'Remove-IntuneRoleAssignmentScopeTag' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Remove-IntuneRoleAssignmentScopeTag -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeTagNames 'ZT-ClientA' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - happy path' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'roleScopeTags$')              { return $script:MockScopeTagsResponse }
                if ($Method -eq 'PATCH')                                              { return $null }
                return @{ value = @() }
            }
        }

        It 'PATCHes the assignment to remove the scope tag' {
            Remove-IntuneRoleAssignmentScopeTag -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeTagNames 'ZT-ClientA'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext { $script:MockContext }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleDefinitions$')          { return $script:MockRolesResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments$')           { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'roleAssignments/assign-id-1') { return $script:MockAssignment }
                if ($Method -eq 'GET' -and $Uri -match 'roleScopeTags$')              { return $script:MockScopeTagsResponse }
                return @{ value = @() }
            }
        }

        It 'does not PATCH when -WhatIfMode is specified' {
            Remove-IntuneRoleAssignmentScopeTag -RoleName 'HelpDesk Reader' -AssignmentName 'HD-ClientA' -ScopeTagNames 'ZT-ClientA' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'parameter validation' {
        It 'RoleName is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleAssignmentScopeTag
            $cmd.Parameters['RoleName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'AssignmentName is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleAssignmentScopeTag
            $cmd.Parameters['AssignmentName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'ScopeTagNames is mandatory' {
            $cmd = Get-Command Remove-IntuneRoleAssignmentScopeTag
            $cmd.Parameters['ScopeTagNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } | Should -Not -BeNullOrEmpty
        }
    }
}
