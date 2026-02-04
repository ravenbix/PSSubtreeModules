function Get-PSSubtreeModule
{
    <#
    .SYNOPSIS
        Lists all tracked modules managed by PSSubtreeModules.

    .DESCRIPTION
        Retrieves information about modules tracked in the subtree-modules.yaml
        configuration file. Returns objects containing the module name, repository
        URL, and reference (branch or tag) for each tracked module.

        Supports wildcard filtering to find specific modules by name pattern.

    .PARAMETER Name
        The name of the module(s) to retrieve. Supports wildcard characters.
        If not specified, defaults to '*' which returns all modules.

    .PARAMETER Path
        The path to the repository containing the subtree-modules.yaml configuration.
        If not specified, defaults to the current working directory.

    .EXAMPLE
        Get-PSSubtreeModule

        Returns all tracked modules.

    .EXAMPLE
        Get-PSSubtreeModule -Name 'Pester'

        Returns the module named 'Pester' if it exists.

    .EXAMPLE
        Get-PSSubtreeModule -Name 'PS*'

        Returns all modules whose names start with 'PS'.

    .EXAMPLE
        Get-PSSubtreeModule -Name '*Logger*'

        Returns all modules containing 'Logger' in their name.

    .EXAMPLE
        Get-PSSubtreeModule -Path 'C:\repos\my-modules'

        Returns all modules from a specific repository.

    .OUTPUTS
        PSCustomObject
        Returns objects with the following properties:
        - Name: The module name
        - Repository: The source repository URL
        - Ref: The branch, tag, or commit reference

    .NOTES
        The configuration is read from subtree-modules.yaml in the repository root.
        If no modules are tracked, an empty result is returned (not an error).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [SupportsWildcards()]
        [string]
        $Name = '*',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path = (Get-Location)
    )

    begin
    {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"
    }

    process
    {
        # Resolve the configuration file path
        $configPath = Join-Path -Path $Path -ChildPath 'subtree-modules.yaml'
        Write-Verbose "Reading configuration from: $configPath"

        # Read the configuration
        try
        {
            $config = Get-ModuleConfig -Path $configPath
        }
        catch
        {
            $errorMessage = "Failed to read module configuration: $($_.Exception.Message)"
            Write-Error -Message $errorMessage -Category ReadError -ErrorId 'ConfigReadError'
            return
        }

        # Check if there are any modules configured
        if ($null -eq $config.modules -or $config.modules.Count -eq 0)
        {
            Write-Verbose "No modules are currently tracked."
            return
        }

        Write-Verbose "Found $($config.modules.Count) tracked module(s)"
        Write-Verbose "Filtering with pattern: $Name"

        # Iterate through modules and filter by name pattern
        foreach ($moduleName in $config.modules.Keys)
        {
            # Use -like operator for wildcard matching
            if ($moduleName -like $Name)
            {
                $moduleInfo = $config.modules[$moduleName]

                Write-Verbose "Returning module: $moduleName"

                # Create and output the result object
                [PSCustomObject]@{
                    PSTypeName = 'PSSubtreeModules.ModuleInfo'
                    Name       = $moduleName
                    Repository = $moduleInfo.repo
                    Ref        = $moduleInfo.ref
                }
            }
        }
    }

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
