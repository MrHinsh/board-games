[CmdletBinding()]
param(
    [string]$Username,

    [Parameter(Mandatory = $true)]
    [int]$GameId,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 10)]
    [decimal]$Rating,

    [string]$Endpoint = 'https://boardgamegeek.com',
    [string]$Cookie,
    [string]$SessionFile = '.\.local\secrets\bgg-session.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-ToCookieMap {
    param([object]$InputObject)

    $map = [ordered]@{}
    if ($null -eq $InputObject) {
        return $map
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            if ($null -ne $key) {
                $map[[string]$key] = [string]$InputObject[$key]
            }
        }
        return $map
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        if ($null -ne $property.Value) {
            $map[$property.Name] = [string]$property.Value
        }
    }

    return $map
}

function Build-BggCookieHeader {
    param([object]$CookieMap)

    $resolvedCookieMap = Convert-ToCookieMap -InputObject $CookieMap
    if ($resolvedCookieMap.Count -eq 0) {
        return $null
    }

    $segments = New-Object System.Collections.Generic.List[string]
    foreach ($name in @('SessionID', 'bggusername', 'bggpassword')) {
        if ($resolvedCookieMap.Contains($name) -and $resolvedCookieMap[$name]) {
            $segments.Add("$name=$($resolvedCookieMap[$name])")
        }
    }

    foreach ($entry in $resolvedCookieMap.GetEnumerator()) {
        if ($entry.Key -in @('SessionID', 'bggusername', 'bggpassword')) {
            continue
        }

        if ($entry.Value) {
            $segments.Add("$($entry.Key)=$($entry.Value)")
        }
    }

    return ($segments -join '; ')
}

function Get-SessionCookieHeader {
    param([object]$SessionRecord)

    if ($null -eq $SessionRecord) {
        return $null
    }

    if ($SessionRecord.PSObject.Properties.Name -contains 'cookies') {
        $cookieHeader = Build-BggCookieHeader -CookieMap $SessionRecord.cookies
        if ($cookieHeader) {
            return $cookieHeader
        }
    }

    if ($SessionRecord.PSObject.Properties.Name -contains 'cookie' -and $SessionRecord.cookie) {
        return ([string]$SessionRecord.cookie).Trim()
    }

    return $null
}

function Resolve-BggCookie {
    param(
        [string]$Cookie,
        [string]$SessionFile
    )

    if ($Cookie) {
        return $Cookie.Trim()
    }

    if (Test-Path $SessionFile) {
        $cached = Get-Content -Path $SessionFile -Raw | ConvertFrom-Json
        $cachedCookie = Get-SessionCookieHeader -SessionRecord $cached
        if ($cachedCookie) {
            return $cachedCookie
        }
    }

    if ($env:BGG_COOKIE) {
        return ([string]$env:BGG_COOKIE).Trim()
    }

    throw "No BGG cookie found. Run .\\Login-Bgg.ps1 first to populate $SessionFile."
}

function Resolve-BggUsername {
    param(
        [string]$Username,
        [string]$SessionFile
    )

    if ($Username) {
        return $Username
    }

    if (Test-Path $SessionFile) {
        $cached = Get-Content -Path $SessionFile -Raw | ConvertFrom-Json
        if ($cached.username) {
            return [string]$cached.username
        }
    }

    if ($env:BGG_USERNAME) {
        return [string]$env:BGG_USERNAME
    }

    throw 'No BGG username found. Provide -Username or run .\\Login-Bgg.ps1 first.'
}

$cookieString = Resolve-BggCookie -Cookie $Cookie -SessionFile $SessionFile
$effectiveUsername = Resolve-BggUsername -Username $Username -SessionFile $SessionFile

$collectionReferer = "$Endpoint/collection/user/$([uri]::EscapeDataString($effectiveUsername))?subtype=boardgame&own=1&ff=1"
$browserHeaders = @{
    Accept = 'text/javascript, text/html, application/xml, text/xml, */*'
    'Accept-Language' = 'en-GB,en;q=0.9'
    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0'
    'X-Requested-With' = 'XMLHttpRequest'
    Referer = $collectionReferer
    Cookie = $cookieString
}

