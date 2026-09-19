[CmdletBinding()]
param(
    [string]$CanonicalPath = (Join-Path $PSScriptRoot '..\data\working\canonical\games.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$failures = [System.Collections.Generic.List[string]]::new()

# 1. Parse-check every PowerShell script (skills, scripts/, repo root)
$scriptFiles = Get-ChildItem -Path $repoRoot -Recurse -Filter '*.ps1' -File |
    Where-Object { $_.FullName -notmatch '\\(tools|\.local|\.git)\\' }

foreach ($file in $scriptFiles) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        foreach ($e in $errors) {
            $failures.Add("PARSE $($file.FullName.Substring($repoRoot.Length + 1)) line $($e.Extent.StartLineNumber): $($e.Message)")
        }
    }
}
Write-Host ("Parsed {0} scripts" -f $scriptFiles.Count)

# 2. Validate canonical games.json against .agents/context/contracts.md
if (-not (Test-Path $CanonicalPath)) {
    $failures.Add("DATA canonical file missing: $CanonicalPath")
} else {
    $games = Get-Content -Path $CanonicalPath -Raw | ConvertFrom-Json
    if ($games -isnot [System.Array]) {
        $failures.Add('DATA games.json must be a JSON array')
    } else {
        $requiredFields = @('group_key', 'bgg_id', 'name', 'year_published', 'rating', 'num_plays', 'reimplements', 'reimplemented_by')
        $seenIds = @{}
        $index = 0
        foreach ($game in $games) {
            foreach ($field in $requiredFields) {
                if (-not $game.PSObject.Properties[$field]) {
                    $failures.Add("DATA games[$index] missing required field '$field'")
                }
            }
            $idProp = $game.PSObject.Properties['bgg_id']
            if ($idProp) {
                $id = $idProp.Value
                if ($seenIds.ContainsKey($id)) {
                    $failures.Add("DATA duplicate bgg_id $id at games[$index] (first at games[$($seenIds[$id])])")
                } else {
                    $seenIds[$id] = $index
                }
            }
            $playsProp = $game.PSObject.Properties['num_plays']
            if ($playsProp -and $playsProp.Value -lt 0) {
                $failures.Add("DATA games[$index] num_plays is negative")
            }
            foreach ($relationshipField in @('reimplements', 'reimplemented_by')) {
                $relationshipProp = $game.PSObject.Properties[$relationshipField]
                if ($relationshipProp -and $null -eq $relationshipProp.Value) {
                    $failures.Add("DATA games[$index] $relationshipField must be an array, not null")
                } elseif ($relationshipProp) {
                    foreach ($relationshipId in @($relationshipProp.Value)) {
                        if ($relationshipId -isnot [int] -and $relationshipId -isnot [long]) {
                            $failures.Add("DATA games[$index] $relationshipField contains non-integer value '$relationshipId'")
                        }
                    }
                }
            }
            $index++
        }
        Write-Host ("Validated {0} canonical games" -f $games.Count)
    }
}

# 3. Every .claude skill shim must point at scripts that exist
$shimDir = Join-Path $repoRoot '.claude\skills'
if (Test-Path $shimDir) {
    $shims = Get-ChildItem -Path $shimDir -Recurse -Filter 'SKILL.md' -File
    foreach ($shim in $shims) {
        $content = Get-Content -Path $shim.FullName -Raw
        if ($content -notmatch '(?s)^---\s*\r?\nname:') {
            $failures.Add("SKILL $($shim.FullName.Substring($repoRoot.Length + 1)) missing YAML frontmatter")
        }
        foreach ($match in [regex]::Matches($content, '\./\.agents/[\w./-]+\.ps1')) {
            $target = Join-Path $repoRoot (($match.Value -replace '^\./', '').Replace('/', '\'))
            if (-not (Test-Path $target)) {
                $failures.Add("SKILL $($shim.Name) references missing script: $($match.Value)")
            }
        }
    }
    Write-Host ("Checked {0} Claude skill shims" -f $shims.Count)
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
    throw ("Test-Repo failed with {0} issue(s)" -f $failures.Count)
}

& (Join-Path $PSScriptRoot 'Test-SystemBoundaries.ps1')
Write-Host 'Test-Repo: all checks passed' -ForegroundColor Green
