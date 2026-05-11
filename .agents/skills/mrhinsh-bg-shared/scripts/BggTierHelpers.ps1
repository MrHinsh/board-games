Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [object]$Default = @()
    )

    if (-not (Test-Path $Path)) {
        return $Default
    }

    $raw = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $Default
    }

    return ($raw | ConvertFrom-Json)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $Value | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding UTF8
}

function Get-TierOrder {
    return @('S', 'A', 'B', 'C', 'D', 'F', 'U', 'X')
}

function Test-IsNonRankedTier {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tier
    )

    return $Tier -in @('U', 'X')
}

function Get-TierSortWeight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tier
    )

    $index = [array]::IndexOf((Get-TierOrder), $Tier)
    if ($index -lt 0) {
        return 999
    }

    return $index
}

function Get-TierLabelFromBucket {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Bucket
    )

    switch ($Bucket) {
        10 { return 'S' }
        9 { return 'A' }
        8 { return 'B' }
        7 { return 'C' }
        6 { return 'D' }
        { $_ -ge 1 -and $_ -le 5 } { return 'F' }
        default { return 'U' }
    }
}

function Get-TierRankingGroupKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tier,

        [Parameter(Mandatory = $true)]
        [int]$SourceBucket
    )

    if ($Tier -eq 'F') {
        return 'F'
    }

    if ($Tier -eq 'X') {
        return 'X'
    }

    return "$Tier|$SourceBucket"
}

function Get-InitialBucketFromRating {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Rating,

        [int]$ExistingBucket = -1
    )

    if ($ExistingBucket -ge 0) {
        return $ExistingBucket
    }

    if ($Rating -le 0) {
        return 0
    }

    if ($Rating -eq [math]::Floor($Rating)) {
        return [int]$Rating
    }

    if ($Rating -ge 2) {
        return [int]([math]::Floor($Rating) + 1)
    }

    return 1
}

function Convert-TierRankToBggRating {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tier,

        [Parameter(Mandatory = $true)]
        [int]$SourceBucket,

        [Parameter(Mandatory = $true)]
        [int]$RankInTier,

        [Parameter(Mandatory = $true)]
        [int]$TierCount
    )

    if ($Tier -eq 'U') {
        return 0.0
    }

    if ($Tier -eq 'X') {
        throw 'Tier X is an exit tier and is excluded from rating conversion.'
    }

    if ($TierCount -lt 1) {
        throw 'TierCount must be at least 1.'
    }

    if ($RankInTier -lt 1 -or $RankInTier -gt $TierCount) {
        throw 'RankInTier must be within 1..TierCount.'
    }

    if ($Tier -eq 'F') {
        $fBase = 1.0
        $fWidth = 3.999
        if ($TierCount -eq 1) {
            return [math]::Round(($fBase + $fWidth), 3)
        }

        $fFraction = (($TierCount - $RankInTier) / ($TierCount - 1)) * $fWidth
        return [math]::Round(($fBase + $fFraction), 3)
    }

    $baseBand = [math]::Max($SourceBucket - 1, 1)
    if ($TierCount -eq 1) {
        return [math]::Round(($baseBand + 0.999), 3)
    }

    $fraction = (($TierCount - $RankInTier) / ($TierCount - 1)) * 0.999
    return [math]::Round(($baseBand + $fraction), 3)
}

function Get-BggGameUrl {
    param(
        [Parameter(Mandatory = $true)]
        [int]$GameId
    )

    return "https://boardgamegeek.com/boardgame/$GameId"
}

function Get-CanonicalGameMap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CanonicalPath
    )

    $items = @(Read-JsonFile -Path $CanonicalPath -Default @())
    $map = @{}
    foreach ($item in $items) {
        $map[[int]$item.bgg_id] = $item
    }

    return $map
}

function Import-TabularData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Input file not found: $Path"
    }

    $extension = [System.IO.Path]::GetExtension($Path)
    switch ($extension.ToLowerInvariant()) {
        '.csv' {
            return @(Import-Csv -Path $Path)
        }
        '.json' {
            return @(Read-JsonFile -Path $Path -Default @())
        }
        default {
            throw "Unsupported import format: $extension"
        }
    }
}
