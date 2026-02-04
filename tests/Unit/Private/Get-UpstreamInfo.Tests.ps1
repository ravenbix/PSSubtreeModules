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
    $privateFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Get-UpstreamInfo.ps1'
    . $privateFunctionPath
}

Describe 'Get-UpstreamInfo' -Tag 'Unit', 'Private' {
    Context 'When git is available and repository is accessible' {
        BeforeAll {
            # Mock Get-Command to return a valid git path
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should return commit hash for branch ref' {
            # Mock git ls-remote with --refs first
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return @(
                    "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2`trefs/heads/main",
                    "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3`trefs/heads/develop"
                )
            }

            $result = Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'main'

            $result | Should -Not -BeNullOrEmpty
            $result.CommitHash | Should -Be 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2'
            $result.Ref | Should -Be 'main'
            $result.Repository | Should -Be 'https://github.com/owner/repo.git'
        }

        It 'Should return commit hash for tag ref' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return @(
                    "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2`trefs/heads/main",
                    "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4`trefs/tags/v1.0.0"
                )
            }

            $result = Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'v1.0.0'

            $result | Should -Not -BeNullOrEmpty
            $result.CommitHash | Should -Be 'c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4'
            $result.Ref | Should -Be 'v1.0.0'
        }

        It 'Should return PSCustomObject with correct properties' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2`trefs/heads/main"
            }

            $result = Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'main'

            $result.PSObject.Properties.Name | Should -Contain 'CommitHash'
            $result.PSObject.Properties.Name | Should -Contain 'Ref'
            $result.PSObject.Properties.Name | Should -Contain 'Repository'
        }

        It 'Should use HEAD as default ref' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2`tHEAD"
            }

            $result = Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git'

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName git -Times 1 -Exactly -ParameterFilter { $args -contains 'HEAD' }
        }

        It 'Should handle full ref path format' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2`trefs/heads/feature/my-branch"
            }

            $result = Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'refs/heads/feature/my-branch'

            $result | Should -Not -BeNullOrEmpty
            $result.CommitHash | Should -Be 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2'
        }
    }

    Context 'When ref is not found' {
        BeforeAll {
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should return null when ref does not exist' {
            # First call returns refs but no match, second direct call also fails
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return @(
                    "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2`trefs/heads/main"
                )
            } -ParameterFilter { $args -contains '--refs' }

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return $null
            } -ParameterFilter { $args -notcontains '--refs' }

            $result = Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'nonexistent-branch'

            $result | Should -BeNullOrEmpty
        }

        It 'Should output warning when ref not found' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return @()
            }

            $warningOutput = Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'invalid-ref' -WarningVariable warnings 3>&1

            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When repository is unreachable' {
        BeforeAll {
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should return null on network error' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 128
                return 'fatal: unable to access repository'
            }

            $result = Get-UpstreamInfo -Repository 'https://github.com/owner/invalid-repo.git' -Ref 'main'

            $result | Should -BeNullOrEmpty
        }

        It 'Should output warning on network error' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 128
                return 'fatal: unable to access repository'
            }

            $warningOutput = Get-UpstreamInfo -Repository 'https://github.com/owner/invalid-repo.git' -Ref 'main' -WarningVariable warnings 3>&1

            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Should not throw exception on network error' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 128
                return 'fatal: could not read from remote repository'
            }

            { Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'main' } | Should -Not -Throw
        }
    }

    Context 'When git is not available' {
        BeforeAll {
            Mock -CommandName Get-Command -MockWith {
                return $null
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should return null when git is not installed' {
            $result = Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'main'

            $result | Should -BeNullOrEmpty
        }

        It 'Should write error when git is not installed' {
            Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'main' -ErrorVariable errors 2>&1 | Out-Null

            $errors | Should -Not -BeNullOrEmpty
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

        It 'Should require Repository parameter' {
            { Get-UpstreamInfo -Repository $null } | Should -Throw
        }

        It 'Should not accept empty Repository' {
            { Get-UpstreamInfo -Repository '' } | Should -Throw
        }

        It 'Should not accept empty Ref' {
            { Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref '' } | Should -Throw
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

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2`trefs/heads/main"
            }
        }

        It 'Should output verbose messages when -Verbose is used' {
            $verboseOutput = Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'main' -Verbose 4>&1

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

        It 'Should handle repository URL without .git suffix' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2`trefs/heads/main"
            }

            $result = Get-UpstreamInfo -Repository 'https://github.com/owner/repo' -Ref 'main'

            $result | Should -Not -BeNullOrEmpty
            $result.Repository | Should -Be 'https://github.com/owner/repo'
        }

        It 'Should handle refs with special characters in name' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2`trefs/heads/feature/my-feature_v2"
            }

            $result = Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'feature/my-feature_v2'

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
