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

    # Dot source all private helper functions
    $privateFunctions = @(
        'Invoke-GitCommand.ps1'
        'Get-ModuleConfig.ps1'
        'Save-ModuleConfig.ps1'
        'Get-UpstreamInfo.ps1'
        'Get-SubtreeInfo.ps1'
    )

    foreach ($func in $privateFunctions)
    {
        $funcPath = Join-Path -Path $projectPath -ChildPath "source/Private/$func"
        if (Test-Path -Path $funcPath)
        {
            . $funcPath
        }
    }

    # Dot source all public functions
    $publicFunctions = Get-ChildItem -Path (Join-Path -Path $projectPath -ChildPath 'source/Public') -Filter '*.ps1' -ErrorAction SilentlyContinue
    foreach ($func in $publicFunctions)
    {
        . $func.FullName
    }

    # Helper function to create a test Git repository
    function New-TestGitRepository
    {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        # Create directory
        New-Item -Path $Path -ItemType Directory -Force | Out-Null

        # Save current location
        $originalLocation = Get-Location
        Set-Location -Path $Path

        try
        {
            # Initialize git repository
            git init --initial-branch=main 2>&1 | Out-Null
            git config user.email "test@test.com" 2>&1 | Out-Null
            git config user.name "Test User" 2>&1 | Out-Null

            # Create an initial commit
            $readmeFile = Join-Path -Path $Path -ChildPath 'README.md'
            Set-Content -Path $readmeFile -Value '# Test Repository'
            git add README.md 2>&1 | Out-Null
            git commit -m "Initial commit" 2>&1 | Out-Null
        }
        finally
        {
            Set-Location -Path $originalLocation
        }
    }

    # Helper function to create a module with manifest
    function New-TestModule
    {
        param (
            [Parameter(Mandatory = $true)]
            [string]$BasePath,

            [Parameter(Mandatory = $true)]
            [string]$ModuleName,

            [Parameter()]
            [string]$Version = '1.0.0',

            [Parameter()]
            [string[]]$RequiredModules = @(),

            [Parameter()]
            [hashtable[]]$RequiredModulesWithVersion = @(),

            [Parameter()]
            [string[]]$ExternalModuleDependencies = @(),

            [Parameter()]
            [string[]]$NestedModules = @()
        )

        $modulePath = Join-Path -Path $BasePath -ChildPath "modules/$ModuleName"
        New-Item -Path $modulePath -ItemType Directory -Force | Out-Null

        # Build RequiredModules array for manifest
        $reqModulesArray = @()
        foreach ($mod in $RequiredModules)
        {
            $reqModulesArray += "'$mod'"
        }
        foreach ($mod in $RequiredModulesWithVersion)
        {
            $entry = "@{ ModuleName = '$($mod.ModuleName)'"
            if ($mod.ModuleVersion)
            {
                $entry += "; ModuleVersion = '$($mod.ModuleVersion)'"
            }
            if ($mod.RequiredVersion)
            {
                $entry += "; RequiredVersion = '$($mod.RequiredVersion)'"
            }
            if ($mod.MaximumVersion)
            {
                $entry += "; MaximumVersion = '$($mod.MaximumVersion)'"
            }
            $entry += ' }'
            $reqModulesArray += $entry
        }

        # Build manifest content
        $manifestContent = @"
@{
    ModuleVersion = '$Version'
    GUID = '$([Guid]::NewGuid())'
    RootModule = '$ModuleName.psm1'
    Description = 'Test module: $ModuleName'
"@

        if ($reqModulesArray.Count -gt 0)
        {
            $manifestContent += "`n    RequiredModules = @(`n        $($reqModulesArray -join ",`n        ")`n    )"
        }

        if ($ExternalModuleDependencies.Count -gt 0)
        {
            $extDepsStr = ($ExternalModuleDependencies | ForEach-Object { "'$_'" }) -join ', '
            $manifestContent += "`n    ExternalModuleDependencies = @($extDepsStr)"
        }

        if ($NestedModules.Count -gt 0)
        {
            $nestedStr = ($NestedModules | ForEach-Object { "'$_'" }) -join ', '
            $manifestContent += "`n    NestedModules = @($nestedStr)"
        }

        $manifestContent += "`n}"

        $manifestPath = Join-Path -Path $modulePath -ChildPath "$ModuleName.psd1"
        Set-Content -Path $manifestPath -Value $manifestContent

        # Create empty psm1 file
        $psmPath = Join-Path -Path $modulePath -ChildPath "$ModuleName.psm1"
        Set-Content -Path $psmPath -Value "# $ModuleName module"
    }
}

