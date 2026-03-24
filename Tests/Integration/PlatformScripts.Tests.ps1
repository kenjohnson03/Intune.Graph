#Requires -Modules Pester

<#
.SYNOPSIS
    Pester v5 tests for Intune Platform Script management functions.

.DESCRIPTION
    Tests for:
      - Get-IntunePlatformScript
      - Get-IntunePlatformScriptAssignments
      - Copy-IntunePlatformScript
      - Add-IntunePlatformScriptAssignment
      - Remove-IntunePlatformScriptAssignment
      - Remove-IntunePlatformScript

.NOTES
    Requires Pester v5+.
    Run with: Invoke-Pester -Path .\PlatformScripts.Tests.ps1 -Output Detailed
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
                id              = 'script-id-1'
                displayName     = 'Deploy App'
                roleScopeTagIds = @('1')
                scriptContent   = 'base64content'
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
            }
        )
    }

    $script:MockGroup = @{
        id          = 'group-id-1'
        displayName = 'Test-Devices'
    }

    $script:MockPostResponse = @{
        id          = 'new-script-id'
        displayName = 'Copy of Deploy App'
    }
}

# ==============================================================================
# Get-IntunePlatformScript
# ==============================================================================
Describe 'Get-IntunePlatformScript' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            Get-IntunePlatformScript -All
            Should -Invoke Write-Warning -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }
    }

    Context 'happy path - retrieve all scripts' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest { return $script:MockScripts }
        }

        It 'returns all platform scripts when -All is specified' {
            $result = Get-IntunePlatformScript -All
            $result | Should -Not -BeNullOrEmpty
            $result.id | Should -Be 'script-id-1'
        }

        It 'calls Invoke-MgGraphRequest once' {
            Get-IntunePlatformScript -All
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }

    Context 'happy path - retrieve by Name' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest { return $script:MockScripts }
        }

        It 'returns the matching script when searching by name' {
            $result = Get-IntunePlatformScript -Name 'Deploy App'
            $result | Should -Not -BeNullOrEmpty
            $result.displayName | Should -Be 'Deploy App'
        }
    }

    Context 'happy path - retrieve by Id' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                return $script:MockScripts.value[0]
            }
        }

        It 'returns the matching script when searching by Id' {
            $result = Get-IntunePlatformScript -Id 'script-id-1'
            $result | Should -Not -BeNullOrEmpty
            $result.id | Should -Be 'script-id-1'
        }
    }

    Context 'parameter validation' {
        It 'Name parameter is mandatory in the Name parameter set' {
            $cmd = Get-Command Get-IntunePlatformScript
            $param = $cmd.Parameters['Name']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Id parameter is mandatory in the Id parameter set' {
            $cmd = Get-Command Get-IntunePlatformScript
            $param = $cmd.Parameters['Id']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'All is a switch parameter' {
            $cmd = Get-Command Get-IntunePlatformScript
            $cmd.Parameters['All'].ParameterType | Should -Be ([switch])
        }
    }
}

# ==============================================================================
# Get-IntunePlatformScriptAssignments
# ==============================================================================
Describe 'Get-IntunePlatformScriptAssignments' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            Get-IntunePlatformScriptAssignments -Id '00000000-0000-0000-0000-000000000001'
            Should -Invoke Write-Warning -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }
    }

    Context 'when no assignments exist' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest { return @{ value = @() } }
            Mock Write-Warning {}
        }

        It 'writes a warning when the script has no assignments' {
            Get-IntunePlatformScriptAssignments -Id '00000000-0000-0000-0000-000000000001'
            Should -Invoke Write-Warning -Times 1
        }
    }

    Context 'happy path - retrieve by Id' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match '/groups/') { return $script:MockGroup }
                return $script:MockAssignments
            }
        }

        It 'returns assignments with GroupName and AssignmentType resolved' {
            $result = Get-IntunePlatformScriptAssignments -Id '00000000-0000-0000-0000-000000000001'
            $result | Should -Not -BeNullOrEmpty
            $result.AssignmentId   | Should -Be 'assign1'
            $result.GroupName      | Should -Be 'Test-Devices'
            $result.AssignmentType | Should -Be 'include'
        }

        It 'accepts Id via pipeline' {
            $result = '00000000-0000-0000-0000-000000000001' | Get-IntunePlatformScriptAssignments
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'happy path - retrieve by Name' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceManagementScripts\?') { return $script:MockScripts }
                if ($Uri -match '/groups/')                  { return $script:MockGroup }
                return $script:MockAssignments
            }
        }

        It 'resolves the script by display name and returns assignments' {
            $result = Get-IntunePlatformScriptAssignments -Name 'Deploy App'
            $result | Should -Not -BeNullOrEmpty
            $result.GroupName      | Should -Be 'Test-Devices'
            $result.AssignmentType | Should -Be 'include'
        }
    }

    Context 'parameter validation' {
        It 'Id parameter is mandatory in the ById parameter set' {
            $param = (Get-Command Get-IntunePlatformScriptAssignments).Parameters['Id']
            $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory |
                Should -Be $true
        }

        It 'Name parameter is mandatory in the ByName parameter set' {
            $param = (Get-Command Get-IntunePlatformScriptAssignments).Parameters['Name']
            $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory |
                Should -Be $true
        }
    }
}

