BeforeAll {
    # Convert-Path required for PS7 or Join-Path fails
    $projectPath = "$($PSScriptRoot)\..\..\..\" | Convert-Path

    <#
        If the tests are run outside of the build script (e.g with Invoke-Pester)
        the parent scope has not set the variable $ProjectName.
    #>
    if (-not $ProjectName)
    {
        # Assuming project folder name is project name.
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName

    # Dot source the private function
    $privateFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Get-SubtreeInfo.ps1'
    . $privateFunctionPath
}

Describe 'Get-SubtreeInfo' -Tag 'Unit', 'Private' {
    Context 'When git is available and subtree metadata exists' {
        BeforeAll {
            # Mock Get-Command to return a valid git path
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should return subtree info for valid module' {
            # Mock git log output with subtree metadata
            $mockCommitOutput = @"
abc123def456abc123def456abc123def456abc123|2024-01-15T10:30:00-05:00|Squashed 'modules/TestModule/' content from commit fedcba98

git-subtree-dir: modules/TestModule
git-subtree-split: fedcba9876543210fedcba9876543210fedcba98
"@

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $mockCommitOutput
            }

            $result = Get-SubtreeInfo -ModuleName 'TestModule'

            $result | Should -Not -BeNullOrEmpty
            $result.CommitHash | Should -Be 'fedcba9876543210fedcba9876543210fedcba98'
            $result.LocalCommitHash | Should -Be 'abc123def456abc123def456abc123def456abc123'
            $result.ModuleName | Should -Be 'TestModule'
            $result.Prefix | Should -Be 'modules/TestModule'
        }

        It 'Should return PSCustomObject with all expected properties' {
            $mockCommitOutput = @"
abc123def456abc123def456abc123def456abc123|2024-01-15T10:30:00-05:00|Squashed commit

git-subtree-dir: modules/TestModule
git-subtree-split: fedcba9876543210fedcba9876543210fedcba98
"@

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $mockCommitOutput
            }

            $result = Get-SubtreeInfo -ModuleName 'TestModule'

            $result.PSObject.Properties.Name | Should -Contain 'CommitHash'
            $result.PSObject.Properties.Name | Should -Contain 'LocalCommitHash'
            $result.PSObject.Properties.Name | Should -Contain 'CommitDate'
            $result.PSObject.Properties.Name | Should -Contain 'ModuleName'
            $result.PSObject.Properties.Name | Should -Contain 'Prefix'
        }

        It 'Should extract correct commit date' {
            $mockCommitOutput = @"
abc123def456abc123def456abc123def456abc123|2024-06-20T14:45:30+00:00|Squashed commit

git-subtree-dir: modules/TestModule
git-subtree-split: fedcba9876543210fedcba9876543210fedcba98
"@

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $mockCommitOutput
            }

            $result = Get-SubtreeInfo -ModuleName 'TestModule'

            $result.CommitDate | Should -Be '2024-06-20T14:45:30+00:00'
        }

        It 'Should handle custom ModulesPath' {
            $mockCommitOutput = @"
abc123def456abc123def456abc123def456abc123|2024-01-15T10:30:00-05:00|Squashed commit

git-subtree-dir: libs/TestModule
git-subtree-split: fedcba9876543210fedcba9876543210fedcba98
"@

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $mockCommitOutput
            }

            $result = Get-SubtreeInfo -ModuleName 'TestModule' -ModulesPath 'libs'

            $result | Should -Not -BeNullOrEmpty
            $result.Prefix | Should -Be 'libs/TestModule'
        }
    }

    Context 'When no subtree metadata exists' {
        BeforeAll {
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should return null when no matching commits found' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $null
            }

            $result = Get-SubtreeInfo -ModuleName 'NonExistentModule'

            $result | Should -BeNullOrEmpty
        }

        It 'Should return null when git-subtree-split marker is missing' {
            $mockCommitOutput = @"
abc123def456abc123def456abc123def456abc123|2024-01-15T10:30:00-05:00|Regular commit without subtree metadata

git-subtree-dir: modules/TestModule
"@

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $mockCommitOutput
            }

            $result = Get-SubtreeInfo -ModuleName 'TestModule'

            $result | Should -BeNullOrEmpty
        }

        It 'Should return null when git-subtree-dir does not match prefix' {
            $mockCommitOutput = @"
abc123def456abc123def456abc123def456abc123|2024-01-15T10:30:00-05:00|Squashed commit

git-subtree-dir: modules/DifferentModule
git-subtree-split: fedcba9876543210fedcba9876543210fedcba98
"@

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $mockCommitOutput
            }

            $result = Get-SubtreeInfo -ModuleName 'TestModule'

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When git command fails' {
        BeforeAll {
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should return null when git log fails' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 128
                return 'fatal: not a git repository'
            }

            $result = Get-SubtreeInfo -ModuleName 'TestModule'

            $result | Should -BeNullOrEmpty
        }

        It 'Should output warning when git log fails' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 128
                return 'fatal: not a git repository'
            }

            Get-SubtreeInfo -ModuleName 'TestModule' -WarningVariable warnings 3>&1 | Out-Null

            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When git is not available' {
        BeforeAll {
            Mock -CommandName Get-Command -MockWith {
                return $null
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should return null when git is not installed' {
            $result = Get-SubtreeInfo -ModuleName 'TestModule'

            $result | Should -BeNullOrEmpty
        }

        It 'Should write error when git is not installed' {
            Get-SubtreeInfo -ModuleName 'TestModule' -ErrorVariable errors 2>&1 | Out-Null

            $errors | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When using WorkingDirectory parameter' {
        BeforeAll {
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }

            $mockCommitOutput = @"
abc123def456abc123def456abc123def456abc123|2024-01-15T10:30:00-05:00|Squashed commit

git-subtree-dir: modules/TestModule
git-subtree-split: fedcba9876543210fedcba9876543210fedcba98
"@

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $mockCommitOutput
            }

            Mock -CommandName Get-Location -MockWith {
                return [PSCustomObject]@{ Path = '/original/path' }
            }

            Mock -CommandName Set-Location -MockWith { }
        }

        It 'Should change to working directory and restore location' {
            # Create a temp directory for testing
            $tempDir = Join-Path -Path $TestDrive -ChildPath 'testrepo'
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $result = Get-SubtreeInfo -ModuleName 'TestModule' -WorkingDirectory $tempDir

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName Set-Location -Times 2 -Exactly
        }

        It 'Should fail when working directory does not exist' {
            $invalidDir = Join-Path -Path $TestDrive -ChildPath 'nonexistent'

            { Get-SubtreeInfo -ModuleName 'TestModule' -WorkingDirectory $invalidDir } | Should -Throw
        }
    }

    Context 'Parameter validation' {
        BeforeAll {
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should require ModuleName parameter' {
            { Get-SubtreeInfo -ModuleName $null } | Should -Throw
        }

        It 'Should not accept empty ModuleName' {
            { Get-SubtreeInfo -ModuleName '' } | Should -Throw
        }

        It 'Should not accept empty ModulesPath' {
            { Get-SubtreeInfo -ModuleName 'TestModule' -ModulesPath '' } | Should -Throw
        }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }

            $mockCommitOutput = @"
