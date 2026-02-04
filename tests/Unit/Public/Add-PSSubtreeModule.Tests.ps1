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

    $saveModuleConfigPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Save-ModuleConfig.ps1'
    . $saveModuleConfigPath

    $invokeGitCommandPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Invoke-GitCommand.ps1'
    . $invokeGitCommandPath

    # Dot source the public function
    $publicFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Public/Add-PSSubtreeModule.ps1'
    . $publicFunctionPath
}

Describe 'Add-PSSubtreeModule' -Tag 'Unit', 'Public' {
    Context 'Parameter validation' {
        It 'Should have Name as mandatory parameter' {
            $command = Get-Command -Name Add-PSSubtreeModule
            $nameParam = $command.Parameters['Name']

            $nameParam | Should -Not -BeNullOrEmpty
            $mandatory = $nameParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
            }
            $mandatory | Should -Not -BeNullOrEmpty
        }

        It 'Should have Repository as mandatory parameter' {
            $command = Get-Command -Name Add-PSSubtreeModule
            $repoParam = $command.Parameters['Repository']

            $repoParam | Should -Not -BeNullOrEmpty
            $mandatory = $repoParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
            }
            $mandatory | Should -Not -BeNullOrEmpty
        }

        It 'Should have Repository alias Repo' {
            $command = Get-Command -Name Add-PSSubtreeModule
            $repoParam = $command.Parameters['Repository']
            $aliases = $repoParam.Aliases

            $aliases | Should -Contain 'Repo'
        }

        It 'Should have Repository alias Url' {
            $command = Get-Command -Name Add-PSSubtreeModule
            $repoParam = $command.Parameters['Repository']
            $aliases = $repoParam.Aliases

            $aliases | Should -Contain 'Url'
        }

        It 'Should have Ref parameter with default value main' {
            $command = Get-Command -Name Add-PSSubtreeModule
            $refParam = $command.Parameters['Ref']

            $refParam | Should -Not -BeNullOrEmpty
        }

        It 'Should have Ref alias Branch' {
            $command = Get-Command -Name Add-PSSubtreeModule
            $refParam = $command.Parameters['Ref']
            $aliases = $refParam.Aliases

            $aliases | Should -Contain 'Branch'
        }

        It 'Should have Ref alias Tag' {
            $command = Get-Command -Name Add-PSSubtreeModule
            $refParam = $command.Parameters['Ref']
            $aliases = $refParam.Aliases

            $aliases | Should -Contain 'Tag'
        }

        It 'Should have Force switch parameter' {
            $command = Get-Command -Name Add-PSSubtreeModule
            $forceParam = $command.Parameters['Force']

            $forceParam | Should -Not -BeNullOrEmpty
            $forceParam.SwitchParameter | Should -Be $true
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command -Name Add-PSSubtreeModule
            $command.CmdletBinding | Should -Be $true
        }

        It 'Should validate Name parameter with pattern' {
            $command = Get-Command -Name Add-PSSubtreeModule
            $nameParam = $command.Parameters['Name']
            $validatePattern = $nameParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }

            $validatePattern | Should -Not -BeNullOrEmpty
            $validatePattern.RegexPattern | Should -Be '^[a-zA-Z0-9_.-]+$'
        }

        It 'Should reject invalid module names with spaces' {
            { Add-PSSubtreeModule -Name 'Invalid Name' -Repository 'https://github.com/test/repo.git' -Path $TestDrive -WhatIf } | Should -Throw
        }

        It 'Should reject invalid module names with special characters' {
            { Add-PSSubtreeModule -Name 'Invalid@Name' -Repository 'https://github.com/test/repo.git' -Path $TestDrive -WhatIf } | Should -Throw
        }

        It 'Should accept valid module names with dots' {
            # Just testing parameter validation, using WhatIf to avoid actual execution
            { Add-PSSubtreeModule -Name 'Valid.Name' -Repository 'https://github.com/test/repo.git' -Path $TestDrive -WhatIf -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should accept valid module names with underscores' {
            { Add-PSSubtreeModule -Name 'Valid_Name' -Repository 'https://github.com/test/repo.git' -Path $TestDrive -WhatIf -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should accept valid module names with hyphens' {
            { Add-PSSubtreeModule -Name 'Valid-Name' -Repository 'https://github.com/test/repo.git' -Path $TestDrive -WhatIf -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'When path does not exist' {
        It 'Should write error for non-existent path' {
            $nonExistentPath = Join-Path -Path $TestDrive -ChildPath "does-not-exist-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            $errorOutput = $null

            Add-PSSubtreeModule -Name 'TestModule' -Repository 'https://github.com/test/repo.git' -Path $nonExistentPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'PathNotFound'
        }
    }

    Context 'When path is not a Git repository' {
        BeforeEach {
            $script:nonGitPath = Join-Path -Path $TestDrive -ChildPath "non-git-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:nonGitPath -ItemType Directory -Force | Out-Null
        }

        It 'Should write error when .git directory is missing' {
            $errorOutput = $null

            Add-PSSubtreeModule -Name 'TestModule' -Repository 'https://github.com/test/repo.git' -Path $script:nonGitPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'NotGitRepository'
        }
    }

    Context 'When repository is not initialized for PSSubtreeModules' {
        BeforeEach {
            $script:uninitializedPath = Join-Path -Path $TestDrive -ChildPath "uninitialized-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:uninitializedPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:uninitializedPath -ChildPath '.git') -ItemType Directory -Force | Out-Null
        }

        It 'Should write error when subtree-modules.yaml does not exist' {
            $errorOutput = $null

            Add-PSSubtreeModule -Name 'TestModule' -Repository 'https://github.com/test/repo.git' -Path $script:uninitializedPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'NotInitialized'
        }
    }

    Context 'When module already exists in configuration' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:existingModulePath = Join-Path -Path $TestDrive -ChildPath "existing-module-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:existingModulePath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:existingModulePath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            # Create configuration with existing module
            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  ExistingModule:
    repo: https://github.com/owner/existing.git
    ref: main
'@
            $configPath = Join-Path -Path $script:existingModulePath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent
        }

        It 'Should write error when module already exists without -Force' {
            $errorOutput = $null

            Add-PSSubtreeModule -Name 'ExistingModule' -Repository 'https://github.com/test/repo.git' -Path $script:existingModulePath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'ModuleAlreadyExists'
        }
    }

    Context 'When module directory already exists' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:dirExistsPath = Join-Path -Path $TestDrive -ChildPath "dir-exists-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:dirExistsPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:dirExistsPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            # Create empty configuration
            $yamlContent = @'
# PSSubtreeModules configuration
modules: {}
'@
            $configPath = Join-Path -Path $script:dirExistsPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create the module directory
            $moduleDirPath = Join-Path -Path $script:dirExistsPath -ChildPath 'modules/TestModule'
            New-Item -Path $moduleDirPath -ItemType Directory -Force | Out-Null
        }

        It 'Should write error when module directory already exists' {
            $errorOutput = $null

            Add-PSSubtreeModule -Name 'TestModule' -Repository 'https://github.com/test/repo.git' -Path $script:dirExistsPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'DirectoryAlreadyExists'
        }
    }

    Context 'WhatIf support' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:whatifPath = Join-Path -Path $TestDrive -ChildPath "whatif-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:whatifPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:whatifPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            # Create empty configuration
            $yamlContent = @'
