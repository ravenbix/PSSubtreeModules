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

    # Helper function to get git log
    function Get-GitLog
    {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [Parameter()]
            [int]$Count = 10
        )

        $originalLocation = Get-Location
        Set-Location -Path $Path
        try
        {
            $log = git log --oneline -n $Count 2>&1
            return $log
        }
        finally
        {
            Set-Location -Path $originalLocation
        }
    }

    # Test repository URL - using a small, stable public repository
    # This should be a real, publicly accessible repository for true integration testing
    $script:testRepoUrl = 'https://github.com/PowerShell/DscResource.Common.git'
    $script:testRepoRef = 'main'

    # Check if we can access the test repository (network check)
    $script:networkAvailable = $false
    try
    {
        $null = git ls-remote --exit-code $script:testRepoUrl 2>&1
        if ($LASTEXITCODE -eq 0)
        {
            $script:networkAvailable = $true
        }
    }
    catch
    {
        # Network not available
    }
}

Describe 'Full Workflow Integration Tests' -Tag 'Integration' {
    BeforeEach {
        # Create a unique test directory for each test
        $script:testDir = Join-Path -Path $TestDrive -ChildPath "integration-test-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
        New-TestGitRepository -Path $script:testDir
    }

    AfterEach {
        # Cleanup is handled by Pester's TestDrive
    }

    Context 'Initialize-PSSubtreeModule workflow' -Skip:(-not $script:yamlAvailable) {
        It 'Should create all required files when initializing a repository' {
            $result = Initialize-PSSubtreeModule -Path $script:testDir

            # Verify all files were created
            (Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml') | Should -Exist
            (Join-Path -Path $script:testDir -ChildPath 'modules/.gitkeep') | Should -Exist
            (Join-Path -Path $script:testDir -ChildPath '.gitignore') | Should -Exist
            (Join-Path -Path $script:testDir -ChildPath 'README.md') | Should -Exist
            (Join-Path -Path $script:testDir -ChildPath '.github/workflows/check-updates.yml') | Should -Exist

            # Verify result contains FileInfo objects
            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 5
        }

        It 'Should create valid YAML configuration file' {
            Initialize-PSSubtreeModule -Path $script:testDir

            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = Get-ModuleConfig -Path $configPath

            $config | Should -Not -BeNullOrEmpty
            $config.modules | Should -Not -BeNullOrEmpty
            $config.modules.Count | Should -Be 0
        }
    }

    Context 'Complete workflow: Initialize -> Add -> Get -> Update -> Remove' -Skip:(-not $script:yamlAvailable -or -not $script:networkAvailable) {
        It 'Should complete full module lifecycle with real git operations' {
            # Step 1: Initialize the repository
            Write-Verbose "Step 1: Initializing repository" -Verbose
            $initResult = Initialize-PSSubtreeModule -Path $script:testDir
            $initResult | Should -Not -BeNullOrEmpty

            # Commit the initialization files
            $originalLocation = Get-Location
            Set-Location -Path $script:testDir
            try
            {
                git add -A 2>&1 | Out-Null
                git commit -m "feat: initialize PSSubtreeModules" 2>&1 | Out-Null
            }
            finally
            {
                Set-Location -Path $originalLocation
            }

            # Step 2: Add a module
            Write-Verbose "Step 2: Adding module from $script:testRepoUrl" -Verbose
            $addResult = Add-PSSubtreeModule -Name 'DscResource.Common' -Repository $script:testRepoUrl -Ref $script:testRepoRef -Path $script:testDir -Confirm:$false

            $addResult | Should -Not -BeNullOrEmpty
            $addResult.Name | Should -Be 'DscResource.Common'
            $addResult.Repository | Should -Be $script:testRepoUrl
            $addResult.Ref | Should -Be $script:testRepoRef

            # Verify module directory was created
            $modulePath = Join-Path -Path $script:testDir -ChildPath 'modules/DscResource.Common'
            $modulePath | Should -Exist

            # Verify configuration was updated
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = Get-ModuleConfig -Path $configPath
            $config.modules.Contains('DscResource.Common') | Should -Be $true
            $config.modules['DscResource.Common'].repo | Should -Be $script:testRepoUrl

            # Verify conventional commit was created
            $log = Get-GitLog -Path $script:testDir -Count 5
            ($log -join "`n") | Should -Match 'feat\(modules\): add DscResource\.Common'

            # Step 3: Get the module
            Write-Verbose "Step 3: Getting module list" -Verbose
            $getResult = Get-PSSubtreeModule -Path $script:testDir

            $getResult | Should -Not -BeNullOrEmpty
            $getResult.Name | Should -Be 'DscResource.Common'
            $getResult.Repository | Should -Be $script:testRepoUrl
            $getResult.Ref | Should -Be $script:testRepoRef

            # Step 4: Check module status
            Write-Verbose "Step 4: Checking module status" -Verbose
            $statusResult = Get-PSSubtreeModuleStatus -Path $script:testDir

            $statusResult | Should -Not -BeNullOrEmpty
            $statusResult.Name | Should -Be 'DscResource.Common'
            $statusResult.Ref | Should -Be $script:testRepoRef
            $statusResult.Status | Should -BeIn @('Current', 'UpdateAvailable', 'Unknown')

            # Step 5: Update the module (should be already up to date, but tests the operation)
            Write-Verbose "Step 5: Updating module" -Verbose
            $updateResult = Update-PSSubtreeModule -Name 'DscResource.Common' -Path $script:testDir -Confirm:$false

            $updateResult | Should -Not -BeNullOrEmpty
            $updateResult.Name | Should -Be 'DscResource.Common'
            $updateResult.Ref | Should -Be $script:testRepoRef

            # Step 6: Remove the module
            Write-Verbose "Step 6: Removing module" -Verbose
            $removeResult = Remove-PSSubtreeModule -Name 'DscResource.Common' -Path $script:testDir -Force

            $removeResult | Should -Not -BeNullOrEmpty
            $removeResult.Name | Should -Be 'DscResource.Common'

            # Verify module directory was removed
            $modulePath | Should -Not -Exist

            # Verify configuration was updated
            $config = Get-ModuleConfig -Path $configPath
            $config.modules.Contains('DscResource.Common') | Should -Be $false

            # Verify removal commit was created
            $log = Get-GitLog -Path $script:testDir -Count 5
            ($log -join "`n") | Should -Match 'feat\(modules\): remove DscResource\.Common'
        }
    }

    Context 'Get-PSSubtreeModule with wildcards' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            # Initialize and set up a test config with multiple modules
            Initialize-PSSubtreeModule -Path $script:testDir

            # Manually create a config with multiple modules for testing wildcards
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'Pester'           = [ordered]@{
                        repo = 'https://github.com/pester/Pester.git'
                        ref  = 'main'
                    }
                    'PSScriptAnalyzer' = [ordered]@{
                        repo = 'https://github.com/PowerShell/PSScriptAnalyzer.git'
                        ref  = 'main'
                    }
                    'PSReadLine'       = [ordered]@{
                        repo = 'https://github.com/PowerShell/PSReadLine.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath
        }

        It 'Should return all modules when using default wildcard' {
            $result = Get-PSSubtreeModule -Path $script:testDir

            $result | Should -HaveCount 3
            $result.Name | Should -Contain 'Pester'
            $result.Name | Should -Contain 'PSScriptAnalyzer'
            $result.Name | Should -Contain 'PSReadLine'
        }

        It 'Should filter modules by prefix pattern' {
            $result = Get-PSSubtreeModule -Name 'PS*' -Path $script:testDir

            $result | Should -HaveCount 2
            $result.Name | Should -Contain 'PSScriptAnalyzer'
            $result.Name | Should -Contain 'PSReadLine'
        }

        It 'Should return single module by exact name' {
            $result = Get-PSSubtreeModule -Name 'Pester' -Path $script:testDir

            $result | Should -HaveCount 1
            $result.Name | Should -Be 'Pester'
        }

        It 'Should return empty when pattern matches nothing' {
            $result = Get-PSSubtreeModule -Name 'NonExistent*' -Path $script:testDir

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Error handling for missing prerequisites' -Skip:(-not $script:yamlAvailable) {
        It 'Should error when trying to add module before initialization' {
            # Test directory is a git repo but not initialized for PSSubtreeModules
            $errorOutput = $null

            Add-PSSubtreeModule -Name 'TestModule' -Repository 'https://github.com/test/repo.git' -Path $script:testDir -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'NotInitialized'
        }

        It 'Should error when trying to update non-existent module' {
            Initialize-PSSubtreeModule -Path $script:testDir

            $errorOutput = $null

            Update-PSSubtreeModule -Name 'NonExistent' -Path $script:testDir -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'ModuleNotTracked'
        }

        It 'Should error when trying to remove non-existent module' {
            Initialize-PSSubtreeModule -Path $script:testDir

            $errorOutput = $null

            Remove-PSSubtreeModule -Name 'NonExistent' -Path $script:testDir -Force -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'ModuleNotTracked'
        }
    }

    Context 'WhatIf support across workflow' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            Initialize-PSSubtreeModule -Path $script:testDir
        }

        It 'Should not create files when Initialize is called with -WhatIf on fresh directory' {
            $freshDir = Join-Path -Path $TestDrive -ChildPath "whatif-test-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-TestGitRepository -Path $freshDir

            Initialize-PSSubtreeModule -Path $freshDir -WhatIf

            # Only the README.md from git init should exist
            (Join-Path -Path $freshDir -ChildPath 'subtree-modules.yaml') | Should -Not -Exist
            (Join-Path -Path $freshDir -ChildPath 'modules') | Should -Not -Exist
        }

        It 'Should not make changes when Add is called with -WhatIf' {
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $contentBefore = Get-Content -Path $configPath -Raw

            Add-PSSubtreeModule -Name 'TestModule' -Repository 'https://github.com/test/repo.git' -Path $script:testDir -WhatIf

            $contentAfter = Get-Content -Path $configPath -Raw
            $contentAfter | Should -Be $contentBefore

            # Module directory should not be created
            (Join-Path -Path $script:testDir -ChildPath 'modules/TestModule') | Should -Not -Exist
        }
    }

    Context 'Initialize with -Force' -Skip:(-not $script:yamlAvailable) {
        It 'Should overwrite existing files when -Force is specified' {
            # First initialization
            Initialize-PSSubtreeModule -Path $script:testDir

            # Modify the README
            $readmePath = Join-Path -Path $script:testDir -ChildPath 'README.md'
            Set-Content -Path $readmePath -Value 'Custom content'

            # Second initialization with -Force
            Initialize-PSSubtreeModule -Path $script:testDir -Force

            # README should be overwritten
            $content = Get-Content -Path $readmePath -Raw
            $content | Should -Match 'PSSubtreeModules'
            $content | Should -Not -Match 'Custom content'
        }

        It 'Should warn but not overwrite when -Force is not specified' {
            # First initialization
            Initialize-PSSubtreeModule -Path $script:testDir

            # Modify the config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $customConfig = [ordered]@{
                modules = [ordered]@{
                    'CustomModule' = [ordered]@{
                        repo = 'https://example.com/repo.git'
                        ref  = 'main'
                    }
                }
            }
            Save-ModuleConfig -Configuration $customConfig -Path $configPath

            # Second initialization without -Force
            $warningOutput = Initialize-PSSubtreeModule -Path $script:testDir -WarningVariable warnings 3>&1

            # Config should still have custom content
            $config = Get-ModuleConfig -Path $configPath
            $config.modules.Contains('CustomModule') | Should -Be $true
        }
    }

    Context 'Module addition with Force parameter' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            Initialize-PSSubtreeModule -Path $script:testDir

            # Manually add a module entry to config
            $configPath = Join-Path -Path $script:testDir -ChildPath 'subtree-modules.yaml'
            $config = [ordered]@{
                modules = [ordered]@{
                    'ExistingModule' = [ordered]@{
                        repo = 'https://github.com/old/repo.git'
                        ref  = 'v1.0.0'
                    }
                }
            }
            Save-ModuleConfig -Configuration $config -Path $configPath
        }

        It 'Should error when adding existing module without -Force' {
            $errorOutput = $null

            Add-PSSubtreeModule -Name 'ExistingModule' -Repository 'https://github.com/new/repo.git' -Path $script:testDir -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'ModuleAlreadyExists'
        }
    }

    Context 'Conventional commit messages' -Skip:(-not $script:yamlAvailable -or -not $script:networkAvailable) {
        It 'Should create properly formatted conventional commits throughout workflow' {
            # Initialize
            Initialize-PSSubtreeModule -Path $script:testDir

            # Commit init files
            $originalLocation = Get-Location
            Set-Location -Path $script:testDir
            try
            {
                git add -A 2>&1 | Out-Null
                git commit -m "feat: initialize PSSubtreeModules" 2>&1 | Out-Null
            }
            finally
            {
                Set-Location -Path $originalLocation
            }

            # Add a module
            $addResult = Add-PSSubtreeModule -Name 'DscResource.Common' -Repository $script:testRepoUrl -Ref $script:testRepoRef -Path $script:testDir -Confirm:$false

            # Verify add commit
            $log = Get-GitLog -Path $script:testDir -Count 3
            ($log -join "`n") | Should -Match 'feat\(modules\): add DscResource\.Common at main'

            # Remove the module
            Remove-PSSubtreeModule -Name 'DscResource.Common' -Path $script:testDir -Force

            # Verify remove commit
            $log = Get-GitLog -Path $script:testDir -Count 3
            ($log -join "`n") | Should -Match 'feat\(modules\): remove DscResource\.Common'
        }
    }

    Context 'Empty module list handling' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            Initialize-PSSubtreeModule -Path $script:testDir
        }

        It 'Should return empty when no modules are tracked' {
            $result = Get-PSSubtreeModule -Path $script:testDir

            $result | Should -BeNullOrEmpty
        }

        It 'Should return empty status when no modules are tracked' {
            $result = Get-PSSubtreeModuleStatus -Path $script:testDir

            $result | Should -BeNullOrEmpty
        }

        It 'Should warn when trying to update with -All on empty module list' {
            $warningOutput = Update-PSSubtreeModule -All -Path $script:testDir -WarningVariable warnings 3>&1

            $warnings | Should -Not -BeNullOrEmpty
            $warnings[0].Message | Should -Match 'No modules are currently tracked'
        }
    }
}
