#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Pester v5 tests for Intune Scope Tag management functions.

.DESCRIPTION
    Tests all scope tag functions by mocking Get-MgContext and
    Invoke-MgGraphRequest so no live Graph connection is required.
#>

BeforeAll {
    Get-ChildItem -Path "$PSScriptRoot\..\..\Source" -Filter "*.ps1" -Recurse |
        ForEach-Object { . $_.FullName }

    # --- Shared mock data ---
    $script:MockTagsResponse = @{
        value = @(
            @{
                id          = '1'
                displayName = 'ScopeTagTest'
                description = 'Test tag'
                isBuiltIn   = $false
            }
        )
    }

    $script:MockAssignmentsResponse = @{
        value = @(
            @{
                id     = 'assign1'
                target = @{
                    '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                    groupId       = 'group-guid-1'
                }
            }
        )
    }

    $script:MockGroupsResponse = @{
        value = @(
            @{
                id          = 'group-guid-1'
                displayName = 'Test-Group-ScopeTag'
            }
        )
    }

    $script:MockCreatedTag = @{
        id          = '99'
        displayName = 'NewScopeTag'
        description = 'Automated scope tag: NewScopeTag'
        isBuiltIn   = $false
    }
}

# ===========================================================================
#  New-IntuneScopeTag
# ===========================================================================
Describe 'New-IntuneScopeTag' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = New-IntuneScopeTag -ScopeTagName @('ScopeTagTest') 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - tag already exists' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest { $script:MockTagsResponse }
        }

        It 'reports NO CHANGE and does not POST' {
            New-IntuneScopeTag -ScopeTagName @('ScopeTagTest')
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'GET' }
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'when connected - tag does not exist' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri, $Body, $ContentType)
                if ($Method -eq 'GET') { return @{ value = @() } }
                if ($Method -eq 'POST') { return $script:MockCreatedTag }
            }
        }

        It 'creates the tag via POST' {
            New-IntuneScopeTag -ScopeTagName @('NewScopeTag')
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' }
        }

        It 'uses a custom DescriptionPrefix when supplied' {
            New-IntuneScopeTag -ScopeTagName @('NewScopeTag') -DescriptionPrefix 'Zero Trust'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Body -match 'Zero Trust'
            }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest { @{ value = @() } }
        }

        It 'does not invoke POST when -WhatIfMode is specified' {
            New-IntuneScopeTag -ScopeTagName @('NewScopeTag') -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'parameter validation' {
        It 'ScopeTagName is mandatory' {
            $cmd = Get-Command New-IntuneScopeTag
            $cmd.Parameters['ScopeTagName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Get-IntuneScopeTag
# ===========================================================================
Describe 'Get-IntuneScopeTag' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Get-IntuneScopeTag 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - list all tags' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest { $script:MockTagsResponse }
        }

        It 'calls GET on roleScopeTags' {
            Get-IntuneScopeTag
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'GET' }
        }
    }

    Context 'when connected - filter by TagName' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest { $script:MockTagsResponse }
        }

        It 'returns results when TagName matches' {
            Get-IntuneScopeTag -TagName 'ScopeTagTest'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'GET' }
        }

        It 'does not throw when TagName does not match any tag' {
            { Get-IntuneScopeTag -TagName 'NonExistent' } | Should -Not -Throw
        }
    }

    Context 'when connected - retrieve by TagId' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest {
                @{
                    id          = '1'
                    displayName = 'ScopeTagTest'
                    description = 'Test tag'
                    isBuiltIn   = $false
                }
            }
        }

        It 'calls GET with the specific tag ID in the URI' {
            Get-IntuneScopeTag -TagId '1'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'GET' -and $Uri -match '/1$'
            }
        }
    }

    Context 'parameter validation' {
        It 'does not throw when called with no parameters' {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest { $script:MockTagsResponse }
            { Get-IntuneScopeTag } | Should -Not -Throw
        }
    }
}

