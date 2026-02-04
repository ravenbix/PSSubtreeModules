function Initialize-PSSubtreeModule
{
    <#
    .SYNOPSIS
        Initializes a repository for PSSubtreeModules module management.

    .DESCRIPTION
        Creates the required directory structure and configuration files for managing
        PowerShell modules using Git subtree. This includes creating the modules directory,
        subtree-modules.yaml configuration file, .gitignore, README.md, and GitHub Actions
        workflow for checking module updates.

        This function should be run once in a Git repository before using other
        PSSubtreeModules functions to add and manage modules.

    .PARAMETER Path
        The path to the repository where the module structure should be created.
        If not specified, defaults to the current working directory.

    .PARAMETER Force
        If specified, overwrites existing files without prompting. Use with caution
        as this will replace any customizations made to the generated files.

    .EXAMPLE
        Initialize-PSSubtreeModule

        Initializes the current directory for PSSubtreeModules management.

    .EXAMPLE
        Initialize-PSSubtreeModule -Path 'C:\repos\my-modules'

        Initializes a specific directory for PSSubtreeModules management.

    .EXAMPLE
        Initialize-PSSubtreeModule -Force

        Initializes the current directory, overwriting any existing files.

    .EXAMPLE
        Initialize-PSSubtreeModule -WhatIf

        Shows what files would be created without actually creating them.

    .OUTPUTS
        System.IO.FileInfo
        Returns FileInfo objects for each created file.

    .NOTES
        This function creates the following structure:
        - .github/workflows/check-updates.yml  (GitHub Actions workflow)
        - modules/.gitkeep                     (Module storage directory)
        - .gitignore                           (Git ignore rules)
        - README.md                            (Documentation template)
        - subtree-modules.yaml                 (Module configuration)

        The repository must be a Git repository. If not, an error is thrown.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.IO.FileInfo])]
    param
    (
        [Parameter(Position = 0)]
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
        Write-Verbose "Initializing PSSubtreeModules in: $resolvedPath"

        # Check if directory exists
        if (-not (Test-Path -Path $resolvedPath -PathType Container))
        {
            $errorMessage = "The specified path does not exist or is not a directory: $resolvedPath"
            Write-Error -Message $errorMessage -Category ObjectNotFound -ErrorId 'PathNotFound'
            return
        }

        # Check if it's a Git repository
        $gitDir = Join-Path -Path $resolvedPath -ChildPath '.git'
        if (-not (Test-Path -Path $gitDir))
        {
            $errorMessage = "The specified path is not a Git repository: $resolvedPath. Initialize a Git repository first with 'git init'."
            Write-Error -Message $errorMessage -Category InvalidOperation -ErrorId 'NotGitRepository'
            return
        }

        # Define all files to create
        $filesToCreate = @(
            @{
                RelativePath = 'subtree-modules.yaml'
                Content      = Get-SubtreeModulesYamlContent
            }
            @{
                RelativePath = 'modules/.gitkeep'
                Content      = ''
            }
            @{
                RelativePath = '.gitignore'
                Content      = Get-GitIgnoreContent
            }
            @{
                RelativePath = 'README.md'
                Content      = Get-ReadmeContent
            }
            @{
                RelativePath = '.github/workflows/check-updates.yml'
                Content      = Get-CheckUpdatesWorkflowContent
            }
        )

        # Create each file
        foreach ($fileSpec in $filesToCreate)
        {
            $fullPath = Join-Path -Path $resolvedPath -ChildPath $fileSpec.RelativePath
            $fileExists = Test-Path -Path $fullPath

            # Check if we should skip this file
            if ($fileExists -and -not $Force)
            {
                Write-Warning "File already exists and will be skipped: $($fileSpec.RelativePath). Use -Force to overwrite."
                continue
            }

            # Determine action description
            $action = if ($fileExists) { 'Overwrite' } else { 'Create' }

            if ($PSCmdlet.ShouldProcess($fileSpec.RelativePath, $action))
            {
                try
                {
                    # Ensure parent directory exists
                    $parentDir = Split-Path -Path $fullPath -Parent
                    if ($parentDir -and -not (Test-Path -Path $parentDir))
                    {
                        Write-Verbose "Creating directory: $parentDir"
                        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
                    }

                    # Write the file
                    Write-Verbose "$action file: $fullPath"
                    Set-Content -Path $fullPath -Value $fileSpec.Content -Encoding UTF8 -NoNewline -ErrorAction Stop

                    # Return the file info (use -Force to handle hidden files like .gitignore and .gitkeep)
                    Get-Item -Path $fullPath -Force
                }
                catch
                {
                    $errorMessage = "Failed to create file '$($fileSpec.RelativePath)': $($_.Exception.Message)"
                    Write-Error -Message $errorMessage -Category WriteError -ErrorId 'FileCreationError'
                }
            }
        }

        Write-Verbose "PSSubtreeModules initialization complete"
    }

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
