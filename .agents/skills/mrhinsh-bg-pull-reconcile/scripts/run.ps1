<#
.SYNOPSIS
    Merge a fresh BGG snapshot into canonical data and produce a reconciliation report.

.DESCRIPTION
    1. Reads the normalized snapshot produced by mrhinsh-bg-fetch.
    2. Loads the existing canonical games list.
        3. For each game in the snapshot:
                 - Existing game: updates only safe metadata fields. Never clears or lowers a
                     locally-set rating. If canonical is still unrated, seed from BGG's personal rating.
                     Play count is raised if BGG reports more plays.
                 - New game: adds to canonical using BGG's personal rating when present; only unrated
                     games are appended to intake.
    4. Writes the updated canonical file (sorted by group_key then name).
    5. Appends genuinely new games to the unrated intake (sorted by play count desc).
    6. Writes a reconciliation report with added/updated/unchanged counts.

.NOTES
    Run from the repo root. Pass the snapshot path emitted by mrhinsh-bg-fetch/scripts/run.ps1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SnapshotPath,

    [string]$CanonicalPath  = '.\data\working\canonical\games.json',
    [string]$IntakePath     = '.\data\working\unrated\intake.json',
    [string]$ReconcilePath  = '.\data\reports\quality\reconcile-report.json'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/bgg-integration/reconcile/run.ps1') @PSBoundParameters