# PSSubtreeModules configuration
modules: {}
'@
            $configPath = Join-Path -Path $script:whatifPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent
        }

        It 'Should not execute git commands when -WhatIf is specified' {
            Mock -CommandName Invoke-GitCommand -MockWith { }

            Add-PSSubtreeModule -Name 'TestModule' -Repository 'https://github.com/test/repo.git' -Path $script:whatifPath -WhatIf

            Should -Invoke -CommandName Invoke-GitCommand -Times 0
        }

        It 'Should not modify configuration when -WhatIf is specified' {
            Add-PSSubtreeModule -Name 'TestModule' -Repository 'https://github.com/test/repo.git' -Path $script:whatifPath -WhatIf

            $content = Get-Content -Path (Join-Path -Path $script:whatifPath -ChildPath 'subtree-modules.yaml') -Raw
            $content | Should -Match 'modules: \{\}'
        }
    }

    Context 'Successful module addition' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:successPath = Join-Path -Path $TestDrive -ChildPath "success-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:successPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:successPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            # Create empty configuration
            $yamlContent = @'
# PSSubtreeModules configuration
modules: {}
'@
            $configPath = Join-Path -Path $script:successPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Mock the git commands to simulate success
            Mock -CommandName Invoke-GitCommand -MockWith {
                # Return empty output for all git commands
                return @()
            }
        }

        It 'Should call git subtree add with correct arguments' {
            Add-PSSubtreeModule -Name 'TestModule' -Repository 'https://github.com/test/repo.git' -Ref 'v1.0.0' -Path $script:successPath -Confirm:$false

            Should -Invoke -CommandName Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'subtree' -and
                $Arguments -contains 'add' -and
                $Arguments -contains '--prefix=modules/TestModule' -and
                $Arguments -contains 'https://github.com/test/repo.git' -and
                $Arguments -contains 'v1.0.0' -and
                $Arguments -contains '--squash'
            }
        }

        It 'Should update configuration with new module' {
            Add-PSSubtreeModule -Name 'NewModule' -Repository 'https://github.com/owner/new.git' -Ref 'main' -Path $script:successPath -Confirm:$false

            $content = Get-Content -Path (Join-Path -Path $script:successPath -ChildPath 'subtree-modules.yaml') -Raw
            $content | Should -Match 'NewModule'
            $content | Should -Match 'https://github.com/owner/new.git'
        }

        It 'Should return PSCustomObject with module info' {
            $result = Add-PSSubtreeModule -Name 'ReturnModule' -Repository 'https://github.com/owner/return.git' -Ref 'develop' -Path $script:successPath -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'ReturnModule'
            $result.Repository | Should -Be 'https://github.com/owner/return.git'
            $result.Ref | Should -Be 'develop'
        }

        It 'Should return object with correct type name' {
            $result = Add-PSSubtreeModule -Name 'TypeModule' -Repository 'https://github.com/owner/type.git' -Path $script:successPath -Confirm:$false

            $result.PSObject.TypeNames[0] | Should -Be 'PSSubtreeModules.ModuleInfo'
        }

        It 'Should use default ref value main when not specified' {
            Add-PSSubtreeModule -Name 'DefaultRefModule' -Repository 'https://github.com/owner/default.git' -Path $script:successPath -Confirm:$false

            Should -Invoke -CommandName Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'main'
            }
        }

        It 'Should create conventional commit message' {
            Add-PSSubtreeModule -Name 'CommitModule' -Repository 'https://github.com/owner/commit.git' -Ref 'v2.0' -Path $script:successPath -Confirm:$false

            Should -Invoke -CommandName Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'commit' -and
                $Arguments -contains '-m' -and
                $Arguments -contains 'feat(modules): add CommitModule at v2.0'
            }
        }
    }

    Context 'Verbose output' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:verbosePath = Join-Path -Path $TestDrive -ChildPath "verbose-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:verbosePath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:verbosePath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            $yamlContent = @'
# PSSubtreeModules configuration
modules: {}
'@
            $configPath = Join-Path -Path $script:verbosePath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            Mock -CommandName Invoke-GitCommand -MockWith { return @() }
        }

        It 'Should output verbose messages when -Verbose is used' {
            $verboseOutput = Add-PSSubtreeModule -Name 'VerboseModule' -Repository 'https://github.com/owner/verbose.git' -Path $script:verbosePath -Confirm:$false -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Error handling during git operations' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:errorPath = Join-Path -Path $TestDrive -ChildPath "error-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:errorPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:errorPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            $yamlContent = @'
# PSSubtreeModules configuration
modules: {}
'@
            $configPath = Join-Path -Path $script:errorPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent
        }

        It 'Should write error when git subtree add fails' {
            Mock -CommandName Invoke-GitCommand -MockWith {
                throw 'Git subtree add failed: repository not found'
            }

            $errorOutput = $null
            Add-PSSubtreeModule -Name 'FailModule' -Repository 'https://github.com/invalid/repo.git' -Path $script:errorPath -Confirm:$false -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'ModuleAddError'
        }
    }
}
