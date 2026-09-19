param([string]$FixtureRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../provider/Invoke-BggMcp.ps1')
# Loading a provider must define functions without connecting to BGG.
if (-not (Get-Command Invoke-BggMcpTool -ErrorAction SilentlyContinue)) { throw 'MCP provider did not load.' }
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $repo '.agents/skills/mrhinsh-bg-shared/scripts/Invoke-BggMcp.ps1')
if (-not (Get-Command Invoke-BggMcpTool -ErrorAction SilentlyContinue)) { throw 'Legacy dot-source provider failed.' }
Write-Host 'BGG Integration: provider and legacy library entrypoint load without network.'
