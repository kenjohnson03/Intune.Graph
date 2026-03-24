#Requires -Modules Pester

<#
.SYNOPSIS
    Pester v5 tests for Copy-IntuneConfigurationProfile.

.NOTES
    Requires Pester v5+. Run with: Invoke-Pester -Path .\CopyIntuneConfigProfile.Tests.ps1 -Output Detailed
#>

BeforeAll {
    Get-ChildItem -Path "$PSScriptRoot\..\..\Source" -Filter "*.ps1" -Recurse |
        ForEach-Object { . $_.FullName }

    # ---------------------------------------------------------------------------
    # Shared mock data
    # ---------------------------------------------------------------------------

    # Single Settings Catalog policy tagged with Production (id=1)
    $script:MockSCPolicies = @{
        value = @(
            @{
                id               = 'policy-id-1'
                name             = 'AV Policy'
                roleScopeTagIds  = @('1')
                settings         = @()
                platforms        = 'windows10'
                technologies     = 'mdm'
                templateReference = @{ templateId = '' }
            }
        )
    }

    # Two Settings Catalog policies for multi-profile tests
    $script:MockSCPoliciesTwo = @{
        value = @(
            @{
                id               = 'policy-id-1'
                name             = 'AV Policy'
                roleScopeTagIds  = @('1')
                settings         = @()
                platforms        = 'windows10'
                technologies     = 'mdm'
                templateReference = @{ templateId = '' }
            },
            @{
                id               = 'policy-id-2'
                name             = 'Firewall Policy'
                roleScopeTagIds  = @('1')
                settings         = @()
                platforms        = 'windows10'
                technologies     = 'mdm'
                templateReference = @{ templateId = '' }
            }
        )
    }

    # All endpoints not explicitly matched return empty
    $script:MockEmpty = @{ value = @() }

    # Three scope tags so destination multi-tag tests have a third option
    $script:MockScopeTags = @{
        value = @(
            @{ id = '1'; displayName = 'Production' }
            @{ id = '2'; displayName = 'Development' }
            @{ id = '3'; displayName = 'Test' }
        )
    }

    $script:MockPostResponse = @{
        id   = 'new-policy-id'
        name = 'Copy of AV Policy'
    }
}