Describe 'Dependency Validation Integration Tests' -Tag 'Integration' {
    BeforeEach {
        # Create a unique test directory for each test
        $script:testDir = Join-Path -Path $TestDrive -ChildPath "dep-validation-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
        New-TestGitRepository -Path $script:testDir
    }

    AfterEach {
        # Cleanup is handled by Pester's TestDrive
    }

    Context 'Dependency validation after Initialize and manual module setup' -Skip:(-not $script:yamlAvailable) {
        It 'Should validate dependencies for modules with no dependencies' {
            # Initialize repository
            Initialize-PSSubtreeModule -Path $script:testDir

            # Create a module with no dependencies
            New-TestModule -BasePath $script:testDir -ModuleName 'SimpleModule'

            # Update config to include the module
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'SimpleModule' = [ordered]@{
                        repo = 'https://github.com/test/SimpleModule.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            # Validate dependencies
            $result = Test-PSSubtreeModuleDependency -Path $script:testDir

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'SimpleModule'
            $result.AllDependenciesMet | Should -Be $true
            $result.MissingDependencies | Should -BeNullOrEmpty
        }

        It 'Should detect missing dependencies' {
            # Initialize repository
            Initialize-PSSubtreeModule -Path $script:testDir

            # Create a module with dependencies that don't exist
            New-TestModule -BasePath $script:testDir -ModuleName 'ModuleWithMissing' -RequiredModules @('NonExistentDep1', 'NonExistentDep2')

            # Update config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'ModuleWithMissing' = [ordered]@{
                        repo = 'https://github.com/test/ModuleWithMissing.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            # Validate dependencies
            $result = Test-PSSubtreeModuleDependency -Path $script:testDir

            $result.AllDependenciesMet | Should -Be $false
            $result.MissingDependencies | Should -Contain 'NonExistentDep1'
            $result.MissingDependencies | Should -Contain 'NonExistentDep2'
        }
    }

    Context 'Inter-module dependency validation' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            # Initialize repository
            Initialize-PSSubtreeModule -Path $script:testDir

            # Create a dependency chain: ModuleC -> ModuleB -> ModuleA
            New-TestModule -BasePath $script:testDir -ModuleName 'ModuleA' -Version '2.0.0'
            New-TestModule -BasePath $script:testDir -ModuleName 'ModuleB' -Version '1.5.0' -RequiredModules @('ModuleA')
            New-TestModule -BasePath $script:testDir -ModuleName 'ModuleC' -Version '1.0.0' -RequiredModules @('ModuleB')

            # Update config with all modules
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'ModuleA' = [ordered]@{
                        repo = 'https://github.com/test/ModuleA.git'
                        ref  = 'v2.0.0'
                    }
                    'ModuleB' = [ordered]@{
                        repo = 'https://github.com/test/ModuleB.git'
                        ref  = 'v1.5.0'
                    }
                    'ModuleC' = [ordered]@{
                        repo = 'https://github.com/test/ModuleC.git'
                        ref  = 'v1.0.0'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath
        }

        It 'Should validate all modules in dependency chain have dependencies met' {
            $results = Test-PSSubtreeModuleDependency -Path $script:testDir

            $results | Should -HaveCount 3

            # All modules should have their dependencies met
            foreach ($result in $results)
            {
                $result.AllDependenciesMet | Should -Be $true -Because "$($result.Name) should have all dependencies met"
            }
        }

        It 'Should correctly identify ModuleB depends on ModuleA' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testDir -Name 'ModuleB'

            $result.RequiredModules | Should -Not -BeNullOrEmpty
            $result.RequiredModules[0].Name | Should -Be 'ModuleA'
            $result.RequiredModules[0].Found | Should -Be $true
        }

        It 'Should correctly identify ModuleC depends on ModuleB' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testDir -Name 'ModuleC'

            $result.RequiredModules | Should -Not -BeNullOrEmpty
            $result.RequiredModules[0].Name | Should -Be 'ModuleB'
            $result.RequiredModules[0].Found | Should -Be $true
        }

        It 'Should handle filtering with wildcards' {
            $results = Test-PSSubtreeModuleDependency -Path $script:testDir -Name 'Module*'

            $results | Should -HaveCount 3
            $results.Name | Should -Contain 'ModuleA'
            $results.Name | Should -Contain 'ModuleB'
            $results.Name | Should -Contain 'ModuleC'
        }

        It 'Should handle specific module name filter' {
            $result = Test-PSSubtreeModuleDependency -Path $script:testDir -Name 'ModuleA'

            $result | Should -HaveCount 1
            $result.Name | Should -Be 'ModuleA'
        }
    }

    Context 'Version requirement validation' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            # Initialize repository
            Initialize-PSSubtreeModule -Path $script:testDir

            # Create base module with specific version
            New-TestModule -BasePath $script:testDir -ModuleName 'BaseModule' -Version '2.5.0'
        }

        It 'Should satisfy minimum version requirement when available version is higher' {
            # Create dependent module requiring minimum version 2.0.0
            New-TestModule -BasePath $script:testDir -ModuleName 'DependentModule' -RequiredModulesWithVersion @(
                @{ ModuleName = 'BaseModule'; ModuleVersion = '2.0.0' }
            )

            # Update config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'BaseModule'      = [ordered]@{
                        repo = 'https://github.com/test/BaseModule.git'
                        ref  = 'main'
                    }
                    'DependentModule' = [ordered]@{
                        repo = 'https://github.com/test/DependentModule.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            $result = Test-PSSubtreeModuleDependency -Path $script:testDir -Name 'DependentModule'

            $result.AllDependenciesMet | Should -Be $true
            $result.RequiredModules[0].MinimumVersion | Should -Be '2.0.0'
            $result.RequiredModules[0].Found | Should -Be $true
        }

        It 'Should fail minimum version requirement when available version is lower' {
            # Create dependent module requiring minimum version 3.0.0 (BaseModule is 2.5.0)
            New-TestModule -BasePath $script:testDir -ModuleName 'NeedsNewer' -RequiredModulesWithVersion @(
                @{ ModuleName = 'BaseModule'; ModuleVersion = '3.0.0' }
            )

            # Update config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'BaseModule'  = [ordered]@{
                        repo = 'https://github.com/test/BaseModule.git'
                        ref  = 'main'
                    }
                    'NeedsNewer'  = [ordered]@{
                        repo = 'https://github.com/test/NeedsNewer.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            $result = Test-PSSubtreeModuleDependency -Path $script:testDir -Name 'NeedsNewer'

            $result.AllDependenciesMet | Should -Be $false
            $result.MissingDependencies | Should -Contain 'BaseModule'
        }

        It 'Should satisfy exact version requirement when version matches' {
            # Create dependent module requiring exact version 2.5.0
            New-TestModule -BasePath $script:testDir -ModuleName 'NeedsExact' -RequiredModulesWithVersion @(
                @{ ModuleName = 'BaseModule'; RequiredVersion = '2.5.0' }
            )

            # Update config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'BaseModule'  = [ordered]@{
                        repo = 'https://github.com/test/BaseModule.git'
                        ref  = 'main'
                    }
                    'NeedsExact'  = [ordered]@{
                        repo = 'https://github.com/test/NeedsExact.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            $result = Test-PSSubtreeModuleDependency -Path $script:testDir -Name 'NeedsExact'

            $result.AllDependenciesMet | Should -Be $true
            $result.RequiredModules[0].RequiredVersion | Should -Be '2.5.0'
        }

        It 'Should fail exact version requirement when version differs' {
            # Create dependent module requiring exact version 2.0.0 (BaseModule is 2.5.0)
            New-TestModule -BasePath $script:testDir -ModuleName 'NeedsDifferent' -RequiredModulesWithVersion @(
                @{ ModuleName = 'BaseModule'; RequiredVersion = '2.0.0' }
            )

            # Update config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'BaseModule'     = [ordered]@{
                        repo = 'https://github.com/test/BaseModule.git'
                        ref  = 'main'
                    }
                    'NeedsDifferent' = [ordered]@{
                        repo = 'https://github.com/test/NeedsDifferent.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            $result = Test-PSSubtreeModuleDependency -Path $script:testDir -Name 'NeedsDifferent'

            $result.AllDependenciesMet | Should -Be $false
            $result.MissingDependencies | Should -Contain 'BaseModule'
        }
    }

    Context 'External and nested dependency validation' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            # Initialize repository
            Initialize-PSSubtreeModule -Path $script:testDir
        }

        It 'Should report missing external dependencies' {
            # Create module with external dependencies
            New-TestModule -BasePath $script:testDir -ModuleName 'ModuleWithExternal' -ExternalModuleDependencies @('FakeExternalModule')

            # Update config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'ModuleWithExternal' = [ordered]@{
                        repo = 'https://github.com/test/ModuleWithExternal.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            $result = Test-PSSubtreeModuleDependency -Path $script:testDir

            $result.AllDependenciesMet | Should -Be $false
            $result.ExternalModuleDependencies | Should -Not -BeNullOrEmpty
            $result.ExternalModuleDependencies[0].Name | Should -Be 'FakeExternalModule'
            $result.ExternalModuleDependencies[0].Found | Should -Be $false
        }

        It 'Should skip script files in nested modules' {
            # Create module with nested modules including script files
            New-TestModule -BasePath $script:testDir -ModuleName 'ModuleWithNested' -NestedModules @(
                'internal.ps1',
                'helper.psm1',
                './relative/path.ps1',
                'ExternalNestedRef'
            )

            # Update config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'ModuleWithNested' = [ordered]@{
                        repo = 'https://github.com/test/ModuleWithNested.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            $result = Test-PSSubtreeModuleDependency -Path $script:testDir

            # Script files and relative paths should be skipped
            $result.NestedModules | Should -HaveCount 1
            $result.NestedModules[0].Name | Should -Be 'ExternalNestedRef'
        }

        It 'Should find nested module when it exists in modules directory' {
            # Create both modules
            New-TestModule -BasePath $script:testDir -ModuleName 'NestedDep'
            New-TestModule -BasePath $script:testDir -ModuleName 'ParentModule' -NestedModules @('NestedDep')

            # Update config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'NestedDep'    = [ordered]@{
                        repo = 'https://github.com/test/NestedDep.git'
                        ref  = 'main'
                    }
                    'ParentModule' = [ordered]@{
                        repo = 'https://github.com/test/ParentModule.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            $result = Test-PSSubtreeModuleDependency -Path $script:testDir -Name 'ParentModule'

            $result.AllDependenciesMet | Should -Be $true
            $result.NestedModules[0].Found | Should -Be $true
        }
    }

    Context 'Workflow integration: filtering modules with missing dependencies' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            # Initialize repository with mixed modules (some with satisfied deps, some missing)
            Initialize-PSSubtreeModule -Path $script:testDir

            # ModuleOK has no dependencies
            New-TestModule -BasePath $script:testDir -ModuleName 'ModuleOK'

            # ModuleAlsoOK depends on ModuleOK (satisfied)
            New-TestModule -BasePath $script:testDir -ModuleName 'ModuleAlsoOK' -RequiredModules @('ModuleOK')

            # ModuleBroken depends on NonExistent (missing)
            New-TestModule -BasePath $script:testDir -ModuleName 'ModuleBroken' -RequiredModules @('NonExistent')

            # Update config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'ModuleOK'     = [ordered]@{
                        repo = 'https://github.com/test/ModuleOK.git'
                        ref  = 'main'
                    }
                    'ModuleAlsoOK' = [ordered]@{
                        repo = 'https://github.com/test/ModuleAlsoOK.git'
                        ref  = 'main'
                    }
                    'ModuleBroken' = [ordered]@{
                        repo = 'https://github.com/test/ModuleBroken.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath
        }

        It 'Should return all modules when checking dependencies' {
            $results = Test-PSSubtreeModuleDependency -Path $script:testDir

            $results | Should -HaveCount 3
        }

        It 'Should filter to only modules with missing dependencies using pipeline' {
            $brokenModules = Test-PSSubtreeModuleDependency -Path $script:testDir |
                Where-Object { -not $_.AllDependenciesMet }

            $brokenModules | Should -HaveCount 1
            $brokenModules.Name | Should -Be 'ModuleBroken'
        }

        It 'Should filter to only modules with all dependencies met' {
            $goodModules = Test-PSSubtreeModuleDependency -Path $script:testDir |
                Where-Object { $_.AllDependenciesMet }

            $goodModules | Should -HaveCount 2
            $goodModules.Name | Should -Contain 'ModuleOK'
            $goodModules.Name | Should -Contain 'ModuleAlsoOK'
        }
    }

    Context 'Error handling and edge cases' -Skip:(-not $script:yamlAvailable) {
        It 'Should return empty result for empty module list' {
            Initialize-PSSubtreeModule -Path $script:testDir

            $result = Test-PSSubtreeModuleDependency -Path $script:testDir

            $result | Should -BeNullOrEmpty
        }

        It 'Should handle module with missing manifest gracefully' {
            Initialize-PSSubtreeModule -Path $script:testDir

            # Create module directory without manifest
            $modulePath = Join-Path -Path $script:testDir -ChildPath 'modules/NoManifest'
            New-Item -Path $modulePath -ItemType Directory -Force | Out-Null

            # Update config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'NoManifest' = [ordered]@{
                        repo = 'https://github.com/test/NoManifest.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            # Should not throw, but should mark as dependencies not met
            $result = Test-PSSubtreeModuleDependency -Path $script:testDir -WarningAction SilentlyContinue

            $result.AllDependenciesMet | Should -Be $false
        }

        It 'Should handle malformed manifest gracefully' {
            Initialize-PSSubtreeModule -Path $script:testDir

            # Create module with invalid manifest
            $modulePath = Join-Path -Path $script:testDir -ChildPath 'modules/BadManifest'
            New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $modulePath 'BadManifest.psd1') -Value 'this is not valid @{ powershell'

            # Update config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'BadManifest' = [ordered]@{
                        repo = 'https://github.com/test/BadManifest.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            # Should not throw
            { Test-PSSubtreeModuleDependency -Path $script:testDir -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should work without PSSubtreeModules initialization if config exists' {
            # Manually create just the config file and modules (no Initialize call)
            New-Item -Path (Join-Path -Path $script:testDir -ChildPath 'modules') -ItemType Directory -Force | Out-Null
            New-TestModule -BasePath $script:testDir -ModuleName 'ManualModule'

            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'ManualModule' = [ordered]@{
                        repo = 'https://github.com/test/ManualModule.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath

            $result = Test-PSSubtreeModuleDependency -Path $script:testDir

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'ManualModule'
        }
    }

    Context 'Verbose output verification' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            Initialize-PSSubtreeModule -Path $script:testDir
            New-TestModule -BasePath $script:testDir -ModuleName 'VerboseTest' -RequiredModules @('SomeDep')

            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'VerboseTest' = [ordered]@{
                        repo = 'https://github.com/test/VerboseTest.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath
        }

        It 'Should produce verbose output about dependency search' {
            $verboseOutput = Test-PSSubtreeModuleDependency -Path $script:testDir -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty

            # Should mention searching for dependencies
            $verboseText = $verboseMessages.Message -join "`n"
            $verboseText | Should -Match 'Searching for dependency'
        }
    }

    Context 'Pipeline input support' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            Initialize-PSSubtreeModule -Path $script:testDir

            New-TestModule -BasePath $script:testDir -ModuleName 'PipelineModule1'
            New-TestModule -BasePath $script:testDir -ModuleName 'PipelineModule2'

            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'PipelineModule1' = [ordered]@{
                        repo = 'https://github.com/test/PipelineModule1.git'
                        ref  = 'main'
                    }
                    'PipelineModule2' = [ordered]@{
                        repo = 'https://github.com/test/PipelineModule2.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath
        }

        It 'Should accept module name from pipeline' {
            $result = 'PipelineModule1' | Test-PSSubtreeModuleDependency -Path $script:testDir

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'PipelineModule1'
        }

        It 'Should accept multiple module names from pipeline' {
            $results = @('PipelineModule1', 'PipelineModule2') | Test-PSSubtreeModuleDependency -Path $script:testDir

            $results | Should -HaveCount 2
        }
    }
}
