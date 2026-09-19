Set-StrictMode -Version Latest

function ConvertFrom-BggPreviewJson {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Json)

    # BGG currently serialises an empty dynamicinfo object as `"dynamicinfo":}`.
    # Repair only that exact, known token. Any other malformed response must fail.
    $repaired = $Json.Replace('"dynamicinfo":}', '"dynamicinfo":null}')
    return $repaired | ConvertFrom-Json -Depth 100
}

function ConvertTo-ConferenceCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][int]$PreviewId,
        [Parameter(Mandatory = $true)][string]$PreviewTitle
    )

    if (-not $Item.geekitem -or -not $Item.geekitem.item) { return $null }
    $game = $Item.geekitem.item
    $subtypes = @($game.subtypes | Where-Object { $_ })
    $designers = @($game.links.boardgamedesigner | ForEach-Object { $_.name } | Where-Object { $_ })
    $mechanisms = @($game.links.boardgamemechanic | ForEach-Object { $_.name } | Where-Object { $_ })
    $categories = @($game.links.boardgamecategory | ForEach-Object { $_.name } | Where-Object { $_ })

    [pscustomobject][ordered]@{
        preview_id       = $PreviewId
        preview_title    = $PreviewTitle
        preview_item_id  = [int]$Item.itemid
        bgg_id           = [int]$Item.objectid
        name             = [string]$game.primaryname.name
        year_published   = [int]$game.yearpublished
        is_expansion     = ($subtypes -contains 'boardgameexpansion')
        subtypes         = $subtypes
        designers        = $designers
        mechanisms       = $mechanisms
        categories       = $categories
        min_players      = [int]$game.minplayers
        max_players      = [int]$game.maxplayers
        min_play_time    = [int]$game.minplaytime
        max_play_time    = [int]$game.maxplaytime
        thumbs           = [int]$Item.reactions.thumbs
        availability     = [string]$Item.availability_status
        location         = [string]$Item.location
        edition_name     = $(if ($Item.version -and $Item.version.item) { [string]$Item.version.item.name } else { '' })
        edition_bgg_id   = $(if ($Item.version -and $Item.version.item) { [int]$Item.version.item.objectid } else { 0 })
    }
}

function Get-ConferenceEquivalenceIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$CanonicalGames,
        [object[]]$ExplicitEquivalences = @()
    )

    $parent = @{}
    function Find-Root([int]$Id) {
        if (-not $parent.ContainsKey($Id)) { $parent[$Id] = $Id }
        if ($parent[$Id] -ne $Id) { $parent[$Id] = Find-Root $parent[$Id] }
        return [int]$parent[$Id]
    }
    function Join-Ids([int]$Left, [int]$Right) {
        $a = Find-Root $Left; $b = Find-Root $Right
        if ($a -ne $b) { $parent[$b] = $a }
    }

    foreach ($game in $CanonicalGames) {
        $id = [int]$game.bgg_id
        [void](Find-Root $id)
        foreach ($other in @($game.reimplements) + @($game.reimplemented_by)) {
            if ([int]$other -gt 0) { Join-Ids $id ([int]$other) }
        }
    }
    foreach ($entry in $ExplicitEquivalences) {
        $primary = [int]$entry.primary_bgg_id
        [void](Find-Root $primary)
        foreach ($linked in @($entry.linked_bgg_ids)) { Join-Ids $primary ([int]$linked) }
    }

    $result = @{}
    foreach ($id in @($parent.Keys)) { $result[[int]$id] = Find-Root ([int]$id) }
    return $result
}

function Get-ShrunkAffinityScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][string[]]$CandidateValues,
        [Parameter(Mandatory = $true)][object[]]$RatedGames,
        [Parameter(Mandatory = $true)][scriptblock]$ValueSelector,
        [double]$ShrinkK = 5.0
    )

    $mean = [double](($RatedGames | Measure-Object -Property rating -Average).Average)
    $scores = [System.Collections.Generic.List[double]]::new()
    foreach ($value in @($CandidateValues | Where-Object { $_ } | Sort-Object -Unique)) {
        $matches = @($RatedGames | Where-Object { @(& $ValueSelector $_) -contains $value })
        if ($matches.Count -eq 0) { continue }
        $featureMean = [double](($matches | Measure-Object -Property rating -Average).Average)
        $scores.Add((($matches.Count * $featureMean) + ($ShrinkK * $mean)) / ($matches.Count + $ShrinkK))
    }
    if ($scores.Count -eq 0) { return $null }
    return [double](($scores | Measure-Object -Average).Average)
}

function Get-TypeAffinityScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $true)][object[]]$RatedGames
    )

    $complexity = [double]$Candidate.complexity
    if ($complexity -le 0) { return $null }
    $playMinutes = [double]$Candidate.max_play_time
    $weighted = 0.0; $weights = 0.0
    foreach ($game in $RatedGames) {
        $gameComplexity = [double]$game.complexity
        if ($gameComplexity -le 0) { continue }
        $distance = [math]::Abs($complexity - $gameComplexity)
        $weight = 1.0 / (1.0 + (2.0 * $distance))
        if ($playMinutes -gt 0 -and $game.PSObject.Properties['max_play_time'] -and [double]$game.max_play_time -gt 0) {
            $weight *= 1.0 / (1.0 + ([math]::Abs($playMinutes - [double]$game.max_play_time) / 120.0))
        }
        $weighted += $weight * [double]$game.rating
        $weights += $weight
    }
    if ($weights -le 0) { return $null }
    return $weighted / $weights
}

function Get-ConferenceRecommendationBand {
    param([double]$Score, [string]$Confidence, [bool]$IsExpansion, [string]$OwnershipStatus)
    if ($IsExpansion) { return 'Expansion' }
    if ($OwnershipStatus -ne 'new') { return 'Already covered' }
    if ($Confidence -eq 'insufficient') { return 'Watch for reviews' }
    if ($Confidence -eq 'low') {
        if ($Score -ge 7.25) { return 'Worth a demo' }
        return 'Watch for reviews'
    }
    if ($Score -ge 8.0) { return 'Must investigate' }
    if ($Score -ge 7.25) { return 'Worth a demo' }
    if ($Score -ge 6.5) { return 'Watch for reviews' }
    return 'Probably skip'
}

function Get-ConferencePlayTimeLabel {
    param([int]$Minimum, [int]$Maximum)
    if ($Minimum -gt 0 -and $Maximum -gt 0 -and $Maximum -ge $Minimum) {
        if ($Minimum -eq $Maximum) { return "$Minimum min" }
        return "$Minimum-$Maximum min"
    }
    if ($Minimum -gt 0) { return "$Minimum min" }
    if ($Maximum -gt 0) { return "$Maximum min" }
    return 'unknown'
}
