function Save-ModuleConfig
{
    <#
    .SYNOPSIS
        Writes the subtree-modules.yaml configuration file.

    .DESCRIPTION
        Writes the provided configuration to the subtree-modules.yaml file at the specified
        path. Uses the powershell-yaml module to convert the configuration to YAML format.
        Preserves ordered hashtables when writing to maintain consistent key ordering.
        Includes a header comment in the output file for documentation.

    .PARAMETER Configuration
        The configuration to write. Should be an ordered hashtable with a 'modules' key
        containing module definitions. Each module should have 'repo' and 'ref' keys.

    .PARAMETER Path
        The path to write the subtree-modules.yaml configuration file. If not specified,
        defaults to 'subtree-modules.yaml' in the current working directory.

    .EXAMPLE
        $config = [ordered]@{
            modules = [ordered]@{
                'MyModule' = [ordered]@{
                    repo = 'https://github.com/owner/repo.git'
                    ref = 'main'
                }
            }
        }
        Save-ModuleConfig -Configuration $config

        Writes the configuration to 'subtree-modules.yaml' in the current directory.

    .EXAMPLE
        Save-ModuleConfig -Configuration $config -Path 'C:\repos\my-modules\subtree-modules.yaml'

        Writes the configuration to a specific path.

    .EXAMPLE
        $config = Get-ModuleConfig
        $config.modules['NewModule'] = [ordered]@{ repo = 'https://github.com/owner/new.git'; ref = 'v1.0.0' }
        Save-ModuleConfig -Configuration $config

        Adds a new module to the existing configuration and saves it.

    .OUTPUTS
        None. This function does not return any output.

    .NOTES
        This is a private helper function used internally by PSSubtreeModules.
        The configuration file format is:

        # PSSubtreeModules configuration
        modules:
          ModuleName:
            repo: https://github.com/owner/repo.git
            ref: main
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [System.Collections.Specialized.OrderedDictionary]
        $Configuration,

        [Parameter(Position = 1)]
        [string]
        $Path = (Join-Path -Path (Get-Location) -ChildPath 'subtree-modules.yaml')
    )

    begin
    {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"
    }

    process
    {
        Write-Verbose "Writing configuration to: $Path"

        try
        {
            # Validate configuration structure
            if (-not $Configuration.ContainsKey('modules'))
            {
                Write-Verbose "Configuration missing 'modules' key. Adding empty modules collection."
                $Configuration['modules'] = [ordered]@{}
            }

            # Convert configuration to YAML
            Write-Verbose "Converting configuration to YAML format"
            $yamlContent = ConvertTo-Yaml -Data $Configuration

            # Build output with header comment
            $header = "# PSSubtreeModules configuration"
            $output = @($header, $yamlContent) -join [Environment]::NewLine

            # Ensure parent directory exists
            $parentDir = Split-Path -Path $Path -Parent
            if ($parentDir -and -not (Test-Path -Path $parentDir))
            {
                Write-Verbose "Creating parent directory: $parentDir"
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }

            # Write to file
            Write-Verbose "Writing YAML content to file"
            Set-Content -Path $Path -Value $output -Encoding UTF8 -NoNewline -ErrorAction Stop

            Write-Verbose "Configuration saved successfully"
        }
        catch
        {
            $errorMessage = "Failed to write configuration file '$Path': $($_.Exception.Message)"
            Write-Error -Message $errorMessage -Category WriteError -ErrorId 'ConfigWriteError'
            throw
        }
    }

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
