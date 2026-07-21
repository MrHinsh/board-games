<#
.SYNOPSIS
    Merge a fresh BGG snapshot into canonical data and produce a reconciliation report.

.DESCRIPTION
    1. Reads the normalized snapshot produced by mrhinsh-bg-fetch.
    2. Loads the existing canonical games list.
        3. For each game in the snapshot:
                 - Existing game: updates only safe metadata fields. Never clears or lowers a
                     locally-set rating. If canonical is still unrated, seed from BGG's personal rating.
                     Play count is raised if BGG reports more plays.
                 - New game: adds to canonical using BGG's personal rating when present; only unrated
                     games are appended to intake.
    4. Writes the updated canonical file (sorted by group_key then name).
    5. Appends genuinely new games to the unrated intake (sorted by play count desc).
    6. Writes a reconciliation report with added/updated/unchanged counts.

.NOTES
    Run from the repo root. Pass the snapshot path emitted by mrhinsh-bg-fetch/scripts/run.ps1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SnapshotPath,

    [string]$CanonicalPath  = '.\data\working\canonical\games.json',
    [string]$IntakePath     = '.\data\working\unrated\intake.json',
    [string]$ReconcilePath  = '.\data\reports\quality\reconcile-report.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Value
    )

    $property = $Target.PSObject.Properties[$Name]
    if ($property) {
        $property.Value = $Value
    } else {
        $Target | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

# ---------------------------------------------------------------------------
# Load inputs
# ---------------------------------------------------------------------------
Write-Host "[1/3] Loading snapshot and canonical data..." -ForegroundColor Cyan

if (-not (Test-Path $SnapshotPath)) { throw "Snapshot not found: $SnapshotPath" }

$fresh = @(Get-Content -Path $SnapshotPath -Raw | ConvertFrom-Json)

$canonical = if (Test-Path $CanonicalPath) {
    @(Get-Content -Path $CanonicalPath -Raw | ConvertFrom-Json)
} else {
    @()
}

# Index canonical by bgg_id (keep highest-rated entry on duplicates)
$canonicalByBggId = @{}
foreach ($g in $canonical) {
    $id = [int]$g.bgg_id
    if (-not $canonicalByBggId.ContainsKey($id) -or [double]$g.rating -gt [double]$canonicalByBggId[$id].rating) {
        $canonicalByBggId[$id] = $g
    }
}

Write-Host "    Snapshot: $($fresh.Count) games  |  Canonical: $($canonicalByBggId.Count) games"

# ---------------------------------------------------------------------------
# Merge
# ---------------------------------------------------------------------------
Write-Host "[2/3] Merging..." -ForegroundColor Cyan

$safeFields = @('num_plays','bgg_rating','num_ratings','complexity','players','categories','mechanics','year_published','name','collection','previously_owned','want_to_play','want_to_buy','collection_to_exit','collection_status','bgg_comment')

$added     = [System.Collections.Generic.List[object]]::new()
$updated   = [System.Collections.Generic.List[object]]::new()
$unchanged = 0

foreach ($freshGame in $fresh) {
    $id = [int]$freshGame.bgg_id

    if ($canonicalByBggId.ContainsKey($id)) {
        $existing = $canonicalByBggId[$id]
        $changed  = $false

        foreach ($field in $safeFields) {
            $oldVal = $null
            $p = $existing.PSObject.Properties[$field]
            if ($p) { $oldVal = $p.Value }
            $newVal = $freshGame.$field

            if (($oldVal | ConvertTo-Json -Compress) -ne ($newVal | ConvertTo-Json -Compress)) {
                Set-ObjectProperty -Target $existing -Name $field -Value $newVal
                $changed = $true
            }
        }

        # Raise play count, never lower (BGG can lag behind)
        if ([int]$freshGame.num_plays -gt [int]$existing.num_plays) {
            $existing.num_plays = [int]$freshGame.num_plays
            $changed = $true
        }

        if ([double]$existing.rating -le 0 -and [double]$freshGame.rating -gt 0) {
            $existing.rating = [double]$freshGame.rating
            $changed = $true
        }

        if ($changed) { [void]$updated.Add([pscustomobject]@{ bgg_id = $id; name = $existing.name }) }
        else          { $unchanged++ }

    } else {
        # New game – add with rating = 0
        $newEntry = [pscustomobject]@{
            group_key      = if ($freshGame.players) { $freshGame.players } else { 'unknown' }
            bgg_id         = $id
            name           = $freshGame.name
            year_published = $freshGame.year_published
            rating         = [double]$freshGame.rating
            num_plays      = $freshGame.num_plays
            collection     = [bool]$freshGame.collection
            previously_owned = [bool]$freshGame.previously_owned
            want_to_play   = [bool]$freshGame.want_to_play
            want_to_buy    = [bool]$freshGame.want_to_buy
            collection_to_exit = [bool]$freshGame.collection_to_exit
            collection_status = [string]$freshGame.collection_status
            players        = $freshGame.players
            complexity     = $freshGame.complexity
            bgg_rating     = $freshGame.bgg_rating
            num_ratings    = $freshGame.num_ratings
            categories     = $freshGame.categories
            mechanics      = $freshGame.mechanics
            bgg_comment    = if ($freshGame.PSObject.Properties['bgg_comment']) { [string]$freshGame.bgg_comment } else { '' }
            notes          = ''
        }
        $canonicalByBggId[$id] = $newEntry
        [void]$added.Add([pscustomobject]@{ bgg_id = $id; name = $freshGame.name })
    }
}

# Write updated canonical sorted by group_key then name
$newCanonical = $canonicalByBggId.Values | Sort-Object group_key, name
New-Item -ItemType Directory -Force -Path (Split-Path $CanonicalPath) | Out-Null
$newCanonical | ConvertTo-Json -Depth 10 | Set-Content -Path $CanonicalPath -Encoding UTF8

# Append new games to intake (skip any already present)
if ($added.Count -gt 0) {
    $intake    = if (Test-Path $IntakePath) { @(Get-Content -Path $IntakePath -Raw | ConvertFrom-Json) } else { @() }
    $intakeIds = @($intake | ForEach-Object { [int]$_.bgg_id })

    $newIntake = $added | ForEach-Object {
        $id = [int]$_.bgg_id
        if ($intakeIds -notcontains $id) {
            $g = $canonicalByBggId[$id]
            if ([double]$g.rating -gt 0) {
                return
            }

            [pscustomobject]@{
                group_key      = $g.group_key
                bgg_id         = $id
                name           = $g.name
                current_rating = 0.0
                num_plays      = $g.num_plays
                players        = $g.players
                complexity     = $g.complexity
                bgg_rating     = $g.bgg_rating
                bgg_comment    = if ($g.PSObject.Properties['bgg_comment']) { [string]$g.bgg_comment } else { '' }
                notes          = if ($g.PSObject.Properties['notes']) { [string]$g.notes } else { '' }
                categories     = $g.categories
                mechanics      = $g.mechanics
            }
        }
    } | Where-Object { $null -ne $_ }

    if (@($newIntake).Count -gt 0) {
        $merged = @($intake) + @($newIntake) | Sort-Object @{ Expression = { [int]$_.num_plays }; Descending = $true }, name
        New-Item -ItemType Directory -Force -Path (Split-Path $IntakePath) | Out-Null
        $merged | ConvertTo-Json -Depth 10 | Set-Content -Path $IntakePath -Encoding UTF8
    }
}

# ---------------------------------------------------------------------------
# Reconciliation report
# ---------------------------------------------------------------------------
Write-Host "[3/3] Writing reconciliation report..." -ForegroundColor Cyan

$report = [pscustomobject]@{
    run_at              = (Get-Date -Format 'o')
    raw_snapshot        = $SnapshotPath
    total_from_snapshot = $fresh.Count
    total_in_canonical  = $canonicalByBggId.Count
    added               = $added.Count
    updated             = $updated.Count
    unchanged           = $unchanged
    new_games           = @($added)
    updated_games       = @($updated)
}

$reportDir = Split-Path -Path $ReconcilePath -Parent
if ($reportDir -and -not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }
$report | ConvertTo-Json -Depth 10 | Set-Content -Path $ReconcilePath -Encoding UTF8

Write-Host ""
Write-Host "Reconcile complete." -ForegroundColor Green
$report | Format-List run_at, total_from_snapshot, total_in_canonical, added, updated, unchanged
