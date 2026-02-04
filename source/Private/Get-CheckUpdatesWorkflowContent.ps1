function Get-CheckUpdatesWorkflowContent
{
    <#
    .SYNOPSIS
        Returns the GitHub Actions workflow content for checking module updates.

    .DESCRIPTION
        Returns a string containing the default content for the GitHub Actions
        workflow file that checks for module updates. The workflow:
        - Can be triggered manually via workflow_dispatch
        - Can optionally be scheduled (weekly on Monday at 6 AM, commented out by default)
        - Checks for available module updates using Get-PSSubtreeModuleStatus
        - Creates or updates a GitHub issue when updates are available

        This function is used internally by Initialize-PSSubtreeModule to generate
        the .github/workflows/check-updates.yml file.

    .EXAMPLE
        $content = Get-CheckUpdatesWorkflowContent

        Returns the default content for the check-updates.yml workflow file.

    .OUTPUTS
        System.String
        Returns a string containing the YAML workflow content.

    .NOTES
        This is a private helper function used internally by PSSubtreeModules.
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