function Get-BggCollectionItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,
        [Parameter(Mandatory = $true)]
        [int]$GameId,
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    $uri = "$Endpoint/xmlapi2/collection?username=$([uri]::EscapeDataString($Username))&id=$GameId&stats=1"

    $timeout = 1
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $Headers
        if ($response.StatusCode -eq 202) {
            Start-Sleep -Seconds $timeout
            $timeout = [Math]::Min($timeout * 2, 16)
            continue
        }

        if ($response.StatusCode -ne 200) {
            throw "Collection lookup failed with HTTP $($response.StatusCode)."
        }

        [xml]$xml = $response.Content
        $items = @($xml.items.item)
        if ($items.Count -eq 0) {
            return $null
        }

        # We requested a single game id, but keep this defensive.
        return ($items | Where-Object { [int]$_.objectid -eq $GameId } | Select-Object -First 1)
    }

    throw 'BGG collection lookup timed out while waiting for prepared data.'
}

$baseHeaders = @{ Cookie = $cookieString }

$collectionItem = Get-BggCollectionItem -Username $effectiveUsername -GameId $GameId -Endpoint $Endpoint -Headers $baseHeaders
if ($null -eq $collectionItem) {
    throw "Game $GameId is not present in $effectiveUsername's BGG collection. Add it to collection first, then set a rating."
}

$collId = [int]$collectionItem.collid
if ($collId -le 0) {
    throw "Could not resolve collection id (collid) for game $GameId."
}

$beforeRating = $null
if ($collectionItem.stats -and $collectionItem.stats.rating -and $collectionItem.stats.rating.value) {
    $value = [string]$collectionItem.stats.rating.value
    if ($value -ne 'N/A') {
        $beforeRating = [double]$value
    }
}

$editDataHeaders = @{}
foreach ($entry in $browserHeaders.GetEnumerator()) {
    $editDataHeaders[$entry.Key] = $entry.Value
}

$editDataUri = "$Endpoint/geekcollection.php?cellid=9&collid=$collId&fieldname=rating&objecttype=thing&objectid=$GameId&ajax=1&action=editdata"
$editDataResponse = Invoke-WebRequest -Uri $editDataUri -Method Get -Headers $editDataHeaders
if ($editDataResponse.StatusCode -ne 200) {
    throw "BGG editdata lookup failed with HTTP $($editDataResponse.StatusCode)."
}

$formHeaders = @{}
foreach ($entry in $browserHeaders.GetEnumerator()) {
    $formHeaders[$entry.Key] = $entry.Value
}
$formHeaders['content-type'] = 'application/x-www-form-urlencoded; charset=UTF-8'
$formHeaders['Origin'] = $Endpoint
$ratingText = $Rating.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
$form = @{
    fieldname = 'rating'
    collid = $collId
    objecttype = 'thing'
    objectid = "$GameId"
    rating = $ratingText
    B1 = 'Cancel'
    ajax = 1
    action = 'savedata'
}

$response = Invoke-WebRequest `
    -Uri "$Endpoint/geekcollection.php" `
    -Method Post `
    -Headers $formHeaders `
    -Body $form

if ($response.StatusCode -ne 200) {
    throw "BGG rating update failed with HTTP $($response.StatusCode)."
}

$updatedItem = Get-BggCollectionItem -Username $effectiveUsername -GameId $GameId -Endpoint $Endpoint -Headers $baseHeaders
$afterRating = $null
if ($updatedItem -and $updatedItem.stats -and $updatedItem.stats.rating -and $updatedItem.stats.rating.value) {
    $value = [string]$updatedItem.stats.rating.value
    if ($value -ne 'N/A') {
        $afterRating = [double]$value
    }
}

[pscustomobject]@{
    StatusCode = $response.StatusCode
    GameId = $GameId
    CollectionId = $collId
    RatingBefore = $beforeRating
    RatingRequested = [double]$Rating
    RatingAfter = $afterRating
}
