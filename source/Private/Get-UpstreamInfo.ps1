function Get-UpstreamInfo
{
    <#
    .SYNOPSIS
        Retrieves commit information from a remote repository.

    .DESCRIPTION
        Uses 'git ls-remote' to query a remote repository and retrieve the commit hash
        for a specified ref (branch, tag, or commit). This function is used to check
        for available updates by comparing the upstream commit with the local subtree
        commit. Handles network errors gracefully by returning $null on failure.

    .PARAMETER Repository
        The URL of the remote repository to query. Supports HTTPS URLs in the format
        'https://github.com/owner/repo.git' or 'https://github.com/owner/repo'.

    .PARAMETER Ref
        The ref to look up in the remote repository. Can be a branch name (e.g., 'main'),
        a tag (e.g., 'v1.0.0'), or a full commit hash. Defaults to 'HEAD' if not specified.

    .EXAMPLE
        Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'main'

        Returns the commit hash for the 'main' branch of the specified repository.

    .EXAMPLE
        Get-UpstreamInfo -Repository 'https://github.com/owner/repo.git' -Ref 'v2.1.0'

        Returns the commit hash for the 'v2.1.0' tag.

    .EXAMPLE
        $info = Get-UpstreamInfo -Repository $moduleConfig.repo -Ref $moduleConfig.ref
        if ($info) {
            Write-Host "Upstream commit: $($info.CommitHash)"
        }

        Retrieves upstream info and handles the case when the repository is unreachable.

    .OUTPUTS
        PSCustomObject
        Returns a custom object with the following properties:
        - CommitHash: The full commit hash (40 characters)
        - Ref: The resolved ref name
        - Repository: The repository URL that was queried

        Returns $null if the repository cannot be reached or the ref is not found.

    .NOTES
        This is a private helper function used internally by PSSubtreeModules.
        Network errors are handled gracefully - the function returns $null instead
        of throwing an error when the repository cannot be reached. This allows
        calling functions to handle offline scenarios appropriately.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Repository,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Ref = 'HEAD'
    )

    begin
    {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"
    }

    process
    {
        Write-Verbose "Querying upstream repository: $Repository"
        Write-Verbose "Looking up ref: $Ref"

        try
        {
            # Verify git is available
            $gitPath = Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue
            if (-not $gitPath)
            {
                Write-Error -Message 'Git is not installed or not found in PATH.' -Category ObjectNotFound -ErrorId 'GitNotFound'
                return $null
            }

            # Build the ls-remote arguments
            # For HEAD, we just query without specifying refs
            # For branches/tags, we need to check multiple ref patterns
            $lsRemoteArgs = @('ls-remote', '--refs', '--quiet', $Repository)

            Write-Verbose "Executing: git $($lsRemoteArgs -join ' ')"

            # Execute git ls-remote and capture output
            $result = & git @lsRemoteArgs 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0)
            {
                # Network error or invalid repository
                $errorOutput = if ($result)
                {
                    ($result | ForEach-Object { $_.ToString() }) -join "`n"
                }
                else
                {
                    'Unknown error'
                }

                Write-Verbose "git ls-remote failed with exit code ${exitCode}: $errorOutput"
                Write-Warning "Unable to reach repository '$Repository': $errorOutput"
                return $null
            }

            # Parse the output to find the matching ref
            # Output format: <commit-hash><tab><ref-name>
            # Example: a1b2c3d4... refs/heads/main
            #          e5f6g7h8... refs/tags/v1.0.0

            $matchingCommit = $null
            $matchingRef = $null

            if ($result)
            {
                # Convert result to array of lines
                $lines = @($result) | ForEach-Object { $_.ToString() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                Write-Verbose "Received $($lines.Count) refs from repository"

                foreach ($line in $lines)
                {
                    # Parse each line (format: hash<tab>ref)
                    $parts = $line -split '\t', 2
                    if ($parts.Count -eq 2)
                    {
                        $commitHash = $parts[0].Trim()
                        $refName = $parts[1].Trim()

                        # Check for exact matches on various ref patterns
                        # refs/heads/<branch> for branches
                        # refs/tags/<tag> for tags

                        $shortRef = $refName -replace '^refs/heads/', '' -replace '^refs/tags/', ''

                        if ($shortRef -eq $Ref -or $refName -eq $Ref -or $refName -eq "refs/heads/$Ref" -or $refName -eq "refs/tags/$Ref")
                        {
                            Write-Verbose "Found matching ref: $refName -> $commitHash"
                            $matchingCommit = $commitHash
                            $matchingRef = $shortRef
                            break
                        }
                    }
                }
            }

            # If we didn't find a match with ls-remote --refs, try querying directly
            # This handles the case where Ref is a commit hash or HEAD
            if (-not $matchingCommit)
            {
                Write-Verbose "No match found in refs list, trying direct query for ref '$Ref'"

                # Try to resolve the ref directly using ls-remote without --refs
                $directArgs = @('ls-remote', $Repository, $Ref)
                Write-Verbose "Executing: git $($directArgs -join ' ')"

                $directResult = & git @directArgs 2>&1
                $directExitCode = $LASTEXITCODE

                if ($directExitCode -eq 0 -and $directResult)
                {
                    $lines = @($directResult) | ForEach-Object { $_.ToString() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                    foreach ($line in $lines)
                    {
                        $parts = $line -split '\t', 2
                        if ($parts.Count -ge 1)
                        {
                            $matchingCommit = $parts[0].Trim()
                            $matchingRef = if ($parts.Count -ge 2) { $parts[1].Trim() -replace '^refs/heads/', '' -replace '^refs/tags/', '' } else { $Ref }
                            Write-Verbose "Found ref via direct query: $matchingRef -> $matchingCommit"
                            break
                        }
                    }
                }
            }

            if (-not $matchingCommit)
            {
                Write-Verbose "Ref '$Ref' not found in repository '$Repository'"
                Write-Warning "Ref '$Ref' not found in repository '$Repository'"
                return $null
            }

            # Return the result object
            $result = [PSCustomObject]@{
                CommitHash = $matchingCommit
                Ref        = $matchingRef
                Repository = $Repository
            }

            Write-Verbose "Successfully retrieved upstream info: $matchingCommit"
            return $result
        }
        catch
        {
            # Handle any unexpected errors gracefully
            Write-Verbose "Error querying upstream repository: $($_.Exception.Message)"
            Write-Warning "Failed to query repository '$Repository': $($_.Exception.Message)"
            return $null
        }
    }

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
