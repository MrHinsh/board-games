[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PubMeepleCsvPath,

    [Parameter(Mandatory = $true)]
    [string]$RankingCsvPath,

    [string]$ImportRankColumn = 'rank',
    [string]$ImportTitleColumn = 'item',
    [string]$RankingTitleColumn = 'name'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedTitleKey {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    $collapsed = [regex]::Replace($Value.Trim(), '\s+', ' ')
    return $collapsed.ToUpperInvariant()
}

function Test-ColumnExists {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row,

        [Parameter(Mandatory = $true)]
        [string]$ColumnName
    )

    return $null -ne $Row.PSObject.Properties[$ColumnName]
}

if (-not (Test-Path $PubMeepleCsvPath)) {
    throw "PubMeeple CSV not found: $PubMeepleCsvPath"
}

if (-not (Test-Path $RankingCsvPath)) {
    throw "Ranking CSV not found: $RankingCsvPath"
}

$rankingRows = @(Import-Csv -Path $RankingCsvPath)
if ($rankingRows.Count -eq 0) {
    throw "Ranking CSV is empty: $RankingCsvPath"
}

if (-not (Test-ColumnExists -Row $rankingRows[0] -ColumnName $RankingTitleColumn)) {
    throw "Ranking CSV is missing required column '$RankingTitleColumn': $RankingCsvPath"
}

$rankingByKey = @{}
foreach ($row in $rankingRows) {
    $title = [string]$row.$RankingTitleColumn
    $key = Get-NormalizedTitleKey -Value $title
    if ($key -eq '') {
        throw "Ranking CSV contains a blank title in column '$RankingTitleColumn': $RankingCsvPath"
    }

    if ($rankingByKey.ContainsKey($key)) {
        throw "Ranking CSV contains duplicate title matches for '$title' in column '$RankingTitleColumn': $RankingCsvPath"
    }

    $rankingByKey[$key] = $row
}

$importRows = @(Import-Csv -Path $PubMeepleCsvPath)
if ($importRows.Count -eq 0) {
    throw "PubMeeple CSV is empty: $PubMeepleCsvPath"
}

if (-not (Test-ColumnExists -Row $importRows[0] -ColumnName $ImportTitleColumn)) {
    throw "PubMeeple CSV is missing required column '$ImportTitleColumn': $PubMeepleCsvPath"
}

if (-not (Test-ColumnExists -Row $importRows[0] -ColumnName $ImportRankColumn)) {
    throw "PubMeeple CSV is missing required column '$ImportRankColumn': $PubMeepleCsvPath"
}

$orderedImports = [System.Collections.Generic.List[object]]::new()
$seenImportKeys = @{}
$inputSequence = 0

foreach ($row in $importRows) {
    $inputSequence++

    $title = [string]$row.$ImportTitleColumn
    $key = Get-NormalizedTitleKey -Value $title
    if ($key -eq '') {
        continue
    }

    if ($seenImportKeys.ContainsKey($key)) {
        throw "PubMeeple CSV contains duplicate title matches for '$title' in column '$ImportTitleColumn': $PubMeepleCsvPath"
    }

    if (-not $rankingByKey.ContainsKey($key)) {
        throw "PubMeeple CSV title '$title' does not match any row in '$RankingCsvPath' column '$RankingTitleColumn'."
    }

    $rankValue = $inputSequence
    $parsedRank = 0.0
    if (-not [string]::IsNullOrWhiteSpace([string]$row.$ImportRankColumn) -and [double]::TryParse([string]$row.$ImportRankColumn, [ref]$parsedRank)) {
        $rankValue = $parsedRank
    }

    [void]$orderedImports.Add([pscustomobject]@{
        key = $key
        rank = $rankValue
        sequence = $inputSequence
    })
    $seenImportKeys[$key] = $true
}

if ($orderedImports.Count -eq 0) {
    throw "PubMeeple CSV did not contain any usable rows from columns '$ImportRankColumn' and '$ImportTitleColumn': $PubMeepleCsvPath"
}

$reorderedRows = [System.Collections.Generic.List[object]]::new()
$consumed = @{}

foreach ($item in @($orderedImports | Sort-Object @{ Expression = { [double]$_.rank } }, @{ Expression = { [int]$_.sequence } })) {
    [void]$reorderedRows.Add($rankingByKey[$item.key])
    $consumed[$item.key] = $true
}

foreach ($row in $rankingRows) {
    $key = Get-NormalizedTitleKey -Value ([string]$row.$RankingTitleColumn)
    if (-not $consumed.ContainsKey($key)) {
        [void]$reorderedRows.Add($row)
    }
}

$reorderedRows | Export-Csv -Path $RankingCsvPath -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
    RankingCsvPath = $RankingCsvPath
    PubMeepleCsvPath = $PubMeepleCsvPath
    ReorderedCount = $orderedImports.Count
    UnmatchedTargetRowsAppended = $rankingRows.Count - $orderedImports.Count
}