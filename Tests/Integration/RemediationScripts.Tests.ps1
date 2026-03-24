#Requires -Modules Pester

<#
.SYNOPSIS
    Pester v5 tests for Intune Remediation Script management functions.

.DESCRIPTION
    Tests for:
      - Get-IntuneRemediationScript
      - Get-IntuneRemediationScriptAssignments
      - Copy-IntuneRemediationScript
      - Add-IntuneRemediationScriptAssignment
      - Remove-IntuneRemediationScriptAssignment
      - Remove-IntuneRemediationScript
      - Set-IntuneRemediationScriptDescription

.NOTES
    Requires Pester v5+. Run with:
        Invoke-Pester -Path .\RemediationScripts.Tests.ps1 -Output Detailed
#>

BeforeAll {
    Get-ChildItem -Path "$PSScriptRoot\..\..\Source" -Filter "*.ps1" -Recurse |
        ForEach-Object { . $_.FullName }

    # ---------------------------------------------------------------------------
    # Shared mock data
    # ---------------------------------------------------------------------------
    $script:MockScripts = @{
        value = @(
            @{
                id                       = 'remediation-id-1'
                displayName              = 'Fix Registry'
                roleScopeTagIds          = @('1')
                detectionScriptContent   = 'base64detect'
                remediationScriptContent = 'base64remediate'
                description              = 'Initial description'
            }
        )
    }

    $script:MockScopeTags = @{
        value = @(
            @{ id = '1'; displayName = 'Production' },
            @{ id = '2'; displayName = 'Development' }
        )
    }

    $script:MockAssignments = @{
        value = @(
            @{
                id     = 'assign1'
                target = @{
                    '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                    groupId       = 'group-id-1'
                }
                runSchedule = @{
                    '@odata.type' = '#microsoft.graph.deviceHealthScriptRunOnceSchedule'
                }
            }
        )
    }

    $script:MockGroups = @{
        value = @(
            @{ id = 'group-id-1'; displayName = 'Test-Devices' }
        )
    }

    $script:MockPostResponse = @{
        id          = 'new-remediation-id'
        displayName = 'Copy of Fix Registry'
    }
}

# ==============================================================================
# Get-IntuneRemediationScript
# ==============================================================================
Describe 'Get-IntuneRemediationScript' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and returns without executing Graph calls' {
            Get-IntuneRemediationScript
            Should -Invoke 'Write-Warning' -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'happy path - no ScriptName filter (returns all scripts)' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceHealthScripts') { return $script:MockScripts }
                if ($Uri -match 'roleScopeTags')       { return $script:MockScopeTags }
            }
        }

        It 'calls the deviceHealthScripts endpoint' {
            Get-IntuneRemediationScript
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Uri -match 'deviceHealthScripts'
            }
        }

        It 'returns at least one script object' {
            $result = Get-IntuneRemediationScript
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'happy path - ScriptName filter matches' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceHealthScripts') { return $script:MockScripts }
                if ($Uri -match 'roleScopeTags')       { return $script:MockScopeTags }
            }
        }

        It 'returns the matching script when ScriptName is provided' {
            $result = Get-IntuneRemediationScript -ScriptName 'Fix Registry'
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'ScriptName not found' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceHealthScripts') { return $script:MockScripts }
                if ($Uri -match 'roleScopeTags')       { return $script:MockScopeTags }
            }
        }

        It 'does not throw when ScriptName does not match any script' {
            { Get-IntuneRemediationScript -ScriptName 'NonExistentScript' } | Should -Not -Throw
        }
    }

    Context 'parameter validation' {
        It 'ScriptName parameter accepts a string value without error' {
            { Get-Command Get-IntuneRemediationScript | Select-Object -ExpandProperty Parameters } |
                Should -Not -Throw
        }

        It 'ScriptName parameter is optional (function can be called with no arguments)' {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceHealthScripts') { return $script:MockScripts }
                if ($Uri -match 'roleScopeTags')       { return $script:MockScopeTags }
            }
            { Get-IntuneRemediationScript } | Should -Not -Throw
        }
    }
}

