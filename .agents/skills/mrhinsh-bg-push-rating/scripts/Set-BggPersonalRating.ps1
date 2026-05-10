[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'BGG login API requires plaintext password in JSON body; input is collected as PSCredential.')]
param(
    [Parameter(Mandatory = $true)]
    [pscredential]$Credential,

    [Parameter(Mandatory = $true)]
    [int]$GameId,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 10)]
    [decimal]$Rating,

    [string]$Endpoint = 'https://boardgamegeek.com'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$effectiveUsername = $Credential.UserName
$passwordText = $Credential.GetNetworkCredential().Password

function Get-BggCollectionItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,
        [Parameter(Mandatory = $true)]
        [int]$GameId,
        [Parameter(Mandatory = $true)]
        [string]$Endpoint
    )

    $uri = "$Endpoint/xmlapi2/collection?username=$([uri]::EscapeDataString($Username))&id=$GameId&stats=1"

    $timeout = 1
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $response = Invoke-WebRequest -Uri $uri -Method Get
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

$collectionItem = Get-BggCollectionItem -Username $effectiveUsername -GameId $GameId -Endpoint $Endpoint
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

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$loginHeaders = @{ 'content-type' = 'application/json' }
$loginPayload = @{
    credentials = @{
        username = $effectiveUsername
        password = $passwordText
    }
}

$null = Invoke-WebRequest `
    -Uri "$Endpoint/login/api/v1" `
    -Method Post `
    -WebSession $session `
    -Headers $loginHeaders `
    -Body ($loginPayload | ConvertTo-Json -Depth 5 -Compress)

$formHeaders = @{ 'content-type' = 'application/x-www-form-urlencoded' }
$ratingText = $Rating.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
$form = @{
    fieldname = 'rating'
    collid = $collId
    objecttype = 'thing'
    objectid = "$GameId"
    value = $ratingText
    ajax = 1
    action = 'savedata'
}

$response = Invoke-WebRequest `
    -Uri "$Endpoint/geekcollection.php" `
    -Method Post `
    -WebSession $session `
    -Headers $formHeaders `
    -Body $form

if ($response.StatusCode -ne 200) {
    throw "BGG rating update failed with HTTP $($response.StatusCode)."
}

$updatedItem = Get-BggCollectionItem -Username $effectiveUsername -GameId $GameId -Endpoint $Endpoint
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
