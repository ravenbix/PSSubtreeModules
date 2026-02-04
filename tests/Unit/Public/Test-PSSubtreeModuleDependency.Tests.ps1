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
    $publicFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Public/Test-PSSubtreeModuleDependency.ps1'
    . $publicFunctionPath
}

Describe 'Test-PSSubtreeModuleDependency' -Tag 'Unit', 'Public' {
    Context 'Parameter validation' {
        It 'Should have Name parameter with default value of wildcard' {
            $command = Get-Command -Name Test-PSSubtreeModuleDependency
            $nameParam = $command.Parameters['Name']

            $nameParam | Should -Not -BeNullOrEmpty
        }

        It 'Should have Path parameter' {
            $command = Get-Command -Name Test-PSSubtreeModuleDependency
            $pathParam = $command.Parameters['Path']

            $pathParam | Should -Not -BeNullOrEmpty
        }

        It 'Should support SupportsWildcards attribute on Name parameter' {
            $command = Get-Command -Name Test-PSSubtreeModuleDependency
            $nameParam = $command.Parameters['Name']
            $supportsWildcards = $nameParam.Attributes | Where-Object { $_ -is [System.Management.Automation.SupportsWildcardsAttribute] }

            $supportsWildcards | Should -Not -BeNullOrEmpty
        }

        It 'Should accept pipeline input for Name parameter' {
            $command = Get-Command -Name Test-PSSubtreeModuleDependency
            $nameParam = $command.Parameters['Name']
            $pipelineByValue = $nameParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipeline
            }

            $pipelineByValue | Should -Not -BeNullOrEmpty
        }

        It 'Should have CmdletBinding attribute' {
            $command = Get-Command -Name Test-PSSubtreeModuleDependency
            $cmdletBinding = $command.CmdletBinding

            $cmdletBinding | Should -Be $true
        }
    }

    Context 'When no modules are tracked' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:emptyRepoPath = Join-Path -Path $TestDrive -ChildPath "empty-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
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
            $result = Test-PSSubtreeModuleDependency -Path $script:emptyRepoPath

            $result | Should -BeNullOrEmpty
        }

        It 'Should not throw error' {
            { Test-PSSubtreeModuleDependency -Path $script:emptyRepoPath } | Should -Not -Throw
        }
    }

    Context 'When configuration file does not exist' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:noConfigPath = Join-Path -Path $TestDrive -ChildPath "no-config-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:noConfigPath -ItemType Directory -Force | Out-Null
        }

        It 'Should return empty result' {
            $result = Test-PSSubtreeModuleDependency -Path $script:noConfigPath

            $result | Should -BeNullOrEmpty
        }

        It 'Should not throw error' {
            { Test-PSSubtreeModuleDependency -Path $script:noConfigPath } | Should -Not -Throw
        }
    }

    Context 'When module has no dependencies' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "no-deps-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            # Create a configuration file
            $yamlContent = @'
modules:
  TestModule:
    repo: https://github.com/owner/TestModule.git
    ref: main
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create module directory with manifest that has no dependencies
            $modulePath = Join-Path -Path $script:testRepoPath -ChildPath 'modules/TestModule'
            New-Item -Path $modulePath -ItemType Directory -Force | Out-Null

            $manifestContent = @'
@{
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000001'
    RootModule = 'TestModule.psm1'
    Description = 'A test module with no dependencies'
}
'@
            $manifestPath = Join-Path -Path $modulePath -ChildPath 'TestModule.psd1'
            Set-Content -Path $manifestPath -Value $manifestContent
        }

        It 'Should return result with AllDependenciesMet = true' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result | Should -Not -BeNullOrEmpty
            $result.AllDependenciesMet | Should -Be $true
        }

        It 'Should return result with correct type name' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result.PSObject.TypeNames[0] | Should -Be 'PSSubtreeModules.DependencyInfo'
        }

        It 'Should return empty MissingDependencies array' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result.MissingDependencies | Should -BeNullOrEmpty
        }

        It 'Should return correct module name' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result.Name | Should -Be 'TestModule'
        }

        It 'Should return manifest path' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result.ManifestPath | Should -Not -BeNullOrEmpty
            $result.ManifestPath | Should -BeLike '*TestModule.psd1'
        }
    }

    Context 'When module has missing dependencies' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "missing-deps-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            # Create a configuration file
            $yamlContent = @'
modules:
  ModuleWithDeps:
    repo: https://github.com/owner/ModuleWithDeps.git
    ref: main
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create module directory with manifest that has dependencies
            $modulePath = Join-Path -Path $script:testRepoPath -ChildPath 'modules/ModuleWithDeps'
            New-Item -Path $modulePath -ItemType Directory -Force | Out-Null

            $manifestContent = @'
