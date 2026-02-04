function Add-PSSubtreeModule
{
    <#
    .SYNOPSIS
        Adds a PowerShell module from a Git repository using Git subtree.

    .DESCRIPTION
        Adds a module from a GitHub or other Git repository to the local modules directory
        using Git subtree. The module is added with the --squash option to keep history clean.
        The function updates the subtree-modules.yaml configuration file and creates a
        conventional commit message documenting the addition.

        This is the primary way to add new modules to a repository managed by PSSubtreeModules.

    .PARAMETER Name
        The name to use for the module in the modules directory. This becomes the subdirectory
        name under modules/ and the key in subtree-modules.yaml.

    .PARAMETER Repository
        The Git repository URL to add as a subtree. Can be HTTPS or SSH format.
        Examples: 'https://github.com/owner/repo.git' or 'git@github.com:owner/repo.git'

    .PARAMETER Ref
        The Git reference (branch, tag, or commit) to check out. Defaults to 'main'.
        Use specific tags (e.g., 'v1.2.3') for version pinning.

    .PARAMETER Path
        The path to the repository where the module should be added.
        If not specified, defaults to the current working directory.

    .PARAMETER Force
        If specified, overwrites an existing module entry in the configuration.
        Note: Git subtree will still fail if the directory already exists.

    .EXAMPLE
        Add-PSSubtreeModule -Name 'Pester' -Repository 'https://github.com/pester/Pester.git'

        Adds the Pester module from GitHub using the default 'main' branch.

    .EXAMPLE
        Add-PSSubtreeModule -Name 'PSScriptAnalyzer' -Repository 'https://github.com/PowerShell/PSScriptAnalyzer.git' -Ref 'v1.21.0'

        Adds PSScriptAnalyzer pinned to version 1.21.0.

    .EXAMPLE
        Add-PSSubtreeModule -Name 'MyModule' -Repository 'https://github.com/owner/repo.git' -Ref 'develop' -WhatIf

        Shows what would happen without making any changes.

    .EXAMPLE
        Add-PSSubtreeModule -Name 'ExistingModule' -Repository 'https://github.com/owner/repo.git' -Force

        Overwrites an existing configuration entry for ExistingModule.

    .OUTPUTS
        PSCustomObject
        Returns an object representing the added module with Name, Repository, and Ref properties.

    .NOTES
        - The repository must be initialized with Initialize-PSSubtreeModule first
        - Git 1.7.11 or later is required for subtree support
        - Uses --squash flag to keep commit history clean
        - Creates a conventional commit: 'feat(modules): add <name> at <ref>'
        - The working tree should be clean before adding modules
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-zA-Z0-9_.-]+$')]
        [string]
        $Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [Alias('Repo', 'Url')]
        [string]
        $Repository,

        [Parameter(Position = 2)]
        [ValidateNotNullOrEmpty()]
        [Alias('Branch', 'Tag')]
        [string]
        $Ref = 'main',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path = (Get-Location),

        [Parameter()]
        [switch]
        $Force
    )

    begin
    {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"
    }

    process
    {
        # Resolve to absolute path
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        Write-Verbose "Adding module '$Name' to repository at: $resolvedPath"

        # Validate the directory exists
        if (-not (Test-Path -Path $resolvedPath -PathType Container))
        {
            $errorMessage = "The specified path does not exist or is not a directory: $resolvedPath"
            Write-Error -Message $errorMessage -Category ObjectNotFound -ErrorId 'PathNotFound'
            return
        }

        # Validate it's a Git repository
        $gitDir = Join-Path -Path $resolvedPath -ChildPath '.git'
        if (-not (Test-Path -Path $gitDir))
        {
            $errorMessage = "The specified path is not a Git repository: $resolvedPath. Initialize a Git repository first with 'git init'."
            Write-Error -Message $errorMessage -Category InvalidOperation -ErrorId 'NotGitRepository'
            return
        }

        # Validate the subtree-modules.yaml exists (repository should be initialized)
        $configPath = Join-Path -Path $resolvedPath -ChildPath 'subtree-modules.yaml'
        if (-not (Test-Path -Path $configPath))
        {
            $errorMessage = "The repository has not been initialized for PSSubtreeModules. Run Initialize-PSSubtreeModule first."
            Write-Error -Message $errorMessage -Category InvalidOperation -ErrorId 'NotInitialized'
            return
        }

        # Read existing configuration
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

        # Check if module already exists in configuration
        if ($config.modules.Contains($Name) -and -not $Force)
        {
            $errorMessage = "Module '$Name' already exists in configuration. Use -Force to overwrite."
            Write-Error -Message $errorMessage -Category ResourceExists -ErrorId 'ModuleAlreadyExists'
            return
        }

        # Check if the module directory already exists
        $modulePath = Join-Path -Path $resolvedPath -ChildPath "modules/$Name"
        if (Test-Path -Path $modulePath)
        {
            $errorMessage = "Directory already exists: $modulePath. Remove it first or use a different module name."
            Write-Error -Message $errorMessage -Category ResourceExists -ErrorId 'DirectoryAlreadyExists'
            return
        }

        # Define the prefix for git subtree
        $prefix = "modules/$Name"

        # Build the ShouldProcess message
        $shouldProcessMessage = "Add module '$Name' from '$Repository' at ref '$Ref'"

        if ($PSCmdlet.ShouldProcess($shouldProcessMessage, 'Add Module'))
        {
            try
            {
                Write-Verbose "Executing git subtree add --prefix=$prefix $Repository $Ref --squash"

                # Execute git subtree add command
                $subtreeArgs = @(
                    'subtree'
                    'add'
                    "--prefix=$prefix"
                    $Repository
                    $Ref
                    '--squash'
                )

                $null = Invoke-GitCommand -Arguments $subtreeArgs -WorkingDirectory $resolvedPath
                Write-Verbose "Git subtree add completed successfully"

                # Update the configuration
                Write-Verbose "Updating module configuration"
                $config.modules[$Name] = [ordered]@{
                    repo = $Repository
                    ref  = $Ref
                }

                # Save the updated configuration
                Save-ModuleConfig -Configuration $config -Path $configPath
                Write-Verbose "Configuration saved"

                # Stage the updated configuration
                Write-Verbose "Staging configuration file"
                Invoke-GitCommand -Arguments @('add', 'subtree-modules.yaml') -WorkingDirectory $resolvedPath

                # Create conventional commit message
                $commitMessage = "feat(modules): add $Name at $Ref"
                Write-Verbose "Creating commit: $commitMessage"
                Invoke-GitCommand -Arguments @('commit', '-m', $commitMessage) -WorkingDirectory $resolvedPath

                Write-Verbose "Module '$Name' added successfully"

                # Return the module info
                [PSCustomObject]@{
                    PSTypeName = 'PSSubtreeModules.ModuleInfo'
                    Name       = $Name
                    Repository = $Repository
                    Ref        = $Ref
                }
            }
            catch
            {
                $errorMessage = "Failed to add module '$Name': $($_.Exception.Message)"
                Write-Error -Message $errorMessage -Category InvalidOperation -ErrorId 'ModuleAddError'

                # Attempt to clean up if partial changes were made
                Write-Verbose "Attempting to restore state after failure"
                try
                {
                    # Reset any staged changes
                    Invoke-GitCommand -Arguments @('reset', 'HEAD') -WorkingDirectory $resolvedPath -ErrorAction SilentlyContinue
                }
                catch
                {
                    Write-Verbose "Failed to reset: $($_.Exception.Message)"
                }
            }
        }
    }

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
