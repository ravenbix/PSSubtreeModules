function Get-GitIgnoreContent
{
    <#
    .SYNOPSIS
        Returns the default .gitignore content for PSSubtreeModules repositories.

    .DESCRIPTION
        Returns a string containing the default content for the .gitignore file
        used by PSSubtreeModules repositories. The content includes patterns for
        common files and directories that should be ignored by Git, including:
        - PowerShell module build output (output/)
        - Temporary files (*.tmp, *~)
        - IDE and editor files (.vscode/, .idea/, *.sublime-*)
        - OS-specific files (.DS_Store, Thumbs.db, desktop.ini)

        This function is used internally by Initialize-PSSubtreeModule to generate
        the .gitignore file.

    .EXAMPLE
        $content = Get-GitIgnoreContent

        Returns the default content for a .gitignore file.

    .OUTPUTS
        System.String
        Returns a string containing the .gitignore content.

    .NOTES
        This is a private helper function used internally by PSSubtreeModules.
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
