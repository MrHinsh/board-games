[CmdletBinding()]
param()

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/ranking/top-report/run.ps1') @PSBoundParameters
