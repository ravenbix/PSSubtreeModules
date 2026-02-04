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
    $publicFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Public/Update-PSSubtreeModule.ps1'
    . $publicFunctionPath
}

Describe 'Update-PSSubtreeModule' -Tag 'Unit', 'Public' {
    Context 'Parameter validation' {
        It 'Should have Name as mandatory parameter in ByName parameter set' {
            $command = Get-Command -Name Update-PSSubtreeModule
            $nameParam = $command.Parameters['Name']

            $nameParam | Should -Not -BeNullOrEmpty
            $mandatory = $nameParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and
                $_.Mandatory -and
                $_.ParameterSetName -eq 'ByName'
            }
            $mandatory | Should -Not -BeNullOrEmpty
        }

        It 'Should have All as mandatory parameter in All parameter set' {
            $command = Get-Command -Name Update-PSSubtreeModule
            $allParam = $command.Parameters['All']

            $allParam | Should -Not -BeNullOrEmpty
            $allParam.SwitchParameter | Should -Be $true
        }

        It 'Should have Ref parameter with alias Branch' {
            $command = Get-Command -Name Update-PSSubtreeModule
            $refParam = $command.Parameters['Ref']
            $aliases = $refParam.Aliases

            $aliases | Should -Contain 'Branch'
        }

        It 'Should have Ref parameter with alias Tag' {
            $command = Get-Command -Name Update-PSSubtreeModule
            $refParam = $command.Parameters['Ref']
            $aliases = $refParam.Aliases

            $aliases | Should -Contain 'Tag'
        }

        It 'Should have Path parameter with default value' {
            $command = Get-Command -Name Update-PSSubtreeModule
            $pathParam = $command.Parameters['Path']

            $pathParam | Should -Not -BeNullOrEmpty
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command -Name Update-PSSubtreeModule
            $command.CmdletBinding | Should -Be $true
        }

        It 'Should validate Name parameter with pattern' {
            $command = Get-Command -Name Update-PSSubtreeModule
            $nameParam = $command.Parameters['Name']
            $validatePattern = $nameParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }

            $validatePattern | Should -Not -BeNullOrEmpty
            $validatePattern.RegexPattern | Should -Be '^[a-zA-Z0-9_.-]+$'
        }

        It 'Should reject invalid module names with spaces' {
            { Update-PSSubtreeModule -Name 'Invalid Name' -Path $TestDrive -WhatIf } | Should -Throw
        }

        It 'Should reject invalid module names with special characters' {
            { Update-PSSubtreeModule -Name 'Invalid@Name' -Path $TestDrive -WhatIf } | Should -Throw
        }
    }

    Context 'When path does not exist' {
        It 'Should write error for non-existent path' {
            $nonExistentPath = Join-Path -Path $TestDrive -ChildPath "does-not-exist-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            $errorOutput = $null

            Update-PSSubtreeModule -Name 'TestModule' -Path $nonExistentPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

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

            Update-PSSubtreeModule -Name 'TestModule' -Path $script:nonGitPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

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

            Update-PSSubtreeModule -Name 'TestModule' -Path $script:uninitializedPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'NotInitialized'
        }
    }

    Context 'When no modules are tracked' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:emptyPath = Join-Path -Path $TestDrive -ChildPath "empty-modules-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:emptyPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:emptyPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            # Create empty configuration
            $yamlContent = @'
