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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stamp = Get-Date -Format 'yyyy-MM-dd'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$nominationsPath = Join-Path $OutDir "$stamp-nominations.csv"
$resolvedPath    = Join-Path $OutDir "$stamp-resolved.csv"
$scoredPath      = Join-Path $OutDir "$stamp-ranked.csv"

& (Join-Path $PSScriptRoot 'Parse-Nominations.ps1') `
    -SheetDumpPath $SheetDumpPath -OutPath $nominationsPath

& (Join-Path $PSScriptRoot 'Resolve-Nominations.ps1') `
    -NominationsPath $nominationsPath -OutPath $resolvedPath -Endpoint $Endpoint

$scoreArgs = @{
    ResolvedPath = $resolvedPath
    OutPath      = $scoredPath
    Endpoint     = $Endpoint
}
if ($RefreshDesignerIndex.IsPresent) { $scoreArgs.RefreshDesignerIndex = $true }
& (Join-Path $PSScriptRoot 'Score-Nominations.ps1') @scoreArgs

Write-Host ''
Write-Host "Nominations : $nominationsPath"
Write-Host "Resolved    : $resolvedPath"
Write-Host "Ranked      : $scoredPath"
