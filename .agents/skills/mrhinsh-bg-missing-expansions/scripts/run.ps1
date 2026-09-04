<#
.SYNOPSIS
    For each owned base game, list expansions on BGG that are not owned.

.DESCRIPTION
    1. Loads owned base games from the canonical dataset.
    2. Queries the local bgg-mcp server for owned expansions (subtype=boardgameexpansion).
    3. Fetches each base game's thing XML from BGG's XMLAPI2 (Bearer-authenticated),
       cached under data/raw/bgg/details/<id>.xml.
    4. Parses <link type="boardgameexpansion"> entries and diffs against owned expansions.
    5. Writes JSON, CSV, and a markdown summary under data/reports/expansions/.

.NOTES
    Run from the repo root. Requires $env:BGG_API_KEY and the bgg-mcp server running.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [string]$Endpoint         = 'http://localhost:8080/mcp',
    [string]$CanonicalPath    = '.\data\working\canonical\games.json',
    [string]$CacheDir         = '.\data\raw\bgg\details',
    [string]$OutDir           = '.\data\reports\expansions',
    [int]$CacheMaxAgeDays     = 30,
    [int]$RequestDelayMs      = 800,
    [int]$BatchSize           = 20,
    [switch]$IncludeFanExpansions,
    [switch]$IncludePromos,
    [string[]]$Tiers,
    [string]$MembershipPath   = '.\data\working\ranking\tier-membership.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\..\mrhinsh-bg-shared\scripts\Invoke-BggMcp.ps1"

# ---------------------------------------------------------------------------
# Step 1 - owned base games from canonical
# ---------------------------------------------------------------------------
Write-Host "[1/5] Loading owned base games from canonical..." -ForegroundColor Cyan
if (-not (Test-Path $CanonicalPath)) { throw "Canonical file not found: $CanonicalPath" }

$owned = @((Get-Content $CanonicalPath -Raw | ConvertFrom-Json) | Where-Object { $_.collection })
if ($owned.Count -eq 0) { throw "No owned games in canonical dataset." }
Write-Host "    Owned base games: $($owned.Count)"

$tierByBggId = @{}
if ($Tiers) {
    if (-not (Test-Path $MembershipPath)) { throw "Tier membership file not found: $MembershipPath" }
    $membership = Get-Content $MembershipPath -Raw | ConvertFrom-Json
    $tierSet    = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($t in $Tiers) { [void]$tierSet.Add($t.ToUpper()) }
    foreach ($m in $membership) { $tierByBggId[[int]$m.bgg_id] = [string]$m.tier }
    $owned = @($owned | Where-Object {
        $tierByBggId.ContainsKey([int]$_.bgg_id) -and $tierSet.Contains($tierByBggId[[int]$_.bgg_id])
    })
    Write-Host "    Filtered to tiers $($Tiers -join ','): $($owned.Count)"
}

# ---------------------------------------------------------------------------
# Step 2 - owned expansions via MCP
# ---------------------------------------------------------------------------
Write-Host "[2/5] Fetching owned expansions from BGG..." -ForegroundColor Cyan
$ownedExpansionItems = Invoke-BggMcpTool -ToolName 'bgg-collection' `
    -Arguments @{ username = $Username; owned = $true; subtype = 'boardgameexpansion' } `
    -Endpoint $Endpoint -Username $Username -ApiKey $ApiKey

$ownedExpansionIds = [System.Collections.Generic.HashSet[int]]::new()
foreach ($item in @($ownedExpansionItems)) {
    if ($null -eq $item) { continue }
    $idProp = $item.PSObject.Properties['objectid']
    if ($null -eq $idProp) { continue }
    [void]$ownedExpansionIds.Add([int]$idProp.Value)
}
Write-Host "    Owned expansions: $($ownedExpansionIds.Count)"

# ---------------------------------------------------------------------------
# Step 3 - fetch (or read cached) thing XML for each owned base game
# ---------------------------------------------------------------------------
Write-Host "[3/5] Fetching base game details from BGG XMLAPI2..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

$headers    = @{ Authorization = "Bearer $ApiKey" }
$maxAge     = [TimeSpan]::FromDays($CacheMaxAgeDays)
$now        = Get-Date
$xmlById    = @{}

