[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [string]$Endpoint = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [switch]$IncludeExpansions
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Pull owns fetching and reconciliation. Rebuild is a separate workflow.
$snapshot = & (Join-Path $PSScriptRoot '../collection-fetch/run.ps1') @PSBoundParameters
$reconcile = & (Join-Path $PSScriptRoot '../reconcile/run.ps1') -SnapshotPath $snapshot
[pscustomobject]@{
    Username = $Username
    Endpoint = $Endpoint
    IncludeExpansions = [bool]$IncludeExpansions
    SnapshotPath = $snapshot
    Reconcile = $reconcile
}
