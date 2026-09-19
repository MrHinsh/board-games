Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-McpRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [Parameter(Mandatory = $true)]
        [hashtable]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 20
    return Invoke-RestMethod -Method Post -Uri $Endpoint -ContentType 'application/json' -Body $json
}

function Get-McpTextFromResponse {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    if (-not $Response.result) {
        $errorPayload = $Response | ConvertTo-Json -Depth 20
        throw "MCP response does not contain a result payload: $errorPayload"
    }

    if (-not $Response.result.content -or $Response.result.content.Count -eq 0) {
        $raw = $Response | ConvertTo-Json -Depth 20
        throw "MCP result has no content entries: $raw"
    }

    $textContent = $Response.result.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
    if (-not $textContent) {
        $raw = $Response | ConvertTo-Json -Depth 20
        throw "MCP result has no text content: $raw"
    }

    return [string]$textContent.text
}

function Invoke-BggMcpTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter(Mandatory = $true)]
        [hashtable]$Arguments,

        [string]$Endpoint = 'http://localhost:8080/mcp',
        [string]$Username,
        [string]$ApiKey,
        [string]$Cookie
    )

    $uriBuilder = [System.UriBuilder]::new($Endpoint)
    $queryPairs = [System.Collections.Generic.List[string]]::new()

    if ($Username) {
        $queryPairs.Add('BGG_USERNAME=' + [System.Uri]::EscapeDataString($Username))
    }
    if ($ApiKey) {
        $queryPairs.Add('BGG_API_KEY=' + [System.Uri]::EscapeDataString($ApiKey))
    }

    if ($Cookie) {
        Write-Verbose 'Cookie parameter is ignored for MCP calls. Configure authentication in the MCP server environment.'
    }

    if ($queryPairs.Count -gt 0) {
        $uriBuilder.Query = [string]::Join('&', $queryPairs)
    }

    $targetEndpoint = $uriBuilder.Uri.AbsoluteUri
    $requestId = [int](Get-Random -Minimum 1000 -Maximum 999999)

    # Initialize first for compatibility with MCP servers that enforce handshake.
    $initializeRequest = @{
        jsonrpc = '2.0'
        id = $requestId
        method = 'initialize'
        params = @{
            protocolVersion = '2024-11-05'
            capabilities = @{}
            clientInfo = @{
                name = 'bgg-powershell-client'
                version = '1.0.0'
            }
        }
    }

    [void](Invoke-McpRequest -Endpoint $targetEndpoint -Body $initializeRequest)

    $callRequest = @{
        jsonrpc = '2.0'
        id = ($requestId + 1)
        method = 'tools/call'
        params = @{
            name = $ToolName
            arguments = $Arguments
        }
    }

    $callResponse = Invoke-McpRequest -Endpoint $targetEndpoint -Body $callRequest
    $text = Get-McpTextFromResponse -Response $callResponse

    try {
        return $text | ConvertFrom-Json -Depth 50
    }
    catch {
        return $text
    }
}
