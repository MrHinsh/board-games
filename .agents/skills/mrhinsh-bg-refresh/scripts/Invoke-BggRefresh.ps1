<#
.SYNOPSIS
    Refresh canonical game data from BGG without overwriting locally-set ratings.

.DESCRIPTION
    1. Fetches a fresh played-games collection from BGG via the MCP server.
    2. Saves it as an immutable timestamped raw snapshot under data/raw/bgg/collection/.
    3. Merges the fresh data into data/working/canonical/games.json:
         - Existing games: updates only safe metadata (num_plays, bgg_rating, complexity,
           players, categories, mechanics, year_published). Never clears or lowers rating.
         - New games (not yet in canonical): adds them with rating = 0 and appends to
           data/working/unrated/intake.json.
    4. Writes a reconciliation report to data/reports/quality/reconcile-report.json.

.NOTES
    Run from the repo root. Requires MCP server on $Endpoint.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [string]$Endpoint     = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [string]$CanonicalPath  = '.\data\working\canonical\games.json',
    [string]$IntakePath     = '.\data\working\unrated\intake.json',
    [string]$RawDir         = '.\data\raw\bgg\collection',
    [string]$ReconcilePath  = '.\data\reports\quality\reconcile-report.json',
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
# Step 1 – fetch fresh collection from BGG
# ---------------------------------------------------------------------------
Write-Host "[1/5] Fetching fresh collection from BGG..." -ForegroundColor Cyan

$toolArgs = @{ username = $Username; played = $true; owned = $true }
if (-not $IncludeExpansions) { $toolArgs.subtype = 'boardgame' }