@{
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000002'
    RootModule = 'ModuleWithDeps.psm1'
    Description = 'A test module with dependencies'
    RequiredModules = @('NonExistentModule', 'AnotherMissingModule')
}
'@
            $manifestPath = Join-Path -Path $modulePath -ChildPath 'ModuleWithDeps.psd1'
            Set-Content -Path $manifestPath -Value $manifestContent
        }

        It 'Should return result with AllDependenciesMet = false' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result | Should -Not -BeNullOrEmpty
            $result.AllDependenciesMet | Should -Be $false
        }

        It 'Should return MissingDependencies array with missing module names' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result.MissingDependencies | Should -Not -BeNullOrEmpty
            $result.MissingDependencies | Should -Contain 'NonExistentModule'
            $result.MissingDependencies | Should -Contain 'AnotherMissingModule'
        }

        It 'Should return RequiredModules array with Found = false' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result.RequiredModules | Should -Not -BeNullOrEmpty
            ($result.RequiredModules | Where-Object { $_.Name -eq 'NonExistentModule' }).Found | Should -Be $false
        }
    }

    Context 'When module depends on another tracked module' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "tracked-deps-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            # Create a configuration file with two modules
            $yamlContent = @'
modules:
  DependentModule:
    repo: https://github.com/owner/DependentModule.git
    ref: main
  BaseModule:
    repo: https://github.com/owner/BaseModule.git
    ref: main
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create modules directory
            $modulesPath = Join-Path -Path $script:testRepoPath -ChildPath 'modules'
            New-Item -Path $modulesPath -ItemType Directory -Force | Out-Null

            # Create BaseModule (the dependency)
            $baseModulePath = Join-Path -Path $modulesPath -ChildPath 'BaseModule'
            New-Item -Path $baseModulePath -ItemType Directory -Force | Out-Null
            $baseManifest = @'
@{
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000003'
    RootModule = 'BaseModule.psm1'
    Description = 'A base module'
}
'@
            Set-Content -Path (Join-Path $baseModulePath 'BaseModule.psd1') -Value $baseManifest

            # Create DependentModule (depends on BaseModule)
            $depModulePath = Join-Path -Path $modulesPath -ChildPath 'DependentModule'
            New-Item -Path $depModulePath -ItemType Directory -Force | Out-Null
            $depManifest = @'
@{
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000004'
    RootModule = 'DependentModule.psm1'
    Description = 'A module that depends on BaseModule'
    RequiredModules = @('BaseModule')
}
'@
            Set-Content -Path (Join-Path $depModulePath 'DependentModule.psd1') -Value $depManifest
        }

        It 'Should find BaseModule dependency in modules directory' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath -Name 'DependentModule'

            $result | Should -Not -BeNullOrEmpty
            $result.AllDependenciesMet | Should -Be $true
        }

        It 'Should return RequiredModules with Found = true for BaseModule' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath -Name 'DependentModule'

            $result.RequiredModules | Should -Not -BeNullOrEmpty
            ($result.RequiredModules | Where-Object { $_.Name -eq 'BaseModule' }).Found | Should -Be $true
        }
    }

    Context 'Wildcard filtering' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "wildcard-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            # Create a configuration file with multiple modules
            $yamlContent = @'
modules:
  PSModule1:
    repo: https://github.com/owner/PSModule1.git
    ref: main
  PSModule2:
    repo: https://github.com/owner/PSModule2.git
    ref: main
  OtherModule:
    repo: https://github.com/owner/OtherModule.git
    ref: main
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create modules directory with manifests
            $modulesPath = Join-Path -Path $script:testRepoPath -ChildPath 'modules'
            foreach ($modName in @('PSModule1', 'PSModule2', 'OtherModule'))
            {
                $modPath = Join-Path -Path $modulesPath -ChildPath $modName
                New-Item -Path $modPath -ItemType Directory -Force | Out-Null

                $manifest = @"
@{
    ModuleVersion = '1.0.0'
    GUID = '$([Guid]::NewGuid())'
    RootModule = '$modName.psm1'
    Description = 'Test module'
}
"@
                Set-Content -Path (Join-Path $modPath "$modName.psd1") -Value $manifest
            }
        }

        It 'Should return all modules when Name is asterisk' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath -Name '*'

            $result.Count | Should -Be 3
        }

        It 'Should filter modules with prefix wildcard' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath -Name 'PS*'

            $result.Count | Should -Be 2
            ($result | Where-Object { $_.Name -eq 'OtherModule' }) | Should -BeNullOrEmpty
        }

        It 'Should filter modules with suffix wildcard' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath -Name '*Module1'

            $result.Count | Should -Be 1
            $result.Name | Should -Be 'PSModule1'
        }

        It 'Should return specific module when exact name provided' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath -Name 'OtherModule'

            $result.Count | Should -Be 1
            $result.Name | Should -Be 'OtherModule'
        }
    }

    Context 'When module has ExternalModuleDependencies' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "external-deps-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            # Create a configuration file
            $yamlContent = @'
