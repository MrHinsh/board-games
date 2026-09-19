<#
.SYNOPSIS
    Parse host nominations out of a saved dump of the club sign-up sheet.

.DESCRIPTION
    The Drive connector renders the whole workbook as markdown tables. The
    'Sign Up Here' tab lays each host out as a block:

        | Host 01: | David Mck |
        | Game 1:  | The Networks |
        | Game 2:  | Altiplano |
        | Game 3:  | Yamatai |
        | [merged] Comments: |
        | [merged] <host comment> |

    This script finds those blocks wherever they sit in the dump and emits one
    row per nominated game. It does not touch BGG or the canonical dataset.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SheetDumpPath,

    [Parameter(Mandatory = $true)]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SheetDumpPath)) { throw "Sheet dump not found: $SheetDumpPath" }

$raw = Get-Content -Path $SheetDumpPath -Raw

# The connector may hand back either the bare text or {"fileContent": "..."}.
$text = $raw
if ($raw.TrimStart().StartsWith('{')) {
    try {
        $obj = $raw | ConvertFrom-Json
        if ($obj.PSObject.Properties.Name -contains 'fileContent') { $text = [string]$obj.fileContent }
    } catch {
        Write-Verbose 'Dump is not JSON; treating as plain text.'
    }
}

$lines = $text -split "`r?`n"

function Get-CellAfterLabel {
    param([string]$Line, [string]$LabelPattern, [int]$Window = 2)

    # Only look a couple of cells past the label. The sheet puts three column
    # groups side by side (nominations, voting, table sorting), so an unbounded
    # scan for the next non-empty cell walks into the voting columns and returns
    # things like "1st Choice:" as a game name.
    $cells = @($Line -split '\|' | ForEach-Object { $_.Trim() })
    for ($i = 0; $i -lt $cells.Count; $i++) {
        if ($cells[$i] -match $LabelPattern) {
            $limit = [Math]::Min($i + $Window, $cells.Count - 1)
            for ($j = $i + 1; $j -le $limit; $j++) {
                if ($cells[$j]) { return $cells[$j] }
            }
            return ''
        }
    }
    return $null
}

function Test-IsLabelText {
    param([string]$Value)
    if (-not $Value) { return $true }
    $v = $Value.Trim()
    if ($v.EndsWith(':')) { return $true }
    if ($v -match '(?i)^\d+(st|nd|rd|th)\s+choice') { return $true }
    if ($v -match '(?i)^(attendee|table|player|host|game|reserve)\s*\d*\s*:?$') { return $true }
    return $false
}

function Clear-SheetText {
    param([string]$Value)
    if (-not $Value) { return '' }
    $v = $Value -replace '\\\[merged\\\]', '' -replace '\[merged\]', ''
    $v = $v -replace '\\([!*_])', '$1'
    return $v.Trim()
}

$rows = [System.Collections.Generic.List[object]]::new()
$currentHost = $null
$currentIndex = $null
$pendingComment = $null

foreach ($line in $lines) {
    $hostVal = Get-CellAfterLabel -Line $line -LabelPattern '^Host\s*0*(\d+)\s*:'
    if ($null -ne $hostVal) {
        # flush comment onto the previous host's rows before switching
        if ($pendingComment -and $currentHost) {
            foreach ($r in $rows) { if ($r.host -eq $currentHost) { $r.host_comment = $pendingComment } }
        }
        $pendingComment = $null
        if ($line -match 'Host\s*0*(\d+)\s*:') { $currentIndex = [int]$Matches[1] }
        $name = Clear-SheetText $hostVal
        # an unclaimed host slot has no name; do not open a block for it
        $currentHost = $(if (Test-IsLabelText $name) { $null } else { $name })
        continue
    }

    if ($currentHost) {
        $gameVal = Get-CellAfterLabel -Line $line -LabelPattern '^Game\s*(\d+)\s*:'
        if ($null -ne $gameVal) {
            $slot = 0
            if ($line -match 'Game\s*(\d+)\s*:') { $slot = [int]$Matches[1] }
            $game = Clear-SheetText $gameVal
            if ($game -and -not (Test-IsLabelText $game)) {
                $rows.Add([pscustomobject]@{
                    host_index   = $currentIndex
                    host         = $currentHost
                    slot         = $slot
                    game_raw     = $game
                    host_comment = ''
                })
            }
            continue
        }

        # a merged, non-label line inside a host block is that host's comment
        if ($line -match 'merged' -and $line -notmatch '(?i)Comments\s*:') {
            $c = Clear-SheetText (($line -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -First 1))
            if ($c -and $c.Length -gt 2) { $pendingComment = $c }
        }
    }
}

if ($pendingComment -and $currentHost) {
    foreach ($r in $rows) { if ($r.host -eq $currentHost) { $r.host_comment = $pendingComment } }
}

if ($rows.Count -eq 0) {
    throw "No host nominations found in $SheetDumpPath. Check that the dump includes the 'Sign Up Here' tab."
}

$outDir = Split-Path -Parent $OutPath
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$rows | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8

$hostCount = @($rows | Select-Object -ExpandProperty host -Unique).Count
Write-Host ("Parsed {0} nominations from {1} hosts -> {2}" -f $rows.Count, $hostCount, $OutPath)
