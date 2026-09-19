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

$engine = if (Get-Command wslc -ErrorAction SilentlyContinue) {
    'wslc'
} elseif (Get-Command docker -ErrorAction SilentlyContinue) {
    'docker'
} else {
    throw 'Neither wslc nor docker was found in PATH.'
}

& $engine rm -f $ContainerName 2>$null | Out-Null

$runArgs = @(
    'run', '-d',
    '--name', $ContainerName,
    '-p', "${Port}:8080",
    '-e', 'MCP_MODE=http',
    '-e', 'MCP_PORT=8080'
)

if ($ApiKey) {
    $runArgs += @('-e', "BGG_API_KEY=$ApiKey")
}
if ($Cookie) {
    Write-Warning 'Cookie parameter is ignored. MCP authentication should be configured via API key/environment only.'
}
if ($Username) {
    $runArgs += @('-e', "BGG_USERNAME=$Username")
}

$runArgs += 'kdaniel/bgg-mcp'

$containerId = & $engine @runArgs
if (-not $containerId) {
    throw "Failed to start bgg-mcp container via $engine."
}

$status = [pscustomobject]@{
    Container = $ContainerName
    Port = $Port
    Endpoint = "http://localhost:$Port/mcp"
    ConfigSchema = "http://localhost:$Port/.well-known/mcp-config"
}

$status