# ==============================================================================
# Get-IntuneRemediationScriptAssignments
# ==============================================================================
Describe 'Get-IntuneRemediationScriptAssignments' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and returns without executing Graph calls' {
            Get-IntuneRemediationScriptAssignments -ScriptName 'Fix Registry'
            Should -Invoke 'Write-Warning' -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'happy path - script exists and has assignments' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceHealthScripts' -and $Uri -notmatch 'assignments') {
                    return $script:MockScripts
                }
                if ($Uri -match 'assignments') {
                    return $script:MockAssignments
                }
                if ($Uri -match 'groups') {
                    return $script:MockGroups
                }
            }
        }

        It 'calls the assignments endpoint' {
            Get-IntuneRemediationScriptAssignments -ScriptName 'Fix Registry'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Uri -match 'assignments'
            }
        }

        It 'returns assignment data' {
            $result = Get-IntuneRemediationScriptAssignments -ScriptName 'Fix Registry'
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'ScriptName not found' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceHealthScripts') {
                    return @{ value = @() }
                }
            }
        }

        It 'throws when the script name does not exist' {
            { Get-IntuneRemediationScriptAssignments -ScriptName 'NonExistentScript' } | Should -Throw
        }
    }

    Context 'parameter validation' {
        It 'ScriptName is a mandatory parameter' {
            $param = (Get-Command Get-IntuneRemediationScriptAssignments).Parameters['ScriptName']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }
    }
}

