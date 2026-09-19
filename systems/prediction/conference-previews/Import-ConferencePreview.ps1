<#
.SYNOPSIS
    Fetch and normalize a BoardGameGeek GeekPreview candidate list.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int]$PreviewId,
    [Parameter(Mandatory = $true)][string]$OutPath,
    [string]$BaseUri = 'https://boardgamegeek.com',
    [ValidateRange(1, 12)][int]$PageThrottleLimit = 8,
    [int]$RequestDelayMs = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ConferencePreview.ps1')

function Get-JsonText([string]$Uri) {
    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing
    if ([int]$response.StatusCode -ne 200) { throw "BGG returned HTTP $($response.StatusCode) for $Uri" }
    return [string]$response.Content
}

$previewUri = "$BaseUri/api/geekpreviews?previewid=$PreviewId&nosession=1"
$preview = ConvertFrom-BggPreviewJson -Json (Get-JsonText $previewUri)
if (-not $preview.config -or [int]$preview.config.numpages -lt 1) {
    throw "GeekPreview $PreviewId did not provide a positive page count."
}

$rows = [System.Collections.Generic.List[object]]::new()
$pageNumbers = @(1..[int]$preview.config.numpages)
$pageResponses = @($pageNumbers | ForEach-Object -ThrottleLimit $PageThrottleLimit -Parallel {
    $page = $_
    $uri = "$using:BaseUri/api/geekpreviewitems?previewid=$using:PreviewId&pageid=$page&nosession=1"
    foreach ($attempt in 1..3) {
        try {
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing
            $content = [string]$response.Content
            if ([int]$response.StatusCode -eq 200 -and $content.TrimStart().StartsWith('[')) {
                [pscustomobject]@{ page = $page; json = $content }
                break
            }
        } catch {
            if ($attempt -eq 3) { throw }
        }
        if ($attempt -eq 3) { throw "BGG did not return a JSON array for preview page $page after 3 attempts." }
        Start-Sleep -Seconds $attempt
    }
})
foreach ($pageResponse in @($pageResponses | Sort-Object page)) {
    $items = @(ConvertFrom-BggPreviewJson -Json $pageResponse.json)
    foreach ($item in $items) {
        $candidate = ConvertTo-ConferenceCandidate -Item $item -PreviewId $PreviewId -PreviewTitle $preview.title
        if ($null -ne $candidate) { $rows.Add($candidate) }
    }
    if ($PageThrottleLimit -eq 1 -and $RequestDelayMs -gt 0 -and $pageResponse.page -lt [int]$preview.config.numpages) {
        Start-Sleep -Milliseconds $RequestDelayMs
    }
}

$distinct = @($rows | Group-Object bgg_id | ForEach-Object { $_.Group | Sort-Object thumbs -Descending | Select-Object -First 1 })
if ($distinct.Count -lt 1) { throw "GeekPreview $PreviewId returned no usable games." }
if ([int]$preview.config.numitems -gt 0 -and $rows.Count -ne [int]$preview.config.numitems) {
    Write-Warning "Preview metadata reported $($preview.config.numitems) items; fetched $($rows.Count)."
}

$outDir = Split-Path -Parent $OutPath
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$payload = [ordered]@{
    preview_id = $PreviewId
    title = [string]$preview.title
    source_url = "$BaseUri/geekpreview/$PreviewId"
    fetched_at = (Get-Date).ToUniversalTime().ToString('o')
    reported_item_count = [int]$preview.config.numitems
    fetched_item_count = $rows.Count
    distinct_game_count = $distinct.Count
    candidates = $distinct
}
$payload | ConvertTo-Json -Depth 12 | Set-Content -Path $OutPath -Encoding UTF8
Write-Host ("Imported {0} distinct games from '{1}' -> {2}" -f $distinct.Count, $preview.title, $OutPath)
