function Get-SubtreeInfo
{
    <#
    .SYNOPSIS
        Retrieves local subtree commit metadata for a module.

    .DESCRIPTION
        Parses the git log to extract subtree metadata from squash commits. When modules
        are added or updated using 'git subtree add/pull --squash', the commit message
        contains special metadata lines: 'git-subtree-dir' (the prefix path) and
        'git-subtree-split' (the upstream commit hash that was merged).

        This function searches for the most recent commit containing subtree metadata
        for the specified module prefix and extracts the upstream commit hash.

    .PARAMETER ModuleName
        The name of the module to retrieve subtree information for. This corresponds
        to the directory name under the modules/ folder (e.g., 'MyModule' for
        'modules/MyModule').

    .PARAMETER ModulesPath
        The base path where modules are stored. Defaults to 'modules'. The subtree
        prefix searched for will be '$ModulesPath/$ModuleName'.

    .PARAMETER WorkingDirectory
        The directory containing the git repository. If not specified, uses the
        current working directory.

    .EXAMPLE
        Get-SubtreeInfo -ModuleName 'PSScriptAnalyzer'

        Returns the local subtree commit information for the PSScriptAnalyzer module.

    .EXAMPLE
        Get-SubtreeInfo -ModuleName 'MyModule' -ModulesPath 'libs'

        Returns subtree info for a module stored under 'libs/MyModule'.

    .EXAMPLE
        $info = Get-SubtreeInfo -ModuleName 'MyModule'
        if ($info) {
            Write-Host "Local commit: $($info.CommitHash)"
            Write-Host "Added on: $($info.CommitDate)"
        }

        Retrieves subtree info and displays the upstream commit hash that was merged.

    .OUTPUTS
        PSCustomObject
        Returns a custom object with the following properties:
        - CommitHash: The upstream commit hash that was merged (from git-subtree-split)
        - LocalCommitHash: The local git commit hash that added/updated the subtree
        - CommitDate: The date of the local commit
        - ModuleName: The module name
        - Prefix: The full subtree prefix path (e.g., 'modules/MyModule')

        Returns $null if no subtree metadata is found for the specified module.

    .NOTES
        This is a private helper function used internally by PSSubtreeModules.
        The function looks for git commit messages containing 'git-subtree-dir' and
        'git-subtree-split' markers that are automatically added by git subtree.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ModuleName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ModulesPath = 'modules',

        [Parameter()]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]
        $WorkingDirectory
    )

    begin
    {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"
    }

    process
    {
        $prefix = "$ModulesPath/$ModuleName"
        Write-Verbose "Searching for subtree metadata for prefix: $prefix"

        try
        {
            # Verify git is available
            $gitPath = Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue
            if (-not $gitPath)
            {
                Write-Error -Message 'Git is not installed or not found in PATH.' -Category ObjectNotFound -ErrorId 'GitNotFound'
                return $null
            }

            # Store original location if we need to change directories
            $originalLocation = $null
            if ($PSBoundParameters.ContainsKey('WorkingDirectory'))
            {
                $originalLocation = Get-Location
                Write-Verbose "Changing to working directory: $WorkingDirectory"
                Set-Location -Path $WorkingDirectory
            }

            try
            {
                # Search git log for commits containing git-subtree-dir marker for this prefix
                # Use grep pattern to find commits with our specific prefix
                # Format: hash|date|message body
                $logArgs = @(
                    'log',
                    '--all',
                    '--format=%H|%aI|%B',
                    '--grep=git-subtree-dir: ' + $prefix,
                    '-1'
                )

                Write-Verbose "Executing: git $($logArgs -join ' ')"

                $result = & git @logArgs 2>&1
                $exitCode = $LASTEXITCODE

                if ($exitCode -ne 0)
                {
                    # Git log failed - might not be in a git repository
                    $errorOutput = if ($result)
                    {
                        ($result | ForEach-Object { $_.ToString() }) -join "`n"
                    }
                    else
                    {
                        'Unknown error'
                    }

                    Write-Verbose "git log failed with exit code ${exitCode}: $errorOutput"
                    Write-Warning "Failed to search git history: $errorOutput"
                    return $null
                }

                # Check if we got any results
                if (-not $result -or [string]::IsNullOrWhiteSpace(($result | Out-String)))
                {
                    Write-Verbose "No subtree metadata found for prefix: $prefix"
                    return $null
                }

                # Parse the result
                # The output format is: hash|date|message body (potentially multiline)
                $output = ($result | Out-String).Trim()

                # Split on the first two pipe characters to get hash, date, and message
                $firstPipe = $output.IndexOf('|')
                if ($firstPipe -lt 0)
                {
                    Write-Verbose "Invalid git log output format"
                    return $null
                }

                $localCommitHash = $output.Substring(0, $firstPipe)
                $remaining = $output.Substring($firstPipe + 1)

                $secondPipe = $remaining.IndexOf('|')
                if ($secondPipe -lt 0)
                {
                    Write-Verbose "Invalid git log output format"
                    return $null
                }

                $commitDate = $remaining.Substring(0, $secondPipe)
                $messageBody = $remaining.Substring($secondPipe + 1)

                Write-Verbose "Found commit: $localCommitHash dated $commitDate"

                # Parse the message body for git-subtree-split
                $subtreeSplitHash = $null
                $subtreeDir = $null

                # Split message into lines and search for metadata
                $lines = $messageBody -split "`r?`n"
                foreach ($line in $lines)
                {
                    $trimmedLine = $line.Trim()

                    # Look for git-subtree-dir marker
                    if ($trimmedLine -match '^git-subtree-dir:\s*(.+)$')
                    {
                        $foundDir = $Matches[1].Trim()
                        Write-Verbose "Found git-subtree-dir: $foundDir"

                        # Verify this matches our expected prefix
                        if ($foundDir -eq $prefix)
                        {
                            $subtreeDir = $foundDir
                        }
                    }

                    # Look for git-subtree-split marker (the upstream commit hash)
                    if ($trimmedLine -match '^git-subtree-split:\s*([a-f0-9]{40})$')
                    {
                        $subtreeSplitHash = $Matches[1].Trim()
                        Write-Verbose "Found git-subtree-split: $subtreeSplitHash"
                    }
                }

                # Verify we found the required metadata
                if (-not $subtreeDir)
                {
                    Write-Verbose "git-subtree-dir marker not found or doesn't match prefix"
                    return $null
                }

                if (-not $subtreeSplitHash)
                {
                    Write-Verbose "git-subtree-split marker not found"
                    return $null
                }

                # Return the result object
                $result = [PSCustomObject]@{
                    CommitHash      = $subtreeSplitHash
                    LocalCommitHash = $localCommitHash
                    CommitDate      = $commitDate
                    ModuleName      = $ModuleName
                    Prefix          = $prefix
                }

                Write-Verbose "Successfully retrieved subtree info: upstream commit $subtreeSplitHash"
                return $result
            }
            finally
            {
                # Restore original location if we changed it
                if ($null -ne $originalLocation)
                {
                    Write-Verbose "Restoring original location: $originalLocation"
                    Set-Location -Path $originalLocation
                }
            }
        }
        catch
        {
            # Handle any unexpected errors gracefully
            Write-Verbose "Error retrieving subtree info: $($_.Exception.Message)"
            Write-Warning "Failed to retrieve subtree info for '$ModuleName': $($_.Exception.Message)"
            return $null
        }
    }

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
