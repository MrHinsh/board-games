<#
.SYNOPSIS
    Parse, resolve and score this week's club nominations.

.DESCRIPTION
    Steps 2-4 of the workflow. Step 1 - reading the Google Sheet - cannot run
    from PowerShell; the agent fetches it with the Google Drive connector and
    saves the dump, then passes it here via -SheetDumpPath. See SKILL.md.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SheetDumpPath,

    [string]$OutDir = '.\data\reports\nominations',
    [string]$Endpoint = 'http://localhost:8080/mcp',
    [switch]$RefreshDesignerIndex
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/prediction/club-nominations/run.ps1') @PSBoundParameters
