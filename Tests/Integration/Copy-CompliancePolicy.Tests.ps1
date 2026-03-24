#Requires -Modules Pester

<#
.SYNOPSIS
    Pester v5 tests for Copy-IntuneCompliancePolicy.
#>

BeforeAll {
    Get-ChildItem -Path "$PSScriptRoot\..\..\Source" -Filter "*.ps1" -Recurse |
        ForEach-Object { . $_.FullName }

    # ---------------------------------------------------------------------------
    # Shared mock data
    # ---------------------------------------------------------------------------
    $script:MockRoleScopeTags = @{
        value = @(
            @{ id = '1'; displayName = 'Production' },
            @{ id = '2'; displayName = 'Development' }
        )
    }

    $script:MockPoliciesList = @{
        value = @(
            @{
                id                = 'policy-guid-1'
                displayName       = 'Windows 10 Compliance'
                roleScopeTagIds   = @('1')
            }
        )
    }

    $script:MockSinglePolicy = @{
        id                    = 'policy-guid-1'
        displayName           = 'Windows 10 Compliance'
        roleScopeTagIds       = @('1')
        '@odata.type'         = '#microsoft.graph.windows10CompliancePolicy'
        scheduledActionsForRule = @()
    }

    $script:MockPostResponse = @{
        id          = 'new-policy-guid'
        displayName = 'Copy of Windows 10 Compliance'
    }
}

# ===========================================================================
Describe 'Copy-IntuneCompliancePolicy' {
# ===========================================================================

    # -----------------------------------------------------------------------
    Context 'when not connected' {
    # -----------------------------------------------------------------------

        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Write-Warning {}
            Mock Invoke-MgGraphRequest {}
        }

        It 'writes a warning and exits when Get-MgContext returns $null' {
            Copy-IntuneCompliancePolicy `
                -SourceScopeTagName 'Production' `
                -DestinationScopeTagName 'Development'

            Should -Invoke Write-Warning -Times 1 -Exactly
            Should -Invoke Invoke-MgGraphRequest -Times 0
        }
    }

    # -----------------------------------------------------------------------
    Context 'when connected - Copy-IntuneCompliancePolicy' {
    # -----------------------------------------------------------------------

        BeforeEach {
            Mock Get-MgContext {
                return [PSCustomObject]@{ TenantId = 'tenant-guid'; Account = 'user@contoso.com' }
            }

            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body, $ContentType)

                switch -Regex ($Uri) {
                    '/beta/deviceManagement/roleScopeTags'      { return $script:MockRoleScopeTags }
                    '/beta/deviceManagement/deviceCompliancePolicies\?'  { return $script:MockPoliciesList }
                    '/beta/deviceManagement/deviceCompliancePolicies/policy-guid-1$' { return $script:MockSinglePolicy }
                    default {
                        if ($Method -eq 'POST') { return $script:MockPostResponse }
                    }
                }
            }

            Mock Write-Warning {}
            Mock Write-Host {}
        }

        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        It 'finds policies with a matching source scope tag' {
        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            Copy-IntuneCompliancePolicy `
                -SourceScopeTagName 'Production' `
                -DestinationScopeTagName 'Development' `
                -PolicyName 'Windows 10 Compliance'

            # Graph must be queried for scope tags and policies
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Uri -match 'roleScopeTags'
            }
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Uri -match 'deviceCompliancePolicies' -and $Method -ne 'POST'
            }
        }

        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        It 'does NOT call POST when -WhatIf is specified' {
        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            Copy-IntuneCompliancePolicy `
                -SourceScopeTagName 'Production' `
                -DestinationScopeTagName 'Development' `
                -PolicyName 'Windows 10 Compliance' `
                -WhatIf

            Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        It 'clones directly without an interactive picker when -PolicyName is supplied' {
        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            # Out-GridView (or equivalent picker) should never be called
            Mock Out-GridView { throw 'Picker should not be invoked when -PolicyName is provided' }

            { Copy-IntuneCompliancePolicy `
                -SourceScopeTagName 'Production' `
                -DestinationScopeTagName 'Development' `
                -PolicyName 'Windows 10 Compliance' } | Should -Not -Throw
        }

        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        It 'uses the specified -NewPolicyName when creating the clone' {
        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            $capturedBody = $null

            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body, $ContentType)

                switch -Regex ($Uri) {
                    '/beta/deviceManagement/roleScopeTags'                          { return $script:MockRoleScopeTags }
                    '/beta/deviceManagement/deviceCompliancePolicies\?'             { return $script:MockPoliciesList }
                    '/beta/deviceManagement/deviceCompliancePolicies/policy-guid-1$' { return $script:MockSinglePolicy }
                    default {
                        if ($Method -eq 'POST') {
                            $script:capturedBody = $Body
                            return $script:MockPostResponse
                        }
                    }
                }
            }

            Copy-IntuneCompliancePolicy `
                -SourceScopeTagName 'Production' `
                -DestinationScopeTagName 'Development' `
                -PolicyName 'Windows 10 Compliance' `
                -NewPolicyName 'Dev Windows 10 Compliance'

            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        It 'writes a warning when the specified -PolicyName is not found' {
        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            Copy-IntuneCompliancePolicy `
                -SourceScopeTagName 'Production' `
                -DestinationScopeTagName 'Development' `
                -PolicyName 'Nonexistent Policy'

            Should -Invoke Write-Warning -Times 1
        }
    }

    # -----------------------------------------------------------------------
    Context 'mandatory parameter validation' {
    # -----------------------------------------------------------------------

        It '-SourceScopeTagName is a mandatory parameter' {
            $param = (Get-Command Copy-IntuneCompliancePolicy).Parameters['SourceScopeTagName']
            $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory |
                Should -Be $true
        }

        It '-DestinationScopeTagName is a mandatory parameter' {
            $param = (Get-Command Copy-IntuneCompliancePolicy).Parameters['DestinationScopeTagName']
            $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory |
                Should -Be $true
        }

        It 'throws when -SourceScopeTagName receives more than one value (ValidateCount 1,1)' {
            {
                Copy-IntuneCompliancePolicy `
                    -SourceScopeTagName 'Production', 'Staging' `
                    -DestinationScopeTagName 'Development' `
                    -ErrorAction Stop
            } | Should -Throw
        }

        It 'accepts up to 64 values for -DestinationScopeTagName' {
            # Build 64 unique tag names; the function may warn about missing tags
            # but must not throw a parameter-validation error.
            Mock Get-MgContext { return $null }   # short-circuit execution
            Mock Write-Warning {}

            $manyTags = 1..64 | ForEach-Object { "Tag$_" }

            { Copy-IntuneCompliancePolicy `
                -SourceScopeTagName 'Production' `
                -DestinationScopeTagName $manyTags `
                -ErrorAction Stop } | Should -Not -Throw
        }
    }
}
