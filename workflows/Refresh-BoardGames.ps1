[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [string]$Endpoint = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [switch]$IncludeExpansions
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$pull = & (Join-Path $PSScriptRoot '../systems/bgg-integration/pull/run.ps1') @PSBoundParameters
$rebuild = & (Join-Path $PSScriptRoot 'Rebuild-BoardGames.ps1')
[pscustomobject]@{ Pull = $pull; Rebuild = $rebuild }