# ==============================================================================
# Copy-IntuneRemediationScript
# ==============================================================================
Describe 'Copy-IntuneRemediationScript' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and returns without executing Graph calls' {
            Copy-IntuneRemediationScript -SourceScopeTagName 'Production' `
                -DestinationScopeTagName 'Development'
            Should -Invoke 'Write-Warning' -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'happy path - copy all scripts from source to destination scope tag' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body)
                if ($Method -eq 'POST') { return $script:MockPostResponse }
                if ($Uri -match 'deviceHealthScripts') { return $script:MockScripts }
                if ($Uri -match 'deviceManagement/roleScopeTags') { return $script:MockScopeTags }
            }
        }

        It 'issues a POST request to create the cloned script' {
            Copy-IntuneRemediationScript -SourceScopeTagName 'Production' `
                -DestinationScopeTagName 'Development' `
                -ScriptName 'Fix Registry' -NewScriptName 'Fix Registry - Test Copy'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'does not throw when cloning a named script' {
            { Copy-IntuneRemediationScript -SourceScopeTagName 'Production' `
                -DestinationScopeTagName 'Development' `
                -ScriptName 'Fix Registry' -NewScriptName 'Fix Registry - Test Copy' } |
                Should -Not -Throw
        }
    }

    Context 'happy path - copy specific script with custom new name' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body)
                if ($Method -eq 'POST') { return $script:MockPostResponse }
                if ($Uri -match 'deviceHealthScripts') { return $script:MockScripts }
                if ($Uri -match 'deviceManagement/roleScopeTags') { return $script:MockScopeTags }
            }
        }

        It 'accepts ScriptName and NewScriptName parameters without error' {
            {
                Copy-IntuneRemediationScript -SourceScopeTagName 'Production' `
                    -DestinationScopeTagName 'Development' `
                    -ScriptName 'Fix Registry' `
                    -NewScriptName 'Fix Registry - Dev Copy'
            } | Should -Not -Throw
        }
    }

    Context 'WhatIfMode - no write calls are made' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Uri -match 'deviceHealthScripts') { return $script:MockScripts }
                if ($Uri -match 'deviceManagement/roleScopeTags') { return $script:MockScopeTags }
            }
        }

        It 'does not issue any POST requests when WhatIfMode is specified' {
            Copy-IntuneRemediationScript -SourceScopeTagName 'Production' `
                -DestinationScopeTagName 'Development' `
                -ScriptName 'Fix Registry' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'POST'
            }
        }
    }

    Context 'ScriptName not found' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceHealthScripts') { return @{ value = @() } }
                if ($Uri -match 'deviceManagement/roleScopeTags') { return $script:MockScopeTags }
            }
        }

        It 'does not throw when no scripts exist under the source scope tag' {
            { Copy-IntuneRemediationScript -SourceScopeTagName 'Production' `
                -DestinationScopeTagName 'Development' -ScriptName 'NonExistent' } |
                Should -Not -Throw
        }
    }

    Context 'parameter validation' {
        It 'SourceScopeTagName is mandatory' {
            $param = (Get-Command Copy-IntuneRemediationScript).Parameters['SourceScopeTagName']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }

        It 'DestinationScopeTagName is mandatory' {
            $param = (Get-Command Copy-IntuneRemediationScript).Parameters['DestinationScopeTagName']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }

        It 'WhatIfMode is a switch parameter' {
            $param = (Get-Command Copy-IntuneRemediationScript).Parameters['WhatIfMode']
            $param.ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
        }
    }
}

# ==============================================================================
# Add-IntuneRemediationScriptAssignment
# ==============================================================================
Describe 'Add-IntuneRemediationScriptAssignment' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and returns without executing Graph calls' {
            Add-IntuneRemediationScriptAssignment -ScriptName 'Fix Registry' `
                -GroupName 'Test-Devices' -IncludeExclude 'include'
            Should -Invoke 'Write-Warning' -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'happy path - add include assignment' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body)
                if ($Method -eq 'POST') { return @{ id = 'new-assign-id' } }
                if ($Uri -match 'deviceHealthScripts') { return $script:MockScripts }
                if ($Uri -match 'groups') { return $script:MockGroups }
            }
        }

        It 'issues a POST request to create the assignment' {
            Add-IntuneRemediationScriptAssignment -ScriptName 'Fix Registry' `
                -GroupName 'Test-Devices' -IncludeExclude 'include'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST'
            }
        }
    }

    Context 'happy path - add exclude assignment' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body)
                if ($Method -eq 'POST') { return @{ id = 'new-assign-id' } }
                if ($Uri -match 'deviceHealthScripts') { return $script:MockScripts }
                if ($Uri -match 'groups') { return $script:MockGroups }
            }
        }

        It 'issues a POST request when IncludeExclude is set to exclude' {
            Add-IntuneRemediationScriptAssignment -ScriptName 'Fix Registry' `
                -GroupName 'Test-Devices' -IncludeExclude 'exclude'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST'
            }
        }
    }

    Context 'ScriptName not found' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceHealthScripts') { return @{ value = @() } }
                if ($Uri -match 'groups') { return $script:MockGroups }
            }
        }

        It 'throws when the script is not found' {
            { Add-IntuneRemediationScriptAssignment -ScriptName 'NonExistent' `
                -GroupName 'Test-Devices' -IncludeExclude 'include' } | Should -Throw
        }
    }

    Context 'parameter validation' {
        It 'ScriptName is mandatory' {
            $param = (Get-Command Add-IntuneRemediationScriptAssignment).Parameters['ScriptName']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }

        It 'GroupName is mandatory' {
            $param = (Get-Command Add-IntuneRemediationScriptAssignment).Parameters['GroupName']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }

        It 'IncludeExclude is mandatory' {
            $param = (Get-Command Add-IntuneRemediationScriptAssignment).Parameters['IncludeExclude']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }

        It 'IncludeExclude only accepts "include" or "exclude"' {
            $param = (Get-Command Add-IntuneRemediationScriptAssignment).Parameters['IncludeExclude']
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'include'
            $validateSet.ValidValues | Should -Contain 'exclude'
        }
    }
}

# ==============================================================================
# Remove-IntuneRemediationScriptAssignment
# ==============================================================================
Describe 'Remove-IntuneRemediationScriptAssignment' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and returns without executing Graph calls' {
            Remove-IntuneRemediationScriptAssignment -ScriptName 'Fix Registry' `
                -GroupName 'Test-Devices'
            Should -Invoke 'Write-Warning' -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'happy path - assignment exists and is removed' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Method -eq 'POST') { return $null }
                if ($Uri -match 'deviceHealthScripts' -and $Uri -notmatch 'assignments') {
                    return $script:MockScripts
                }
                if ($Uri -match 'assignments') { return $script:MockAssignments }
                if ($Uri -match 'groups') { return $script:MockGroups }
            }
        }

        It 'issues a POST request to the assign endpoint to remove the assignment' {
            Remove-IntuneRemediationScriptAssignment -ScriptName 'Fix Registry' `
                -GroupName 'Test-Devices'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST'
            }
        }
    }

    Context 'ScriptName not found' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceHealthScripts') { return @{ value = @() } }
            }
        }

        It 'throws when the script is not found' {
            { Remove-IntuneRemediationScriptAssignment -ScriptName 'NonExistent' `
                -GroupName 'Test-Devices' } | Should -Throw
        }
    }

    Context 'parameter validation' {
        It 'ScriptName is mandatory' {
            $param = (Get-Command Remove-IntuneRemediationScriptAssignment).Parameters['ScriptName']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }

        It 'GroupName is mandatory' {
            $param = (Get-Command Remove-IntuneRemediationScriptAssignment).Parameters['GroupName']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }
    }
}