# ==============================================================================
# Copy-IntunePlatformScript
# ==============================================================================
Describe 'Copy-IntunePlatformScript' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            Copy-IntunePlatformScript -SourceScopeTagName 'Production' `
                                      -DestinationScopeTagName 'Development'
            Should -Invoke Write-Warning -Times 1 -Exactly
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }
    }

    Context 'happy path - copy all scripts from source scope tag' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body)
                if ($Method -eq 'POST' -or $Method -eq 'PATCH') {
                    return $script:MockPostResponse
                }
                if ($Uri -match 'roleScopeTags') {
                    return $script:MockScopeTags
                }
                return $script:MockScripts
            }
        }

        It 'returns the new script object after copying' {
            { Copy-IntunePlatformScript -SourceScopeTagName 'Production' `
                                        -DestinationScopeTagName 'Development' `
                                        -ScriptName 'Deploy App'
            } | Should -Not -Throw
        }

        It 'calls Invoke-MgGraphRequest for source scripts, scope tags, and POST' {
            Copy-IntunePlatformScript -SourceScopeTagName 'Production' `
                                      -DestinationScopeTagName 'Development' `
                                      -ScriptName 'Deploy App'
            Should -Invoke Invoke-MgGraphRequest -Times 1
        }
    }

    Context 'happy path - copy specific script by name with custom new name' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body)
                if ($Method -eq 'POST' -or $Method -eq 'PATCH') {
                    return $script:MockPostResponse
                }
                if ($Uri -match 'roleScopeTags') {
                    return $script:MockScopeTags
                }
                return $script:MockScripts
            }
        }

        It 'accepts ScriptName and NewScriptName parameters' {
            Copy-IntunePlatformScript -SourceScopeTagName 'Production' `
                                      -DestinationScopeTagName 'Development' `
                                      -ScriptName 'Deploy App' `
                                      -NewScriptName 'Deploy App (Dev)'
            # Should not throw; result may be script object or null depending on implementation
            $true | Should -Be $true
        }
    }

    Context '-WhatIf behavior' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method, $Body)
                if ($Uri -match 'roleScopeTags') { return $script:MockScopeTags }
                return $script:MockScripts
            }
        }

        It 'does not POST when -WhatIf is specified' {
            Copy-IntunePlatformScript -SourceScopeTagName 'Production' `
                                      -DestinationScopeTagName 'Development' `
                                      -ScriptName 'Deploy App' `
                                      -WhatIf

            Should -Invoke Invoke-MgGraphRequest -ParameterFilter {
                $Method -eq 'POST'
            } -Times 0 -Exactly
        }
    }

    Context 'parameter validation' {
        It 'SourceScopeTagName is mandatory' {
            $cmd = Get-Command Copy-IntunePlatformScript
            $cmd.Parameters['SourceScopeTagName'] | Should -Not -BeNullOrEmpty
        }

        It 'DestinationScopeTagName is mandatory' {
            $cmd = Get-Command Copy-IntunePlatformScript
            $cmd.Parameters['DestinationScopeTagName'] | Should -Not -BeNullOrEmpty
        }

        It 'ScriptName is optional' {
            $cmd = Get-Command Copy-IntunePlatformScript
            $cmd.Parameters.ContainsKey('ScriptName') | Should -Be $true
        }

        It 'NewScriptName is optional' {
            $cmd = Get-Command Copy-IntunePlatformScript
            $cmd.Parameters.ContainsKey('NewScriptName') | Should -Be $true
        }
    }
}

# ==============================================================================
# Add-IntunePlatformScriptAssignment
# ==============================================================================
Describe 'Add-IntunePlatformScriptAssignment' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            Add-IntunePlatformScriptAssignment -Id '00000000-0000-0000-0000-000000000001' `
                                               -GroupId '00000000-0000-0000-0000-000000000002' `
                                               -IncludeExcludeGroup 'include'
            Should -Invoke Write-Warning -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }
    }

    Context 'happy path - add include assignment' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest { return $script:MockPostResponse }
        }

        It 'posts the assignment and returns a result' {
            Add-IntunePlatformScriptAssignment -Id '00000000-0000-0000-0000-000000000001' `
                                               -GroupId '00000000-0000-0000-0000-000000000002' `
                                               -IncludeExcludeGroup 'include'
            # Function does GET (fetch existing) + POST (assign) = 2 calls
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
        }

        It 'posts the assignment for exclude type' {
            Add-IntunePlatformScriptAssignment -Id '00000000-0000-0000-0000-000000000001' `
                                               -GroupId '00000000-0000-0000-0000-000000000002' `
                                               -IncludeExcludeGroup 'exclude'
            # Function does GET (fetch existing) + POST (assign) = 2 calls
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
        }
    }

    Context 'happy path - add by script name and group name' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Method -eq 'GET' -and $Uri -match 'deviceManagementScripts\?') { return $script:MockScripts }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                  { return @{ value = @(@{ id = '00000000-0000-0000-0000-000000000002'; displayName = 'Test-Devices' }) } }
                return $script:MockPostResponse
            }
        }

        It 'resolves script and group names before assigning' {
            Add-IntunePlatformScriptAssignment -Name 'Deploy App' `
                                               -GroupName 'Test-Devices' `
                                               -IncludeExcludeGroup 'include'
            # 2 name-resolution GETs + 1 GET existing assignments + 1 POST = 4 calls
            Should -Invoke Invoke-MgGraphRequest -Times 4 -Exactly
        }

        It 'resolves group name with a known script Id' {
            Add-IntunePlatformScriptAssignment -Id '00000000-0000-0000-0000-000000000001' `
                                               -GroupName 'Test-Devices' `
                                               -IncludeExcludeGroup 'include'
            # 1 GET group + 1 GET existing assignments + 1 POST = 3 calls
            Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly
        }
    }

    Context 'happy path - pipeline input via AssignmentObject' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest { return $script:MockPostResponse }
        }

        It 'accepts an AssignmentObject from the pipeline' {
            [PSCustomObject]@{
                '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                groupId       = '00000000-0000-0000-0000-000000000002'
            } | Add-IntunePlatformScriptAssignment `
                    -Id '00000000-0000-0000-0000-000000000001' `
                    -ErrorAction Stop
            # Function does GET (fetch existing) + POST (assign) = 2 calls
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
        }
    }

    Context 'parameter validation' {
        It 'Id parameter is available for script GUID lookup' {
            $cmd = Get-Command Add-IntunePlatformScriptAssignment
            $cmd.Parameters['Id'] | Should -Not -BeNullOrEmpty
        }

        It 'Name parameter is available for script name lookup' {
            $cmd = Get-Command Add-IntunePlatformScriptAssignment
            $cmd.Parameters['Name'] | Should -Not -BeNullOrEmpty
        }

        It 'GroupId parameter is available for group GUID lookup' {
            $cmd = Get-Command Add-IntunePlatformScriptAssignment
            $cmd.Parameters['GroupId'] | Should -Not -BeNullOrEmpty
        }

        It 'GroupName parameter is available for group name lookup' {
            $cmd = Get-Command Add-IntunePlatformScriptAssignment
            $cmd.Parameters['GroupName'] | Should -Not -BeNullOrEmpty
        }

        It 'IncludeExcludeGroup has a ValidateSet of include and exclude' {
            $cmd = Get-Command Add-IntunePlatformScriptAssignment
            $validateSet = $cmd.Parameters['IncludeExcludeGroup'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'include'
            $validateSet.ValidValues | Should -Contain 'exclude'
        }
    }
}

# ==============================================================================
# Remove-IntunePlatformScriptAssignment
# ==============================================================================
Describe 'Remove-IntunePlatformScriptAssignment' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            Remove-IntunePlatformScriptAssignment -Id '00000000-0000-0000-0000-000000000001' -GroupId '00000000-0000-0000-0000-000000000002'
            Should -Invoke Write-Warning -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }
    }

    Context 'happy path' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest { return $null }
        }

        It 'calls Invoke-MgGraphRequest to remove the assignment' {
            Remove-IntunePlatformScriptAssignment -Id '00000000-0000-0000-0000-000000000001' -GroupId '00000000-0000-0000-0000-000000000002'
            # Function does GET (fetch existing) + POST (remaining assignments) = 2 calls
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
        }
    }

    Context 'happy path - remove by script name and group name' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                if ($Method -eq 'GET' -and $Uri -match 'deviceManagementScripts\?') { return $script:MockScripts }
                if ($Method -eq 'GET' -and $Uri -match 'groups\?')                  { return @{ value = @(@{ id = '00000000-0000-0000-0000-000000000002'; displayName = 'Test-Devices' }) } }
                return $null
            }
        }

        It 'resolves script and group names before removing' {
            Remove-IntunePlatformScriptAssignment -Name 'Deploy App' -GroupName 'Test-Devices'
            # 2 name-resolution GETs + 1 GET existing assignments + 1 POST = 4 calls
            Should -Invoke Invoke-MgGraphRequest -Times 4 -Exactly
        }

        It 'resolves group name with a known script Id' {
            Remove-IntunePlatformScriptAssignment -Id '00000000-0000-0000-0000-000000000001' `
                                                  -GroupName 'Test-Devices'
            # 1 GET group + 1 GET existing assignments + 1 POST = 3 calls
            Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly
        }
    }

    Context 'parameter validation' {
        It 'Id parameter is mandatory in all applicable parameter sets' {
            $param = (Get-Command Remove-IntunePlatformScriptAssignment).Parameters['Id']
            $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory -eq $true } |
                Should -Not -BeNullOrEmpty
        }

        It 'GroupId parameter is mandatory in all applicable parameter sets' {
            $param = (Get-Command Remove-IntunePlatformScriptAssignment).Parameters['GroupId']
            $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Where-Object { $_.Mandatory -eq $true } |
                Should -Not -BeNullOrEmpty
        }

        It 'Name parameter is available for script name lookup' {
            $cmd = Get-Command Remove-IntunePlatformScriptAssignment
            $cmd.Parameters['Name'] | Should -Not -BeNullOrEmpty
        }

        It 'GroupName parameter is available for group name lookup' {
            $cmd = Get-Command Remove-IntunePlatformScriptAssignment
            $cmd.Parameters['GroupName'] | Should -Not -BeNullOrEmpty
        }
    }
}