$rawItems = @(Invoke-BggMcpTool -ToolName 'bgg-collection' -Arguments $toolArgs `
    -Endpoint $Endpoint -Username $Username -ApiKey $ApiKey -Cookie $Cookie)

if (-not $rawItems -or $rawItems.Count -eq 0) {
    throw "No games returned from BGG. Check MCP server and username."
}

Write-Host "    Fetched $($rawItems.Count) collection items."

# ---------------------------------------------------------------------------
# Step 2 – enrich with details (same batching as fetch skill)
# ---------------------------------------------------------------------------
Write-Host "[2/5] Enriching with game details..." -ForegroundColor Cyan

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

$fresh = $rawItems | ForEach-Object {
    $id  = [int](Get-Val -Item $_ -Field 'objectid' -Default 0)
    $det = $detailMap[$id]
    [pscustomobject]@{
        bgg_id         = $id
        name           = Get-Val -Item $_ -Field 'name' -Default ''
        year_published = Get-Val -Item $_ -Field 'yearpublished' -Default 0
        rating         = [double](Get-Val -Item $_ -Field 'rating' -Default 0)
        num_plays      = [int](Get-Val -Item $_ -Field 'numplays' -Default 0)
        players        = Get-DetailVal -Item $det -Field 'players'
        complexity     = Get-DetailVal -Item $det -Field 'complexity'
        bgg_rating     = Get-DetailVal -Item $det -Field 'bgg_rating'
        num_ratings    = Get-DetailVal -Item $det -Field 'num_ratings'
        categories     = Get-DetailVal -Item $det -Field 'categories' -Default @()
        mechanics      = Get-DetailVal -Item $det -Field 'mechanics' -Default @()
    }
}

# Dedupe fresh by bgg_id, keeping highest play count
$freshByBggId = @{}
foreach ($g in $fresh) {
    $id = [int]$g.bgg_id
    if (-not $freshByBggId.ContainsKey($id) -or [int]$g.num_plays -gt [int]$freshByBggId[$id].num_plays) {
        $freshByBggId[$id] = $g
    }
}

Write-Host "    Got details for $($freshByBggId.Count) unique games."

# ---------------------------------------------------------------------------
# Step 3 – save raw snapshot
# ---------------------------------------------------------------------------
Write-Host "[3/5] Saving raw snapshot..." -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $RawDir | Out-Null
$timestamp = (Get-Date -Format 'yyyy-MM-ddTHHmmssZ')
$rawPath = Join-Path $RawDir "$timestamp.json"
$freshByBggId.Values | ConvertTo-Json -Depth 10 | Set-Content -Path $rawPath -Encoding UTF8
Write-Host "    Saved: $rawPath"

# ---------------------------------------------------------------------------
# Step 4 – merge into canonical
# ---------------------------------------------------------------------------
Write-Host "[4/5] Merging into canonical data..." -ForegroundColor Cyan

# Load existing canonical (may not exist on very first run)
$canonicalExists = Test-Path $CanonicalPath
$canonical = if ($canonicalExists) {
    @(Get-Content -Path $CanonicalPath -Raw | ConvertFrom-Json)
} else {
    @()
}

# Index canonical by bgg_id; keep all entries (duplicates collapse to highest rating)
$canonicalByBggId = @{}
foreach ($g in $canonical) {
    $id = [int]$g.bgg_id
    if (-not $canonicalByBggId.ContainsKey($id) -or [double]$g.rating -gt [double]$canonicalByBggId[$id].rating) {
        $canonicalByBggId[$id] = $g
    }
}

# Metrics
$added   = [System.Collections.Generic.List[object]]::new()
$updated = [System.Collections.Generic.List[object]]::new()
$unchanged = 0

# Fields safe to update from BGG (never rating/tier/rank)
$safeFields = @('num_plays','bgg_rating','num_ratings','complexity','players','categories','mechanics','year_published','name')

foreach ($freshGame in $freshByBggId.Values) {
    $id = [int]$freshGame.bgg_id

    if ($canonicalByBggId.ContainsKey($id)) {
        # Existing game – update metadata only
        $existing = $canonicalByBggId[$id]
        $changed = $false

        foreach ($field in $safeFields) {
            $oldVal = $null
            $p = $existing.PSObject.Properties[$field]
            if ($p) { $oldVal = $p.Value }
            $newVal = $freshGame.$field

            # Compare serialised to handle arrays
            if (($oldVal | ConvertTo-Json -Compress) -ne ($newVal | ConvertTo-Json -Compress)) {
                $existing.$field = $newVal
                $changed = $true
            }
        }

        # Raise play count, never lower it (BGG can lag)
        if ([int]$freshGame.num_plays -gt [int]$existing.num_plays) {
            $existing.num_plays = [int]$freshGame.num_plays
            $changed = $true
        }

        if ($changed) {
            [void]$updated.Add([pscustomobject]@{ bgg_id = $id; name = $existing.name })
        } else {
            $unchanged++
        }
    } else {
        # New game – add to canonical with rating = 0
        $newEntry = [pscustomobject]@{
            group_key      = if ($freshGame.players) { $freshGame.players } else { 'unknown' }
            bgg_id         = $id
            name           = $freshGame.name
            year_published = $freshGame.year_published
            rating         = 0.0     # locally unrated
            num_plays      = $freshGame.num_plays
            players        = $freshGame.players
            complexity     = $freshGame.complexity
            bgg_rating     = $freshGame.bgg_rating
            num_ratings    = $freshGame.num_ratings
            categories     = $freshGame.categories
            mechanics      = $freshGame.mechanics
        }
        $canonicalByBggId[$id] = $newEntry
        [void]$added.Add([pscustomobject]@{ bgg_id = $id; name = $freshGame.name })
    }
}

# Rebuild canonical array sorted by group_key then name
$newCanonical = $canonicalByBggId.Values | Sort-Object group_key, name
$newCanonical | ConvertTo-Json -Depth 10 | Set-Content -Path $CanonicalPath -Encoding UTF8

# ---------------------------------------------------------------------------
# Step 4b – append genuinely new games to intake
# ---------------------------------------------------------------------------
if ($added.Count -gt 0) {
    $intakeExists = Test-Path $IntakePath
    $intake = if ($intakeExists) { @(Get-Content -Path $IntakePath -Raw | ConvertFrom-Json) } else { @() }
    $intakeIds = @($intake | ForEach-Object { [int]$_.bgg_id })

    $newIntake = $added | ForEach-Object {
        $id = [int]$_.bgg_id
        if ($intakeIds -notcontains $id) {
            $g = $canonicalByBggId[$id]
            [pscustomobject]@{
                group_key      = $g.group_key
                bgg_id         = $id
                name           = $g.name
                current_rating = 0.0
                num_plays      = $g.num_plays
                players        = $g.players
                complexity     = $g.complexity
                bgg_rating     = $g.bgg_rating
                categories     = $g.categories
                mechanics      = $g.mechanics
            }
        }
    } | Where-Object { $null -ne $_ }

    if (@($newIntake).Count -gt 0) {
        $merged = @($intake) + @($newIntake) | Sort-Object @{ Expression = { [int]$_.num_plays }; Descending = $true }, name
        $merged | ConvertTo-Json -Depth 10 | Set-Content -Path $IntakePath -Encoding UTF8
    }
}

# ---------------------------------------------------------------------------
# Step 5 – reconcile report
# ---------------------------------------------------------------------------
Write-Host "[5/5] Writing reconcile report..." -ForegroundColor Cyan

$report = [pscustomobject]@{
    run_at    = (Get-Date -Format 'o')
    raw_snapshot = $rawPath
    total_from_bgg = $freshByBggId.Count
    total_in_canonical = $canonicalByBggId.Count
    added     = $added.Count
    updated   = $updated.Count
    unchanged = $unchanged
    new_games = @($added)
    updated_games = @($updated)
}

$reportDir = Split-Path -Path $ReconcilePath -Parent
if ($reportDir -and -not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }
$report | ConvertTo-Json -Depth 10 | Set-Content -Path $ReconcilePath -Encoding UTF8

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Refresh complete." -ForegroundColor Green
$report | Format-List run_at, total_from_bgg, total_in_canonical, added, updated, unchanged
