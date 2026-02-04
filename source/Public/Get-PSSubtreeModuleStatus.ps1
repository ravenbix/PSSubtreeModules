function Get-PSSubtreeModuleStatus
{
    <#
    .SYNOPSIS
        Checks for available upstream updates for tracked modules.

    .DESCRIPTION
        Compares the local subtree commit with the upstream repository to determine
        if updates are available for tracked modules. For each module, retrieves
        the current local commit hash (from git subtree metadata) and queries the
        upstream repository for the latest commit on the tracked ref.

        Returns status information including whether updates are available,
        the local and upstream commit hashes, and the tracking ref.

    .PARAMETER Name
        The name of the module(s) to check. Supports wildcard characters.
        If not specified, defaults to '*' which checks all tracked modules.

    .PARAMETER UpdateAvailable
        When specified, only returns modules that have updates available.
        Filters out modules that are current or have unknown status.

    .PARAMETER Path
        The path to the repository containing the subtree-modules.yaml configuration.
        If not specified, defaults to the current working directory.

    .EXAMPLE
        Get-PSSubtreeModuleStatus

        Checks the status of all tracked modules and returns their update status.

    .EXAMPLE
        Get-PSSubtreeModuleStatus -Name 'Pester'

        Checks the update status for the Pester module only.

    .EXAMPLE
        Get-PSSubtreeModuleStatus -UpdateAvailable

        Returns only the modules that have updates available from upstream.

    .EXAMPLE
        Get-PSSubtreeModuleStatus -Name 'PS*' -UpdateAvailable

        Returns modules starting with 'PS' that have updates available.

    .EXAMPLE
        Get-PSSubtreeModuleStatus -Verbose

        Checks all modules and displays verbose output including full commit hashes,
        dates, and comparison details.

    .OUTPUTS
        PSCustomObject
        Returns objects with the following properties:
        - Name: The module name
        - Ref: The branch, tag, or commit reference being tracked
        - Status: One of 'Current', 'UpdateAvailable', 'Unknown'
        - LocalCommit: The short commit hash currently in the local subtree
        - UpstreamCommit: The short commit hash available upstream
        - LocalCommitFull: The full 40-character local commit hash (verbose detail)
        - UpstreamCommitFull: The full 40-character upstream commit hash (verbose detail)

    .NOTES
        The status values are:
        - 'Current': The local commit matches the upstream commit
        - 'UpdateAvailable': The upstream has a newer commit than local
        - 'Unknown': Unable to determine status (network error, no local metadata, etc.)

        Network errors are handled gracefully - modules that cannot be checked will
        show 'Unknown' status with a warning message.
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
        [switch]
        $UpdateAvailable,

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

        # Iterate through modules and check status
        foreach ($moduleName in $config.modules.Keys)
        {
            # Use -like operator for wildcard matching
            if ($moduleName -notlike $Name)
            {
                continue
            }

            $moduleInfo = $config.modules[$moduleName]
            Write-Verbose "Checking status for module: $moduleName"
            Write-Verbose "  Repository: $($moduleInfo.repo)"
            Write-Verbose "  Ref: $($moduleInfo.ref)"

            # Initialize result variables
            $status = 'Unknown'
            $localCommitFull = $null
            $upstreamCommitFull = $null
            $localCommitShort = $null
            $upstreamCommitShort = $null

            # Get local subtree info
            $localInfo = Get-SubtreeInfo -ModuleName $moduleName -WorkingDirectory $Path

            if ($localInfo)
            {
                $localCommitFull = $localInfo.CommitHash
                $localCommitShort = $localCommitFull.Substring(0, 7)
                Write-Verbose "  Local commit: $localCommitFull (from $($localInfo.CommitDate))"
            }
            else
            {
                Write-Verbose "  Unable to retrieve local subtree info for '$moduleName'"
                Write-Warning "Cannot determine local commit for '$moduleName'. Module may not have been added via git subtree."
            }

            # Get upstream info
            $upstreamInfo = Get-UpstreamInfo -Repository $moduleInfo.repo -Ref $moduleInfo.ref

            if ($upstreamInfo)
            {
                $upstreamCommitFull = $upstreamInfo.CommitHash
                $upstreamCommitShort = $upstreamCommitFull.Substring(0, 7)
                Write-Verbose "  Upstream commit: $upstreamCommitFull"
            }
            else
            {
                Write-Verbose "  Unable to retrieve upstream info for '$moduleName'"
                # Warning already emitted by Get-UpstreamInfo
            }

            # Determine status
            if ($localCommitFull -and $upstreamCommitFull)
            {
                if ($localCommitFull -eq $upstreamCommitFull)
                {
                    $status = 'Current'
                    Write-Verbose "  Status: Current (commits match)"
                }
                else
                {
                    $status = 'UpdateAvailable'
                    Write-Verbose "  Status: UpdateAvailable (local: $localCommitShort, upstream: $upstreamCommitShort)"
                }
            }
            else
            {
                Write-Verbose "  Status: Unknown (missing commit information)"
            }

            # Create the result object
            $resultObject = [PSCustomObject]@{
                PSTypeName         = 'PSSubtreeModules.ModuleStatus'
                Name               = $moduleName
                Ref                = $moduleInfo.ref
                Status             = $status
                LocalCommit        = $localCommitShort
                UpstreamCommit     = $upstreamCommitShort
                LocalCommitFull    = $localCommitFull
                UpstreamCommitFull = $upstreamCommitFull
            }

            # Apply filter if -UpdateAvailable is specified
            if ($UpdateAvailable)
            {
                if ($status -eq 'UpdateAvailable')
                {
                    $resultObject
                }
                else
                {
                    Write-Verbose "  Skipping '$moduleName' (status is not UpdateAvailable)"
                }
            }
            else
            {
                $resultObject
            }
        }
    }

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
