Set-StrictMode -Version Latest

function Update-BggDesignerIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Games,
        [Parameter(Mandatory = $true)][object[]]$TrainingGames,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Endpoint = 'http://localhost:8080/mcp',
        [int]$MaxAgeDays = 30,
        [switch]$Refresh,
        [scriptblock]$FetchDetails
    )

    $targetIds = @($Games | Where-Object { [int]$_.num_plays -gt 0 } | ForEach-Object { [int]$_.bgg_id })
    $targetIds += @($TrainingGames | ForEach-Object { [int]$_.bgg_id })
    $targetIds = @($targetIds | Sort-Object -Unique)

    $previousFullRefresh = $null
    if (Test-Path $Path) { $previousFullRefresh = (Get-Item $Path).LastWriteTime }
    $rebuild = $Refresh.IsPresent -or -not $previousFullRefresh
    if (-not $rebuild) {
        $rebuild = ((Get-Date) - $previousFullRefresh).TotalDays -gt $MaxAgeDays
    }

    $byId = @{}
    if (Test-Path $Path) {
        $cached = Get-Content -Path $Path -Raw | ConvertFrom-Json
        foreach ($property in $cached.PSObject.Properties) { $byId[[int]$property.Name] = @($property.Value) }
    }

    $idsToFetch = @(if ($rebuild) { $targetIds } else { $targetIds | Where-Object { -not $byId.ContainsKey($_) } })
    if ($idsToFetch.Count -eq 0) { return $byId }

    if (-not $FetchDetails) {
        $FetchDetails = { param([int[]]$Ids, [string]$McpEndpoint)
            Invoke-BggMcpTool -ToolName 'bgg-details' -Arguments @{ ids = $Ids } -Endpoint $McpEndpoint
        }
    }

    Write-Host ("Fetching designers for {0} games ({1} played games in scope)..." -f $idsToFetch.Count, @($Games | Where-Object { [int]$_.num_plays -gt 0 }).Count)
    for ($i = 0; $i -lt $idsToFetch.Count; $i += 20) {
        $batch = @($idsToFetch[$i..([Math]::Min($i + 19, $idsToFetch.Count - 1))])
        $result = & $FetchDetails $batch $Endpoint
        if ($result -is [string]) { throw "BGG details failed for designer batch: $result" }
        $details = @($result | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'id' })
        $byReturnedId = @{}
        foreach ($detail in $details) { $byReturnedId[[int]$detail.id] = $detail }
        foreach ($id in $batch) {
            if (-not $byReturnedId.ContainsKey([int]$id)) { throw "BGG details omitted game $id; designer cache was not written." }
            $byId[[int]$id] = @((([string]$byReturnedId[[int]$id].designer) -split ',\s*') | Where-Object { $_ })
        }
        if ($i + 20 -lt $idsToFetch.Count) { Start-Sleep -Seconds 2 }
    }

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $out = [ordered]@{}
    foreach ($id in ($byId.Keys | Sort-Object)) { $out["$id"] = $byId[$id] }
    $out | ConvertTo-Json -Depth 4 | Set-Content -Path $Path -Encoding UTF8
    # The file timestamp is the full-refresh clock. Incremental additions must
    # not postpone the next scheduled refresh of existing entries.
    if (-not $rebuild -and $previousFullRefresh) { (Get-Item $Path).LastWriteTime = $previousFullRefresh }
    Write-Host "Designer index cached -> $Path"
    return $byId
}
