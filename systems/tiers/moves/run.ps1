[CmdletBinding()]
param(
	[string]$MembershipPath = '.\data\working\ranking\tier-membership.json',
	[string]$QueuePath = '.\data\publish\queue\pending-tier-moves.json',
	[string]$ImportPath,
	[int]$GameId,
	[string]$Tier,
	[int]$SourceBucket = -1,
	[string]$Notes = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'Apply-BggTierMoves.ps1'
$invokeArgs = @{
	MembershipPath = $MembershipPath
	QueuePath = $QueuePath
}

if ($ImportPath) {
	$invokeArgs.ImportPath = $ImportPath
}

if ($GameId -gt 0) {
	$invokeArgs.GameId = $GameId
}

if (-not [string]::IsNullOrWhiteSpace($Tier)) {
	$invokeArgs.Tier = $Tier
	$invokeArgs.SourceBucket = $SourceBucket
	$invokeArgs.Notes = $Notes
}

& $scriptPath @invokeArgs