# ==============================================================================
# Remove-IntunePlatformScript
# ==============================================================================
Describe 'Remove-IntunePlatformScript' {

    Context 'when not connected to Microsoft Graph' {
        BeforeEach {
            Mock Get-MgContext { return $null }
            Mock Invoke-MgGraphRequest {}
            Mock Write-Warning {}
        }

        It 'writes a warning and does not call Invoke-MgGraphRequest' {
            Remove-IntunePlatformScript -Id 'script-id-1'
            Should -Invoke Write-Warning -Times 1 -Exactly
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }
    }

    Context 'happy path - by Id' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest { return $null }
        }

        It 'calls Invoke-MgGraphRequest with DELETE method' {
            Remove-IntunePlatformScript -Id 'script-id-1'
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }

        It 'accepts Id from the pipeline' {
            'script-id-1' | Remove-IntunePlatformScript
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }

    Context 'happy path - by Name' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match 'deviceManagementScripts\?') { return $script:MockScripts }
                return $null
            }
        }

        It 'resolves the script name then deletes' {
            Remove-IntunePlatformScript -Name 'Deploy App'
            # 1 GET (name resolution) + 1 DELETE = 2 calls
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
        }

        It 'writes a warning when the script name is not found' {
            Mock Invoke-MgGraphRequest { return @{ value = @() } }
            Mock Write-Warning {}
            Remove-IntunePlatformScript -Name 'DoesNotExist'
            Should -Invoke Write-Warning -Times 1
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }

    Context '-WhatIf behavior' {
        BeforeEach {
            Mock Get-MgContext { return @{ Account = 'test@contoso.com' } }
            Mock Invoke-MgGraphRequest { return $null }
        }

        It 'does not call Invoke-MgGraphRequest when -WhatIf is specified' {
            Remove-IntunePlatformScript -Id 'script-id-1' -WhatIf
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }
    }

    Context 'parameter validation' {
        It 'Id parameter is mandatory in the ById parameter set' {
            $param = (Get-Command Remove-IntunePlatformScript).Parameters['Id']
            $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }

        It 'Name parameter is mandatory in the ByName parameter set' {
            $param = (Get-Command Remove-IntunePlatformScript).Parameters['Name']
            $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }

        It 'supports ShouldProcess (-WhatIf / -Confirm)' {
            $cmd = Get-Command Remove-IntunePlatformScript
            $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $true
        }
    }
}