abc123def456abc123def456abc123def456abc123|2024-01-15T10:30:00-05:00|Squashed commit

git-subtree-dir: modules/TestModule
git-subtree-split: fedcba9876543210fedcba9876543210fedcba98
"@

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $mockCommitOutput
            }
        }

        It 'Should output verbose messages when -Verbose is used' {
            $verboseOutput = Get-SubtreeInfo -ModuleName 'TestModule' -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Edge cases' {
        BeforeAll {
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should handle module names with dots' {
            $mockCommitOutput = @"
abc123def456abc123def456abc123def456abc123|2024-01-15T10:30:00-05:00|Squashed commit

git-subtree-dir: modules/My.Module.Name
git-subtree-split: fedcba9876543210fedcba9876543210fedcba98
"@

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $mockCommitOutput
            }

            $result = Get-SubtreeInfo -ModuleName 'My.Module.Name'

            $result | Should -Not -BeNullOrEmpty
            $result.ModuleName | Should -Be 'My.Module.Name'
        }

        It 'Should handle module names with hyphens and underscores' {
            $mockCommitOutput = @"
abc123def456abc123def456abc123def456abc123|2024-01-15T10:30:00-05:00|Squashed commit

git-subtree-dir: modules/My-Module_Name
git-subtree-split: fedcba9876543210fedcba9876543210fedcba98
"@

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $mockCommitOutput
            }

            $result = Get-SubtreeInfo -ModuleName 'My-Module_Name'

            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should handle commit messages with multiple git-subtree markers' {
            # This can happen with merged subtree pulls
            $mockCommitOutput = @"
abc123def456abc123def456abc123def456abc123|2024-01-15T10:30:00-05:00|Merge commit for subtree

git-subtree-dir: modules/TestModule
git-subtree-split: fedcba9876543210fedcba9876543210fedcba98
"@

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $mockCommitOutput
            }

            $result = Get-SubtreeInfo -ModuleName 'TestModule'

            $result | Should -Not -BeNullOrEmpty
            $result.CommitHash | Should -Be 'fedcba9876543210fedcba9876543210fedcba98'
        }

        It 'Should handle empty git log output' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return ''
            }

            $result = Get-SubtreeInfo -ModuleName 'TestModule'

            $result | Should -BeNullOrEmpty
        }

        It 'Should handle whitespace-only git log output' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return '   '
            }

            $result = Get-SubtreeInfo -ModuleName 'TestModule'

            $result | Should -BeNullOrEmpty
        }
    }
}
