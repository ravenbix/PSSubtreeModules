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

                    # Return the file info
                    Get-Item -Path $fullPath
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

#region Helper Functions

function Get-SubtreeModulesYamlContent
{
    <#
    .SYNOPSIS
        Returns the default subtree-modules.yaml content.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @'
# PSSubtreeModules configuration
modules: {}
'@
}

function Get-GitIgnoreContent
{
    <#
    .SYNOPSIS
        Returns the default .gitignore content for PSSubtreeModules repositories.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @'
# PSSubtreeModules .gitignore

# PowerShell module build output
output/

# Temporary files
*.tmp
*~

# IDE and editor files
.vscode/
.idea/
*.sublime-*

# macOS
.DS_Store

# Windows
Thumbs.db
desktop.ini
'@
}

function Get-ReadmeContent
{
    <#
    .SYNOPSIS
        Returns the default README.md content for PSSubtreeModules repositories.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @'
# PowerShell Modules

This repository manages PowerShell modules using [PSSubtreeModules](https://github.com/your-org/PSSubtreeModules) with Git subtree.

## Quick Start

```powershell
# Add a module from GitHub
Add-PSSubtreeModule -Name 'ModuleName' -Repository 'https://github.com/owner/repo.git' -Ref 'main'

# List all tracked modules
Get-PSSubtreeModule

# Check for available updates
Get-PSSubtreeModuleStatus -UpdateAvailable

# Update a specific module
Update-PSSubtreeModule -Name 'ModuleName'

# Update all modules
Update-PSSubtreeModule -All

# Remove a module
Remove-PSSubtreeModule -Name 'ModuleName'
```

## Using the Modules

Add the `modules` directory to your PSModulePath:

```powershell
# Temporarily (current session only)
$env:PSModulePath = "$(Get-Location)/modules;$env:PSModulePath"

# Permanently (via profile)
Install-PSSubtreeModuleProfile
```

Then import modules as usual:

```powershell
Import-Module ModuleName
```

## Module Configuration

Modules are tracked in `subtree-modules.yaml`:

```yaml
modules:
  ModuleName:
    repo: https://github.com/owner/repo.git
    ref: main
```

## Checking for Updates

The included GitHub Actions workflow can check for module updates automatically. See `.github/workflows/check-updates.yml` for configuration.

To check manually:

```powershell
# Check all modules for updates
Get-PSSubtreeModuleStatus

# Filter to only modules with updates available
Get-PSSubtreeModuleStatus -UpdateAvailable
```

## Dependency Validation

Check if all module dependencies are satisfied:

```powershell
# Check all modules
Test-PSSubtreeModuleDependency

# Check a specific module
Test-PSSubtreeModuleDependency -Name 'ModuleName'
```

## Requirements

- PowerShell 5.1 or later
- Git 1.7.11 or later (for subtree support)
- PSSubtreeModules module
'@
}

function Get-CheckUpdatesWorkflowContent
{
    <#
    .SYNOPSIS
        Returns the GitHub Actions workflow content for checking module updates.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @'
name: Check Module Updates

on:
  workflow_dispatch:
  # Uncomment to enable scheduled runs:
  # schedule:
  #   - cron: '0 6 * * 1'  # Weekly on Monday at 6 AM

jobs:
  check-updates:
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - uses: actions/checkout@v4

      - name: Install PSSubtreeModules
        shell: pwsh
        run: |
          Install-Module -Name PSSubtreeModules -Scope CurrentUser -Force

      - name: Check for updates
        id: check
        shell: pwsh
        run: |
          $updates = Get-PSSubtreeModuleStatus -UpdateAvailable
          if ($updates) {
            $body = "The following modules have updates available:`n`n"
            foreach ($u in $updates) {
              $body += "- **$($u.Name)**: $($u.LocalCommit) -> $($u.UpstreamCommit)`n"
            }
            echo "has_updates=true" >> $env:GITHUB_OUTPUT
            echo "body<<EOF" >> $env:GITHUB_OUTPUT
            echo $body >> $env:GITHUB_OUTPUT
            echo "EOF" >> $env:GITHUB_OUTPUT
          }

      - name: Create/Update Issue
        if: steps.check.outputs.has_updates == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const title = 'Module Updates Available';
            const labels = ['dependencies', 'automated'];
            const body = `${{ steps.check.outputs.body }}`;

            const issues = await github.rest.issues.listForRepo({
              owner: context.repo.owner,
              repo: context.repo.repo,
              labels: labels.join(','),
              state: 'open'
            });

            const existing = issues.data.find(i => i.title === title);
            if (existing) {
              await github.rest.issues.update({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: existing.number,
                body: body
              });
            } else {
              await github.rest.issues.create({
                owner: context.repo.owner,
                repo: context.repo.repo,
                title: title,
                body: body,
                labels: labels
              });
            }
'@
}

#endregion Helper Functions
