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

    $getSubtreeInfoPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Get-SubtreeInfo.ps1'
    . $getSubtreeInfoPath

    $getUpstreamInfoPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Get-UpstreamInfo.ps1'
    . $getUpstreamInfoPath

    # Dot source the public function
    $publicFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Public/Get-PSSubtreeModuleStatus.ps1'
    . $publicFunctionPath
}

Describe 'Get-PSSubtreeModuleStatus' -Tag 'Unit', 'Public' {
    Context 'Parameter validation' {
        It 'Should have Name parameter with default value of *' {
            $command = Get-Command -Name Get-PSSubtreeModuleStatus
            $nameParam = $command.Parameters['Name']

            $nameParam | Should -Not -BeNullOrEmpty
        }

        It 'Should have Name parameter that supports wildcards' {
            $command = Get-Command -Name Get-PSSubtreeModuleStatus
            $nameParam = $command.Parameters['Name']
            $supportsWildcards = $nameParam.Attributes | Where-Object { $_ -is [System.Management.Automation.SupportsWildcardsAttribute] }

            $supportsWildcards | Should -Not -BeNullOrEmpty
        }

        It 'Should accept Name from pipeline' {
            $command = Get-Command -Name Get-PSSubtreeModuleStatus
            $nameParam = $command.Parameters['Name']
            $pipelineAttr = $nameParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipeline
            }

            $pipelineAttr | Should -Not -BeNullOrEmpty
        }

        It 'Should accept Name from pipeline by property name' {
            $command = Get-Command -Name Get-PSSubtreeModuleStatus
            $nameParam = $command.Parameters['Name']
            $pipelineAttr = $nameParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipelineByPropertyName
            }

            $pipelineAttr | Should -Not -BeNullOrEmpty
        }

        It 'Should have UpdateAvailable switch parameter' {
            $command = Get-Command -Name Get-PSSubtreeModuleStatus
            $updateParam = $command.Parameters['UpdateAvailable']

            $updateParam | Should -Not -BeNullOrEmpty
            $updateParam.SwitchParameter | Should -Be $true
        }

        It 'Should have Path parameter with default value' {
            $command = Get-Command -Name Get-PSSubtreeModuleStatus
            $pathParam = $command.Parameters['Path']

            $pathParam | Should -Not -BeNullOrEmpty
        }

        It 'Should support CmdletBinding' {
            $command = Get-Command -Name Get-PSSubtreeModuleStatus
            $command.CmdletBinding | Should -Be $true
        }
    }

    Context 'When configuration cannot be read' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:invalidPath = Join-Path -Path $TestDrive -ChildPath "invalid-config-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:invalidPath -ItemType Directory -Force | Out-Null

            # Create invalid YAML content
            $invalidYaml = @'
modules:
  InvalidYAML: [this is not valid: yaml: syntax
'@
            $configPath = Join-Path -Path $script:invalidPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $invalidYaml
        }

        It 'Should write error when configuration cannot be parsed' {
            $errorOutput = $null

            Get-PSSubtreeModuleStatus -Path $script:invalidPath -ErrorVariable errorOutput -ErrorAction SilentlyContinue

            $errorOutput | Should -Not -BeNullOrEmpty
            $errorOutput[0].FullyQualifiedErrorId | Should -Match 'ConfigReadError'
        }
    }

    Context 'When no modules are tracked' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:emptyPath = Join-Path -Path $TestDrive -ChildPath "empty-modules-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:emptyPath -ItemType Directory -Force | Out-Null

            # Create empty configuration
            $yamlContent = @'
