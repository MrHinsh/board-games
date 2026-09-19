<#
.SYNOPSIS
    Resolve nominated game names to BGG ids via the local bgg-mcp server.

.DESCRIPTION
    Club members type game names freehand, so this does fuzzy resolution and
    then sanity-checks the result. Two failure modes are common and both are
    caught here rather than silently poisoning the ranking:

      - a same-name title from decades earlier ("Summit" 1961, "El Dorado" 1973)
      - a stub BGG entry with almost no ratings ("Anno 1800", 14 ratings)

    Anything suspicious is reported so it can be pinned in name-overrides.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NominationsPath,

    [Parameter(Mandatory = $true)]
    [string]$OutPath,

    [string]$OverridesPath = (Join-Path $PSScriptRoot '../../../../systems/prediction/club-nominations/name-overrides.json'),
    [string]$NameCachePath = '.\data\working\nominations\name-cache.json',
    [string]$Endpoint = 'http://localhost:8080/mcp',
    [int]$RequestDelayMs = 2000,
    [int]$MinYear = 1990,
    [int]$MinRatings = 300,
    [switch]$RefreshNames
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/prediction/club-nominations/Resolve-Nominations.ps1') @PSBoundParameters
