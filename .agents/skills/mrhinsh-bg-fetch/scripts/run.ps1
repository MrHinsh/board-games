<#
.SYNOPSIS
    Fetch a fresh played-games collection from BGG and save an immutable raw snapshot.

.DESCRIPTION
    1. Calls the BGG MCP server to retrieve the user's played collection.
    2. Enriches each entry with game details (complexity, players, categories, mechanics).
    3. Deduplicates by bgg_id (keeps highest play count).
    4. Maps raw BGG fields to the canonical schema (bgg_id, name, year_published, …).
    5. Writes a timestamped JSON snapshot to data/raw/bgg/collection/<timestamp>.json.
    6. Emits the snapshot path to stdout so callers can pass it to mrhinsh-bg-reconcile.

.NOTES
    Run from the repo root. Requires the BGG MCP server running at $Endpoint.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [string]$Endpoint          = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [string]$RawDir            = '.\data\raw\bgg\collection',
    [switch]$IncludeExpansions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\..\mrhinsh-bg-shared\scripts\Invoke-BggMcp.ps1"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-Val {
    param([object]$Item, [string]$Field, $Default = $null)
    $p = $Item.PSObject.Properties[$Field]
    if ($null -eq $p -or $null -eq $p.Value -or $p.Value -eq '') { return $Default }
    return $p.Value
}

function Get-DetailVal {
    param([object]$Item, [string]$Field, $Default = $null)
    if ($null -eq $Item) { return $Default }
    $p = $Item.PSObject.Properties[$Field]
    if ($null -eq $p -or $null -eq $p.Value -or $p.Value -eq '') { return $Default }
    return $p.Value
}

# ---------------------------------------------------------------------------
# Step 1 – fetch collection from BGG
# ---------------------------------------------------------------------------
Write-Host "[1/3] Fetching played collection from BGG..." -ForegroundColor Cyan

$toolArgs = @{ username = $Username; played = $true; owned = $true }
if (-not $IncludeExpansions) { $toolArgs.subtype = 'boardgame' }

$rawItems = @(Invoke-BggMcpTool -ToolName 'bgg-collection' -Arguments $toolArgs `
    -Endpoint $Endpoint -Username $Username -ApiKey $ApiKey -Cookie $Cookie)

if (-not $rawItems -or $rawItems.Count -eq 0) {
    throw "No games returned from BGG. Check MCP server and username."
}

Write-Host "    Fetched $($rawItems.Count) collection items."

# ---------------------------------------------------------------------------
# Step 2 – enrich with game details
# ---------------------------------------------------------------------------
Write-Host "[2/3] Enriching with game details..." -ForegroundColor Cyan

$detailMap = @{}
$ids = @($rawItems | ForEach-Object { [int](Get-Val -Item $_ -Field 'objectid' -Default 0) } | Select-Object -Unique)

foreach ($batch in ($ids | ForEach-Object -Begin { $buf = [System.Collections.Generic.List[int]]::new() } -Process {
    [void]$buf.Add($_)
    if ($buf.Count -ge 20) { ,@($buf); $buf.Clear() }
} -End { if ($buf.Count -gt 0) { ,@($buf) } })) {
    $details = @(Invoke-BggMcpTool -ToolName 'bgg-details' -Arguments @{ ids = $batch } `
        -Endpoint $Endpoint -Username $Username -ApiKey $ApiKey -Cookie $Cookie)
    foreach ($d in $details) {
        if ($null -ne $d -and $null -ne $d.id) { $detailMap[[int]$d.id] = $d }
    }
}

# Map to canonical schema and deduplicate by bgg_id (keep highest play count)
$byBggId = @{}
foreach ($item in $rawItems) {
    $id  = [int](Get-Val -Item $item -Field 'objectid' -Default 0)
    $det = $detailMap[$id]
    $entry = [pscustomobject]@{
        bgg_id         = $id
        name           = Get-Val -Item $item -Field 'name' -Default ''
        year_published = Get-Val -Item $item -Field 'yearpublished' -Default 0
        rating         = [double](Get-Val -Item $item -Field 'rating' -Default 0)
        num_plays      = [int](Get-Val -Item $item -Field 'numplays' -Default 0)
        players        = Get-DetailVal -Item $det -Field 'players'
        complexity     = Get-DetailVal -Item $det -Field 'complexity'
        bgg_rating     = Get-DetailVal -Item $det -Field 'bgg_rating'
        num_ratings    = Get-DetailVal -Item $det -Field 'num_ratings'
        categories     = Get-DetailVal -Item $det -Field 'categories' -Default @()
        mechanics      = Get-DetailVal -Item $det -Field 'mechanics' -Default @()
    }
    if (-not $byBggId.ContainsKey($id) -or [int]$entry.num_plays -gt [int]$byBggId[$id].num_plays) {
        $byBggId[$id] = $entry
    }
}

Write-Host "    Enriched $($byBggId.Count) unique games."

# ---------------------------------------------------------------------------
# Step 3 – save immutable raw snapshot
# ---------------------------------------------------------------------------
Write-Host "[3/3] Saving raw snapshot..." -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $RawDir | Out-Null
$timestamp   = (Get-Date -Format 'yyyy-MM-ddTHHmmssZ')
$snapshotPath = Join-Path $RawDir "$timestamp.json"
$byBggId.Values | ConvertTo-Json -Depth 10 | Set-Content -Path $snapshotPath -Encoding UTF8

Write-Host "    Saved: $snapshotPath" -ForegroundColor Green

# Emit the path so callers (e.g. mrhinsh-bg-refresh) can pass it to mrhinsh-bg-reconcile
Write-Output $snapshotPath
