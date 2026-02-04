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

    # Import powershell-yaml module for YAML support
    Import-Module -Name powershell-yaml -ErrorAction Stop

    # Dot source the private function
    $privateFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Save-ModuleConfig.ps1'
    . $privateFunctionPath
}

Describe 'Save-ModuleConfig' -Tag 'Unit', 'Private' {
    Context 'When saving valid configuration' {
        BeforeAll {
            $script:configPath = Join-Path -Path $TestDrive -ChildPath 'subtree-modules.yaml'
        }

        It 'Should write configuration to file' {
            $config = [ordered]@{
                modules = [ordered]@{
                    'TestModule' = [ordered]@{
                        repo = 'https://github.com/owner/repo.git'
                        ref  = 'main'
                    }
                }
            }

            Save-ModuleConfig -Configuration $config -Path $script:configPath

            Test-Path -Path $script:configPath | Should -Be $true
        }

        It 'Should include header comment in output' {
            $config = [ordered]@{
                modules = [ordered]@{
                    'TestModule' = [ordered]@{
                        repo = 'https://github.com/owner/repo.git'
                        ref  = 'main'
                    }
                }
            }

            Save-ModuleConfig -Configuration $config -Path $script:configPath

            $content = Get-Content -Path $script:configPath -Raw
            $content | Should -Match '# PSSubtreeModules configuration'
        }

        It 'Should write valid YAML content' {
            $config = [ordered]@{
                modules = [ordered]@{
                    'TestModule' = [ordered]@{
                        repo = 'https://github.com/owner/repo.git'
                        ref  = 'main'
                    }
                }
            }

            Save-ModuleConfig -Configuration $config -Path $script:configPath

            $content = Get-Content -Path $script:configPath -Raw
            # Remove header comment and parse
            $yamlContent = $content -replace '(?m)^#.*\r?\n', ''

            { $yamlContent | ConvertFrom-Yaml } | Should -Not -Throw
        }

        It 'Should preserve module data correctly' {
            $config = [ordered]@{
                modules = [ordered]@{
                    'TestModule' = [ordered]@{
                        repo = 'https://github.com/owner/repo.git'
                        ref  = 'v1.2.3'
                    }
                }
            }

            Save-ModuleConfig -Configuration $config -Path $script:configPath

            $content = Get-Content -Path $script:configPath -Raw
            $yamlContent = $content -replace '(?m)^#.*\r?\n', ''
            $parsed = $yamlContent | ConvertFrom-Yaml -Ordered

            $parsed.modules['TestModule'].repo | Should -Be 'https://github.com/owner/repo.git'
            $parsed.modules['TestModule'].ref | Should -Be 'v1.2.3'
        }

        It 'Should handle multiple modules' {
            $config = [ordered]@{
                modules = [ordered]@{
                    'Module1' = [ordered]@{
                        repo = 'https://github.com/owner/module1.git'
                        ref  = 'main'
                    }
                    'Module2' = [ordered]@{
                        repo = 'https://github.com/owner/module2.git'
                        ref  = 'v2.0.0'
                    }
                    'Module3' = [ordered]@{
                        repo = 'https://github.com/owner/module3.git'
                        ref  = 'develop'
                    }
                }
            }

            Save-ModuleConfig -Configuration $config -Path $script:configPath

            $content = Get-Content -Path $script:configPath -Raw
            $yamlContent = $content -replace '(?m)^#.*\r?\n', ''
            $parsed = $yamlContent | ConvertFrom-Yaml -Ordered

            $parsed.modules.Keys.Count | Should -Be 3
            $parsed.modules['Module1'].ref | Should -Be 'main'
            $parsed.modules['Module2'].ref | Should -Be 'v2.0.0'
            $parsed.modules['Module3'].ref | Should -Be 'develop'
        }

        It 'Should use UTF8 encoding' {
            $config = [ordered]@{
                modules = [ordered]@{
                    'TestModule' = [ordered]@{
                        repo = 'https://github.com/owner/repo.git'
                        ref  = 'main'
                    }
                }
            }

            Save-ModuleConfig -Configuration $config -Path $script:configPath

            # Read content and check it can be parsed
            $content = Get-Content -Path $script:configPath -Raw -Encoding UTF8
            $content | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When saving to nested directory' {
        It 'Should create parent directory if it does not exist' {
            $nestedPath = Join-Path -Path $TestDrive -ChildPath 'nested/path/subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{}
            }

            Save-ModuleConfig -Configuration $config -Path $nestedPath

            Test-Path -Path $nestedPath | Should -Be $true
            $parentDir = Split-Path -Path $nestedPath -Parent
            Test-Path -Path $parentDir -PathType Container | Should -Be $true
        }
    }

    Context 'When configuration has missing modules key' {
        It 'Should add empty modules collection' {
            $configPath = Join-Path -Path $TestDrive -ChildPath 'nomodules.yaml'
            $config = [ordered]@{
                otherkey = 'value'
            }

            Save-ModuleConfig -Configuration $config -Path $configPath

            $content = Get-Content -Path $configPath -Raw
            $content | Should -Match 'modules:'
        }
    }

    Context 'When saving empty modules collection' {
        It 'Should handle empty modules collection gracefully' {
            $configPath = Join-Path -Path $TestDrive -ChildPath 'empty-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{}
            }

            Save-ModuleConfig -Configuration $config -Path $configPath

            Test-Path -Path $configPath | Should -Be $true
            $content = Get-Content -Path $configPath -Raw
            $content | Should -Match 'modules:'
        }
    }

    Context 'Parameter validation' {
        It 'Should require Configuration parameter' {
            { Save-ModuleConfig -Configuration $null } | Should -Throw
        }

        It 'Should reject non-OrderedDictionary configuration' {
            $configPath = Join-Path -Path $TestDrive -ChildPath 'invalid.yaml'
            $config = @{
                modules = @{}
            }

            { Save-ModuleConfig -Configuration $config -Path $configPath } | Should -Throw
        }
    }

    Context 'Error handling' {
        It 'Should throw error when write fails' {
            # Create a read-only directory scenario by mocking Set-Content
            Mock -CommandName Set-Content -MockWith {
                throw 'Access denied'
            }

            $configPath = Join-Path -Path $TestDrive -ChildPath 'readonly.yaml'
            $config = [ordered]@{
                modules = [ordered]@{}
            }

            { Save-ModuleConfig -Configuration $config -Path $configPath } | Should -Throw
        }
    }

    Context 'Default path behavior' {
        BeforeAll {
            # Save the original location
            $script:originalLocation = Get-Location
        }

        AfterAll {
            # Restore the original location
            Set-Location -Path $script:originalLocation
        }

        It 'Should use current directory when Path not specified' {
            Set-Location -Path $TestDrive

            $config = [ordered]@{
                modules = [ordered]@{
                    'DefaultModule' = [ordered]@{
                        repo = 'https://github.com/owner/repo.git'
                        ref  = 'main'
                    }
                }
            }

            Save-ModuleConfig -Configuration $config

            $expectedPath = Join-Path -Path $TestDrive -ChildPath 'subtree-modules.yaml'
            Test-Path -Path $expectedPath | Should -Be $true
        }
    }

    Context 'Verbose output' {
        It 'Should output verbose messages when -Verbose is used' {
            $configPath = Join-Path -Path $TestDrive -ChildPath 'verbose-test.yaml'
            $config = [ordered]@{
                modules = [ordered]@{}
            }

            $verboseOutput = Save-ModuleConfig -Configuration $config -Path $configPath -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Round-trip testing' {
        BeforeAll {
            # Dot source Get-ModuleConfig for round-trip testing
            $getConfigPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Get-ModuleConfig.ps1'
            . $getConfigPath
        }

        It 'Should preserve data through save/load cycle' {
            $configPath = Join-Path -Path $TestDrive -ChildPath 'roundtrip.yaml'
            $originalConfig = [ordered]@{
                modules = [ordered]@{
                    'Module1' = [ordered]@{
                        repo = 'https://github.com/owner/module1.git'
                        ref  = 'main'
                    }
                    'Module2' = [ordered]@{
                        repo = 'https://github.com/owner/module2.git'
                        ref  = 'v1.0.0'
                    }
                }
            }

            Save-ModuleConfig -Configuration $originalConfig -Path $configPath
            $loadedConfig = Get-ModuleConfig -Path $configPath

            $loadedConfig.modules.Keys.Count | Should -Be 2
            $loadedConfig.modules['Module1'].repo | Should -Be $originalConfig.modules['Module1'].repo
            $loadedConfig.modules['Module1'].ref | Should -Be $originalConfig.modules['Module1'].ref
            $loadedConfig.modules['Module2'].repo | Should -Be $originalConfig.modules['Module2'].repo
            $loadedConfig.modules['Module2'].ref | Should -Be $originalConfig.modules['Module2'].ref
        }
    }
}
