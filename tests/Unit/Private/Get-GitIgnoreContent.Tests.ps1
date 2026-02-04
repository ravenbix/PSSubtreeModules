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
    $privateFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Get-GitIgnoreContent.ps1'
    . $privateFunctionPath
}

Describe 'Get-GitIgnoreContent' -Tag 'Unit', 'Private' {
    Context 'When called without parameters' {
        It 'Should return a string' {
            $result = Get-GitIgnoreContent

            $result | Should -BeOfType [string]
        }

        It 'Should return content containing header comment' {
            $result = Get-GitIgnoreContent

            $result | Should -Match '# PSSubtreeModules .gitignore'
        }

        It 'Should contain output directory pattern' {
            $result = Get-GitIgnoreContent

            $result | Should -Match 'output/'
        }

        It 'Should contain temporary file patterns' {
            $result = Get-GitIgnoreContent

            $result | Should -Match '\*\.tmp'
            $result | Should -Match '\*~'
        }

        It 'Should contain IDE/editor file patterns' {
            $result = Get-GitIgnoreContent

            $result | Should -Match '\.vscode/'
            $result | Should -Match '\.idea/'
        }

        It 'Should contain macOS-specific patterns' {
            $result = Get-GitIgnoreContent

            $result | Should -Match '\.DS_Store'
        }

        It 'Should contain Windows-specific patterns' {
            $result = Get-GitIgnoreContent

            $result | Should -Match 'Thumbs\.db'
            $result | Should -Match 'desktop\.ini'
        }
    }

    Context 'Verbose output' {
        It 'Should support -Verbose parameter' {
            { Get-GitIgnoreContent -Verbose } | Should -Not -Throw
        }
    }
}