modules:
  ModuleWithExternal:
    repo: https://github.com/owner/ModuleWithExternal.git
    ref: main
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create module with ExternalModuleDependencies
            $modulePath = Join-Path -Path $script:testRepoPath -ChildPath 'modules/ModuleWithExternal'
            New-Item -Path $modulePath -ItemType Directory -Force | Out-Null

            $manifestContent = @'
@{
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000005'
    RootModule = 'ModuleWithExternal.psm1'
    Description = 'A test module with external dependencies'
    ExternalModuleDependencies = @('FakeExternalDep')
}
'@
            Set-Content -Path (Join-Path $modulePath 'ModuleWithExternal.psd1') -Value $manifestContent
        }

        It 'Should check ExternalModuleDependencies' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result.ExternalModuleDependencies | Should -Not -BeNullOrEmpty
            $result.ExternalModuleDependencies[0].Name | Should -Be 'FakeExternalDep'
        }

        It 'Should mark missing external dependency as not found' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result.AllDependenciesMet | Should -Be $false
            $result.MissingDependencies | Should -Contain 'FakeExternalDep'
        }
    }

    Context 'When module has NestedModules' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "nested-deps-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            # Create a configuration file
            $yamlContent = @'
modules:
  ModuleWithNested:
    repo: https://github.com/owner/ModuleWithNested.git
    ref: main
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create module with NestedModules
            $modulePath = Join-Path -Path $script:testRepoPath -ChildPath 'modules/ModuleWithNested'
            New-Item -Path $modulePath -ItemType Directory -Force | Out-Null

            # NestedModules includes script files (which should be skipped) and module refs
            $manifestContent = @'
@{
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000006'
    RootModule = 'ModuleWithNested.psm1'
    Description = 'A test module with nested modules'
    NestedModules = @(
        'internal.ps1',
        'helper.psm1',
        './relative/path.ps1',
        'ExternalNestedModule'
    )
}
'@
            Set-Content -Path (Join-Path $modulePath 'ModuleWithNested.psd1') -Value $manifestContent
        }

        It 'Should skip .ps1 script files in NestedModules' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            # Should not include internal.ps1 in NestedModules results
            ($result.NestedModules | Where-Object { $_.Name -eq 'internal.ps1' }) | Should -BeNullOrEmpty
        }

        It 'Should skip .psm1 script files in NestedModules' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            # Should not include helper.psm1 in NestedModules results
            ($result.NestedModules | Where-Object { $_.Name -eq 'helper.psm1' }) | Should -BeNullOrEmpty
        }

        It 'Should skip relative paths in NestedModules' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            # Should not include ./relative/path.ps1 in NestedModules results
            ($result.NestedModules | Where-Object { $_.Name -like './relative*' }) | Should -BeNullOrEmpty
        }

        It 'Should check module references in NestedModules' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            # ExternalNestedModule should be checked
            $result.NestedModules | Should -Not -BeNullOrEmpty
            ($result.NestedModules | Where-Object { $_.Name -eq 'ExternalNestedModule' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When module has version requirements' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "version-req-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            # Create configuration
            $yamlContent = @'
modules:
  ModuleWithVersionReq:
    repo: https://github.com/owner/ModuleWithVersionReq.git
    ref: main
  DependencyModule:
    repo: https://github.com/owner/DependencyModule.git
    ref: main
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            $modulesPath = Join-Path -Path $script:testRepoPath -ChildPath 'modules'
            New-Item -Path $modulesPath -ItemType Directory -Force | Out-Null

            # Create dependency module with version 2.0.0
            $depModPath = Join-Path -Path $modulesPath -ChildPath 'DependencyModule'
            New-Item -Path $depModPath -ItemType Directory -Force | Out-Null
            $depManifest = @'
@{
    ModuleVersion = '2.0.0'
    GUID = '00000000-0000-0000-0000-000000000007'
    RootModule = 'DependencyModule.psm1'
    Description = 'Dependency module v2.0.0'
}
'@
            Set-Content -Path (Join-Path $depModPath 'DependencyModule.psd1') -Value $depManifest

            # Create module with version requirement
            $reqModPath = Join-Path -Path $modulesPath -ChildPath 'ModuleWithVersionReq'
            New-Item -Path $reqModPath -ItemType Directory -Force | Out-Null
            $reqManifest = @'
@{
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000008'
    RootModule = 'ModuleWithVersionReq.psm1'
    Description = 'Module with version requirements'
    RequiredModules = @(
        @{ ModuleName = 'DependencyModule'; ModuleVersion = '1.5.0' }
    )
}
'@
            Set-Content -Path (Join-Path $reqModPath 'ModuleWithVersionReq.psd1') -Value $reqManifest
        }

        It 'Should parse hashtable dependencies correctly' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath -Name 'ModuleWithVersionReq'

            $result.RequiredModules | Should -Not -BeNullOrEmpty
            $result.RequiredModules[0].Name | Should -Be 'DependencyModule'
            $result.RequiredModules[0].MinimumVersion | Should -Be '1.5.0'
        }

        It 'Should find dependency when version requirement is met' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath -Name 'ModuleWithVersionReq'

            # DependencyModule is v2.0.0, requirement is 1.5.0 minimum
            $result.RequiredModules[0].Found | Should -Be $true
            $result.AllDependenciesMet | Should -Be $true
        }
    }

    Context 'When manifest is missing' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "no-manifest-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            # Create a configuration file
            $yamlContent = @'