# ===========================================================================
#  Get-IntuneScopeTagAssignment
# ===========================================================================
Describe 'Get-IntuneScopeTagAssignment' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Get-IntuneScopeTagAssignment -TagName 'ScopeTagTest' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - happy path' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Uri -match 'roleScopeTags$') { return $script:MockTagsResponse }
                if ($Uri -match 'assignments$')   { return $script:MockAssignmentsResponse }
                if ($Uri -match 'groups/')         { return $script:MockGroupsResponse.value[0] }
                return @{ value = @() }
            }
        }

        It 'resolves the tag name and retrieves assignments' {
            Get-IntuneScopeTagAssignment -TagName 'ScopeTagTest'
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter {
                $Method -eq 'GET' -and $Uri -match 'assignments'
            }
        }
    }

    Context 'when tag does not exist' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest { @{ value = @() } }
        }

        It 'throws when the scope tag is not found' {
            { Get-IntuneScopeTagAssignment -TagName 'NonExistent' } | Should -Throw
        }
    }

    Context 'parameter validation' {
        It 'TagName is mandatory' {
            $cmd = Get-Command Get-IntuneScopeTagAssignment
            $cmd.Parameters['TagName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Set-IntuneScopeTagAssignment
# ===========================================================================
Describe 'Set-IntuneScopeTagAssignment' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Set-IntuneScopeTagAssignment -TagName 'ScopeTagTest' -GroupNames @('Test-Group-ScopeTag') 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - happy path' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleScopeTags$') { return $script:MockTagsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')        { return $script:MockGroupsResponse }
                if ($Method -eq 'POST' -and $Uri -match 'assign')         { return $null }
                return @{ value = @() }
            }
        }

        It 'posts to the assign endpoint' {
            Set-IntuneScopeTagAssignment -TagName 'ScopeTagTest' -GroupNames @('Test-Group-ScopeTag')
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -match 'assign'
            }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleScopeTags$') { return $script:MockTagsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')        { return $script:MockGroupsResponse }
                return @{ value = @() }
            }
        }

        It 'does not POST when -WhatIfMode is specified' {
            Set-IntuneScopeTagAssignment -TagName 'ScopeTagTest' -GroupNames @('Test-Group-ScopeTag') -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'parameter validation' {
        It 'TagName is mandatory' {
            $cmd = Get-Command Set-IntuneScopeTagAssignment
            $cmd.Parameters['TagName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }

        It 'GroupNames is mandatory' {
            $cmd = Get-Command Set-IntuneScopeTagAssignment
            $cmd.Parameters['GroupNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Remove-IntuneScopeTagAssignment
# ===========================================================================
Describe 'Remove-IntuneScopeTagAssignment' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Remove-IntuneScopeTagAssignment -TagName 'ScopeTagTest' -GroupNames @('Test-Group-ScopeTag') 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - happy path' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleScopeTags$')   { return $script:MockTagsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'assignments$')      { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')          { return $script:MockGroupsResponse }
                if ($Method -eq 'POST' -and $Uri -match 'assign')           { return $null }
                return @{ value = @() }
            }
        }

        It 'posts to the assign endpoint to remove the group' {
            Remove-IntuneScopeTagAssignment -TagName 'ScopeTagTest' -GroupNames @('Test-Group-ScopeTag')
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -match 'assign'
            }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET' -and $Uri -match 'roleScopeTags$') { return $script:MockTagsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'assignments$')    { return $script:MockAssignmentsResponse }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')        { return $script:MockGroupsResponse }
                return @{ value = @() }
            }
        }

        It 'does not POST when -WhatIfMode is specified' {
            Remove-IntuneScopeTagAssignment -TagName 'ScopeTagTest' -GroupNames @('Test-Group-ScopeTag') -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'parameter validation' {
        It 'TagName is mandatory' {
            $cmd = Get-Command Remove-IntuneScopeTagAssignment
            $cmd.Parameters['TagName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }

        It 'GroupNames is mandatory' {
            $cmd = Get-Command Remove-IntuneScopeTagAssignment
            $cmd.Parameters['GroupNames'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Set-IntuneScopeTagDescription
# ===========================================================================
Describe 'Set-IntuneScopeTagDescription' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Set-IntuneScopeTagDescription -TagName 'ScopeTagTest' -Description 'New description' 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - description changes' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET')   { return $script:MockTagsResponse }
                if ($Method -eq 'PATCH') { return $null }
            }
        }

        It 'patches the scope tag description' {
            Set-IntuneScopeTagDescription -TagName 'ScopeTagTest' -Description 'Updated description'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'when connected - description unchanged' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest { $script:MockTagsResponse }
        }

        It 'does not PATCH when description is unchanged' {
            Set-IntuneScopeTagDescription -TagName 'ScopeTagTest' -Description 'Test tag'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest { $script:MockTagsResponse }
        }

        It 'does not PATCH when -WhatIfMode is specified' {
            Set-IntuneScopeTagDescription -TagName 'ScopeTagTest' -Description 'Would update description' -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'when tag is not found' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest { @{ value = @() } }
        }

        It 'throws when the scope tag does not exist' {
            { Set-IntuneScopeTagDescription -TagName 'NonExistent' -Description 'Any description' } | Should -Throw
        }
    }

    Context 'parameter validation' {
        It 'TagName is mandatory' {
            $cmd = Get-Command Set-IntuneScopeTagDescription
            $cmd.Parameters['TagName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }

        It 'Description is mandatory' {
            $cmd = Get-Command Set-IntuneScopeTagDescription
            $cmd.Parameters['Description'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}

# ===========================================================================
#  Remove-IntuneScopeTag
# ===========================================================================
Describe 'Remove-IntuneScopeTag' {

    Context 'when not connected to Graph' {
        BeforeEach {
            Mock Get-MgContext { $null }
            Mock Invoke-MgGraphRequest { throw 'Should not be called' }
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            $warnings = Remove-IntuneScopeTag -ScopeTagName @('ScopeTagTest') 3>&1
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Where-Object { $_ -match 'Not connected' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    Context 'when connected - tag exists and is not built-in' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                if ($Method -eq 'GET')    { return $script:MockTagsResponse }
                if ($Method -eq 'DELETE') { return $null }
            }
        }

        It 'removes the tag via DELETE' {
            Remove-IntuneScopeTag -ScopeTagName @('ScopeTagTest')
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    Context 'when tag does not exist' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest { @{ value = @() } }
        }

        It 'reports NOT FOUND and does not DELETE' {
            Remove-IntuneScopeTag -ScopeTagName @('NonExistent')
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    Context 'when tag is built-in' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest {
                @{
                    value = @(
                        @{
                            id          = '0'
                            displayName = 'Default'
                            description = 'Built-in default tag'
                            isBuiltIn   = $true
                        }
                    )
                }
            }
        }

        It 'skips built-in tags and does not DELETE' {
            Remove-IntuneScopeTag -ScopeTagName @('Default')
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    Context 'WhatIfMode' {
        BeforeEach {
            Mock Get-MgContext {
                [pscustomobject]@{ Environment = 'Global'; Account = 'test@contoso.com' }
            }
            Mock Invoke-MgGraphRequest { $script:MockTagsResponse }
        }

        It 'does not DELETE when -WhatIfMode is specified' {
            Remove-IntuneScopeTag -ScopeTagName @('ScopeTagTest') -WhatIfMode
            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    Context 'parameter validation' {
        It 'ScopeTagName is mandatory' {
            $cmd = Get-Command Remove-IntuneScopeTag
            $cmd.Parameters['ScopeTagName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }
}
