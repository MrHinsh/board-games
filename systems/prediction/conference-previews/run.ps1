<#
.SYNOPSIS
    Import and rank a BGG GeekPreview using the existing taste model.
#>
[CmdletBinding()]
param(
    [int]$PreviewId = 93,
    [string]$OutDir = '.\data\reports\conferences',
    [string]$WorkingDir = '.\data\working\conferences',
    [string]$Endpoint = 'http://localhost:8080/mcp',
    [switch]$RefreshDetails
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyy-MM-dd'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
if (-not (Test-Path $WorkingDir)) { New-Item -ItemType Directory -Path $WorkingDir -Force | Out-Null }

$candidatesPath = Join-Path $WorkingDir "preview-$PreviewId-candidates.json"
$rankedPath = Join-Path $OutDir "$stamp-preview-$PreviewId-ranked.csv"
$reportPath = Join-Path $OutDir "$stamp-preview-$PreviewId-report.md"
$detailsPath = Join-Path $WorkingDir 'bgg-details.json'

& (Join-Path $PSScriptRoot 'Import-ConferencePreview.ps1') -PreviewId $PreviewId -OutPath $candidatesPath
$scoreArgs = @{
    CandidatesPath = $candidatesPath
    OutPath = $rankedPath
    ReportPath = $reportPath
    DetailsCachePath = $detailsPath
    Endpoint = $Endpoint
}
if ($RefreshDetails.IsPresent) { $scoreArgs.RefreshDetails = $true }
& (Join-Path $PSScriptRoot 'Score-ConferencePreview.ps1') @scoreArgs

Write-Host ''
Write-Host "Candidates : $candidatesPath"
Write-Host "Ranked     : $rankedPath"
Write-Host "Report     : $reportPath"