# ==============================================================================
# Remove-IntuneRemediationScript
# ==============================================================================
Describe 'Remove-IntuneRemediationScript' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and returns without executing Graph calls' {
            Remove-IntuneRemediationScript -ScriptNames @('Fix Registry')
            Should -Invoke 'Write-Warning' -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'happy path - single script deleted' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Method -eq 'DELETE') { return $null }
                if ($Uri -match 'deviceHealthScripts') { return $script:MockScripts }
            }
        }

        It 'issues a DELETE request to remove the script' {
            Remove-IntuneRemediationScript -ScriptNames @('Fix Registry')
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }
    }

    Context 'happy path - multiple scripts deleted' {
        BeforeEach {
            $multiScripts = @{
                value = @(
                    @{ id = 'remediation-id-1'; displayName = 'Fix Registry' },
                    @{ id = 'remediation-id-2'; displayName = 'Fix Services' }
                )
            }
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Method -eq 'DELETE') { return $null }
                if ($Uri -match 'deviceHealthScripts') { return $multiScripts }
            }
        }

        It 'issues a DELETE request for each script in the ScriptNames array' {
            Remove-IntuneRemediationScript -ScriptNames @('Fix Registry', 'Fix Services')
            Should -Invoke Invoke-MgGraphRequest -Times 2 -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }
    }

    Context 'WhatIfMode - no delete calls are made' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Uri -match 'deviceHealthScripts') { return $script:MockScripts }
            }
        }

        It 'does not issue any DELETE requests when WhatIfMode is specified' {
            Remove-IntuneRemediationScript -ScriptNames @('Fix Registry') -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }
    }

    Context 'ScriptName not found' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceHealthScripts') { return @{ value = @() } }
            }
            Mock Write-Warning {}
        }

        It 'writes a warning when no matching script is found' {
            Remove-IntuneRemediationScript -ScriptNames @('NonExistent')
            Should -Invoke 'Write-Warning' -Times 1
        }
    }

    Context 'parameter validation' {
        It 'ScriptNames is mandatory' {
            $param = (Get-Command Remove-IntuneRemediationScript).Parameters['ScriptNames']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }

        It 'ScriptNames accepts an array of strings' {
            $param = (Get-Command Remove-IntuneRemediationScript).Parameters['ScriptNames']
            $param.ParameterType | Should -Be ([string[]])
        }

        It 'WhatIfMode is a switch parameter' {
            $param = (Get-Command Remove-IntuneRemediationScript).Parameters['WhatIfMode']
            $param.ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
        }
    }
}

# ==============================================================================
# Set-IntuneRemediationScriptDescription
# ==============================================================================
Describe 'Set-IntuneRemediationScriptDescription' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and returns without executing Graph calls' {
            Set-IntuneRemediationScriptDescription -ScriptName 'Fix Registry' `
                -Description 'New description'
            Should -Invoke 'Write-Warning' -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'happy path - description changes' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Method -eq 'GET')   { return $script:MockScripts }
                if ($Method -eq 'PATCH') { return $null }
            }
        }

        It 'issues a PATCH request to update the description' {
            Set-IntuneRemediationScriptDescription -ScriptName 'Fix Registry' `
                -Description 'Updated description'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH'
            }
        }
    }

    Context 'happy path - description unchanged (no-change detection)' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Method -eq 'GET') { return $script:MockScripts }
            }
        }

        It 'does not PATCH when description is already the same' {
            # MockScripts has description = 'Initial description'; passing the same value triggers NO CHANGE
            Set-IntuneRemediationScriptDescription -ScriptName 'Fix Registry' `
                -Description 'Initial description'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'PATCH'
            }
        }
    }

    Context 'WhatIfMode - no write calls are made' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Method -eq 'GET') { return $script:MockScripts }
            }
        }

        It 'does not PATCH when WhatIfMode is specified' {
            Set-IntuneRemediationScriptDescription -ScriptName 'Fix Registry' `
                -Description 'Would update description' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'PATCH'
            }
        }
    }

    Context 'ScriptName not found' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceHealthScripts') { return @{ value = @() } }
            }
        }

        It 'throws when the script name does not exist' {
            { Set-IntuneRemediationScriptDescription -ScriptName 'NonExistent' `
                -Description 'Any description' } | Should -Throw
        }
    }

    Context 'parameter validation' {
        It 'ScriptName is mandatory' {
            $param = (Get-Command Set-IntuneRemediationScriptDescription).Parameters['ScriptName']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }

        It 'Description is mandatory' {
            $param = (Get-Command Set-IntuneRemediationScriptDescription).Parameters['Description']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }

        It 'WhatIfMode is a switch parameter' {
            $param = (Get-Command Set-IntuneRemediationScriptDescription).Parameters['WhatIfMode']
            $param.ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
        }
    }
}
