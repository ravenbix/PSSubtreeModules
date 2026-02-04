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
    $privateFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Get-CheckUpdatesWorkflowContent.ps1'
    . $privateFunctionPath
}

Describe 'Get-CheckUpdatesWorkflowContent' -Tag 'Unit', 'Private' {
    Context 'When called without parameters' {
        It 'Should return a string' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -BeOfType [string]
        }

        It 'Should return content containing workflow name' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -Match 'name: Check Module Updates'
        }

        It 'Should contain workflow_dispatch trigger' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -Match 'workflow_dispatch'
        }

        It 'Should contain commented schedule section' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -Match '# schedule:'
        }

        It 'Should contain check-updates job' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -Match 'check-updates:'
        }

        It 'Should run on ubuntu-latest' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -Match 'runs-on: ubuntu-latest'
        }

        It 'Should request issues write permission' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -Match 'issues: write'
        }

        It 'Should use actions/checkout' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -Match 'uses: actions/checkout'
        }

        It 'Should install PSSubtreeModules module' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -Match 'Install-Module -Name PSSubtreeModules'
        }

        It 'Should call Get-PSSubtreeModuleStatus -UpdateAvailable' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -Match 'Get-PSSubtreeModuleStatus -UpdateAvailable'
        }

        It 'Should use actions/github-script for issue management' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -Match 'uses: actions/github-script'
        }

        It 'Should create issues with appropriate labels' {
            $result = Get-CheckUpdatesWorkflowContent

            $result | Should -Match "'dependencies'"
            $result | Should -Match "'automated'"
        }
    }

    Context 'Verbose output' {
        It 'Should support -Verbose parameter' {
            { Get-CheckUpdatesWorkflowContent -Verbose } | Should -Not -Throw
        }
    }
}
