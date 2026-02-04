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
    $privateFunctionPath = Join-Path -Path $projectPath -ChildPath 'source/Private/Get-SubtreeModulesYamlContent.ps1'
    . $privateFunctionPath
}

Describe 'Get-SubtreeModulesYamlContent' -Tag 'Unit', 'Private' {
    Context 'When called without parameters' {
        It 'Should return a string' {
            $result = Get-SubtreeModulesYamlContent

            $result | Should -BeOfType [string]
        }

        It 'Should return content containing PSSubtreeModules configuration comment' {
            $result = Get-SubtreeModulesYamlContent

            $result | Should -Match '# PSSubtreeModules configuration'
        }

        It 'Should return content containing modules key' {
            $result = Get-SubtreeModulesYamlContent

            $result | Should -Match 'modules:'
        }

        It 'Should return valid YAML content' {
            # Import powershell-yaml if available to validate
            $yamlAvailable = $null -ne (Get-Module -Name powershell-yaml -ListAvailable)
            if ($yamlAvailable)
            {
                Import-Module powershell-yaml -ErrorAction SilentlyContinue
            }

            $result = Get-SubtreeModulesYamlContent

            if ($yamlAvailable)
            {
                { ConvertFrom-Yaml -Yaml $result } | Should -Not -Throw
            }
            else
            {
                # If powershell-yaml not available, just check it's not empty
                $result | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should return content with empty modules collection' {
            $result = Get-SubtreeModulesYamlContent

            $result | Should -Match 'modules:\s*\{\}'
        }
    }

    Context 'Verbose output' {
        It 'Should support -Verbose parameter' {
            { Get-SubtreeModulesYamlContent -Verbose } | Should -Not -Throw
        }
    }
}
