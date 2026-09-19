[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$GameId,

    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$PlayDate = (Get-Date).ToString('yyyy-MM-dd'),

    [ValidateRange(1, 1000)]
    [int]$Quantity = 1,

    [ValidateRange(0, 1440)]
    [int]$LengthMinutes = 0,

    [string]$Location = '',
    [string]$Comments = '',

    [string]$Endpoint = 'https://boardgamegeek.com',
    [string]$Cookie,
    [string]$SessionFile = '.\.local\secrets\bgg-session.json'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/bgg-integration/plays/Push-BggPlay.ps1') @PSBoundParameters
