# Snapshot the operator-judgment data files before any script mutates them.
# Ratings/ordering in canonical data are the only non-rebuildable data in this repo.
[CmdletBinding()]
param(
    [string]$Reason = 'unspecified',
    [int]$Keep = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$checkpointRoot = Join-Path $repoRoot 'data\state\checkpoints'

$protectedFiles = @(@(
    (Join-Path $repoRoot 'data\working\canonical\games.json'),
    (Join-Path $repoRoot 'data\working\canonical\equivalent-games.json'),
    (Join-Path $repoRoot 'data\working\unrated\intake-ranked.json')
) | Where-Object { Test-Path $_ })

if ($protectedFiles.Count -eq 0) {
    return
}

$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$dir = Join-Path $checkpointRoot "$stamp-$($Reason -replace '[^\w-]', '')"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

foreach ($file in $protectedFiles) {
    Copy-Item -Path $file -Destination $dir
}

# Prune oldest checkpoints beyond the retention count
$all = @(Get-ChildItem -Path $checkpointRoot -Directory | Sort-Object Name -Descending)
if ($all.Count -gt $Keep) {
    $all | Select-Object -Skip $Keep | Remove-Item -Recurse -Force -Confirm:$false
}

Write-Verbose "Checkpoint written: $dir"
