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

    # Dot source the public function
    $publicFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Public/Install-PSSubtreeModuleProfile.ps1'
    . $publicFunctionPath
}

Describe 'Install-PSSubtreeModuleProfile' -Tag 'Unit', 'Public' {
    Context 'Parameter validation' {
        It 'Should have Path parameter' {
            $command = Get-Command -Name Install-PSSubtreeModuleProfile
            $pathParam = $command.Parameters['Path']

            $pathParam | Should -Not -BeNullOrEmpty
        }

        It 'Should have ProfilePath parameter' {
            $command = Get-Command -Name Install-PSSubtreeModuleProfile
            $profilePathParam = $command.Parameters['ProfilePath']

            $profilePathParam | Should -Not -BeNullOrEmpty
        }

        It 'Should have Force switch parameter' {
            $command = Get-Command -Name Install-PSSubtreeModuleProfile
            $forceParam = $command.Parameters['Force']

            $forceParam | Should -Not -BeNullOrEmpty
            $forceParam.SwitchParameter | Should -Be $true
        }

        It 'Should have SupportsShouldProcess attribute' {
            $command = Get-Command -Name Install-PSSubtreeModuleProfile
            $cmdletBinding = $command.CmdletBinding

            $cmdletBinding | Should -Be $true
        }

        It 'Should have CmdletBinding attribute with SupportsShouldProcess' {
            $command = Get-Command -Name Install-PSSubtreeModuleProfile
            $meta = [System.Management.Automation.CommandMetadata]::new($command)

            $meta.SupportsShouldProcess | Should -Be $true
        }
    }

    Context 'When path does not exist' {
        It 'Should write error when path does not exist' {
            $nonExistentPath = Join-Path -Path $TestDrive -ChildPath 'does-not-exist'
            $testProfilePath = Join-Path -Path $TestDrive -ChildPath 'test-profile.ps1'

            { Install-PSSubtreeModuleProfile -Path $nonExistentPath -ProfilePath $testProfilePath -ErrorAction Stop } |
                Should -Throw '*does not exist*'
        }
    }

    Context 'When modules directory does not exist' {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "no-modules-dir-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
        }

        It 'Should write error when modules directory does not exist' {
            $testProfilePath = Join-Path -Path $TestDrive -ChildPath 'test-profile-no-modules.ps1'

            { Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $testProfilePath -ErrorAction Stop } |
                Should -Throw '*modules directory does not exist*'
        }
    }

    Context 'When installing to a new profile' {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "new-profile-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:testRepoPath -ChildPath 'modules') -ItemType Directory -Force | Out-Null

            $script:testProfilePath = Join-Path -Path $TestDrive -ChildPath "test-profile-new-$([Guid]::NewGuid().ToString().Substring(0,8)).ps1"
        }

        AfterAll {
            if (Test-Path -Path $script:testProfilePath)
            {
                Remove-Item -Path $script:testProfilePath -Force
            }
        }

        It 'Should create profile file if it does not exist' {
            $result = Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath

            Test-Path -Path $script:testProfilePath | Should -Be $true
        }

        It 'Should return result object with correct type name' {
            $result = Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            $result.PSObject.TypeNames[0] | Should -Be 'PSSubtreeModules.ProfileInstallation'
        }

        It 'Should return result with ProfilePath property' {
            $result = Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            $result.ProfilePath | Should -Be $script:testProfilePath
        }

        It 'Should return result with ModulesPath property' {
            $result = Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            $result.ModulesPath | Should -BeLike '*modules'
        }

        It 'Should return result with Status property' {
            $result = Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            $result.Status | Should -BeIn @('Installed', 'AlreadyConfigured')
        }

        It 'Should add PSSubtreeModules marker comment to profile' {
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            $content = Get-Content -Path $script:testProfilePath -Raw
            $content | Should -BeLike '*# PSSubtreeModules:*'
        }

        It 'Should add PSModulePath modification code to profile' {
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            $content = Get-Content -Path $script:testProfilePath -Raw
            $content | Should -BeLike '*PSModulePath*'
        }
    }

    Context 'When profile already has configuration (idempotency)' {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "idempotent-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            $modulesPath = Join-Path -Path $script:testRepoPath -ChildPath 'modules'
            New-Item -Path $modulesPath -ItemType Directory -Force | Out-Null

            $script:testProfilePath = Join-Path -Path $TestDrive -ChildPath "test-profile-idempotent-$([Guid]::NewGuid().ToString().Substring(0,8)).ps1"

            # Install initially
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath
        }

        AfterAll {
            if (Test-Path -Path $script:testProfilePath)
            {
                Remove-Item -Path $script:testProfilePath -Force
            }
        }

        It 'Should return AlreadyConfigured status without Force' {
            $result = Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -WarningAction SilentlyContinue

            $result.Status | Should -Be 'AlreadyConfigured'
        }

        It 'Should not duplicate configuration' {
            # Run twice more without Force
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -WarningAction SilentlyContinue
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -WarningAction SilentlyContinue

            $content = Get-Content -Path $script:testProfilePath -Raw
            $matches = [regex]::Matches($content, '# PSSubtreeModules:')

            $matches.Count | Should -Be 1
        }

        It 'Should output warning when already configured' {
            $warningOutput = Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -WarningVariable warnings 3>&1

            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When using -Force parameter' {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "force-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:testRepoPath -ChildPath 'modules') -ItemType Directory -Force | Out-Null

            $script:testProfilePath = Join-Path -Path $TestDrive -ChildPath "test-profile-force-$([Guid]::NewGuid().ToString().Substring(0,8)).ps1"

            # Create profile with existing content including PSSubtreeModules
            $existingContent = @'
# Existing profile content
Write-Host "Loading profile..."

# PSSubtreeModules: /old/path/modules
if (Test-Path -Path '/old/path/modules') {
    $env:PSModulePath = '/old/path/modules' + [System.IO.Path]::PathSeparator + $env:PSModulePath
}
# End PSSubtreeModules

# More existing content
Set-Alias ll Get-ChildItem
'@
            Set-Content -Path $script:testProfilePath -Value $existingContent
        }

        AfterAll {
            if (Test-Path -Path $script:testProfilePath)
            {
                Remove-Item -Path $script:testProfilePath -Force
            }
        }

        It 'Should return Installed status with Force' {
            $result = Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            $result.Status | Should -Be 'Installed'
        }

        It 'Should replace existing configuration with Force' {
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            $content = Get-Content -Path $script:testProfilePath -Raw

            # Old path should be removed
            $content | Should -Not -BeLike '*old/path/modules*'

            # New path should be present
            $modulesPath = Join-Path -Path $script:testRepoPath -ChildPath 'modules'
            $content | Should -BeLike "*# PSSubtreeModules: $modulesPath*"
        }

        It 'Should preserve other profile content with Force' {
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            $content = Get-Content -Path $script:testProfilePath -Raw

            $content | Should -BeLike '*Existing profile content*'
            $content | Should -BeLike '*Set-Alias ll*'
        }
    }

    Context 'When using -WhatIf parameter' {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "whatif-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:testRepoPath -ChildPath 'modules') -ItemType Directory -Force | Out-Null

            $script:testProfilePath = Join-Path -Path $TestDrive -ChildPath "test-profile-whatif-$([Guid]::NewGuid().ToString().Substring(0,8)).ps1"
        }

        It 'Should not create profile file with -WhatIf' {
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -WhatIf

            Test-Path -Path $script:testProfilePath | Should -Be $false
        }

        It 'Should not modify existing profile with -WhatIf' {
            $existingContent = "# Existing profile`nWrite-Host 'Hello'"
            Set-Content -Path $script:testProfilePath -Value $existingContent

            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -WhatIf

            $content = Get-Content -Path $script:testProfilePath -Raw
            $content | Should -Not -BeLike '*PSSubtreeModules*'
        }

        AfterAll {
            if (Test-Path -Path $script:testProfilePath)
            {
                Remove-Item -Path $script:testProfilePath -Force
            }
        }
    }

    Context 'AppliedToCurrentSession behavior' {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "session-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:testRepoPath -ChildPath 'modules') -ItemType Directory -Force | Out-Null

            $script:testProfilePath = Join-Path -Path $TestDrive -ChildPath "test-profile-session-$([Guid]::NewGuid().ToString().Substring(0,8)).ps1"

            # Save current PSModulePath
            $script:originalPSModulePath = $env:PSModulePath
        }

        AfterEach {
            # Restore original PSModulePath
            $env:PSModulePath = $script:originalPSModulePath
        }

        AfterAll {
            if (Test-Path -Path $script:testProfilePath)
            {
                Remove-Item -Path $script:testProfilePath -Force
            }
        }

        It 'Should return AppliedToCurrentSession property' {
            $result = Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath

            $result.AppliedToCurrentSession | Should -BeIn @($true, $false)
        }

        It 'Should add modules path to current session PSModulePath' {
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            $modulesPath = Join-Path -Path $script:testRepoPath -ChildPath 'modules'
            $env:PSModulePath | Should -BeLike "*$modulesPath*"
        }
    }

    Context 'Verbose output' {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "verbose-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:testRepoPath -ChildPath 'modules') -ItemType Directory -Force | Out-Null

            $script:testProfilePath = Join-Path -Path $TestDrive -ChildPath "test-profile-verbose-$([Guid]::NewGuid().ToString().Substring(0,8)).ps1"
        }

        AfterAll {
            if (Test-Path -Path $script:testProfilePath)
            {
                Remove-Item -Path $script:testProfilePath -Force
            }
        }

        It 'Should output verbose messages when -Verbose is used' {
            $verboseOutput = Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }

        It 'Should include profile path in verbose output' {
            $verboseOutput = Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force -Verbose 4>&1

            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseText = ($verboseMessages | ForEach-Object { $_.Message }) -join "`n"
            $verboseText | Should -BeLike '*profile*'
        }
    }

    Context 'Profile directory creation' {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "dir-create-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:testRepoPath -ChildPath 'modules') -ItemType Directory -Force | Out-Null

            $script:newProfileDir = Join-Path -Path $TestDrive -ChildPath "new-profile-dir-$([Guid]::NewGuid().ToString().Substring(0,8))"
            $script:testProfilePath = Join-Path -Path $script:newProfileDir -ChildPath 'profile.ps1'
        }

        AfterAll {
            if (Test-Path -Path $script:newProfileDir)
            {
                Remove-Item -Path $script:newProfileDir -Recurse -Force
            }
        }

        It 'Should create profile directory if it does not exist' {
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath

            Test-Path -Path $script:newProfileDir -PathType Container | Should -Be $true
        }

        It 'Should create profile file in new directory' {
            # May have been created in previous test, but should still exist
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            Test-Path -Path $script:testProfilePath -PathType Leaf | Should -Be $true
        }
    }

    Context 'Default path behavior' {
        BeforeAll {
            # Save original location
            $script:originalLocation = Get-Location
        }

        AfterAll {
            # Restore original location
            Set-Location -Path $script:originalLocation
        }

        It 'Should use current directory when Path not specified' {
            $testPath = Join-Path -Path $TestDrive -ChildPath "default-path-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $testPath -ChildPath 'modules') -ItemType Directory -Force | Out-Null

            $testProfilePath = Join-Path -Path $TestDrive -ChildPath "default-profile-$([Guid]::NewGuid().ToString().Substring(0,8)).ps1"

            Set-Location -Path $testPath

            $result = Install-PSSubtreeModuleProfile -ProfilePath $testProfilePath

            $result.ModulesPath | Should -BeLike "$testPath*modules"

            # Cleanup
            if (Test-Path -Path $testProfilePath)
            {
                Remove-Item -Path $testProfilePath -Force
            }
        }
    }

    Context 'Existing profile modification' {
        BeforeAll {
            $script:testRepoPath = Join-Path -Path $TestDrive -ChildPath "modify-profile-repo-$([Guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -Path $script:testRepoPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:testRepoPath -ChildPath 'modules') -ItemType Directory -Force | Out-Null

            $script:testProfilePath = Join-Path -Path $TestDrive -ChildPath "test-profile-modify-$([Guid]::NewGuid().ToString().Substring(0,8)).ps1"

            # Create existing profile
            $existingContent = @'
# My PowerShell Profile
$env:EDITOR = 'code'

function prompt {
    "PS> "
}
'@
            Set-Content -Path $script:testProfilePath -Value $existingContent
        }

        AfterAll {
            if (Test-Path -Path $script:testProfilePath)
            {
                Remove-Item -Path $script:testProfilePath -Force
            }
        }

        It 'Should append to existing profile content' {
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath

            $content = Get-Content -Path $script:testProfilePath -Raw

            # Original content should still be present
            $content | Should -BeLike '*My PowerShell Profile*'
            $content | Should -BeLike '*EDITOR*'
            $content | Should -BeLike '*function prompt*'

            # New content should be added
            $content | Should -BeLike '*PSSubtreeModules*'
        }

        It 'Should add End marker comment' {
            Install-PSSubtreeModuleProfile -Path $script:testRepoPath -ProfilePath $script:testProfilePath -Force

            $content = Get-Content -Path $script:testProfilePath -Raw
            $content | Should -BeLike '*# End PSSubtreeModules*'
        }
    }
}
