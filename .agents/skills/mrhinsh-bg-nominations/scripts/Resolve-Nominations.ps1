<#
.SYNOPSIS
    Resolve nominated game names to BGG ids via the local bgg-mcp server.

.DESCRIPTION
    Club members type game names freehand, so this does fuzzy resolution and
    then sanity-checks the result. Two failure modes are common and both are
    caught here rather than silently poisoning the ranking:

      - a same-name title from decades earlier ("Summit" 1961, "El Dorado" 1973)
      - a stub BGG entry with almost no ratings ("Anno 1800", 14 ratings)

    Anything suspicious is reported so it can be pinned in name-overrides.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NominationsPath,

    [Parameter(Mandatory = $true)]
    [string]$OutPath,

    [string]$OverridesPath = (Join-Path $PSScriptRoot '..\name-overrides.json'),
    [string]$NameCachePath = '.\data\working\nominations\name-cache.json',
    [string]$Endpoint = 'http://localhost:8080/mcp',
    [int]$RequestDelayMs = 2000,
    [int]$MinYear = 1990,
    [int]$MinRatings = 300,
    [switch]$RefreshNames
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\..\mrhinsh-bg-shared\scripts\Invoke-BggMcp.ps1')

if (-not (Test-Path $NominationsPath)) { throw "Nominations file not found: $NominationsPath" }
$noms = @(Import-Csv -Path $NominationsPath)

$overrides = @{}
if (Test-Path $OverridesPath) {
    $o = Get-Content -Path $OverridesPath -Raw | ConvertFrom-Json
    if ($o.PSObject.Properties.Name -contains 'overrides') {
        foreach ($p in $o.overrides.PSObject.Properties) { $overrides[$p.Name.ToLowerInvariant()] = [int]$p.Value }
    }
}

# "Deep Regrets + Even Deeper Regrets" -> search on the base game only
function Get-SearchQuery {
    param([string]$Raw)
    $q = $Raw
    foreach ($sep in @('\s*\+\s*', '\s+with\s+', '\s*/\s*', '\s*&\s+')) {
        $q = ($q -split $sep)[0]
    }
    return $q.Trim()
}

function Select-BestCandidate {
    param([object[]]$Candidates, [string]$Query)
    $cands = @($Candidates | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'id' })
    if ($cands.Count -eq 0) { return $null }
    $exact = @($cands | Where-Object { $_.name -ieq $Query }) | Select-Object -First 1
    if ($exact) { return $exact }
    $starts = @($cands | Where-Object { $_.name -imatch "^$([regex]::Escape($Query))" }) | Select-Object -First 1
    if ($starts) { return $starts }
    return $cands[0]
}

# BGG search throttles unpredictably: a name that resolves one run can come back
# empty the next. Remember every successful resolution and fall back to it.
$nameCache = @{}
if (Test-Path $NameCachePath) {
    $nc = Get-Content -Path $NameCachePath -Raw | ConvertFrom-Json
    foreach ($p in $nc.PSObject.Properties) { $nameCache[$p.Name] = [int]$p.Value }
}

$resolved = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