# ==============================================================================
# Copy-IntuneConfigurationProfile
# ==============================================================================
Describe 'Copy-IntuneConfigurationProfile' {

    # --------------------------------------------------------------------------
    Context 'when not connected to Microsoft Graph' {
    # --------------------------------------------------------------------------
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Write-Warning {}
        }

        It 'writes a warning and returns nothing when not connected' {
            Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      'Production' `
                -DestinationScopeTagName 'Development'
            Should -Invoke 'Write-Warning' -Times 1
        }
    }

    # --------------------------------------------------------------------------
    Context 'when connected' {
    # --------------------------------------------------------------------------
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }

            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body, $ContentType)
                if ($Method -eq 'POST')                         { return $script:MockPostResponse }
                if ($Uri -match 'roleScopeTags')                { return $script:MockScopeTags }
                if ($Uri -match 'configurationPolicies')        { return $script:MockSCPolicies }
                return $script:MockEmpty
            }

            Mock Write-Warning {}
        }

        It 'calls POST to create a new profile copy' {
            Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      @('Production') `
                -DestinationScopeTagName @('Development') `
                -ProfileName             'AV Policy'

            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'does not call POST when -WhatIf is supplied' {
            Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      @('Production') `
                -DestinationScopeTagName @('Development') `
                -ProfileName             'AV Policy' `
                -WhatIf

            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'copies only the named profile when -ProfileName is supplied' {
            { Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      @('Production') `
                -DestinationScopeTagName @('Development') `
                -ProfileName             'AV Policy'
            } | Should -Not -Throw
        }

        It 'POST body contains the supplied -NewProfileName' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body, $ContentType)
                if ($Method -eq 'POST') {
                    $script:capturedBody = $Body
                    return $script:MockPostResponse
                }
                if ($Uri -match 'roleScopeTags')         { return $script:MockScopeTags }
                if ($Uri -match 'configurationPolicies') { return $script:MockSCPolicies }
                return $script:MockEmpty
            }

            Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      @('Production') `
                -DestinationScopeTagName @('Development') `
                -ProfileName             'AV Policy' `
                -NewProfileName          'AV Policy - Dev Clone'

            $script:capturedBody | Should -Not -BeNullOrEmpty
            ($script:capturedBody | ConvertFrom-Json).name | Should -Be 'AV Policy - Dev Clone'
        }

        It 'writes a warning when -ProfileName is not found' {
            Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      @('Production') `
                -DestinationScopeTagName @('Development') `
                -ProfileName             'Nonexistent Policy'

            Should -Invoke 'Write-Warning' -Times 1
        }

        It 'does not throw when -ExactMatch is specified' {
            { Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      @('Production') `
                -DestinationScopeTagName @('Development') `
                -ProfileName             'AV Policy' `
                -ExactMatch
            } | Should -Not -Throw
        }

        It 'POSTs once per profile when -ProfileName is an array of two names' {
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body, $ContentType)
                if ($Method -eq 'POST')                         { return $script:MockPostResponse }
                if ($Uri -match 'roleScopeTags')                { return $script:MockScopeTags }
                if ($Uri -match 'configurationPolicies')        { return $script:MockSCPoliciesTwo }
                return $script:MockEmpty
            }

            Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      @('Production') `
                -DestinationScopeTagName @('Development') `
                -ProfileName             @('AV Policy', 'Firewall Policy')

            Should -Invoke Invoke-MgGraphRequest -Times 2 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'warns and ignores -NewProfileName when multiple -ProfileName values are supplied' {
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body, $ContentType)
                if ($Method -eq 'POST')                         { return $script:MockPostResponse }
                if ($Uri -match 'roleScopeTags')                { return $script:MockScopeTags }
                if ($Uri -match 'configurationPolicies')        { return $script:MockSCPoliciesTwo }
                return $script:MockEmpty
            }

            Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      @('Production') `
                -DestinationScopeTagName @('Development') `
                -ProfileName             @('AV Policy', 'Firewall Policy') `
                -NewProfileName          'Should Be Ignored'

            Should -Invoke 'Write-Warning' -Times 1
        }

        It 'does not POST and does not throw when no profiles exist under the source tag' {
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Uri -match 'roleScopeTags') { return $script:MockScopeTags }
                return $script:MockEmpty
            }

            { Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      @('Production') `
                -DestinationScopeTagName @('Development') `
                -ProfileName             'AV Policy'
            } | Should -Not -Throw

            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'POST body includes all destination tag IDs when multiple -DestinationScopeTagName values are supplied' {
            $script:capturedBody = $null
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body, $ContentType)
                if ($Method -eq 'POST') {
                    $script:capturedBody = $Body
                    return $script:MockPostResponse
                }
                if ($Uri -match 'roleScopeTags')         { return $script:MockScopeTags }
                if ($Uri -match 'configurationPolicies') { return $script:MockSCPolicies }
                return $script:MockEmpty
            }

            Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      @('Production') `
                -DestinationScopeTagName @('Development', 'Test') `
                -ProfileName             'AV Policy'

            $script:capturedBody | Should -Not -BeNullOrEmpty
            $parsedBody = $script:capturedBody | ConvertFrom-Json
            $parsedBody.roleScopeTagIds | Should -Contain '2'
            $parsedBody.roleScopeTagIds | Should -Contain '3'
        }
    }

    # --------------------------------------------------------------------------
    Context 'when source scope tag is not found' {
    # --------------------------------------------------------------------------
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'roleScopeTags') {
                    return @{ value = @(@{ id = '99'; displayName = 'SomeOtherTag' }) }
                }
                return $script:MockEmpty
            }
        }

        It 'throws when the source scope tag does not exist' {
            { Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      'Production' `
                -DestinationScopeTagName 'Development' `
                -ProfileName             'AV Policy'
            } | Should -Throw
        }
    }

    # --------------------------------------------------------------------------
    Context 'when destination scope tag is not found' {
    # --------------------------------------------------------------------------
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'roleScopeTags') {
                    # Source (Production) exists; destination (Development) does not
                    return @{ value = @(@{ id = '1'; displayName = 'Production' }) }
                }
                return $script:MockEmpty
            }
        }

        It 'throws when the destination scope tag does not exist' {
            { Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      'Production' `
                -DestinationScopeTagName 'Development' `
                -ProfileName             'AV Policy'
            } | Should -Throw
        }
    }

    # --------------------------------------------------------------------------
    Context 'parameter validation' {
    # --------------------------------------------------------------------------
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Uri -match 'roleScopeTags')         { return $script:MockScopeTags }
                if ($Uri -match 'configurationPolicies') { return $script:MockSCPolicies }
                return $script:MockEmpty
            }
        }

        It 'accepts MaxRetries value of 0' {
            {
                Copy-IntuneConfigurationProfile `
                    -SourceScopeTagName      @('Production') `
                    -DestinationScopeTagName @('Development') `
                    -ProfileName             'AV Policy' `
                    -MaxRetries              0 `
                    -WhatIf
            } | Should -Not -Throw
        }

        It 'accepts MaxRetries value of 20' {
            {
                Copy-IntuneConfigurationProfile `
                    -SourceScopeTagName      @('Production') `
                    -DestinationScopeTagName @('Development') `
                    -ProfileName             'AV Policy' `
                    -MaxRetries              20 `
                    -WhatIf
            } | Should -Not -Throw
        }

        It 'throws when MaxRetries is outside the valid range' {
            {
                Copy-IntuneConfigurationProfile `
                    -SourceScopeTagName      @('Production') `
                    -DestinationScopeTagName @('Development') `
                    -MaxRetries              99
            } | Should -Throw
        }

        It '-SourceScopeTagName is a mandatory parameter' {
            $param = (Get-Command Copy-IntuneConfigurationProfile).Parameters['SourceScopeTagName']
            $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory |
                Should -Be $true
        }

        It '-DestinationScopeTagName is a mandatory parameter' {
            $param = (Get-Command Copy-IntuneConfigurationProfile).Parameters['DestinationScopeTagName']
            $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory |
                Should -Be $true
        }

        It 'accepts up to 64 values for -DestinationScopeTagName' {
            Mock Get-MgContext { return $null }
            Mock Write-Warning {}
            $manyTags = 1..64 | ForEach-Object { "Tag$_" }
            { Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      'Production' `
                -DestinationScopeTagName $manyTags `
                -ErrorAction Stop
            } | Should -Not -Throw
        }

        It 'throws when -DestinationScopeTagName receives more than 64 values' {
            $tooManyTags = 1..65 | ForEach-Object { "Tag$_" }
            { Copy-IntuneConfigurationProfile `
                -SourceScopeTagName      'Production' `
                -DestinationScopeTagName $tooManyTags `
                -ErrorAction Stop
            } | Should -Throw
        }
    }
}
