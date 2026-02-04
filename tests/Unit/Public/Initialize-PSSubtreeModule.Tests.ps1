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

    # Dot source the public function and its dependencies
    $publicFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Public/Initialize-PSSubtreeModule.ps1'
    . $publicFunctionPath
}

Describe 'Initialize-PSSubtreeModule' -Tag 'Unit', 'Public' {
    Context 'When initializing a valid Git repository' {
        BeforeEach {
            # Create a mock Git repository in TestDrive with unique name
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "test-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:testRepoPath -ChildPath '.git') -ItemType Directory -Force | Out-Null
        }

        It 'Should create all required files' {
            $result = Initialize-PSSubtreeModule -Path $script:testRepoPath

            # Check that files were created
            Test-Path -Path (Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml') | Should -Be $true
            Test-Path -Path (Join-Path -Path $script:testRepoPath -ChildPath 'modules/.gitkeep') | Should -Be $true
            Test-Path -Path (Join-Path -Path $script:testRepoPath -ChildPath '.gitignore') | Should -Be $true
            Test-Path -Path (Join-Path -Path $script:testRepoPath -ChildPath 'README.md') | Should -Be $true
            Test-Path -Path (Join-Path -Path $script:testRepoPath -ChildPath '.github/workflows/check-updates.yml') | Should -Be $true
        }

        It 'Should return FileInfo objects for created files' {
            $result = Initialize-PSSubtreeModule -Path $script:testRepoPath

            $result | Should -Not -BeNullOrEmpty
            $result | ForEach-Object { $_ | Should -BeOfType [System.IO.FileInfo] }
        }

        It 'Should create subtree-modules.yaml with correct content' {
            Initialize-PSSubtreeModule -Path $script:testRepoPath

            $yamlPath = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            $content = Get-Content -Path $yamlPath -Raw

            $content | Should -Match '# PSSubtreeModules configuration'
            $content | Should -Match 'modules:'
        }

        It 'Should create .gitignore with expected content' {
            Initialize-PSSubtreeModule -Path $script:testRepoPath

            $gitignorePath = Join-Path -Path $script:testRepoPath -ChildPath '.gitignore'
            $content = Get-Content -Path $gitignorePath -Raw

            $content | Should -Match 'output/'
            $content | Should -Match '\.DS_Store'
        }

        It 'Should create README.md with PSSubtreeModules documentation' {
            Initialize-PSSubtreeModule -Path $script:testRepoPath

            $readmePath = Join-Path -Path $script:testRepoPath -ChildPath 'README.md'
            $content = Get-Content -Path $readmePath -Raw

            $content | Should -Match 'PSSubtreeModules'
            $content | Should -Match 'Add-PSSubtreeModule'
        }

        It 'Should create GitHub Actions workflow' {
            Initialize-PSSubtreeModule -Path $script:testRepoPath

            $workflowPath = Join-Path -Path $script:testRepoPath -ChildPath '.github/workflows/check-updates.yml'
            $content = Get-Content -Path $workflowPath -Raw

            $content | Should -Match 'Check Module Updates'
            $content | Should -Match 'Get-PSSubtreeModuleStatus'
        }

        It 'Should create modules directory' {
            Initialize-PSSubtreeModule -Path $script:testRepoPath

            Test-Path -Path (Join-Path -Path $script:testRepoPath -ChildPath 'modules') -PathType Container | Should -Be $true
        }
    }

    Context 'When files already exist' {
        BeforeEach {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "existing-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:testRepoPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            # Create an existing file
            $existingFile = Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $existingFile -Value '# Existing content'
        }

        It 'Should skip existing files without -Force' {
            $result = Initialize-PSSubtreeModule -Path $script:testRepoPath -WarningAction SilentlyContinue

            # The existing file should not be modified
            $content = Get-Content -Path (Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml') -Raw
            $content | Should -Match 'Existing content'
        }

        It 'Should output warning for skipped files' {
            $warnings = Initialize-PSSubtreeModule -Path $script:testRepoPath -WarningVariable warningOutput 3>&1

            # Should have a warning about the existing file
            $warningOutput | Should -Not -BeNullOrEmpty
            $warningOutput[0].Message | Should -Match 'already exists'
        }

        It 'Should overwrite existing files with -Force' {
            $result = Initialize-PSSubtreeModule -Path $script:testRepoPath -Force

            # The file should be overwritten
            $content = Get-Content -Path (Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml') -Raw
            $content | Should -Match '# PSSubtreeModules configuration'
        }
    }

    Context 'When path is not a Git repository' {
        BeforeEach {
            $script:nonGitPath = Join-Path -Path $TestDrive -ChildPath "non-git-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:nonGitPath -ItemType Directory -Force | Out-Null
        }

        It 'Should write error when .git directory is missing' {
            $errorOutput = $null
            Initialize-PSSubtreeModule -Path $script:nonGitPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'NotGitRepository'
        }

        It 'Should not create any files when not a Git repository' {
            Initialize-PSSubtreeModule -Path $script:nonGitPath -ErrorAction SilentlyContinue

            Test-Path -Path (Join-Path -Path $script:nonGitPath -ChildPath 'subtree-modules.yaml') | Should -Be $false
        }
    }

    Context 'When path does not exist' {
        It 'Should write error for non-existent path' {
            $nonExistentPath = Join-Path -Path $TestDrive -ChildPath "does-not-exist-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            $errorOutput = $null
            Initialize-PSSubtreeModule -Path $nonExistentPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'PathNotFound'
        }
    }

    Context 'WhatIf support' {
        BeforeEach {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "whatif-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:testRepoPath -ChildPath '.git') -ItemType Directory -Force | Out-Null
        }

        It 'Should not create files when -WhatIf is specified' {
            Initialize-PSSubtreeModule -Path $script:testRepoPath -WhatIf

            Test-Path -Path (Join-Path -Path $script:testRepoPath -ChildPath 'subtree-modules.yaml') | Should -Be $false
            Test-Path -Path (Join-Path -Path $script:testRepoPath -ChildPath 'modules') | Should -Be $false
        }

        It 'Should return nothing when -WhatIf is specified' {
            $result = Initialize-PSSubtreeModule -Path $script:testRepoPath -WhatIf

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {
        It 'Should have Path parameter with default value' {
            $command = Get-Command -Name Initialize-PSSubtreeModule
            $pathParam = $command.Parameters['Path']

            $pathParam | Should -Not -BeNullOrEmpty
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command -Name Initialize-PSSubtreeModule
            $command.CmdletBinding | Should -Be $true
        }

        It 'Should have Force switch parameter' {
            $command = Get-Command -Name Initialize-PSSubtreeModule
            $forceParam = $command.Parameters['Force']

            $forceParam | Should -Not -BeNullOrEmpty
            $forceParam.SwitchParameter | Should -Be $true
        }
    }

    Context 'Verbose output' {
        BeforeEach {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "verbose-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:testRepoPath -ChildPath '.git') -ItemType Directory -Force | Out-Null
        }

        It 'Should output verbose messages when -Verbose is used' {
            $verboseOutput = Initialize-PSSubtreeModule -Path $script:testRepoPath -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }
}