foreach ($n in $noms) {
    $rawName = [string]$n.game_raw
    $key = $rawName.Trim().ToLowerInvariant()
    $query = Get-SearchQuery -Raw $rawName
    $id = $null
    $matchedName = ''
    $source = ''

    if ($overrides.ContainsKey($key)) {
        $id = $overrides[$key]; $source = 'override'
    } elseif ($overrides.ContainsKey($query.ToLowerInvariant())) {
        $id = $overrides[$query.ToLowerInvariant()]; $source = 'override'
    } elseif ($nameCache.ContainsKey($key) -and -not $RefreshNames.IsPresent) {
        # cache first: BGG throttles hard, and most weeks repeat many titles
        $id = $nameCache[$key]; $source = 'cache'
    } else {
        # progressively looser queries: full text, then subtitle dropped, then
        # first two words - covers "Anno 1800: The Boardgame" and misspellings
        # in a trailing subtitle such as "Amalfi: Reinassance"
        $attemptQueries = [System.Collections.Generic.List[string]]::new()
        $attemptQueries.Add($query)
        if ($query -match '^(.*?):') { $attemptQueries.Add($Matches[1].Trim()) }
        $words = @($query -split '\s+')
        if ($words.Count -gt 2) { $attemptQueries.Add(($words[0..1] -join ' ')) }

        $best = $null
        foreach ($q in @($attemptQueries | Select-Object -Unique)) {
            foreach ($attempt in 1..2) {
                try {
                    $r = Invoke-BggMcpTool -ToolName 'bgg-search' -Arguments @{ query = $q } -Endpoint $Endpoint
                    $best = Select-BestCandidate -Candidates @($r) -Query $q
                } catch {
                    $best = $null
                }
                if ($best) { break }
                Start-Sleep -Seconds (2 * $attempt)
            }
            if ($best) { break }
        }
        if ($best) {
            $id = [int]$best.id; $matchedName = [string]$best.name; $source = 'search'
            $nameCache[$key] = $id
        } elseif ($nameCache.ContainsKey($key)) {
            $id = $nameCache[$key]; $source = 'cache'
            $warnings.Add("THROTTLED '$rawName' - search returned nothing; reused cached id $id")
        }
        Start-Sleep -Milliseconds $RequestDelayMs
    }

    if (-not $id) {
        $warnings.Add("UNRESOLVED '$rawName' (host $($n.host)) - add it to name-overrides.json")
    }

    $resolved.Add([pscustomobject]@{
        host_index   = $n.host_index
        host         = $n.host
        slot         = $n.slot
        game_raw     = $rawName
        query        = $query
        bgg_id       = $id
        matched_name = $matchedName
        source       = $source
        year         = ''
        num_ratings  = ''
        suspect      = ''
    })
}

# verify what we resolved to, in batches of 20
$ids = @($resolved | Where-Object { $_.bgg_id } | ForEach-Object { [int]$_.bgg_id } | Sort-Object -Unique)
$details = @()
for ($i = 0; $i -lt $ids.Count; $i += 20) {
    $batch = $ids[$i..([Math]::Min($i + 19, $ids.Count - 1))]
    # a throttled or errored call comes back as a plain string, not game objects
    $batchResult = @(Invoke-BggMcpTool -ToolName 'bgg-details' -Arguments @{ ids = $batch } -Endpoint $Endpoint)
    $details += @($batchResult | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'id' })
    Start-Sleep -Seconds 2
}
$byId = @{}
foreach ($d in $details) { if (-not $byId.ContainsKey([int]$d.id)) { $byId[[int]$d.id] = $d } }

foreach ($r in $resolved) {
    if (-not $r.bgg_id) { continue }
    $id = [int]$r.bgg_id
    if (-not $byId.ContainsKey($id)) { continue }
    $g = $byId[$id]
    $r.year = $g.year
    $r.num_ratings = $g.num_ratings
    if ($r.source -eq 'override') { continue }

    $reasons = @()
    if ([int]$g.year -gt 0 -and [int]$g.year -lt $MinYear) { $reasons += "year $($g.year)" }
    if ([int]$g.year -eq 0) { $reasons += 'no year' }
    if ([int]$g.num_ratings -lt $MinRatings) { $reasons += "only $($g.num_ratings) ratings" }
    if ($reasons.Count -gt 0) {
        $r.suspect = ($reasons -join ', ')
        $warnings.Add("SUSPECT '$($r.game_raw)' -> '$($g.name)' [$id] ($($r.suspect)) - pin it in name-overrides.json if wrong")
    }
}

$outDir = Split-Path -Parent $OutPath
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$resolved | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8

$cacheDir = Split-Path -Parent $NameCachePath
if ($cacheDir -and -not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
$cacheOut = [ordered]@{}
foreach ($k in ($nameCache.Keys | Sort-Object)) { $cacheOut[$k] = $nameCache[$k] }
$cacheOut | ConvertTo-Json -Depth 3 | Set-Content -Path $NameCachePath -Encoding UTF8

Write-Host ("Resolved {0}/{1} nominations -> {2}" -f @($resolved | Where-Object { $_.bgg_id }).Count, $resolved.Count, $OutPath)
foreach ($w in $warnings) { Write-Warning $w }
