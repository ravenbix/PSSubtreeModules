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
    $privateFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Get-ModuleConfig.ps1'
    . $privateFunctionPath
}

Describe 'Get-ModuleConfig' -Tag 'Unit', 'Private' {
    Context 'When configuration file exists' {
        BeforeAll {
            $script:configPath = Join-Path -Path $TestDrive -ChildPath 'subtree-modules.yaml'
        }

        It 'Should read valid YAML configuration' {
            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  TestModule:
    repo: https://github.com/owner/repo.git
    ref: main
'@
            Set-Content -Path $script:configPath -Value $yamlContent

            $result = Get-ModuleConfig -Path $script:configPath

            $result | Should -Not -BeNullOrEmpty
            $result.modules | Should -Not -BeNullOrEmpty
            $result.modules['TestModule'] | Should -Not -BeNullOrEmpty
            $result.modules['TestModule'].repo | Should -Be 'https://github.com/owner/repo.git'
            $result.modules['TestModule'].ref | Should -Be 'main'
        }

        It 'Should return ordered dictionary' {
            $yamlContent = @'
modules:
  ModuleA:
    repo: https://github.com/owner/moduleA.git
    ref: main
  ModuleB:
    repo: https://github.com/owner/moduleB.git
    ref: v1.0.0
  ModuleC:
    repo: https://github.com/owner/moduleC.git
    ref: develop
'@
            Set-Content -Path $script:configPath -Value $yamlContent

            $result = Get-ModuleConfig -Path $script:configPath

            $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        }

        It 'Should handle configuration with multiple modules' {
            $yamlContent = @'
modules:
  Module1:
    repo: https://github.com/owner/module1.git
    ref: main
  Module2:
    repo: https://github.com/owner/module2.git
    ref: v2.0.0
'@
            Set-Content -Path $script:configPath -Value $yamlContent

            $result = Get-ModuleConfig -Path $script:configPath

            $result.modules.Keys.Count | Should -Be 2
            $result.modules['Module1'].ref | Should -Be 'main'
            $result.modules['Module2'].ref | Should -Be 'v2.0.0'
        }

        It 'Should handle YAML with comments' {
            $yamlContent = @'
# PSSubtreeModules configuration
# This file tracks module dependencies
modules:
  TestModule:
    repo: https://github.com/owner/repo.git
    ref: main
    # Pinned to main branch
'@
            Set-Content -Path $script:configPath -Value $yamlContent

            $result = Get-ModuleConfig -Path $script:configPath

            $result.modules['TestModule'].repo | Should -Be 'https://github.com/owner/repo.git'
        }
    }

    Context 'When configuration file does not exist' {
        It 'Should return default structure with empty modules' {
            $nonExistentPath = Join-Path -Path $TestDrive -ChildPath 'nonexistent.yaml'

            $result = Get-ModuleConfig -Path $nonExistentPath

            $result | Should -Not -BeNullOrEmpty
            $result.modules | Should -Not -BeNull
            $result.modules.Keys.Count | Should -Be 0
        }

        It 'Should return ordered dictionary for default structure' {
            $nonExistentPath = Join-Path -Path $TestDrive -ChildPath 'nonexistent2.yaml'

            $result = Get-ModuleConfig -Path $nonExistentPath

            $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $result.modules | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        }
    }

    Context 'When configuration file is empty' {
        It 'Should return default structure for empty file' {
            $emptyPath = Join-Path -Path $TestDrive -ChildPath 'empty.yaml'
            Set-Content -Path $emptyPath -Value ''

            $result = Get-ModuleConfig -Path $emptyPath

            $result | Should -Not -BeNullOrEmpty
            $result.modules | Should -Not -BeNull
            $result.modules.Keys.Count | Should -Be 0
        }

        It 'Should return default structure for whitespace-only file' {
            $whitespacePath = Join-Path -Path $TestDrive -ChildPath 'whitespace.yaml'
            Set-Content -Path $whitespacePath -Value '   '

            $result = Get-ModuleConfig -Path $whitespacePath

            $result | Should -Not -BeNullOrEmpty
            $result.modules | Should -Not -BeNull
        }
    }

    Context 'When configuration file is malformed' {
        It 'Should throw error for invalid YAML' {
            $invalidPath = Join-Path -Path $TestDrive -ChildPath 'invalid.yaml'
            Set-Content -Path $invalidPath -Value 'invalid: yaml: content: [unclosed'

            { Get-ModuleConfig -Path $invalidPath } | Should -Throw
        }
    }

    Context 'When modules key is missing' {
        It 'Should add empty modules collection' {
            $noModulesPath = Join-Path -Path $TestDrive -ChildPath 'nomodules.yaml'
            Set-Content -Path $noModulesPath -Value 'otherkey: value'

            $result = Get-ModuleConfig -Path $noModulesPath

            $result.modules | Should -Not -BeNull
            $result.modules.Keys.Count | Should -Be 0
        }
    }

    Context 'When modules key is null' {
        It 'Should replace null modules with empty collection' {
            $nullModulesPath = Join-Path -Path $TestDrive -ChildPath 'nullmodules.yaml'
            Set-Content -Path $nullModulesPath -Value 'modules:'

            $result = Get-ModuleConfig -Path $nullModulesPath

            $result.modules | Should -Not -BeNull
            $result.modules.Keys.Count | Should -Be 0
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
            # Create a config in the test drive
            $configPath = Join-Path -Path $TestDrive -ChildPath 'subtree-modules.yaml'
            $yamlContent = @'
modules:
  DefaultPathModule:
    repo: https://github.com/owner/repo.git
    ref: main
'@
            Set-Content -Path $configPath -Value $yamlContent

            # Change to the test drive directory
            Set-Location -Path $TestDrive

            $result = Get-ModuleConfig

            $result.modules['DefaultPathModule'] | Should -Not -BeNullOrEmpty
            $result.modules['DefaultPathModule'].ref | Should -Be 'main'
        }
    }

    Context 'Verbose output' {
        It 'Should output verbose messages when -Verbose is used' {
            $configPath = Join-Path -Path $TestDrive -ChildPath 'verbose-test.yaml'
            Set-Content -Path $configPath -Value 'modules:'

            $verboseOutput = Get-ModuleConfig -Path $configPath -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }
}
