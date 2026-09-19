function Select-ExplicitEquivalentOwnedItems {
    [CmdletBinding()]
    param(
        [object[]]$Items,
        [string]$EquivalentGamesPath,
        [switch]$IncludeExpansions
    )

    if ($IncludeExpansions -or -not (Test-Path $EquivalentGamesPath)) {
        return @()
    }

    $equivalentIds = @{}
    foreach ($group in @(Get-Content $EquivalentGamesPath -Raw | ConvertFrom-Json)) {
        $equivalentIds[[int]$group.primary_bgg_id] = $true
        foreach ($linkedId in @($group.linked_bgg_ids)) {
            $equivalentIds[[int]$linkedId] = $true
        }
    }

    return @($Items | Where-Object {
        $idProperty = $_.PSObject.Properties['objectid']
        $null -ne $idProperty -and $equivalentIds.ContainsKey([int]$idProperty.Value)
    })
}
