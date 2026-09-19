<#
.SYNOPSIS
    For each owned base game, list expansions on BGG that are not owned.

.DESCRIPTION
    1. Loads owned base games from the canonical dataset.
    2. Queries the local bgg-mcp server for owned expansions (subtype=boardgameexpansion).
    3. Fetches each base game's thing XML from BGG's XMLAPI2 (Bearer-authenticated),
       cached under data/raw/bgg/details/<id>.xml.
    4. Parses <link type="boardgameexpansion"> entries and diffs against owned expansions.
    5. Writes JSON, CSV, and a markdown summary under data/reports/expansions/.

.NOTES
    Run from the repo root. Requires $env:BGG_API_KEY and the bgg-mcp server running.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [string]$Endpoint         = 'http://localhost:8080/mcp',
    [string]$CanonicalPath    = '.\data\working\canonical\games.json',
    [string]$CacheDir         = '.\data\raw\bgg\details',
    [string]$OutDir           = '.\data\reports\expansions',
    [int]$CacheMaxAgeDays     = 30,
    [int]$RequestDelayMs      = 800,
    [int]$BatchSize           = 20,
    [switch]$IncludeFanExpansions,
    [switch]$IncludePromos,
    [string[]]$Tiers,
    [string]$MembershipPath   = '.\data\working\ranking\tier-membership.json'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/what-am-i-missing/expansions/run.ps1') @PSBoundParameters