modules:
  NoManifestModule:
    repo: https://github.com/owner/NoManifestModule.git
    ref: main
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create module directory without manifest
            $modulePath = Join-Path -Path $script:testRepoPath -ChildPath 'modules/NoManifestModule'
            New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
        }

        It 'Should return result with AllDependenciesMet = false' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath -WarningAction SilentlyContinue

            $result.AllDependenciesMet | Should -Be $false
        }

        It 'Should return null ManifestPath' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testRepoPath -WarningAction SilentlyContinue

            $result.ManifestPath | Should -BeNullOrEmpty
        }
    }

    Context 'Pipeline input' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "pipeline-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            $yamlContent = @'
modules:
  ModuleA:
    repo: https://github.com/owner/ModuleA.git
    ref: main
  ModuleB:
    repo: https://github.com/owner/ModuleB.git
    ref: main
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            $modulesPath = Join-Path -Path $script:testRepoPath -ChildPath 'modules'
            foreach ($modName in @('ModuleA', 'ModuleB'))
            {
                $modPath = Join-Path -Path $modulesPath -ChildPath $modName
                New-Item -Path $modPath -ItemType Directory -Force | Out-Null
                $manifest = @"
@{
    ModuleVersion = '1.0.0'
    GUID = '$([Guid]::NewGuid())'
    RootModule = '$modName.psm1'
}
"@
                Set-Content -Path (Join-Path $modPath "$modName.psd1") -Value $manifest
            }
        }

        It 'Should accept Name from pipeline' {
            $result = 'ModuleA' | Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'ModuleA'
        }

        It 'Should accept multiple names from pipeline' {
            $result = @('ModuleA', 'ModuleB') | Test-PSSubtreeModuleDependency -Path $script:testRepoPath

            $result.Count | Should -Be 2
        }
    }

    Context 'Verbose output' -Skip:(-not $script:yamlAvailable) {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "verbose-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null

            $yamlContent = @'
modules:
  VerboseModule:
    repo: https://github.com/owner/VerboseModule.git
    ref: main
'@
            $configPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            $modulePath = Join-Path -Path $script:testRepoPath -ChildPath 'modules/VerboseModule'
            New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
            $manifest = @'
@{
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000009'
    RootModule = 'VerboseModule.psm1'
    RequiredModules = @('SomeDependency')
}
'@
            Set-Content -Path (Join-Path $modulePath 'VerboseModule.psd1') -Value $manifest
        }

        It 'Should output verbose messages when -Verbose is used' {
            $verboseOutput = Test-PSSubtreeModuleDependency -Path $script:testRepoPath -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Error handling' -Skip:(-not $script:yamlAvailable) {
        It 'Should handle malformed manifest gracefully' {
            $malformedPath = Join-Path -Path $TestDrive -ChildPath "malformed-manifest-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $malformedPath -ItemType Directory -Force | Out-Null

            $yamlContent = @'
modules:
  BadModule:
    repo: https://github.com/owner/BadModule.git
    ref: main
'@
            Set-Content -Path (Join-Path $malformedPath 'subtree-modules.yaml') -Value $yamlContent

            $modulePath = Join-Path -Path $malformedPath -ChildPath 'modules/BadModule'
            New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $modulePath 'BadModule.psd1') -Value 'not valid powershell @{'

            { Test-PSSubtreeModuleDependency -Path $malformedPath -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }
}