$idsToFetch = New-Object System.Collections.Generic.List[int]
foreach ($g in $owned) {
    $id = [int]$g.bgg_id
    $cachePath = Join-Path $CacheDir "$id.xml"
    if (Test-Path $cachePath) {
        $age = $now - (Get-Item $cachePath).LastWriteTime
        if ($age -lt $maxAge) {
            $xmlById[$id] = [xml](Get-Content $cachePath -Raw)
            continue
        }
    }
    $idsToFetch.Add($id) | Out-Null
}
Write-Host "    Cached: $($xmlById.Count) / To fetch: $($idsToFetch.Count)"

function Invoke-BggThing {
    param([int[]]$Ids)

    $joined = ($Ids -join ',')
    $url    = "https://boardgamegeek.com/xmlapi2/thing?id=$joined&stats=1"

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $resp = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 60
            if ($resp.StatusCode -eq 202) {
                Start-Sleep -Seconds ([Math]::Min(30, 2 * $attempt))
                continue
            }
            return [xml]$resp.Content
        }
        catch {
            $code = $_.Exception.Response.StatusCode.value__
            if ($code -eq 429 -or $code -eq 202 -or $code -eq 503) {
                Start-Sleep -Seconds ([Math]::Min(60, 5 * $attempt))
                continue
            }
            throw
        }
    }
    throw "Failed to fetch BGG thing after retries: $url"
}

$fetched = 0
for ($i = 0; $i -lt $idsToFetch.Count; $i += $BatchSize) {
    $batch = $idsToFetch[$i..([Math]::Min($i + $BatchSize - 1, $idsToFetch.Count - 1))]
    $xml   = Invoke-BggThing -Ids $batch
    foreach ($item in @($xml.items.item)) {
        if ($null -eq $item) { continue }
        $itemId = [int]$item.id
        $singleXml = New-Object System.Xml.XmlDocument
        $rootItems = $singleXml.CreateElement('items')
        [void]$rootItems.SetAttribute('termsofuse', $xml.items.termsofuse)
        [void]$singleXml.AppendChild($rootItems)
        $imported = $singleXml.ImportNode($item, $true)
        [void]$rootItems.AppendChild($imported)
        $singleXml.Save((Join-Path $CacheDir "$itemId.xml"))
        $xmlById[$itemId] = $singleXml
        $fetched++
    }
    Write-Host "    Batch $([Math]::Floor($i / $BatchSize) + 1): +$($batch.Count) IDs (total fetched: $fetched)"
    if ($i + $BatchSize -lt $idsToFetch.Count) {
        Start-Sleep -Milliseconds $RequestDelayMs
    }
}

# ---------------------------------------------------------------------------
# Step 4 - diff and build report
# ---------------------------------------------------------------------------
Write-Host "[4/5] Computing missing expansions..." -ForegroundColor Cyan

$fanPattern = '(?i)\bfan\s+expansion\b'

# Promo / merchandise / tiny-expansion patterns. Exclude by default; enable with -IncludePromos.
$promoPattern = '(?ix)
    \b(promo|promos|promotional|promodeck|preorder|kickstarter\s+exclusive|convention\s+exclusive|
       essen\s+exclusive|spiel\s+exclusive|gen\s?con|arkham\s+night|
       playmat|neoprene|acrylic|sleeve|sleeves|insert|organizer|storage\s+box|deck\s+box|
       dice\s+tray|dice\s+tower|coin(s)?|pin|badge|sticker(s)?|keychain|bookmark|magnet|
       art\s+print|postcard|greeting\s+card|calendar|puzzle|accessories|
       accessory\s+pack|swag|merch|
       beta\s+card(s)?|extra\s+(apprentices|player\s+boards|buildings)|
       mini\s+card\s+set|single\s+card|one[- ]card|bonus\s+card|
       gift\s+set|charity|treasure\s+chest)\b'

$report     = New-Object System.Collections.Generic.List[object]