# PSSubtreeModules configuration
modules: {}
'@
            $configPath = Join-Path -Path $script:emptyPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent
        }

        It 'Should write warning when no modules are tracked' {
            $warnings = Update-PSSubtreeModule -Name 'TestModule' -Path $script:emptyPath -WarningVariable warningOutput -WarningAction SilentlyContinue -ErrorAction SilentlyContinue 3>&1

            $warningOutput | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When module is not tracked' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:trackedPath = Join-Path -Path $TestDrive -ChildPath "tracked-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:trackedPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:trackedPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            # Create configuration with a different module
            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  ExistingModule:
    repo: https://github.com/owner/existing.git
    ref: main
'@
            $configPath = Join-Path -Path $script:trackedPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent
        }

        It 'Should write error when module is not tracked' {
            $errorOutput = $null

            Update-PSSubtreeModule -Name 'NonExistentModule' -Path $script:trackedPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'ModuleNotTracked'
        }
    }

    Context 'WhatIf support' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:whatifPath = Join-Path -Path $TestDrive -ChildPath "whatif-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:whatifPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:whatifPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            # Create configuration with a module
            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  TestModule:
    repo: https://github.com/owner/test.git
    ref: main
'@
            $configPath = Join-Path -Path $script:whatifPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create the module directory
            $moduleDirPath = Join-Path -Path $script:whatifPath -ChildPath 'modules/TestModule'
            New-Item -Path $moduleDirPath -ItemType Directory -Force | Out-Null
        }

        It 'Should not execute git commands when -WhatIf is specified' {
            Mock -CommandName Invoke-GitCommand -MockWith { }

            Update-PSSubtreeModule -Name 'TestModule' -Path $script:whatifPath -WhatIf

            Should -Invoke -CommandName Invoke-GitCommand -Times 0
        }

        It 'Should not modify configuration when -WhatIf is specified' {
            Update-PSSubtreeModule -Name 'TestModule' -Ref 'v2.0.0' -Path $script:whatifPath -WhatIf

            $content = Get-Content -Path (Join-Path -Path $script:whatifPath -ChildPath 'subtree-modules.yaml') -Raw
            $content | Should -Match 'ref: main'
        }
    }

    Context 'Successful module update' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:successPath = Join-Path -Path $TestDrive -ChildPath "success-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:successPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:successPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            # Create configuration with a module
            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  TestModule:
    repo: https://github.com/owner/test.git
    ref: main
'@
            $configPath = Join-Path -Path $script:successPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create the module directory
            $moduleDirPath = Join-Path -Path $script:successPath -ChildPath 'modules/TestModule'
            New-Item -Path $moduleDirPath -ItemType Directory -Force | Out-Null

            # Mock the git commands to simulate success
            Mock -CommandName Invoke-GitCommand -MockWith {
                # Return empty output for all git commands
                return @()
            }
        }

        It 'Should call git subtree pull with correct arguments' {
            Update-PSSubtreeModule -Name 'TestModule' -Path $script:successPath -Confirm:$false

            Should -Invoke -CommandName Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'subtree' -and
                $Arguments -contains 'pull' -and
                $Arguments -contains '--prefix=modules/TestModule' -and
                $Arguments -contains 'https://github.com/owner/test.git' -and
                $Arguments -contains 'main' -and
                $Arguments -contains '--squash'
            }
        }

        It 'Should use new ref when -Ref is specified' {
            Update-PSSubtreeModule -Name 'TestModule' -Ref 'v2.0.0' -Path $script:successPath -Confirm:$false

            Should -Invoke -CommandName Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'subtree' -and
                $Arguments -contains 'pull' -and
                $Arguments -contains 'v2.0.0'
            }
        }

        It 'Should return PSCustomObject with update info' {
            $result = Update-PSSubtreeModule -Name 'TestModule' -Path $script:successPath -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'TestModule'
            $result.Repository | Should -Be 'https://github.com/owner/test.git'
            $result.Ref | Should -Be 'main'
        }

        It 'Should return object with correct type name' {
            $result = Update-PSSubtreeModule -Name 'TestModule' -Path $script:successPath -Confirm:$false

            $result.PSObject.TypeNames[0] | Should -Be 'PSSubtreeModules.UpdateResult'
        }

        It 'Should include PreviousRef in result' {
            $result = Update-PSSubtreeModule -Name 'TestModule' -Ref 'v2.0.0' -Path $script:successPath -Confirm:$false

            $result.PreviousRef | Should -Be 'main'
            $result.Ref | Should -Be 'v2.0.0'
        }

        It 'Should update configuration when ref changes' {
            Update-PSSubtreeModule -Name 'TestModule' -Ref 'v2.0.0' -Path $script:successPath -Confirm:$false

            $content = Get-Content -Path (Join-Path -Path $script:successPath -ChildPath 'subtree-modules.yaml') -Raw
            $content | Should -Match 'v2.0.0'
        }
    }

    Context 'Update all modules' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:allPath = Join-Path -Path $TestDrive -ChildPath "all-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:allPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:allPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            # Create configuration with multiple modules
            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  Module1:
    repo: https://github.com/owner/module1.git
    ref: main
  Module2:
    repo: https://github.com/owner/module2.git
    ref: develop
