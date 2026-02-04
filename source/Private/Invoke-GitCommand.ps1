function Invoke-GitCommand
{
    <#
    .SYNOPSIS
        Executes a git command with error handling.

    .DESCRIPTION
        Executes a git command by passing the provided arguments to the git executable.
        Captures both stdout and stderr output, checks the exit code, and throws an
        error if the command fails. This function serves as the foundation for all
        git operations in the PSSubtreeModules module.

    .PARAMETER Arguments
        An array of arguments to pass to the git command. Each argument should be
        a separate string element in the array.

    .PARAMETER WorkingDirectory
        The directory from which to execute the git command. If not specified,
        uses the current working directory.

    .EXAMPLE
        Invoke-GitCommand -Arguments 'status'

        Runs 'git status' and returns the output.

    .EXAMPLE
        Invoke-GitCommand -Arguments 'subtree', 'add', '--prefix=modules/MyModule', 'https://github.com/owner/repo.git', 'main', '--squash'

        Adds a module using git subtree with the squash option.

    .EXAMPLE
        Invoke-GitCommand -Arguments 'log', '--oneline', '-5' -WorkingDirectory '/path/to/repo'

        Shows the last 5 commits in oneline format from a specific repository.

    .OUTPUTS
        System.String[]
        Returns the output from the git command as an array of strings.

    .NOTES
        This is a private helper function used internally by PSSubtreeModules.
        Git 1.7.11 or later is required for subtree support.
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Arguments,

        [Parameter()]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]
        $WorkingDirectory
    )

    begin
    {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"

        # Verify git is available
        $gitPath = Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue
        if (-not $gitPath)
        {
            throw 'Git is not installed or not found in PATH. Please install Git 1.7.11 or later.'
        }
    }

    process
    {
        $gitArgs = $Arguments -join ' '
        Write-Verbose "Executing: git $gitArgs"

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
            # Execute git command and capture both stdout and stderr
            $result = & git @Arguments 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0)
            {
                # Convert error output to string for the error message
                $errorOutput = if ($result)
                {
                    ($result | ForEach-Object { $_.ToString() }) -join "`n"
                }
                else
                {
                    'No error output captured'
                }

                throw "Git command failed with exit code ${exitCode}: $errorOutput"
            }

            Write-Verbose "Git command completed successfully"

            # Return the result
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

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
