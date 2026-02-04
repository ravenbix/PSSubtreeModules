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
    $publicFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Public/Remove-PSSubtreeModule.ps1'
    . $publicFunctionPath
}

Describe 'Remove-PSSubtreeModule' -Tag 'Unit', 'Public' {
    Context 'Parameter validation' {
        It 'Should have Name as mandatory parameter' {
            $command = Get-Command -Name Remove-PSSubtreeModule
            $nameParam = $command.Parameters['Name']

            $nameParam | Should -Not -BeNullOrEmpty
            $mandatory = $nameParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
            }
            $mandatory | Should -Not -BeNullOrEmpty
        }

        It 'Should accept Name from pipeline' {
            $command = Get-Command -Name Remove-PSSubtreeModule
            $nameParam = $command.Parameters['Name']
            $pipelineAttr = $nameParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipeline
            }

            $pipelineAttr | Should -Not -BeNullOrEmpty
        }

        It 'Should accept Name from pipeline by property name' {
            $command = Get-Command -Name Remove-PSSubtreeModule
            $nameParam = $command.Parameters['Name']
            $pipelineAttr = $nameParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipelineByPropertyName
            }

            $pipelineAttr | Should -Not -BeNullOrEmpty
        }

        It 'Should have Force switch parameter' {
            $command = Get-Command -Name Remove-PSSubtreeModule
            $forceParam = $command.Parameters['Force']

            $forceParam | Should -Not -BeNullOrEmpty
            $forceParam.SwitchParameter | Should -Be $true
        }

        It 'Should have Path parameter with default value' {
            $command = Get-Command -Name Remove-PSSubtreeModule
            $pathParam = $command.Parameters['Path']

            $pathParam | Should -Not -BeNullOrEmpty
        }

        It 'Should support ShouldProcess' {
            $command = Get-Command -Name Remove-PSSubtreeModule
            $command.CmdletBinding | Should -Be $true
        }

        It 'Should have High ConfirmImpact' {
            $command = Get-Command -Name Remove-PSSubtreeModule
            $cmdletBindingAttr = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

            $cmdletBindingAttr.ConfirmImpact | Should -Be 'High'
        }

        It 'Should validate Name parameter with pattern' {
            $command = Get-Command -Name Remove-PSSubtreeModule
            $nameParam = $command.Parameters['Name']
            $validatePattern = $nameParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }

            $validatePattern | Should -Not -BeNullOrEmpty
            $validatePattern.RegexPattern | Should -Be '^[a-zA-Z0-9_.-]+$'
        }

        It 'Should reject invalid module names with spaces' {
            { Remove-PSSubtreeModule -Name 'Invalid Name' -Path $TestDrive -WhatIf } | Should -Throw
        }

        It 'Should reject invalid module names with special characters' {
            { Remove-PSSubtreeModule -Name 'Invalid@Name' -Path $TestDrive -WhatIf } | Should -Throw
        }
    }

    Context 'When path does not exist' {
        It 'Should write error for non-existent path' {
            $nonExistentPath = Join-Path -Path $TestDrive -ChildPath "does-not-exist-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            $errorOutput = $null

            Remove-PSSubtreeModule -Name 'TestModule' -Path $nonExistentPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

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

            Remove-PSSubtreeModule -Name 'TestModule' -Path $script:nonGitPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

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

            Remove-PSSubtreeModule -Name 'TestModule' -Path $script:uninitializedPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

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
            $warnings = Remove-PSSubtreeModule -Name 'TestModule' -Path $script:emptyPath -Force -WarningVariable warningOutput -WarningAction SilentlyContinue 3>&1

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

            Remove-PSSubtreeModule -Name 'NonExistentModule' -Path $script:trackedPath -Force -ErrorVariable errorOutput -ErrorAction SilentlyContinue

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

            Remove-PSSubtreeModule -Name 'TestModule' -Path $script:whatifPath -WhatIf

            Should -Invoke -CommandName Invoke-GitCommand -Times 0
        }

        It 'Should not modify configuration when -WhatIf is specified' {
            Remove-PSSubtreeModule -Name 'TestModule' -Path $script:whatifPath -WhatIf

            $content = Get-Content -Path (Join-Path -Path $script:whatifPath -ChildPath 'subtree-modules.yaml') -Raw
            $content | Should -Match 'TestModule'
        }

        It 'Should not remove module directory when -WhatIf is specified' {
            Remove-PSSubtreeModule -Name 'TestModule' -Path $script:whatifPath -WhatIf

            Test-Path -Path (Join-Path -Path $script:whatifPath -ChildPath 'modules/TestModule') | Should -Be $true
        }
    }

    Context 'Successful module removal' -Skip:(-not $script:yamlAvailable) {
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

        It 'Should call git rm with correct arguments' {
            Remove-PSSubtreeModule -Name 'TestModule' -Path $script:successPath -Force

            Should -Invoke -CommandName Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'rm' -and
                $Arguments -contains '-rf' -and
                $Arguments -contains 'modules/TestModule'
            }
        }

        It 'Should update configuration to remove module' {
            Remove-PSSubtreeModule -Name 'TestModule' -Path $script:successPath -Force

            $content = Get-Content -Path (Join-Path -Path $script:successPath -ChildPath 'subtree-modules.yaml') -Raw
            $content | Should -Not -Match 'TestModule'
        }

        It 'Should return PSCustomObject with module info' {
            $result = Remove-PSSubtreeModule -Name 'TestModule' -Path $script:successPath -Force

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'TestModule'
            $result.Repository | Should -Be 'https://github.com/owner/test.git'
            $result.Ref | Should -Be 'main'
        }

        It 'Should return object with correct type name' {
            $result = Remove-PSSubtreeModule -Name 'TestModule' -Path $script:successPath -Force

            $result.PSObject.TypeNames[0] | Should -Be 'PSSubtreeModules.ModuleInfo'
        }

        It 'Should create conventional commit message' {
            Remove-PSSubtreeModule -Name 'TestModule' -Path $script:successPath -Force

            Should -Invoke -CommandName Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'commit' -and
                $Arguments -contains '-m' -and
                $Arguments -contains 'feat(modules): remove TestModule'
            }
        }
    }

    Context 'Module directory does not exist' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:missingDirPath = Join-Path -Path $TestDrive -ChildPath "missing-dir-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:missingDirPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:missingDirPath -ChildPath '.git') -ItemType Directory -Force | Out-Null

            # Create configuration with a module, but don't create the directory
            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  MissingModule:
    repo: https://github.com/owner/missing.git
    ref: main
