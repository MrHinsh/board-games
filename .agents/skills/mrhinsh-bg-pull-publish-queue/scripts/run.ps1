[CmdletBinding()]
param()

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/tiers/rating-sheet/run.ps1') @PSBoundParameters
