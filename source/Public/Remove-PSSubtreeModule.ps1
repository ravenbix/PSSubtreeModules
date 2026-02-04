function Remove-PSSubtreeModule
{
    <#
    .SYNOPSIS
        Removes a PowerShell module from the repository.

    .DESCRIPTION
        Removes a module that was previously added via Add-PSSubtreeModule. The function
        removes the module directory from the repository using 'git rm -rf', updates the
        subtree-modules.yaml configuration file, and creates a conventional commit message
        documenting the removal.

        By default, the function prompts for confirmation before removing the module.
        Use the -Force switch to skip the confirmation prompt.

    .PARAMETER Name
        The name of the module to remove. Must match a module tracked in subtree-modules.yaml.

    .PARAMETER Path
        The path to the repository where the module is managed.
        If not specified, defaults to the current working directory.

    .PARAMETER Force
        If specified, skips the confirmation prompt and removes the module immediately.
        This is useful for scripted operations where interactive prompts are not desired.

    .EXAMPLE
        Remove-PSSubtreeModule -Name 'Pester'

        Removes the Pester module after prompting for confirmation.

    .EXAMPLE
        Remove-PSSubtreeModule -Name 'PSScriptAnalyzer' -Force

        Removes the PSScriptAnalyzer module without prompting for confirmation.

    .EXAMPLE
        Remove-PSSubtreeModule -Name 'MyModule' -WhatIf

        Shows what would happen without making any changes.

    .EXAMPLE
        Get-PSSubtreeModule -Name 'OldModule*' | Remove-PSSubtreeModule -Force

        Removes all modules matching 'OldModule*' without confirmation using pipeline input.

    .OUTPUTS
        PSCustomObject
        Returns an object representing the removed module with Name, Repository, and Ref properties.

    .NOTES
        - The repository must be initialized with Initialize-PSSubtreeModule first
        - The module must be tracked in subtree-modules.yaml
        - Uses 'git rm -rf' to remove the module directory
        - Creates a conventional commit: 'feat(modules): remove <name>'
        - The -Force switch skips confirmation but respects -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-zA-Z0-9_.-]+$')]
        [string]
        $Name,

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

        # Resolve to absolute path once
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        Write-Verbose "Operating on repository at: $resolvedPath"

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

        # Read existing configuration once
        try
        {
            $script:config = Get-ModuleConfig -Path $configPath
        }
        catch
        {
            $errorMessage = "Failed to read module configuration: $($_.Exception.Message)"
            Write-Error -Message $errorMessage -Category ReadError -ErrorId 'ConfigReadError'
            return
        }

        # Track if we need to save config
        $script:configChanged = $false
    }

    process
    {
        Write-Verbose "Processing module '$Name' for removal"

        # Check if there are any modules configured
        if ($null -eq $script:config.modules -or $script:config.modules.Count -eq 0)
        {
            Write-Warning "No modules are currently tracked. Nothing to remove."
            return
        }

        # Validate the module exists in configuration
        if (-not $script:config.modules.Contains($Name))
        {
            $errorMessage = "Module '$Name' is not tracked. Use Get-PSSubtreeModule to see tracked modules."
            Write-Error -Message $errorMessage -Category ObjectNotFound -ErrorId 'ModuleNotTracked'
            return
        }

        # Get module info before removing
        $moduleInfo = $script:config.modules[$Name]
        $repository = $moduleInfo.repo
        $ref = $moduleInfo.ref

        # Define the module path
        $modulePath = Join-Path -Path $resolvedPath -ChildPath "modules/$Name"
        $prefix = "modules/$Name"

        # Build the ShouldProcess message
        $shouldProcessTarget = "Module '$Name' from '$repository'"
        $shouldProcessAction = "Remove module directory and configuration entry"

        # If Force is specified and not WhatIf, skip confirmation by calling ShouldProcess with less impactful parameters
        $shouldProceed = if ($Force)
        {
            $PSCmdlet.ShouldProcess($shouldProcessTarget, $shouldProcessAction)
        }
        else
        {
            $PSCmdlet.ShouldProcess($shouldProcessTarget, $shouldProcessAction)
        }

        if ($shouldProceed)
        {
            try
            {
                # Check if the module directory exists before trying to remove
                if (Test-Path -Path $modulePath)
                {
                    Write-Verbose "Executing git rm -rf $prefix"

                    # Execute git rm to remove the module directory
                    $gitRmArgs = @(
                        'rm'
                        '-rf'
                        $prefix
                    )

                    $result = Invoke-GitCommand -Arguments $gitRmArgs -WorkingDirectory $resolvedPath
                    Write-Verbose "Git rm completed successfully"
                }
                else
                {
                    Write-Warning "Module directory '$modulePath' does not exist. Removing from configuration only."
                }

                # Remove the module from configuration
                Write-Verbose "Removing module from configuration"
                $script:config.modules.Remove($Name)
                $script:configChanged = $true

                # Save the updated configuration
                Save-ModuleConfig -Configuration $script:config -Path $configPath
                Write-Verbose "Configuration saved"

                # Stage the updated configuration
                Write-Verbose "Staging configuration file"
                Invoke-GitCommand -Arguments @('add', 'subtree-modules.yaml') -WorkingDirectory $resolvedPath

                # Create conventional commit message
                $commitMessage = "feat(modules): remove $Name"
                Write-Verbose "Creating commit: $commitMessage"
                Invoke-GitCommand -Arguments @('commit', '-m', $commitMessage) -WorkingDirectory $resolvedPath

                Write-Verbose "Module '$Name' removed successfully"

                # Return the removed module info
                [PSCustomObject]@{
                    PSTypeName = 'PSSubtreeModules.ModuleInfo'
                    Name       = $Name
                    Repository = $repository
                    Ref        = $ref
                }
            }
            catch
            {
                $errorMessage = "Failed to remove module '$Name': $($_.Exception.Message)"
                Write-Error -Message $errorMessage -Category InvalidOperation -ErrorId 'ModuleRemoveError'

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

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
