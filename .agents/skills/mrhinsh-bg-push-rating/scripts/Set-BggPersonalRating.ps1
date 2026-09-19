[CmdletBinding()]
param(
    [string]$Username,

    [Parameter(Mandatory = $true)]
    [int]$GameId,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 10)]
    [decimal]$Rating,

    [string]$Endpoint = 'https://boardgamegeek.com',
    [string]$Cookie,
    [string]$SessionFile = '.\.local\secrets\bgg-session.json'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/bgg-integration/ratings/Set-BggPersonalRating.ps1') @PSBoundParameters
