function Install-PSSubtreeModuleProfile
{
    <#
    .SYNOPSIS
        Configures PSModulePath in user's PowerShell profile.

    .DESCRIPTION
        Modifies the user's PowerShell profile to include the modules directory from a
        PSSubtreeModules-managed repository in the PSModulePath environment variable.

        This makes modules tracked by PSSubtreeModules available for import without
        manually modifying the module path each session.

        The function is idempotent - running it multiple times will not create duplicate
        entries in the profile. The change is also applied to the current session.

    .PARAMETER Path
        The path to the repository containing the modules directory.
        If not specified, defaults to the current working directory.

    .PARAMETER ProfilePath
        The path to the PowerShell profile to modify.
        If not specified, defaults to the CurrentUserAllHosts profile ($PROFILE.CurrentUserAllHosts).

    .PARAMETER Force
        If specified, overwrites an existing entry even if it appears to be present.
        Use this to repair a corrupted profile entry.

    .EXAMPLE
        Install-PSSubtreeModuleProfile

        Adds the modules directory from the current directory to the default profile
        and applies the change to the current session.

    .EXAMPLE
        Install-PSSubtreeModuleProfile -Path 'C:\repos\my-modules'

        Adds the modules directory from the specified repository path to the profile.

    .EXAMPLE
        Install-PSSubtreeModuleProfile -ProfilePath $PROFILE.CurrentUserCurrentHost

        Uses the current-host-only profile instead of the all-hosts profile.

    .EXAMPLE
        Install-PSSubtreeModuleProfile -WhatIf

        Shows what changes would be made without actually modifying the profile.

    .OUTPUTS
        PSCustomObject
        Returns an object with details about the profile modification:
        - ProfilePath: The profile file that was modified
        - ModulesPath: The modules directory path that was added
        - AppliedToCurrentSession: Boolean indicating if the current session was updated

    .NOTES
        - If the profile file doesn't exist, it will be created
        - The function adds code to the profile that checks if the path exists before adding it
        - The modules directory must exist in the specified repository
        - Changes take effect immediately in the current session and in future sessions
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path = (Get-Location),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ProfilePath,

        [Parameter()]
        [switch]
        $Force
    )

    begin
    {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"

        # Determine which profile to use
        if ([string]::IsNullOrEmpty($ProfilePath))
        {
            # Use CurrentUserAllHosts profile by default
            if ($null -ne $PROFILE -and $PROFILE -is [System.Management.Automation.PSObject])
            {
                $ProfilePath = $PROFILE.CurrentUserAllHosts
            }
            elseif ($null -ne $PROFILE)
            {
                $ProfilePath = $PROFILE
            }
            else
            {
                # Fallback for edge cases where $PROFILE is not available
                if ($IsWindows -or (-not $PSVersionTable.PSEdition -or $PSVersionTable.PSEdition -eq 'Desktop'))
                {
                    $ProfilePath = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'PowerShell\profile.ps1'
                }
                else
                {
                    $ProfilePath = Join-Path -Path $HOME -ChildPath '.config/powershell/profile.ps1'
                }
            }
        }

        Write-Verbose "Using profile: $ProfilePath"
    }

    process
    {
        # Resolve to absolute path
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        Write-Verbose "Repository path: $resolvedPath"

        # Validate the directory exists
        if (-not (Test-Path -Path $resolvedPath -PathType Container))
        {
            $errorMessage = "The specified path does not exist or is not a directory: $resolvedPath"
            Write-Error -Message $errorMessage -Category ObjectNotFound -ErrorId 'PathNotFound'
            return
        }

        # Determine the modules directory path
        $modulesPath = Join-Path -Path $resolvedPath -ChildPath 'modules'

        # Validate modules directory exists
        if (-not (Test-Path -Path $modulesPath -PathType Container))
        {
            $errorMessage = "The modules directory does not exist: $modulesPath. Initialize the repository with Initialize-PSSubtreeModule first."
            Write-Error -Message $errorMessage -Category ObjectNotFound -ErrorId 'ModulesDirectoryNotFound'
            return
        }

        Write-Verbose "Modules path to add: $modulesPath"

        # Create the profile snippet to add
        # Use a marker comment for idempotent detection and clean removal
        $markerStart = "# PSSubtreeModules: $modulesPath"
        $profileSnippet = @"

$markerStart
if (Test-Path -Path '$modulesPath') {
    `$env:PSModulePath = '$modulesPath' + [System.IO.Path]::PathSeparator + `$env:PSModulePath
}
# End PSSubtreeModules
"@

        # Check if profile file exists
        $profileExists = Test-Path -Path $ProfilePath -PathType Leaf
        Write-Verbose "Profile exists: $profileExists"

        # Check if already configured (idempotent check)
        $alreadyConfigured = $false
        if ($profileExists)
        {
            try
            {
                $existingContent = Get-Content -Path $ProfilePath -Raw -ErrorAction Stop
                if ($existingContent -and $existingContent.Contains($markerStart))
                {
                    $alreadyConfigured = $true
                    Write-Verbose "Profile already contains PSSubtreeModules configuration for this path"
                }
            }
            catch
            {
                Write-Verbose "Could not read profile to check existing configuration: $($_.Exception.Message)"
            }
        }

        # Determine what action to take
        if ($alreadyConfigured -and -not $Force)
        {
            Write-Verbose "Profile already configured. Use -Force to overwrite."
            Write-Warning "PSModulePath configuration for '$modulesPath' already exists in profile. Use -Force to reinstall."

            # Still apply to current session if not already present
            $appliedToSession = $false
            if (-not ($env:PSModulePath -split [System.IO.Path]::PathSeparator).Contains($modulesPath))
            {
                if ($PSCmdlet.ShouldProcess('Current Session', 'Add modules path to PSModulePath'))
                {
                    $env:PSModulePath = $modulesPath + [System.IO.Path]::PathSeparator + $env:PSModulePath
                    Write-Verbose "Applied to current session"
                    $appliedToSession = $true
                }
            }

            return [PSCustomObject]@{
                PSTypeName               = 'PSSubtreeModules.ProfileInstallation'
                ProfilePath              = $ProfilePath
                ModulesPath              = $modulesPath
                Status                   = 'AlreadyConfigured'
                AppliedToCurrentSession  = $appliedToSession
            }
        }

        # Build the action description
        $action = if ($profileExists) { 'Modify' } else { 'Create' }

        if ($PSCmdlet.ShouldProcess($ProfilePath, "$action profile to add PSModulePath entry"))
        {
            try
            {
                # Ensure the profile directory exists
                $profileDir = Split-Path -Path $ProfilePath -Parent
                if ($profileDir -and -not (Test-Path -Path $profileDir))
                {
                    Write-Verbose "Creating profile directory: $profileDir"
                    New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
                }

                # Handle existing content
                $newContent = ''
                if ($profileExists)
                {
                    $existingContent = Get-Content -Path $ProfilePath -Raw -ErrorAction Stop

                    if ($Force -and $existingContent -and $existingContent.Contains($markerStart))
                    {
                        # Remove existing entry when using -Force
                        Write-Verbose "Removing existing PSSubtreeModules entry (Force mode)"
                        $pattern = [regex]::Escape($markerStart) + '[\s\S]*?# End PSSubtreeModules\r?\n?'
                        $existingContent = [regex]::Replace($existingContent, $pattern, '')
                    }

                    $newContent = $existingContent
                }

                # Append the new snippet
                $newContent = $newContent.TrimEnd() + $profileSnippet + "`n"

                # Write the profile
                Write-Verbose "Writing profile: $ProfilePath"
                Set-Content -Path $ProfilePath -Value $newContent -Encoding UTF8 -NoNewline -ErrorAction Stop

                Write-Verbose "Profile updated successfully"

                # Apply to current session
                $appliedToSession = $false
                if (-not ($env:PSModulePath -split [System.IO.Path]::PathSeparator).Contains($modulesPath))
                {
                    $env:PSModulePath = $modulesPath + [System.IO.Path]::PathSeparator + $env:PSModulePath
                    Write-Verbose "Applied to current session"
                    $appliedToSession = $true
                }
                else
                {
                    Write-Verbose "Path already in current session PSModulePath"
                    $appliedToSession = $true
                }

                # Return result
                [PSCustomObject]@{
                    PSTypeName               = 'PSSubtreeModules.ProfileInstallation'
                    ProfilePath              = $ProfilePath
                    ModulesPath              = $modulesPath
                    Status                   = 'Installed'
                    AppliedToCurrentSession  = $appliedToSession
                }
            }
            catch
            {
                $errorMessage = "Failed to update profile: $($_.Exception.Message)"
                Write-Error -Message $errorMessage -Category WriteError -ErrorId 'ProfileUpdateError'
            }
        }
    }

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