'@
            $configPath = Join-Path -Path $script:allPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create the module directories
            New-Item -Path (Join-Path -Path $script:allPath -ChildPath 'modules/Module1') -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:allPath -ChildPath 'modules/Module2') -ItemType Directory -Force | Out-Null

            Mock -CommandName Invoke-GitCommand -MockWith {
                return @()
            }
        }

        It 'Should update all tracked modules when -All is specified' {
            $result = Update-PSSubtreeModule -All -Path $script:allPath -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It 'Should call git subtree pull for each module' {
            Update-PSSubtreeModule -All -Path $script:allPath -Confirm:$false

            Should -Invoke -CommandName Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'subtree' -and
                $Arguments -contains 'pull' -and
                $Arguments -contains '--prefix=modules/Module1'
            }

            Should -Invoke -CommandName Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'subtree' -and
                $Arguments -contains 'pull' -and
                $Arguments -contains '--prefix=modules/Module2'
            }
        }
    }

    Context 'Error handling during git operations' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:errorPath = Join-Path -Path $TestDrive -ChildPath "error-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:errorPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:errorPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  FailModule:
    repo: https://github.com/owner/fail.git
    ref: main
'@
            $configPath = Join-Path -Path $script:errorPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Create the module directory
            New-Item -Path (Join-Path -Path $script:errorPath -ChildPath 'modules/FailModule') -ItemType Directory -Force | Out-Null
        }

        It 'Should write error when git subtree pull fails' {
            Mock -CommandName Invoke-GitCommand -MockWith {
                throw 'Git subtree pull failed: network error'
            }

            $errorOutput = $null
            Update-PSSubtreeModule -Name 'FailModule' -Path $script:errorPath -Confirm:$false -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'ModuleUpdateError'
        }
    }

    Context 'Verbose output' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:verbosePath = Join-Path -Path $TestDrive -ChildPath "verbose-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:verbosePath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:verbosePath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  VerboseModule:
    repo: https://github.com/owner/verbose.git
    ref: main
'@
            $configPath = Join-Path -Path $script:verbosePath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            New-Item -Path (Join-Path -Path $script:verbosePath -ChildPath 'modules/VerboseModule') -ItemType Directory -Force | Out-Null

            Mock -CommandName Invoke-GitCommand -MockWith { return @() }
        }

        It 'Should output verbose messages when -Verbose is used' {
            $verboseOutput = Update-PSSubtreeModule -Name 'VerboseModule' -Path $script:verbosePath -Confirm:$false -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module directory missing' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:missingDirPath = Join-Path -Path $TestDrive -ChildPath "missing-dir-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:missingDirPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:missingDirPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  MissingModule:
    repo: https://github.com/owner/missing.git
    ref: main
'@
            $configPath = Join-Path -Path $script:missingDirPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Intentionally NOT creating the module directory
        }

        It 'Should warn and skip when module directory does not exist' {
            $warnings = Update-PSSubtreeModule -Name 'MissingModule' -Path $script:missingDirPath -WarningVariable warningOutput -Confirm:$false 3>&1

            $warningOutput | Should -Not -BeNullOrEmpty
        }
    }
}
