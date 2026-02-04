# PSSubtreeModules

Manage PowerShell module collections using Git subtree for version-controlled, offline-capable module management.

[![Build Status](https://github.com/your-org/PSSubtreeModules/workflows/CI/badge.svg)](https://github.com/your-org/PSSubtreeModules/actions)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/PSSubtreeModules.svg)](https://www.powershellgallery.com/packages/PSSubtreeModules)

## Overview

PSSubtreeModules provides a Git subtree-based approach to managing PowerShell module dependencies. It's designed for environments where:

- **PSResourceGet/PowerShellGet is unavailable** - Air-gapped or restricted environments
- **Version control of dependencies is required** - Track exact module versions in your repository
- **Offline operation is needed** - No network access required after initial setup
- **Reproducible builds are essential** - Same modules, same versions, every time

## Features

- **Git Subtree Integration** - Leverages Git's built-in subtree functionality with `--squash` for clean history
- **YAML Configuration** - Human-readable `subtree-modules.yaml` tracks all modules
- **Update Detection** - Check for upstream updates without modifying your repository
- **Dependency Validation** - Verify module dependencies are satisfied
- **Profile Integration** - Automatically configure PSModulePath for seamless module loading
- **Conventional Commits** - Standardized commit messages for module operations
- **GitHub Actions Support** - Automated update checking workflow included

## Requirements

- **PowerShell** 5.1 or later (Windows PowerShell or PowerShell Core 7+)
- **Git** 1.7.11 or later (for subtree support)
- **powershell-yaml** module (automatically installed as dependency)

## Installation

### From PowerShell Gallery (Recommended)

```powershell
Install-Module -Name PSSubtreeModules -Scope CurrentUser
```

### Manual Installation

```powershell
# Clone the repository
git clone https://github.com/your-org/PSSubtreeModules.git

# Build the module
cd PSSubtreeModules
./build.ps1 -Tasks build

# Import the built module
Import-Module ./output/module/PSSubtreeModules/0.0.1/PSSubtreeModules.psd1
```

### Verify Installation

```powershell
Get-Module -Name PSSubtreeModules -ListAvailable
Get-Command -Module PSSubtreeModules
```

## Quick Start

### 1. Initialize a Repository

Create a new Git repository for managing your module collection:

```powershell
# Create and initialize a new directory
mkdir my-modules
cd my-modules
git init

# Initialize PSSubtreeModules structure
Initialize-PSSubtreeModule
```

This creates:
- `subtree-modules.yaml` - Module configuration file
- `modules/` - Directory where modules will be stored
- `.gitignore` - Standard ignore patterns
- `README.md` - Documentation template
- `.github/workflows/check-updates.yml` - GitHub Actions workflow

### 2. Add Modules

Add modules from GitHub or other Git repositories:

```powershell
# Add a module from the main branch
Add-PSSubtreeModule -Name 'Pester' -Repository 'https://github.com/pester/Pester.git'

# Add a module pinned to a specific version tag
Add-PSSubtreeModule -Name 'PSScriptAnalyzer' -Repository 'https://github.com/PowerShell/PSScriptAnalyzer.git' -Ref 'v1.21.0'

# Add a module from a specific branch
Add-PSSubtreeModule -Name 'MyModule' -Repository 'https://github.com/owner/MyModule.git' -Ref 'develop'
```

### 3. Use the Modules

Make the modules available in your PowerShell session:

```powershell
# Option 1: Permanently add to your profile
Install-PSSubtreeModuleProfile

# Option 2: Temporarily add to current session
$env:PSModulePath = "$(Get-Location)/modules" + [System.IO.Path]::PathSeparator + $env:PSModulePath

# Now import and use modules normally
Import-Module Pester
```

### 4. Check for Updates

```powershell
# Check status of all modules
Get-PSSubtreeModuleStatus

# Show only modules with available updates
Get-PSSubtreeModuleStatus -UpdateAvailable

# Check a specific module
Get-PSSubtreeModuleStatus -Name 'Pester'
```

### 5. Update Modules

```powershell
# Update a specific module to latest
Update-PSSubtreeModule -Name 'Pester'

# Update to a specific version
Update-PSSubtreeModule -Name 'Pester' -Ref 'v5.5.0'

# Update all modules
Update-PSSubtreeModule -All
```

### 6. Remove Modules

```powershell
# Remove a module (prompts for confirmation)
Remove-PSSubtreeModule -Name 'OldModule'

# Remove without confirmation
Remove-PSSubtreeModule -Name 'OldModule' -Force
```

## Command Reference

### Initialize-PSSubtreeModule

Creates the directory structure and configuration files for PSSubtreeModules.

```powershell
Initialize-PSSubtreeModule [-Path <String>] [-Force] [-WhatIf] [-Confirm]
```

**Parameters:**
- `-Path` - Repository path (default: current directory)
- `-Force` - Overwrite existing files
- `-WhatIf` - Preview changes without applying

**Example:**
```powershell
Initialize-PSSubtreeModule -Path 'C:\repos\my-modules'
```

### Add-PSSubtreeModule

Adds a module from a Git repository using git subtree.

```powershell
Add-PSSubtreeModule -Name <String> -Repository <String> [-Ref <String>] [-Path <String>] [-Force] [-WhatIf] [-Confirm]
```

**Parameters:**
- `-Name` - Module name (becomes directory name under `modules/`)
- `-Repository` - Git repository URL (HTTPS or SSH)
- `-Ref` - Branch, tag, or commit (default: `main`)
- `-Path` - Repository path (default: current directory)
- `-Force` - Overwrite existing configuration entry

**Example:**
```powershell
Add-PSSubtreeModule -Name 'PSReadLine' -Repository 'https://github.com/PowerShell/PSReadLine.git' -Ref 'v2.3.4'
```

### Get-PSSubtreeModule

Lists tracked modules from configuration.

```powershell
Get-PSSubtreeModule [[-Name] <String>] [-Path <String>]
```

**Parameters:**
- `-Name` - Module name pattern with wildcard support (default: `*`)
- `-Path` - Repository path (default: current directory)

**Examples:**
```powershell
# List all modules
Get-PSSubtreeModule

# Find modules starting with 'PS'
Get-PSSubtreeModule -Name 'PS*'

# Get a specific module
Get-PSSubtreeModule -Name 'Pester'
```

### Update-PSSubtreeModule

Updates modules to latest or specific version.

```powershell
Update-PSSubtreeModule -Name <String> [-Ref <String>] [-Path <String>] [-WhatIf] [-Confirm]
Update-PSSubtreeModule -All [-Path <String>] [-WhatIf] [-Confirm]
```

**Parameters:**
- `-Name` - Module name to update
- `-Ref` - New branch/tag to track (updates configuration)
- `-All` - Update all tracked modules
- `-Path` - Repository path (default: current directory)

**Examples:**
```powershell
# Update to latest on current branch
Update-PSSubtreeModule -Name 'Pester'

# Switch to a new version
Update-PSSubtreeModule -Name 'Pester' -Ref 'v5.5.0'

# Update everything
Update-PSSubtreeModule -All
```

### Remove-PSSubtreeModule

Removes a module from the repository.

```powershell
Remove-PSSubtreeModule -Name <String> [-Path <String>] [-Force] [-WhatIf] [-Confirm]
```

**Parameters:**
- `-Name` - Module name to remove
- `-Path` - Repository path (default: current directory)
- `-Force` - Skip confirmation prompt

**Example:**
```powershell
Get-PSSubtreeModule -Name 'Old*' | Remove-PSSubtreeModule -Force
```

### Get-PSSubtreeModuleStatus

Checks for available upstream updates.

```powershell
Get-PSSubtreeModuleStatus [[-Name] <String>] [-UpdateAvailable] [-Path <String>]
```

**Parameters:**
- `-Name` - Module name pattern with wildcard support (default: `*`)
- `-UpdateAvailable` - Only return modules with updates available
- `-Path` - Repository path (default: current directory)

**Output Properties:**
- `Name` - Module name
- `Ref` - Tracked branch/tag
- `Status` - `Current`, `UpdateAvailable`, or `Unknown`
- `LocalCommit` - Short hash of local version
- `UpstreamCommit` - Short hash of upstream version

**Examples:**
```powershell
# Check all modules
Get-PSSubtreeModuleStatus

# Find modules needing updates
Get-PSSubtreeModuleStatus -UpdateAvailable | Format-Table

# Check specific module with details
Get-PSSubtreeModuleStatus -Name 'Pester' -Verbose
```

### Test-PSSubtreeModuleDependency

Validates module dependencies are satisfied.

```powershell
Test-PSSubtreeModuleDependency [[-Name] <String>] [-Path <String>]
```

**Parameters:**
- `-Name` - Module name pattern with wildcard support (default: `*`)
- `-Path` - Repository path (default: current directory)

**Output Properties:**
- `Name` - Module name
- `AllDependenciesMet` - Boolean indicating all dependencies are satisfied
- `RequiredModules` - Array of required module dependency status
- `MissingDependencies` - List of missing dependency names

**Examples:**
```powershell
# Check all modules
Test-PSSubtreeModuleDependency

# Find modules with missing dependencies
Test-PSSubtreeModuleDependency | Where-Object { -not $_.AllDependenciesMet }

# Check specific module
Test-PSSubtreeModuleDependency -Name 'MyModule' -Verbose
```

### Install-PSSubtreeModuleProfile

Configures PSModulePath in user's PowerShell profile.

```powershell
Install-PSSubtreeModuleProfile [[-Path] <String>] [-ProfilePath <String>] [-Force] [-WhatIf] [-Confirm]
```

**Parameters:**
- `-Path` - Repository containing modules (default: current directory)
- `-ProfilePath` - Profile file to modify (default: `$PROFILE.CurrentUserAllHosts`)
- `-Force` - Reinstall even if already configured

**Output Properties:**
- `ProfilePath` - Profile file that was modified
- `ModulesPath` - Path added to PSModulePath
- `Status` - `Installed` or `AlreadyConfigured`
- `AppliedToCurrentSession` - Whether current session was updated

**Example:**
```powershell
# Configure default profile
Install-PSSubtreeModuleProfile

# Use a specific profile
Install-PSSubtreeModuleProfile -ProfilePath $PROFILE.CurrentUserCurrentHost
```

## Configuration File

The `subtree-modules.yaml` file tracks all managed modules:

```yaml
# PSSubtreeModules configuration
modules:
  Pester:
    repo: https://github.com/pester/Pester.git
    ref: main

  PSScriptAnalyzer:
    repo: https://github.com/PowerShell/PSScriptAnalyzer.git
    ref: v1.21.0
    # Pinned to stable release
```

## GitHub Actions Integration

The initialized repository includes a GitHub Actions workflow (`.github/workflows/check-updates.yml`) that can:

- Check for module updates on demand or on a schedule
- Create/update an issue when updates are available

**To enable scheduled checks**, edit the workflow file and uncomment the schedule:

```yaml
on:
  workflow_dispatch:
  schedule:
    - cron: '0 6 * * 1'  # Weekly on Monday at 6 AM
```

**Note:** The workflow requires `dependencies` and `automated` labels to be created in your repository settings.

## Common Workflows

### Setting Up a New Project

```powershell
# Create project directory
mkdir my-project
cd my-project
git init

# Initialize PSSubtreeModules
Initialize-PSSubtreeModule

# Add your dependencies
Add-PSSubtreeModule -Name 'Pester' -Repository 'https://github.com/pester/Pester.git' -Ref 'v5.5.0'
Add-PSSubtreeModule -Name 'PSScriptAnalyzer' -Repository 'https://github.com/PowerShell/PSScriptAnalyzer.git' -Ref 'v1.21.0'

# Configure profile for easy access
Install-PSSubtreeModuleProfile

# Commit the initial setup
git add .
git commit -m "Initial module setup"
```

### Updating All Modules Before Release

```powershell
# Check what's available
Get-PSSubtreeModuleStatus | Format-Table Name, Ref, Status, LocalCommit, UpstreamCommit

# Update modules with available updates
Get-PSSubtreeModuleStatus -UpdateAvailable | ForEach-Object {
    Update-PSSubtreeModule -Name $_.Name
}

# Verify dependencies still work
Test-PSSubtreeModuleDependency | Where-Object { -not $_.AllDependenciesMet }
```

### Cloning and Setting Up an Existing Repository

```powershell
# Clone the repository (modules are included via subtree)
git clone https://github.com/your-org/my-project.git
cd my-project

# Configure your profile to use the modules
Install-PSSubtreeModuleProfile

# Verify everything is working
Get-PSSubtreeModule
Test-PSSubtreeModuleDependency
```

## Troubleshooting

### "Repository has not been initialized for PSSubtreeModules"

Run `Initialize-PSSubtreeModule` first to create the required structure.

### "Module already exists in configuration"

The module is already tracked. Use `-Force` to update the configuration entry, or use `Update-PSSubtreeModule` to update the module content.

### Git subtree operations fail

Ensure your Git version is 1.7.11 or later:
```powershell
git --version
```

### Module not found after adding

Verify the module is in `modules/` directory and your PSModulePath is configured:
```powershell
$env:PSModulePath -split [System.IO.Path]::PathSeparator
```

### Status shows "Unknown"

This typically means:
- Network issues preventing upstream checks
- Module wasn't added via git subtree (no subtree metadata in commit history)

Run with `-Verbose` for more details:
```powershell
Get-PSSubtreeModuleStatus -Name 'ModuleName' -Verbose
```

## Development

### Building the Module

```powershell
# Build only
./build.ps1 -Tasks build

# Run tests
./build.ps1 -Tasks test

# Build and test
./build.ps1 -Tasks build, test
```

### Running Tests

```powershell
# All tests
./build.ps1 -Tasks test

# Specific test file
Invoke-Pester -Path tests/Unit/Public/Get-PSSubtreeModule.Tests.ps1 -Output Detailed
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Related Projects

- [PowerShellGet](https://github.com/PowerShell/PowerShellGet) - Official PowerShell module management
- [PSDepend](https://github.com/RamblingCookieMonster/PSDepend) - Dependency management for PowerShell
- [ModuleFast](https://github.com/JustinGrote/ModuleFast) - High-performance module installer