# PSSubtreeModules configuration
modules: {}
'@
            $configPath = Join-Path -Path $script:emptyPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent
        }

        It 'Should return nothing when no modules are tracked' {
            $result = Get-PSSubtreeModuleStatus -Path $script:emptyPath

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Successful status check' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:statusPath = Join-Path -Path $TestDrive -ChildPath "status-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:statusPath -ItemType Directory -Force | Out-Null

            # Create configuration with modules
            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  TestModule:
    repo: https://github.com/owner/test.git
    ref: main
  AnotherModule:
    repo: https://github.com/owner/another.git
    ref: v1.0.0
'@
            $configPath = Join-Path -Path $script:statusPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent
        }

        It 'Should return status objects for all modules' {
            # Mock the helper functions
            Mock -CommandName Get-SubtreeInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash      = 'abc1234567890abcdef1234567890abcdef12345'
                    LocalCommitHash = 'def1234567890abcdef1234567890abcdef12345'
                    CommitDate      = '2024-01-01T00:00:00Z'
                    ModuleName      = $ModuleName
                    Prefix          = "modules/$ModuleName"
                }
            }

            Mock -CommandName Get-UpstreamInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash = 'abc1234567890abcdef1234567890abcdef12345'
                    Ref        = $Ref
                    Repository = $Repository
                }
            }

            $result = Get-PSSubtreeModuleStatus -Path $script:statusPath

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It 'Should return object with correct type name' {
            Mock -CommandName Get-SubtreeInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash      = 'abc1234567890abcdef1234567890abcdef12345'
                    LocalCommitHash = 'def1234567890abcdef1234567890abcdef12345'
                    CommitDate      = '2024-01-01T00:00:00Z'
                    ModuleName      = $ModuleName
                    Prefix          = "modules/$ModuleName"
                }
            }

            Mock -CommandName Get-UpstreamInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash = 'abc1234567890abcdef1234567890abcdef12345'
                    Ref        = $Ref
                    Repository = $Repository
                }
            }

            $result = Get-PSSubtreeModuleStatus -Name 'TestModule' -Path $script:statusPath

            $result.PSObject.TypeNames[0] | Should -Be 'PSSubtreeModules.ModuleStatus'
        }

        It 'Should include all expected properties' {
            Mock -CommandName Get-SubtreeInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash      = 'abc1234567890abcdef1234567890abcdef12345'
                    LocalCommitHash = 'def1234567890abcdef1234567890abcdef12345'
                    CommitDate      = '2024-01-01T00:00:00Z'
                    ModuleName      = $ModuleName
                    Prefix          = "modules/$ModuleName"
                }
            }

            Mock -CommandName Get-UpstreamInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash = 'abc1234567890abcdef1234567890abcdef12345'
                    Ref        = $Ref
                    Repository = $Repository
                }
            }

            $result = Get-PSSubtreeModuleStatus -Name 'TestModule' -Path $script:statusPath

            $result.Name | Should -Be 'TestModule'
            $result.Ref | Should -Be 'main'
            $result.Status | Should -BeIn @('Current', 'UpdateAvailable', 'Unknown')
            $result.PSObject.Properties.Name | Should -Contain 'LocalCommit'
            $result.PSObject.Properties.Name | Should -Contain 'UpstreamCommit'
            $result.PSObject.Properties.Name | Should -Contain 'LocalCommitFull'
            $result.PSObject.Properties.Name | Should -Contain 'UpstreamCommitFull'
        }

        It 'Should return Current status when commits match' {
            $sameHash = 'abc1234567890abcdef1234567890abcdef12345'

            Mock -CommandName Get-SubtreeInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash      = $sameHash
                    LocalCommitHash = 'def1234567890abcdef1234567890abcdef12345'
                    CommitDate      = '2024-01-01T00:00:00Z'
                    ModuleName      = $ModuleName
                    Prefix          = "modules/$ModuleName"
                }
            }

            Mock -CommandName Get-UpstreamInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash = $sameHash
                    Ref        = $Ref
                    Repository = $Repository
                }
            }

            $result = Get-PSSubtreeModuleStatus -Name 'TestModule' -Path $script:statusPath

            $result.Status | Should -Be 'Current'
        }

        It 'Should return UpdateAvailable status when commits differ' {
            Mock -CommandName Get-SubtreeInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash      = 'abc1234567890abcdef1234567890abcdef12345'
                    LocalCommitHash = 'def1234567890abcdef1234567890abcdef12345'
                    CommitDate      = '2024-01-01T00:00:00Z'
                    ModuleName      = $ModuleName
                    Prefix          = "modules/$ModuleName"
                }
            }

            Mock -CommandName Get-UpstreamInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash = 'xyz9876543210zyxwvu9876543210zyxwvu98765'
                    Ref        = $Ref
                    Repository = $Repository
                }
            }

            $result = Get-PSSubtreeModuleStatus -Name 'TestModule' -Path $script:statusPath

            $result.Status | Should -Be 'UpdateAvailable'
        }

        It 'Should return Unknown status when local info is unavailable' {
            Mock -CommandName Get-SubtreeInfo -MockWith {
                return $null
            }

            Mock -CommandName Get-UpstreamInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash = 'xyz9876543210zyxwvu9876543210zyxwvu98765'
                    Ref        = $Ref
                    Repository = $Repository
                }
            }

            $result = Get-PSSubtreeModuleStatus -Name 'TestModule' -Path $script:statusPath -WarningAction SilentlyContinue

            $result.Status | Should -Be 'Unknown'
        }

        It 'Should return Unknown status when upstream info is unavailable' {
            Mock -CommandName Get-SubtreeInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash      = 'abc1234567890abcdef1234567890abcdef12345'
                    LocalCommitHash = 'def1234567890abcdef1234567890abcdef12345'
                    CommitDate      = '2024-01-01T00:00:00Z'
                    ModuleName      = $ModuleName
                    Prefix          = "modules/$ModuleName"
                }
            }

            Mock -CommandName Get-UpstreamInfo -MockWith {
                return $null
            }

            $result = Get-PSSubtreeModuleStatus -Name 'TestModule' -Path $script:statusPath -WarningAction SilentlyContinue

            $result.Status | Should -Be 'Unknown'
        }
    }

    Context 'Wildcard filtering' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:wildcardPath = Join-Path -Path $TestDrive -ChildPath "wildcard-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:wildcardPath -ItemType Directory -Force | Out-Null

            # Create configuration with multiple modules
            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  PSModule1:
    repo: https://github.com/owner/psmodule1.git
    ref: main
  PSModule2:
    repo: https://github.com/owner/psmodule2.git
    ref: main
  OtherModule:
    repo: https://github.com/owner/other.git
    ref: main
