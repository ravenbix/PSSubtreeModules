function Get-SubtreeModulesYamlContent
{
    <#
    .SYNOPSIS
        Returns the default subtree-modules.yaml content.

    .DESCRIPTION
        Returns a string containing the default content for the subtree-modules.yaml
        configuration file used by PSSubtreeModules. The content includes a header
        comment and an empty modules collection.

        This function is used internally by Initialize-PSSubtreeModule to generate
        the initial configuration file.

    .EXAMPLE
        $content = Get-SubtreeModulesYamlContent

        Returns the default YAML content for a new subtree-modules.yaml file.

    .OUTPUTS
        System.String
        Returns a string containing the YAML content.

    .NOTES
        This is a private helper function used internally by PSSubtreeModules.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @'
# PSSubtreeModules configuration
modules: {}
'@
}
