[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$QueuePath = '.\data\publish\queue\pending-rating-updates.json',
    [string]$Username,
    [int]$Limit = 0,

    # Ratings jumps larger than this require -AllowLargeDelta (guards against a bad rebalance)
    [decimal]$MaxDelta = 2.0,
    [switch]$AllowLargeDelta
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$setRatingScript = Join-Path $PSScriptRoot 'Set-BggPersonalRating.ps1'
if (-not (Test-Path $QueuePath)) {
    throw "Queue file not found: $QueuePath"
}

$queue = @(Get-Content -Path $QueuePath -Raw | ConvertFrom-Json)
if ($queue.Count -eq 0) {
    [pscustomobject]@{
        QueuePath = $QueuePath
        Attempted = 0
        Succeeded = 0
        Failed = 0
    }
    return
}

if ($Limit -gt 0) {
    $queue = @($queue | Select-Object -First $Limit)
}

# Validate the queue before anything reaches BGG. All rules are deterministic;
# ratings/ordering themselves are operator judgment and are never altered here.
$validationErrors = [System.Collections.Generic.List[string]]::new()
foreach ($item in $queue) {
    $label = "$($item.name) ($($item.bgg_id))"
    $rating = [decimal]$item.target_rating

    if ($rating -lt 1 -or $rating -gt 10) {
        $validationErrors.Add("${label}: target_rating $rating outside 1-10")
    }
    $tierProp = $item.PSObject.Properties['tier']
    if ($tierProp -and [string]$tierProp.Value -in @('X', 'U')) {
        $validationErrors.Add("${label}: tier $($tierProp.Value) must never be synced to BGG")
    }
    $currentProp = $item.PSObject.Properties['current_rating']
    if ($currentProp -and $null -ne $currentProp.Value -and [decimal]$currentProp.Value -gt 0) {
        $delta = [Math]::Abs($rating - [decimal]$currentProp.Value)
        if ($delta -gt $MaxDelta -and -not $AllowLargeDelta) {
            $validationErrors.Add("${label}: rating change $delta exceeds $MaxDelta (re-run with -AllowLargeDelta if intended)")
        }
    }
}

if ($validationErrors.Count -gt 0) {
    $validationErrors | ForEach-Object { Write-Warning $_ }
    throw ("Queue validation failed with {0} issue(s); nothing was synced." -f $validationErrors.Count)
}

$results = [System.Collections.Generic.List[object]]::new()
foreach ($item in $queue) {
    $gameId = [int]$item.bgg_id
    $targetRating = [decimal]$item.target_rating
    $name = [string]$item.name

    if (-not $PSCmdlet.ShouldProcess("$name ($gameId)", "Set BGG rating to $targetRating")) {
        [void]$results.Add([pscustomobject]@{
            bgg_id = $gameId
            name = $name
            target_rating = $targetRating
            status = 'skipped'
        })
        continue
    }

    try {
        $result = & $setRatingScript -Username $Username -GameId $gameId -Rating $targetRating
        [void]$results.Add([pscustomobject]@{
            bgg_id = $gameId
            name = $name
            target_rating = $targetRating
            status = 'synced'
            response = $result
        })
    } catch {
        [void]$results.Add([pscustomobject]@{
            bgg_id = $gameId
            name = $name
            target_rating = $targetRating
            status = 'failed'
            error = $_.Exception.Message
        })
    }
}

$remaining = @()
foreach ($item in (Get-Content -Path $QueuePath -Raw | ConvertFrom-Json)) {
    $match = $results | Where-Object { [int]$_.bgg_id -eq [int]$item.bgg_id } | Select-Object -First 1
    if ($null -eq $match -or $match.status -ne 'synced') {
        $remaining += $item
    }
}
$remaining | ConvertTo-Json -Depth 20 | Set-Content -Path $QueuePath -Encoding UTF8

[pscustomobject]@{
    QueuePath = $QueuePath
    Attempted = $results.Count
    Succeeded = @($results | Where-Object { $_.status -eq 'synced' }).Count
    Failed = @($results | Where-Object { $_.status -eq 'failed' }).Count
    Skipped = @($results | Where-Object { $_.status -eq 'skipped' }).Count
}
