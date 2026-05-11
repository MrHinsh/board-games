[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$QueuePath = '.\data\publish\queue\pending-rating-updates.json',
    [string]$Username,
    [int]$Limit = 0
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
