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

    # Dot source the private function
    $privateFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Get-ReadmeContent.ps1'
    . $privateFunctionPath
}

Describe 'Get-ReadmeContent' -Tag 'Unit', 'Private' {
    Context 'When called without parameters' {
        It 'Should return a string' {
            $result = Get-ReadmeContent

            $result | Should -BeOfType [string]
        }

        It 'Should return content containing markdown header' {
            $result = Get-ReadmeContent

            $result | Should -Match '# PowerShell Modules'
        }

        It 'Should contain Quick Start section' {
            $result = Get-ReadmeContent

            $result | Should -Match '## Quick Start'
        }

        It 'Should contain Add-PSSubtreeModule example' {
            $result = Get-ReadmeContent

            $result | Should -Match 'Add-PSSubtreeModule'
        }

        It 'Should contain Get-PSSubtreeModule example' {
            $result = Get-ReadmeContent

            $result | Should -Match 'Get-PSSubtreeModule'
        }

        It 'Should contain Update-PSSubtreeModule example' {
            $result = Get-ReadmeContent

            $result | Should -Match 'Update-PSSubtreeModule'
        }

        It 'Should contain Remove-PSSubtreeModule example' {
            $result = Get-ReadmeContent

            $result | Should -Match 'Remove-PSSubtreeModule'
        }

        It 'Should contain Using the Modules section' {
            $result = Get-ReadmeContent

            $result | Should -Match '## Using the Modules'
        }

        It 'Should contain Module Configuration section' {
            $result = Get-ReadmeContent

            $result | Should -Match '## Module Configuration'
        }

        It 'Should contain subtree-modules.yaml reference' {
            $result = Get-ReadmeContent

            $result | Should -Match 'subtree-modules\.yaml'
        }

        It 'Should contain Requirements section' {
            $result = Get-ReadmeContent

            $result | Should -Match '## Requirements'
        }

        It 'Should contain PSModulePath reference' {
            $result = Get-ReadmeContent

            $result | Should -Match 'PSModulePath'
        }
    }

    Context 'Verbose output' {
        It 'Should support -Verbose parameter' {
            { Get-ReadmeContent -Verbose } | Should -Not -Throw
        }
    }
}