'@
            $configPath = Join-Path -Path $script:missingDirPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            Mock -CommandName Invoke-GitCommand -MockWith {
                return @()
            }
        }

        It 'Should warn but still remove from config when directory is missing' {
            $warnings = Remove-PSSubtreeModule -Name 'MissingModule' -Path $script:missingDirPath -Force -WarningVariable warningOutput 3>&1

            $warningOutput | Should -Not -BeNullOrEmpty
            $warningOutput[0].Message | Should -Match 'does not exist'
        }

        It 'Should remove module from configuration even when directory is missing' {
            Remove-PSSubtreeModule -Name 'MissingModule' -Path $script:missingDirPath -Force

            $content = Get-Content -Path (Join-Path -Path $script:missingDirPath -ChildPath 'subtree-modules.yaml') -Raw
            $content | Should -Not -Match 'MissingModule'
        }

        It 'Should not call git rm when directory is missing' {
            Remove-PSSubtreeModule -Name 'MissingModule' -Path $script:missingDirPath -Force

            Should -Not -Invoke -CommandName Invoke-GitCommand -ParameterFilter {
                $Arguments -contains 'rm'
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

        It 'Should write error when git rm fails' {
            Mock -CommandName Invoke-GitCommand -MockWith {
                throw 'Git rm failed'
            }

            $errorOutput = $null
            Remove-PSSubtreeModule -Name 'FailModule' -Path $script:errorPath -Force -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'ModuleRemoveError'
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
            $verboseOutput = Remove-PSSubtreeModule -Name 'VerboseModule' -Path $script:verbosePath -Force -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }
}
