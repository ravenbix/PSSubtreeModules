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

    # Try to import powershell-yaml module
    $script:yamlAvailable = $false
    try
    {
        Import-Module -Name powershell-yaml -ErrorAction Stop
        $script:yamlAvailable = $true
    }
    catch
    {
        # YAML module not available, tests that require it will be skipped
    }

    # Dot source the private helper functions first
    $getModuleConfigPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Get-ModuleConfig.ps1'
    . $getModuleConfigPath

    # Dot source the public function
    $publicFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Public/Get-PSSubtreeModule.ps1'
    . $publicFunctionPath
}

Describe 'Get-PSSubtreeModule' -Tag 'Unit', 'Public' {
    Context 'When modules are configured' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath 'test-repo'
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            # Create a valid configuration file
            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  Pester:
    repo: https://github.com/pester/Pester.git
    ref: main
  PSScriptAnalyzer:
    repo: https://github.com/PowerShell/PSScriptAnalyzer.git
    ref: v1.21.0
  MyModule:
    repo: https://github.com/owner/mymodule.git
    ref: develop
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent
        }

        It 'Should return all modules when Name is not specified' {
            $result = Get-PSSubtreeModule -Path $script:testRepoPath

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 3
        }

        It 'Should return PSCustomObject with correct type name' {
            $result = Get-PSSubtreeModule -Path $script:testRepoPath

            $result[0].PSObject.TypeNames[0] | Should -Be 'PSSubtreeModules.ModuleInfo'
        }

        It 'Should return objects with Name, Repository, and Ref properties' {
            $result = Get-PSSubtreeModule -Path $script:testRepoPath -Name 'Pester'

            $result.Name | Should -Be 'Pester'
            $result.Repository | Should -Be 'https://github.com/pester/Pester.git'
            $result.Ref | Should -Be 'main'
        }

        It 'Should return specific module when Name is specified' {
            $result = Get-PSSubtreeModule -Path $script:testRepoPath -Name 'PSScriptAnalyzer'

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'PSScriptAnalyzer'
            $result.Ref | Should -Be 'v1.21.0'
        }

        It 'Should support wildcard patterns with asterisk at start' {
            $result = Get-PSSubtreeModule -Path $script:testRepoPath -Name '*Analyzer'

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'PSScriptAnalyzer'
        }

        It 'Should support wildcard patterns with asterisk at end' {
            $result = Get-PSSubtreeModule -Path $script:testRepoPath -Name 'PS*'

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            $result.Name | Should -Be 'PSScriptAnalyzer'
        }

        It 'Should support wildcard patterns with asterisk in middle' {
            $result = Get-PSSubtreeModule -Path $script:testRepoPath -Name '*Script*'

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'PSScriptAnalyzer'
        }

        It 'Should return empty when wildcard matches nothing' {
            $result = Get-PSSubtreeModule -Path $script:testRepoPath -Name 'NonExistent*'

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When no modules are configured' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:emptyRepoPath = Join-Path -Path $TestDrive -ChildPath 'empty-repo'
            New-Item -Path $script:emptyRepoPath -ItemType Directory -Force | Out-Null

            # Create a configuration file with no modules
            $yamlContent = @'
# PSSubtreeModules configuration
modules: {}
'@
            $configPath = Join-Path -Path $script:emptyRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent
        }

        It 'Should return empty result' {
            $result = Get-PSSubtreeModule -Path $script:emptyRepoPath

            $result | Should -BeNullOrEmpty
        }

        It 'Should not throw error' {
            { Get-PSSubtreeModule -Path $script:emptyRepoPath } | Should -Not -Throw
        }
    }

    Context 'When configuration file does not exist' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:noConfigPath = Join-Path -Path $TestDrive -ChildPath 'no-config-repo'
            New-Item -Path $script:noConfigPath -ItemType Directory -Force | Out-Null
        }

        It 'Should return empty result' {
            $result = Get-PSSubtreeModule -Path $script:noConfigPath

            $result | Should -BeNullOrEmpty
        }

        It 'Should not throw error' {
            { Get-PSSubtreeModule -Path $script:noConfigPath } | Should -Not -Throw
        }
    }

    Context 'Pipeline input' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath 'pipeline-repo'
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            $yamlContent = @'
modules:
  ModuleA:
    repo: https://github.com/owner/moduleA.git
    ref: main
  ModuleB:
    repo: https://github.com/owner/moduleB.git
    ref: v1.0.0
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent
        }

        It 'Should accept Name from pipeline' {
            $result = 'ModuleA' | Get-PSSubtreeModule -Path $script:testRepoPath

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'ModuleA'
        }

        It 'Should accept multiple names from pipeline' {
            $result = @('ModuleA', 'ModuleB') | Get-PSSubtreeModule -Path $script:testRepoPath

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }
    }

    Context 'Parameter validation' {
        It 'Should have Name parameter with default value of wildcard' {
            $command = Get-Command -Name Get-PSSubtreeModule
            $nameParam = $command.Parameters['Name']

            $nameParam | Should -Not -BeNullOrEmpty
        }

        It 'Should have Path parameter' {
            $command = Get-Command -Name Get-PSSubtreeModule
            $pathParam = $command.Parameters['Path']

            $pathParam | Should -Not -BeNullOrEmpty
        }

        It 'Should support SupportsWildcards attribute on Name parameter' {
            $command = Get-Command -Name Get-PSSubtreeModule
            $nameParam = $command.Parameters['Name']
            $supportsWildcards = $nameParam.Attributes | Where-Object { $_ -is [System.Management.Automation.SupportsWildcardsAttribute] }

            $supportsWildcards | Should -Not -BeNullOrEmpty
        }

        It 'Should accept pipeline input by property name for Name parameter' {
            $command = Get-Command -Name Get-PSSubtreeModule
            $nameParam = $command.Parameters['Name']
            $pipelineByPropertyName = $nameParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipelineByPropertyName
            }

            $pipelineByPropertyName | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Default path behavior' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            # Save the original location
            $script:originalLocation = Get-Location
        }

        AfterAll {
            # Restore the original location
            Set-Location -Path $script:originalLocation
        }

        It 'Should use current directory when Path not specified' {
            $testPath = Join-Path -Path $TestDrive -ChildPath 'default-path-repo'
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null

            $yamlContent = @'
modules:
  DefaultModule:
    repo: https://github.com/owner/repo.git
    ref: main
'@
            $configPath = Join-Path -Path $testPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            Set-Location -Path $testPath

            $result = Get-PSSubtreeModule

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'DefaultModule'
        }
    }

    Context 'Verbose output' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath 'verbose-repo'
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            $yamlContent = @'
modules:
  TestModule:
    repo: https://github.com/owner/repo.git
    ref: main
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent
        }

        It 'Should output verbose messages when -Verbose is used' {
            $verboseOutput = Get-PSSubtreeModule -Path $script:testRepoPath -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Error handling' -Skip:(-not $script:yamlAvailable) {
        It 'Should handle malformed YAML gracefully' {
            $malformedPath = Join-Path -Path $TestDrive -ChildPath 'malformed-repo'
            New-Item -Path $malformedPath -ItemType Directory -Force | Out-Null

            $malformedYaml = 'invalid: yaml: content: [unclosed'
            $configPath = Join-Path -Path $malformedPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $malformedYaml

            { Get-PSSubtreeModule -Path $malformedPath -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }
}