foreach ($g in ($owned | Sort-Object -Property name)) {
    $id  = [int]$g.bgg_id
    $doc = $xmlById[$id]
    if ($null -eq $doc) { continue }

    $allLinks = @()
    $item = $doc.items.item
    if ($item.PSObject.Properties['link']) { $allLinks = @($item.link) }
    $links = @($allLinks | Where-Object {
        $_.type -eq 'boardgameexpansion' -and $_.GetAttribute('inbound') -ne 'true'
    })

    $missing = New-Object System.Collections.Generic.List[object]
    foreach ($link in $links) {
        $expId   = [int]$link.id
        $expName = [string]$link.value
        if ($ownedExpansionIds.Contains($expId)) { continue }
        $isFan   = $expName -match $fanPattern
        $isPromo = $expName -match $promoPattern
        if ($isFan   -and -not $IncludeFanExpansions) { continue }
        if ($isPromo -and -not $IncludePromos)        { continue }
        $missing.Add([pscustomobject]@{
            expansion_id   = $expId
            expansion_name = $expName
            is_fan         = [bool]$isFan
            is_promo       = [bool]$isPromo
        }) | Out-Null
    }

    if ($missing.Count -gt 0) {
        $entry = [pscustomobject]@{
            bgg_id         = $id
            name           = $g.name
            year_published = $g.year_published
            missing_count  = $missing.Count
            missing        = $missing
        }
        if ($Tiers) { Add-Member -InputObject $entry -NotePropertyName tier -NotePropertyValue $tierByBggId[$id] -Force }
        $report.Add($entry) | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Step 5 - write outputs
# ---------------------------------------------------------------------------
Write-Host "[5/5] Writing report..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$suffix = ''
if ($Tiers) { $suffix += '-tiers-' + ((@($Tiers) | Sort-Object) -join '') }
if ($IncludePromos)        { $suffix += '-withpromos' }
if ($IncludeFanExpansions) { $suffix += '-withfans' }
$jsonPath = Join-Path $OutDir ("missing-expansions$suffix.json")
$csvPath  = Join-Path $OutDir ("missing-expansions$suffix.csv")
$mdPath   = Join-Path $OutDir ("summary$suffix.md")

$report | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

$csvRows = foreach ($g in $report) {
    foreach ($e in $g.missing) {
        $row = [ordered]@{}
        if ($Tiers) { $row['tier'] = $g.tier }
        $row['base_bgg_id']    = $g.bgg_id
        $row['base_name']      = $g.name
        $row['expansion_id']   = $e.expansion_id
        $row['expansion_name'] = $e.expansion_name
        $row['is_fan']         = $e.is_fan
        $row['is_promo']       = $e.is_promo
        [pscustomobject]$row
    }
}
$csvRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$topN = 15
$md = @()
$md += "# Missing expansions report"
$md += ""
$md += "Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm'))"
$md += "Owned base games considered: $($owned.Count) | Owned expansions: $($ownedExpansionIds.Count)"
$md += "Base games with missing expansions: $($report.Count)"
$md += "Total missing expansions: $(@($csvRows).Count)"
if ($Tiers)                { $md += "Tier filter: $($Tiers -join ',')" }
$md += ($(if ($IncludeFanExpansions) { 'Fan expansions: INCLUDED' } else { 'Fan expansions: excluded' }))
$md += ($(if ($IncludePromos)        { 'Promos/merch: INCLUDED'    } else { 'Promos/merch: excluded'    }))
$md += ""
$md += "## Games by missing-expansion count"
$md += ""
if ($Tiers) {
    $md += "| Tier | Base game | Year | Missing |"
    $md += "|---|---|---|---|"
    foreach ($g in ($report | Sort-Object @{e='tier';d=$false}, @{e='missing_count';d=$true})) {
        $md += "| $($g.tier) | $($g.name) | $($g.year_published) | $($g.missing_count) |"
    }
} else {
    $md += "Showing top $topN."
    $md += ""
    $md += "| Base game | Year | Missing |"
    $md += "|---|---|---|"
    foreach ($g in ($report | Sort-Object missing_count -Descending | Select-Object -First $topN)) {
        $md += "| $($g.name) | $($g.year_published) | $($g.missing_count) |"
    }
}
$md -join "`n" | Set-Content -Path $mdPath -Encoding UTF8

Write-Host ""
Write-Host "  JSON: $jsonPath" -ForegroundColor Green
Write-Host "  CSV : $csvPath"  -ForegroundColor Green
Write-Host "  MD  : $mdPath"   -ForegroundColor Green

[pscustomobject]@{
    OwnedBaseGames        = $owned.Count
    OwnedExpansions       = $ownedExpansionIds.Count
    GamesWithMissing      = $report.Count
    TotalMissingRows      = @($csvRows).Count
    IncludeFanExpansions  = [bool]$IncludeFanExpansions
    JsonPath              = $jsonPath
    CsvPath               = $csvPath
    SummaryPath           = $mdPath
}
