function Update-PSSubtreeModule
{
    <#
    .SYNOPSIS
        Updates PowerShell modules managed by Git subtree to the latest or a specific version.

    .DESCRIPTION
        Updates modules tracked in subtree-modules.yaml by pulling changes from the upstream
        repository using Git subtree. The module can be updated to the latest version of its
        current ref or changed to a different branch/tag. Uses the --squash option to keep
        commit history clean.

        This function supports updating individual modules by name, or all modules at once
        using the -All switch. When a new -Ref is specified, the configuration is updated
        to reflect the change.

    .PARAMETER Name
        The name of the module to update. Must match a module tracked in subtree-modules.yaml.
        This parameter is required unless -All is specified.

    .PARAMETER Ref
        The Git reference (branch, tag, or commit) to update to. If not specified, updates
        to the latest version of the module's current ref. Use this to switch branches or
        update to a specific version tag.

    .PARAMETER All
        If specified, updates all tracked modules to their latest versions. Cannot be used
        together with -Name.

    .PARAMETER Path
        The path to the repository where the modules are managed.
        If not specified, defaults to the current working directory.

    .EXAMPLE
        Update-PSSubtreeModule -Name 'Pester'

        Updates the Pester module to the latest version of its current branch/tag.

    .EXAMPLE
        Update-PSSubtreeModule -Name 'PSScriptAnalyzer' -Ref 'v1.22.0'

        Updates PSScriptAnalyzer to version 1.22.0 and updates the configuration.

    .EXAMPLE
        Update-PSSubtreeModule -All

        Updates all tracked modules to their latest versions.

    .EXAMPLE
        Update-PSSubtreeModule -Name 'MyModule' -WhatIf

        Shows what would happen without making any changes.

    .EXAMPLE
        Update-PSSubtreeModule -All -Path 'C:\repos\my-modules'

        Updates all modules in a specific repository.

    .OUTPUTS
        PSCustomObject
        Returns objects representing the updated modules with Name, Repository, Ref,
        and PreviousRef properties.

    .NOTES
        - The repository must be initialized with Initialize-PSSubtreeModule first
        - Git 1.7.11 or later is required for subtree support
        - Uses --squash flag to keep commit history clean
        - Creates conventional commits: 'feat(modules): update <name> to <ref>'
        - When -Ref is specified, the configuration file is updated
        - The working tree should be clean before updating modules
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-zA-Z0-9_.-]+$')]
        [string]
        $Name,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [Alias('Branch', 'Tag')]
        [string]
        $Ref,

        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [switch]
        $All,

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
        # Resolve to absolute path
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        Write-Verbose "Updating modules in repository at: $resolvedPath"

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

        # Check if there are any modules configured
        if ($null -eq $config.modules -or $config.modules.Count -eq 0)
        {
            Write-Warning "No modules are currently tracked. Use Add-PSSubtreeModule to add modules first."
            return
        }

        # Determine which modules to update
        if ($All)
        {
            Write-Verbose "Updating all tracked modules"
            $modulesToUpdate = @($config.modules.Keys)
        }
        else
        {
            # Validate the module exists in configuration
            if (-not $config.modules.Contains($Name))
            {
                $errorMessage = "Module '$Name' is not tracked. Use Get-PSSubtreeModule to see tracked modules."
                Write-Error -Message $errorMessage -Category ObjectNotFound -ErrorId 'ModuleNotTracked'
                return
            }
            $modulesToUpdate = @($Name)
        }

        Write-Verbose "Modules to update: $($modulesToUpdate -join ', ')"

        # Track if config needs saving (only if ref changes)
        $configChanged = $false

        # Update each module
        foreach ($moduleName in $modulesToUpdate)
        {
            $moduleInfo = $config.modules[$moduleName]
            $repository = $moduleInfo.repo
            $currentRef = $moduleInfo.ref

            # Determine the ref to use for update
            $updateRef = if ($PSBoundParameters.ContainsKey('Ref'))
            {
                $Ref
            }
            else
            {
                $currentRef
            }

            # Check if the module directory exists
            $modulePath = Join-Path -Path $resolvedPath -ChildPath "modules/$moduleName"
            if (-not (Test-Path -Path $modulePath))
            {
                Write-Warning "Module directory not found: $modulePath. Skipping '$moduleName'. The module may have been removed without updating the configuration."
                continue
            }

            # Define the prefix for git subtree
            $prefix = "modules/$moduleName"

            # Build the ShouldProcess message
            $refChangeText = if ($updateRef -ne $currentRef)
            {
                "from '$currentRef' to '$updateRef'"
            }
            else
            {
                "to latest at '$updateRef'"
            }
            $shouldProcessMessage = "Update module '$moduleName' $refChangeText"

            if ($PSCmdlet.ShouldProcess($shouldProcessMessage, 'Update Module'))
            {
                try
                {
                    Write-Verbose "Executing git subtree pull --prefix=$prefix $repository $updateRef --squash"

                    # Execute git subtree pull command
                    $subtreeArgs = @(
                        'subtree'
                        'pull'
                        "--prefix=$prefix"
                        $repository
                        $updateRef
                        '--squash'
                    )

                    $result = Invoke-GitCommand -Arguments $subtreeArgs -WorkingDirectory $resolvedPath
                    Write-Verbose "Git subtree pull completed successfully"

                    # Check if this was an "Already up to date" result
                    $alreadyUpToDate = ($result | Out-String) -match 'Already up.to.date|Already up-to-date'

                    # Determine if ref changed
                    $previousRef = $currentRef
                    $refChanged = ($updateRef -ne $currentRef)

                    # Update configuration if ref changed
                    if ($refChanged)
                    {
                        Write-Verbose "Updating ref in configuration from '$currentRef' to '$updateRef'"
                        $config.modules[$moduleName]['ref'] = $updateRef
                        $configChanged = $true
                    }

                    # Create commit message
                    $commitMessage = if ($refChanged)
                    {
                        "feat(modules): update $moduleName from $previousRef to $updateRef"
                    }
                    else
                    {
                        "feat(modules): update $moduleName to latest at $updateRef"
                    }

                    # If config changed, save and stage it
                    if ($refChanged)
                    {
                        Write-Verbose "Saving updated configuration"
                        Save-ModuleConfig -Configuration $config -Path $configPath

                        Write-Verbose "Staging configuration file"
                        Invoke-GitCommand -Arguments @('add', 'subtree-modules.yaml') -WorkingDirectory $resolvedPath

                        Write-Verbose "Creating commit: $commitMessage"
                        Invoke-GitCommand -Arguments @('commit', '-m', $commitMessage) -WorkingDirectory $resolvedPath
                    }

                    Write-Verbose "Module '$moduleName' updated successfully"

                    # Return the module info
                    [PSCustomObject]@{
                        PSTypeName      = 'PSSubtreeModules.UpdateResult'
                        Name            = $moduleName
                        Repository      = $repository
                        Ref             = $updateRef
                        PreviousRef     = $previousRef
                        AlreadyUpToDate = $alreadyUpToDate
                    }
                }
                catch
                {
                    $errorMessage = "Failed to update module '$moduleName': $($_.Exception.Message)"
                    Write-Error -Message $errorMessage -Category InvalidOperation -ErrorId 'ModuleUpdateError'

                    # Attempt to restore state after failure
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
    }

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
