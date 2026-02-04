function Test-PSSubtreeModuleDependency
{
    <#
    .SYNOPSIS
        Validates module dependencies for tracked PSSubtreeModules.

    .DESCRIPTION
        Analyzes the module manifest (.psd1) files of tracked modules to identify
        their dependencies (RequiredModules, ExternalModuleDependencies, NestedModules)
        and validates whether those dependencies are satisfied.

        Dependencies are checked against:
        - Other modules tracked in the modules/ directory
        - Modules available in the PSModulePath

        Uses Import-PowerShellDataFile to parse manifests (not Test-ModuleManifest)
        which allows dependency validation even when dependencies aren't installed.

    .PARAMETER Name
        The name of the module(s) to check. Supports wildcard characters.
        If not specified, defaults to '*' which checks all tracked modules.

    .PARAMETER Path
        The path to the repository containing the subtree-modules.yaml configuration.
        If not specified, defaults to the current working directory.

    .EXAMPLE
        Test-PSSubtreeModuleDependency

        Validates dependencies for all tracked modules and returns their status.

    .EXAMPLE
        Test-PSSubtreeModuleDependency -Name 'Pester'

        Validates dependencies for the Pester module only.

    .EXAMPLE
        Test-PSSubtreeModuleDependency -Name 'PS*'

        Validates dependencies for all modules starting with 'PS'.

    .EXAMPLE
        Test-PSSubtreeModuleDependency | Where-Object { -not $_.AllDependenciesMet }

        Returns only modules that have missing dependencies.

    .EXAMPLE
        Test-PSSubtreeModuleDependency -Verbose

        Validates all modules with verbose output showing dependency resolution details.

    .OUTPUTS
        PSCustomObject
        Returns objects with the following properties:
        - Name: The module name
        - ManifestPath: Path to the module manifest file
        - AllDependenciesMet: Boolean indicating if all dependencies are satisfied
        - RequiredModules: Array of required module dependencies and their status
        - ExternalModuleDependencies: Array of external dependencies and their status
        - NestedModules: Array of nested module dependencies and their status
        - MissingDependencies: Array of dependency names that are not satisfied

    .NOTES
        This function uses Import-PowerShellDataFile instead of Test-ModuleManifest
        because Test-ModuleManifest fails when dependencies aren't installed.
        Import-PowerShellDataFile parses the manifest as a hashtable without
        validating that dependencies exist.

        Dependencies are searched in:
        1. The modules/ directory of the repository (other tracked modules)
        2. Standard PowerShell module paths ($env:PSModulePath)
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
        [ValidateNotNullOrEmpty()]
        [string]
        $Path = (Get-Location)
    )

    begin
    {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"

        # Build list of available module paths to search
        $script:modulePaths = @()

        # Add the modules directory from the repository
        $modulesDir = Join-Path -Path $Path -ChildPath 'modules'
        if (Test-Path -Path $modulesDir -PathType Container)
        {
            $script:modulePaths += $modulesDir
            Write-Verbose "Added modules directory to search path: $modulesDir"
        }

        # Add PSModulePath entries
        $psPaths = $env:PSModulePath -split [System.IO.Path]::PathSeparator
        foreach ($psPath in $psPaths)
        {
            if (-not [string]::IsNullOrWhiteSpace($psPath) -and (Test-Path -Path $psPath -PathType Container))
            {
                $script:modulePaths += $psPath
                Write-Verbose "Added PSModulePath entry: $psPath"
            }
        }

        # Helper function to find a module by name
        function Find-DependencyModule
        {
            param
            (
                [Parameter(Mandatory = $true)]
                [string]
                $ModuleName,

                [Parameter()]
                [string]
                $RequiredVersion = $null,

                [Parameter()]
                [string]
                $MinimumVersion = $null,

                [Parameter()]
                [string]
                $MaximumVersion = $null
            )

            Write-Verbose "    Searching for dependency: $ModuleName"

            foreach ($searchPath in $script:modulePaths)
            {
                $modulePath = Join-Path -Path $searchPath -ChildPath $ModuleName

                if (Test-Path -Path $modulePath -PathType Container)
                {
                    # Check for a manifest in the module directory
                    $manifestPath = Join-Path -Path $modulePath -ChildPath "$ModuleName.psd1"

                    if (Test-Path -Path $manifestPath -PathType Leaf)
                    {
                        Write-Verbose "      Found at: $manifestPath"

                        # If version requirements specified, validate them
                        if ($RequiredVersion -or $MinimumVersion -or $MaximumVersion)
                        {
                            try
                            {
                                $manifest = Import-PowerShellDataFile -Path $manifestPath
                                $foundVersion = [version]$manifest.ModuleVersion

                                if ($RequiredVersion -and $foundVersion -ne [version]$RequiredVersion)
                                {
                                    Write-Verbose "      Version mismatch: found $foundVersion, required $RequiredVersion"
                                    continue
                                }

                                if ($MinimumVersion -and $foundVersion -lt [version]$MinimumVersion)
                                {
                                    Write-Verbose "      Version too low: found $foundVersion, minimum $MinimumVersion"
                                    continue
                                }

                                if ($MaximumVersion -and $foundVersion -gt [version]$MaximumVersion)
                                {
                                    Write-Verbose "      Version too high: found $foundVersion, maximum $MaximumVersion"
                                    continue
                                }

                                Write-Verbose "      Version $foundVersion meets requirements"
                            }
                            catch
                            {
                                Write-Verbose "      Could not parse version from manifest: $($_.Exception.Message)"
                            }
                        }

                        return @{
                            Found        = $true
                            Path         = $manifestPath
                            SearchedPath = $searchPath
                        }
                    }
                }
            }

            Write-Verbose "      Not found in any search path"
            return @{
                Found        = $false
                Path         = $null
                SearchedPath = $null
            }
        }

        # Helper function to parse dependency specification
        function Get-DependencyInfo
        {
            param
            (
                [Parameter(Mandatory = $true)]
                $Dependency
            )

            # Dependencies can be:
            # - String: just the module name
            # - Hashtable: @{ ModuleName = 'Name'; ModuleVersion = '1.0.0'; RequiredVersion = '1.0.0' }

            if ($Dependency -is [string])
            {
                return @{
                    ModuleName      = $Dependency
                    RequiredVersion = $null
                    MinimumVersion  = $null
                    MaximumVersion  = $null
                }
            }
            elseif ($Dependency -is [hashtable] -or $Dependency -is [System.Collections.Specialized.OrderedDictionary])
            {
                return @{
                    ModuleName      = $Dependency.ModuleName
                    RequiredVersion = $Dependency.RequiredVersion
                    MinimumVersion  = $Dependency.ModuleVersion  # ModuleVersion is minimum version
                    MaximumVersion  = $Dependency.MaximumVersion
                }
            }
            else
            {
                Write-Verbose "      Unknown dependency type: $($Dependency.GetType().Name)"
                return @{
                    ModuleName      = $Dependency.ToString()
                    RequiredVersion = $null
                    MinimumVersion  = $null
                    MaximumVersion  = $null
                }
            }
        }
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

        # Iterate through modules and check dependencies
        foreach ($moduleName in $config.modules.Keys)
        {
            # Use -like operator for wildcard matching
            if ($moduleName -notlike $Name)
            {
                continue
            }

            Write-Verbose "Checking dependencies for module: $moduleName"

            # Find the module manifest
            $modulePath = Join-Path -Path $Path -ChildPath "modules/$moduleName"
            $manifestPath = Join-Path -Path $modulePath -ChildPath "$moduleName.psd1"

            # Initialize result
            $result = [PSCustomObject]@{
                PSTypeName                  = 'PSSubtreeModules.DependencyInfo'
                Name                        = $moduleName
                ManifestPath                = $null
                AllDependenciesMet          = $true
                RequiredModules             = @()
                ExternalModuleDependencies  = @()
                NestedModules               = @()
                MissingDependencies         = @()
            }

            # Check if manifest exists
            if (-not (Test-Path -Path $manifestPath -PathType Leaf))
            {
                # Try to find any .psd1 file in the module directory
                $manifestFiles = Get-ChildItem -Path $modulePath -Filter '*.psd1' -ErrorAction SilentlyContinue
                if ($manifestFiles -and $manifestFiles.Count -gt 0)
                {
                    $manifestPath = $manifestFiles[0].FullName
                    Write-Verbose "  Using manifest: $manifestPath"
                }
                else
                {
                    Write-Warning "Module manifest not found for '$moduleName' at: $manifestPath"
                    $result.AllDependenciesMet = $false
                    $result
                    continue
                }
            }

            $result.ManifestPath = $manifestPath
            Write-Verbose "  Manifest: $manifestPath"

            # Parse the manifest using Import-PowerShellDataFile
            try
            {
                $manifest = Import-PowerShellDataFile -Path $manifestPath
            }
            catch
            {
                Write-Warning "Failed to parse manifest for '$moduleName': $($_.Exception.Message)"
                $result.AllDependenciesMet = $false
                $result
                continue
            }

            $missingDeps = @()

            # Check RequiredModules
            if ($manifest.RequiredModules)
            {
                Write-Verbose "  Checking RequiredModules ($($manifest.RequiredModules.Count) entries)"

                foreach ($dep in $manifest.RequiredModules)
                {
                    $depInfo = Get-DependencyInfo -Dependency $dep
                    $findResult = Find-DependencyModule -ModuleName $depInfo.ModuleName `
                        -RequiredVersion $depInfo.RequiredVersion `
                        -MinimumVersion $depInfo.MinimumVersion `
                        -MaximumVersion $depInfo.MaximumVersion

                    $depResult = [PSCustomObject]@{
                        Name            = $depInfo.ModuleName
                        RequiredVersion = $depInfo.RequiredVersion
                        MinimumVersion  = $depInfo.MinimumVersion
                        MaximumVersion  = $depInfo.MaximumVersion
                        Found           = $findResult.Found
                        FoundPath       = $findResult.Path
                    }

                    $result.RequiredModules += $depResult

                    if (-not $findResult.Found)
                    {
                        $missingDeps += $depInfo.ModuleName
                        $result.AllDependenciesMet = $false
                    }
                }
            }

            # Check ExternalModuleDependencies
            if ($manifest.ExternalModuleDependencies)
            {
                Write-Verbose "  Checking ExternalModuleDependencies ($($manifest.ExternalModuleDependencies.Count) entries)"

                foreach ($dep in $manifest.ExternalModuleDependencies)
                {
                    $depInfo = Get-DependencyInfo -Dependency $dep
                    $findResult = Find-DependencyModule -ModuleName $depInfo.ModuleName `
                        -RequiredVersion $depInfo.RequiredVersion `
                        -MinimumVersion $depInfo.MinimumVersion `
                        -MaximumVersion $depInfo.MaximumVersion

                    $depResult = [PSCustomObject]@{
                        Name            = $depInfo.ModuleName
                        RequiredVersion = $depInfo.RequiredVersion
                        MinimumVersion  = $depInfo.MinimumVersion
                        MaximumVersion  = $depInfo.MaximumVersion
                        Found           = $findResult.Found
                        FoundPath       = $findResult.Path
                    }

                    $result.ExternalModuleDependencies += $depResult

                    if (-not $findResult.Found)
                    {
                        $missingDeps += $depInfo.ModuleName
                        $result.AllDependenciesMet = $false
                    }
                }
            }

            # Check NestedModules (only module references, not script files)
            if ($manifest.NestedModules)
            {
                Write-Verbose "  Checking NestedModules ($($manifest.NestedModules.Count) entries)"

                foreach ($dep in $manifest.NestedModules)
                {
                    $depInfo = Get-DependencyInfo -Dependency $dep

                    # Skip script files (.ps1, .psm1) - they are internal to the module
                    if ($depInfo.ModuleName -match '\.(ps1|psm1)$')
                    {
                        Write-Verbose "    Skipping script file: $($depInfo.ModuleName)"
                        continue
                    }

                    # Skip relative paths - they are internal to the module
                    if ($depInfo.ModuleName -match '^\.[\\/]')
                    {
                        Write-Verbose "    Skipping relative path: $($depInfo.ModuleName)"
                        continue
                    }

                    $findResult = Find-DependencyModule -ModuleName $depInfo.ModuleName `
                        -RequiredVersion $depInfo.RequiredVersion `
                        -MinimumVersion $depInfo.MinimumVersion `
                        -MaximumVersion $depInfo.MaximumVersion

                    $depResult = [PSCustomObject]@{
                        Name            = $depInfo.ModuleName
                        RequiredVersion = $depInfo.RequiredVersion
                        MinimumVersion  = $depInfo.MinimumVersion
                        MaximumVersion  = $depInfo.MaximumVersion
                        Found           = $findResult.Found
                        FoundPath       = $findResult.Path
                    }

                    $result.NestedModules += $depResult

                    if (-not $findResult.Found)
                    {
                        $missingDeps += $depInfo.ModuleName
                        $result.AllDependenciesMet = $false
                    }
                }
            }

            $result.MissingDependencies = $missingDeps | Select-Object -Unique

            if ($result.AllDependenciesMet)
            {
                Write-Verbose "  All dependencies satisfied"
            }
            else
            {
                Write-Verbose "  Missing dependencies: $($result.MissingDependencies -join ', ')"
            }

            $result
        }
    }

    end
    {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
