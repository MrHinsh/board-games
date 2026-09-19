[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [string]$Endpoint = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,

    [ValidateSet('none', 'players', 'complexity', 'year')]
    [string]$GroupBy = 'players',

    [int]$Top = 10,
    [switch]$IncludeExpansions,

    [switch]$BuildRatingSheet = $true,

    [string]$CanonicalPath = '.\data\working\canonical\games.json',
    [string]$RankingOutDir = '.\data\reports\ranking',
    [string]$TopOutDir = '.\data\reports\top'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$exportPlayedScript = Join-Path $PSScriptRoot '../systems/bgg-integration/collection-fetch/Export-BggPlayedGames.ps1'
$stackRankScript = Join-Path $PSScriptRoot '../systems/ranking/stackrank/Export-BggStackRank.ps1'
$topScript = Join-Path $PSScriptRoot '../systems/ranking/top-report/Export-BggTop10.ps1'
$ratingSheetScript = Join-Path $PSScriptRoot '../systems/tiers/rating-sheet/New-BggRatingUploadSheet.ps1'

if (-not (Test-Path $exportPlayedScript)) { throw "Missing script: $exportPlayedScript" }
if (-not (Test-Path $stackRankScript)) { throw "Missing script: $stackRankScript" }
if (-not (Test-Path $topScript)) { throw "Missing script: $topScript" }
if ($BuildRatingSheet -and -not (Test-Path $ratingSheetScript)) { throw "Missing script: $ratingSheetScript" }

$playedResult = & $exportPlayedScript `
    -Username $Username `
    -Endpoint $Endpoint `
    -ApiKey $ApiKey `
    -Cookie $Cookie `
    -GroupBy $GroupBy `
    -IncludeExpansions:$IncludeExpansions

$stackRankResult = & $stackRankScript `
    -InputPath $CanonicalPath `
    -OutDir $RankingOutDir

$topResult = & $topScript `
    -Username $Username `
    -Top $Top `
    -Endpoint $Endpoint `
    -ApiKey $ApiKey `
    -Cookie $Cookie `
    -OutDir $TopOutDir `
    -IncludeExpansions:$IncludeExpansions

$sheetResult = $null
if ($BuildRatingSheet) {
    $sheetResult = & $ratingSheetScript
}

[pscustomobject]@{
    Username = $Username
    Endpoint = $Endpoint
    GroupBy = $GroupBy
    IncludeExpansions = [bool]$IncludeExpansions
    TopCount = $Top
    Played = $playedResult
    StackRank = $stackRankResult
    Top = $topResult
    RatingSheet = $sheetResult
}
