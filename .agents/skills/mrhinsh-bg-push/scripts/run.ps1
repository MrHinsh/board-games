[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$QueuePath = '.\data\publish\queue\pending-rating-updates.json',
    [string]$Username,
    [int]$Limit = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\..\mrhinsh-bg-push-rating\scripts\Sync-BggRatingQueue.ps1'
if (-not (Test-Path $scriptPath)) {
    throw "Missing script: $scriptPath"
}

$forwarded = @{
    QueuePath = $QueuePath
    Username = $Username
    Limit = $Limit
}

if ($WhatIfPreference) {
    $forwarded.WhatIf = $true
}

& $scriptPath @forwarded