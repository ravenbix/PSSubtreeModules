function Get-ModuleConfig
{
    <#
    .SYNOPSIS
        Reads the subtree-modules.yaml configuration file.

    .DESCRIPTION
        Reads and parses the subtree-modules.yaml configuration file from the specified
        path. Uses the powershell-yaml module with the -Ordered flag to preserve key
        ordering in the configuration. If the configuration file does not exist, returns
        a default configuration structure with an empty modules collection.

    .PARAMETER Path
        The path to the subtree-modules.yaml configuration file. If not specified,
        defaults to 'subtree-modules.yaml' in the current working directory.

    .EXAMPLE
        Get-ModuleConfig

        Reads the configuration from 'subtree-modules.yaml' in the current directory.

    .EXAMPLE
        Get-ModuleConfig -Path 'C:\repos\my-modules\subtree-modules.yaml'

        Reads the configuration from a specific path.

    .EXAMPLE
        $config = Get-ModuleConfig
        $config.modules.Keys

        Gets all module names from the configuration.

    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary
        Returns an ordered hashtable containing the configuration with a 'modules' key.

    .NOTES
        This is a private helper function used internally by PSSubtreeModules.
        The configuration file format is:

        modules:
          ModuleName:
            repo: https://github.com/owner/repo.git
            ref: main
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param
    (
        [Parameter(Position = 0)]
        [string]
        $Path = (Join-Path -Path (Get-Location) -ChildPath 'subtree-modules.yaml')
    )

    begin
    {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"
    }

    process
    {
        Write-Verbose "Reading configuration from: $Path"

        # Return default structure if file doesn't exist
        if (-not (Test-Path -Path $Path))
        {
            Write-Verbose "Configuration file not found. Returning default structure."
            return [ordered]@{
                modules = [ordered]@{}
            }
        }

        try
        {
            # Read the file content
            $content = Get-Content -Path $Path -Raw -ErrorAction Stop

            # Handle empty file
            if ([string]::IsNullOrWhiteSpace($content))
            {
                Write-Verbose "Configuration file is empty. Returning default structure."
                return [ordered]@{
                    modules = [ordered]@{}
                }
            }

            # Parse YAML with ordered keys
            Write-Verbose "Parsing YAML configuration"
            $config = $content | ConvertFrom-Yaml -Ordered

            # Ensure modules key exists (use Contains for OrderedDictionary compatibility)
            if (-not $config.Contains('modules'))
            {
                Write-Verbose "Configuration missing 'modules' key. Adding empty modules collection."
                $config['modules'] = [ordered]@{}
            }

            # Ensure modules is an ordered dictionary
            if ($null -eq $config['modules'])
            {
                $config['modules'] = [ordered]@{}
            }

            return $config
        }
        catch
        {
            $errorMessage = "Failed to read or parse configuration file '$Path': $($_.Exception.Message)"
            Write-Error -Message $errorMessage -Category InvalidData -ErrorId 'ConfigParseError'
            throw
        }
    }

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
