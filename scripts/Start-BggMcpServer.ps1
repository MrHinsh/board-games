[CmdletBinding()]
param(
    [string]$ContainerName = 'bgg-mcp-http',
    [int]$Port = 8080,
    [string]$ApiKey,
    [string]$Cookie,
    [string]$Username
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker is required but was not found in PATH.'
}

$existing = docker ps -a --filter "name=^/${ContainerName}$" --format '{{.Names}}'
if ($existing -contains $ContainerName) {
    docker rm -f $ContainerName | Out-Null
}

$dockerArgs = @(
    'run', '-d',
    '--name', $ContainerName,
    '-p', "${Port}:8080",
    '-e', 'MCP_MODE=http',
    '-e', 'MCP_PORT=8080'
)

if ($ApiKey) {
    $dockerArgs += @('-e', "BGG_API_KEY=$ApiKey")
}
if ($Cookie) {
    $dockerArgs += @('-e', "BGG_COOKIE=$Cookie")
}
if ($Username) {
    $dockerArgs += @('-e', "BGG_USERNAME=$Username")
}

$dockerArgs += 'kdaniel/bgg-mcp'

$containerId = & docker @dockerArgs
if (-not $containerId) {
    throw 'Failed to start bgg-mcp container.'
}

$status = [pscustomobject]@{
    Container = $ContainerName
    Port = $Port
    Endpoint = "http://localhost:$Port/mcp"
    ConfigSchema = "http://localhost:$Port/.well-known/mcp-config"
}

$status
