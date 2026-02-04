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
    $privateFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Invoke-GitCommand.ps1'
    . $privateFunctionPath
}

Describe 'Invoke-GitCommand' -Tag 'Unit', 'Private' {
    Context 'When git is available' {
        BeforeAll {
            # Mock Get-Command to return a valid git path
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should execute git status successfully' {
            # Mock the git command execution
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return 'On branch main', 'nothing to commit, working tree clean'
            }

            $result = Invoke-GitCommand -Arguments 'status'

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName git -Times 1 -Exactly
        }

        It 'Should execute git command with multiple arguments' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return 'a1b2c3d4 First commit', 'e5f6g7h8 Second commit'
            }

            $result = Invoke-GitCommand -Arguments 'log', '--oneline', '-2'

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName git -Times 1 -Exactly
        }

        It 'Should throw error when git command fails' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 128
                return 'fatal: not a git repository'
            }

            { Invoke-GitCommand -Arguments 'status' } | Should -Throw '*Git command failed with exit code 128*'
        }

        It 'Should return string array output' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return @('line1', 'line2', 'line3')
            }

            $result = Invoke-GitCommand -Arguments 'log'

            $result | Should -BeOfType [System.Object]
            $result.Count | Should -BeGreaterOrEqual 1
        }

        It 'Should include error output in exception message' {
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 1
                return 'error: pathspec ''invalid'' did not match any file(s) known to git'
            }

            { Invoke-GitCommand -Arguments 'checkout', 'invalid' } | Should -Throw '*error: pathspec*'
        }
    }

    Context 'When git is not available' {
        BeforeAll {
            # Mock Get-Command to return nothing (git not found)
            Mock -CommandName Get-Command -MockWith {
                return $null
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should throw error when git is not installed' {
            { Invoke-GitCommand -Arguments 'status' } | Should -Throw '*Git is not installed*'
        }
    }

    Context 'When using WorkingDirectory parameter' {
        BeforeAll {
            # Mock Get-Command to return a valid git path
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }

            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                return 'On branch main'
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

            $result = Invoke-GitCommand -Arguments 'status' -WorkingDirectory $tempDir

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName Set-Location -Times 2 -Exactly
        }

        It 'Should fail when working directory does not exist' {
            $invalidDir = Join-Path -Path $TestDrive -ChildPath 'nonexistent'

            { Invoke-GitCommand -Arguments 'status' -WorkingDirectory $invalidDir } | Should -Throw
        }
    }

    Context 'Parameter validation' {
        BeforeAll {
            # Mock Get-Command to return a valid git path
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{
                    Name   = 'git'
                    Source = '/usr/bin/git'
                }
            } -ParameterFilter { $Name -eq 'git' }
        }

        It 'Should require Arguments parameter' {
            { Invoke-GitCommand -Arguments $null } | Should -Throw
        }

        It 'Should not accept empty string array' {
            { Invoke-GitCommand -Arguments @() } | Should -Throw
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
                return 'output'
            }
        }

        It 'Should output verbose messages when -Verbose is used' {
            $verboseOutput = Invoke-GitCommand -Arguments 'status' -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }
}