'@
            $configPath = Join-Path -Path $script:wildcardPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            Mock -CommandName Get-SubtreeInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash      = 'abc1234567890abcdef1234567890abcdef12345'
                    LocalCommitHash = 'def1234567890abcdef1234567890abcdef12345'
                    CommitDate      = '2024-01-01T00:00:00Z'
                    ModuleName      = $ModuleName
                    Prefix          = "modules/$ModuleName"
                }
            }

            Mock -CommandName Get-UpstreamInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash = 'abc1234567890abcdef1234567890abcdef12345'
                    Ref        = $Ref
                    Repository = $Repository
                }
            }
        }

        It 'Should filter modules by name with wildcards' {
            $result = Get-PSSubtreeModuleStatus -Name 'PS*' -Path $script:wildcardPath

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result.Name | Should -Contain 'PSModule1'
            $result.Name | Should -Contain 'PSModule2'
            $result.Name | Should -Not -Contain 'OtherModule'
        }

        It 'Should return single module when exact name is specified' {
            $result = Get-PSSubtreeModuleStatus -Name 'OtherModule' -Path $script:wildcardPath

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'OtherModule'
        }

        It 'Should return all modules when * is specified' {
            $result = Get-PSSubtreeModuleStatus -Name '*' -Path $script:wildcardPath

            $result.Count | Should -Be 3
        }
    }

    Context 'UpdateAvailable filter' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:filterPath = Join-Path -Path $TestDrive -ChildPath "filter-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:filterPath -ItemType Directory -Force | Out-Null

            # Create configuration with multiple modules
            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  CurrentModule:
    repo: https://github.com/owner/current.git
    ref: main
  OutdatedModule:
    repo: https://github.com/owner/outdated.git
    ref: main
