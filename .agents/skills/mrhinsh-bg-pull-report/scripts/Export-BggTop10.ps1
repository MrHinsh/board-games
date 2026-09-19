[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [int]$Top = 10,
    [string]$Endpoint = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [string]$OutDir = '.\\data\\reports\\top',
    [switch]$IncludeExpansions
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/ranking/top-report/Export-BggTop10.ps1') @PSBoundParameters
