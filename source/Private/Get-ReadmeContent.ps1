function Get-ReadmeContent
{
    <#
    .SYNOPSIS
        Returns the default README.md content for PSSubtreeModules repositories.

    .DESCRIPTION
        Returns a string containing the default content for the README.md file
        used by PSSubtreeModules repositories. The content includes documentation
        for:
        - Quick start guide with common commands
        - PSModulePath configuration
        - Module configuration via subtree-modules.yaml
        - Checking for module updates
        - Dependency validation
        - System requirements

        This function is used internally by Initialize-PSSubtreeModule to generate
        the README.md file.

    .EXAMPLE
        $content = Get-ReadmeContent

        Returns the default content for a README.md file.

    .OUTPUTS
        System.String
        Returns a string containing the README.md markdown content.

    .NOTES
        This is a private helper function used internally by PSSubtreeModules.
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
