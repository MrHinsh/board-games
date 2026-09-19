[CmdletBinding()]
param(
    [string]$ContainerName = 'bgg-mcp-http',
    [int]$Port = 8080,
    [string]$ApiKey,
    [string]$Cookie,
    [string]$Username
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/bgg-integration/collection-fetch/Start-BggMcpServer.ps1') @PSBoundParameters