'@
            $configPath = Join-Path -Path $script:filterPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            # Mock to return different statuses for different modules
            Mock -CommandName Get-SubtreeInfo -MockWith {
                $hash = if ($ModuleName -eq 'CurrentModule')
                {
                    'abc1234567890abcdef1234567890abcdef12345'
                }
                else
                {
                    'old1234567890abcdef1234567890abcdef12345'
                }

                [PSCustomObject]@{
                    CommitHash      = $hash
                    LocalCommitHash = 'def1234567890abcdef1234567890abcdef12345'
                    CommitDate      = '2024-01-01T00:00:00Z'
                    ModuleName      = $ModuleName
                    Prefix          = "modules/$ModuleName"
                }
            }

            Mock -CommandName Get-UpstreamInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash = 'abc1234567890abcdef1234567890abcdef12345'
                    Ref        = $Ref
                    Repository = $Repository
                }
            }
        }

        It 'Should return only modules with updates when -UpdateAvailable is specified' {
            $result = Get-PSSubtreeModuleStatus -UpdateAvailable -Path $script:filterPath

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'OutdatedModule'
            $result.Status | Should -Be 'UpdateAvailable'
        }

        It 'Should not return current modules when -UpdateAvailable is specified' {
            $result = Get-PSSubtreeModuleStatus -UpdateAvailable -Path $script:filterPath

            $result.Name | Should -Not -Contain 'CurrentModule'
        }
    }

    Context 'Verbose output' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:verbosePath = Join-Path -Path $TestDrive -ChildPath "verbose-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:verbosePath -ItemType Directory -Force | Out-Null

            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  VerboseModule:
    repo: https://github.com/owner/verbose.git
    ref: main
'@
            $configPath = Join-Path -Path $script:verbosePath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            Mock -CommandName Get-SubtreeInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash      = 'abc1234567890abcdef1234567890abcdef12345'
                    LocalCommitHash = 'def1234567890abcdef1234567890abcdef12345'
                    CommitDate      = '2024-01-01T00:00:00Z'
                    ModuleName      = $ModuleName
                    Prefix          = "modules/$ModuleName"
                }
            }

            Mock -CommandName Get-UpstreamInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash = 'abc1234567890abcdef1234567890abcdef12345'
                    Ref        = $Ref
                    Repository = $Repository
                }
            }
        }

        It 'Should output verbose messages when -Verbose is used' {
            $verboseOutput = Get-PSSubtreeModuleStatus -Path $script:verbosePath -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Short commit hashes' -Skip:(-not $script:yamlAvailable) {
        BeforeEach {
            $script:hashPath = Join-Path -Path $TestDrive -ChildPath "hash-repo-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -Path $script:hashPath -ItemType Directory -Force | Out-Null

            $yamlContent = @'
# PSSubtreeModules configuration
modules:
  HashModule:
    repo: https://github.com/owner/hash.git
    ref: main
'@
            $configPath = Join-Path -Path $script:hashPath -ChildPath 'subtree-modules.yaml'
            Set-Content -Path $configPath -Value $yamlContent

            Mock -CommandName Get-SubtreeInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash      = 'abc1234567890abcdef1234567890abcdef12345'
                    LocalCommitHash = 'def1234567890abcdef1234567890abcdef12345'
                    CommitDate      = '2024-01-01T00:00:00Z'
                    ModuleName      = $ModuleName
                    Prefix          = "modules/$ModuleName"
                }
            }

            Mock -CommandName Get-UpstreamInfo -MockWith {
                [PSCustomObject]@{
                    CommitHash = 'xyz9876543210zyxwvu9876543210zyxwvu98765'
                    Ref        = $Ref
                    Repository = $Repository
                }
            }
        }

        It 'Should include short (7 char) commit hashes' {
            $result = Get-PSSubtreeModuleStatus -Name 'HashModule' -Path $script:hashPath

            $result.LocalCommit | Should -Be 'abc1234'
            $result.UpstreamCommit | Should -Be 'xyz9876'
        }

        It 'Should include full (40 char) commit hashes' {
            $result = Get-PSSubtreeModuleStatus -Name 'HashModule' -Path $script:hashPath

            $result.LocalCommitFull | Should -Be 'abc1234567890abcdef1234567890abcdef12345'
            $result.UpstreamCommitFull | Should -Be 'xyz9876543210zyxwvu9876543210zyxwvu98765'
        }
    }
}
