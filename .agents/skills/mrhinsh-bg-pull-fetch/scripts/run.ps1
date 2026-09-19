<#
.SYNOPSIS
    Fetch a fresh played-games collection from BGG and save an immutable raw snapshot.

.DESCRIPTION
    1. Calls the BGG MCP server to retrieve the user's played collection.
    2. Enriches each entry with game details (complexity, players, categories, mechanics).
    3. Deduplicates by bgg_id (keeps highest play count).
    4. Maps raw BGG fields to the canonical schema (bgg_id, name, year_published, …).
    5. Writes a timestamped JSON snapshot to data/raw/bgg/collection/<timestamp>.json.
    6. Emits the snapshot path to stdout so callers can pass it to mrhinsh-bg-reconcile.

.NOTES
    Run from the repo root. Requires the BGG MCP server running at $Endpoint.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [string]$Endpoint          = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [string]$RawDir            = '.\data\raw\bgg\collection',
    [switch]$IncludeExpansions,

    # BGG throttles the collection endpoint hard. This step issues eight queries
    # back to back; without a pause between them BGG returns 429 and the whole
    # pull dies at step 1.
    [int]$CollectionDelayMs    = 2500,
    [int]$MaxRetries           = 4
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/bgg-integration/collection-fetch/run.ps1') @PSBoundParameters
