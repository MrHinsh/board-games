[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$workflowScripts = @(Get-ChildItem (Join-Path $repo 'workflows') -Recurse -Filter '*.ps1')
foreach ($file in $workflowScripts) {
    if ($file.DirectoryName -ne (Join-Path $repo 'workflows') -or $file.Name -eq 'run.ps1') {
        throw 'Workflow entrypoints must be descriptively named files directly under workflows/.'
    }
}
foreach ($name in @('Rebuild-BoardGames.ps1','Refresh-BoardGames.ps1','Update-BggData.ps1')) {
    if ($name -notin $workflowScripts.Name) { throw "Missing workflow: $name" }
}
$manifest = @(Get-Content (Join-Path $repo 'architecture/entrypoints.json') -Raw | ConvertFrom-Json)
foreach ($route in $manifest) {
    $entry = Join-Path $repo $route.Entrypoint
    $target = Join-Path $repo $route.Implementation
    if (-not (Test-Path $entry) -or -not (Test-Path $target)) { throw "Missing entrypoint route: $($route.Entrypoint)" }
    $text = Get-Content $entry -Raw
    if ($text -notmatch [regex]::Escape($route.Implementation)) { throw "Entrypoint targets wrong owner: $entry" }
    $tokens=$null; $errors=$null
    $entryAst = [Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
    $targetAst = [Management.Automation.Language.Parser]::ParseFile($target,[ref]$tokens,[ref]$errors)
    if ($entryAst.ParamBlock) {
        $targetNames = @($targetAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        foreach ($p in $entryAst.ParamBlock.Parameters) {
            if ($p.Name.VariablePath.UserPath -notin $targetNames) { throw "Lost parameter $($p.Name) in $target" }
        }
        if ($text -notmatch '@PSBoundParameters') { throw "Entrypoint does not forward bound parameters: $entry" }
    }
}
# Check literal dependencies, including relocated config and checkpoint paths.
foreach ($file in Get-ChildItem (Join-Path $repo 'systems'),(Join-Path $repo 'workflows') -Recurse -Filter '*.ps1') {
    $text = Get-Content $file.FullName -Raw
    $references = @([regex]::Matches($text, 'Join-Path\s+\$PSScriptRoot\s+''([^'']+)''') | ForEach-Object { $_.Groups[1].Value })
    $references += @([regex]::Matches($text, '"\$PSScriptRoot/([^"\r\n]+)"') | ForEach-Object { $_.Groups[1].Value })
    foreach ($reference in $references) {
        if (-not (Test-Path (Join-Path $file.DirectoryName $reference))) { throw "Broken dependency in $($file.FullName): $reference" }
        if ($reference -match '\.agents') { throw "System depends on agent implementation: $($file.FullName)" }
    }
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $tempBase ('board-games-boundaries-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    foreach ($test in Get-ChildItem (Join-Path $repo 'systems'),(Join-Path $repo 'tests/workflows') -Recurse -Filter 'Test-*.ps1' | Sort-Object FullName) {
        & $test.FullName -FixtureRoot $fixture
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($tempBase.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar) -or (Split-Path $resolved -Leaf) -notlike 'board-games-boundaries-*') {
        throw 'Refusing cleanup outside the generated test directory.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "System boundaries: $($manifest.Count) compatibility routes and isolated system/workflow checks passed."
