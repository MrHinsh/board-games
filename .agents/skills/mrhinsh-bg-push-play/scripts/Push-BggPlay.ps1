[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$GameId,

    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$PlayDate = (Get-Date).ToString('yyyy-MM-dd'),

    [ValidateRange(1, 1000)]
    [int]$Quantity = 1,

    [ValidateRange(0, 1440)]
    [int]$LengthMinutes = 0,

    [string]$Location = '',
    [string]$Comments = '',

    [string]$Endpoint = 'https://boardgamegeek.com',
    [string]$Cookie,
    [string]$SessionFile = '.\.local\secrets\bgg-session.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
        if ($cached.cookie) {
            return ([string]$cached.cookie).Trim()
        }
    }

    if ($env:BGG_COOKIE) {
        return ([string]$env:BGG_COOKIE).Trim()
    }

    throw "No BGG cookie found. Run .\\Login-Bgg.ps1 first to populate $SessionFile."
}

$cookieString = Resolve-BggCookie -Cookie $Cookie -SessionFile $SessionFile

$headers = @{
    'content-type' = 'application/json'
    Cookie = $cookieString
}

$playPayload = @{
    ajax = 1
    action = 'save'
    objecttype = 'thing'
    objectid = "$GameId"
    playdate = $PlayDate
    date = (Get-Date).ToString('o')
    location = $Location
    locationfilter = ''
    quantity = $Quantity
    length = $LengthMinutes
    twitter = $false
    bsky = $false
}

if (-not [string]::IsNullOrWhiteSpace($Comments)) {
    $playPayload.comments = $Comments
}

$response = Invoke-WebRequest `
    -Uri "$Endpoint/geekplay.php" `
    -Method Post `
    -Headers $headers `
    -Body ($playPayload | ConvertTo-Json -Depth 10 -Compress)

if ($response.StatusCode -ne 200) {
    throw "BGG play post failed with HTTP $($response.StatusCode)."
}

$parsed = $null
try {
    $parsed = $response.Content | ConvertFrom-Json
} catch {
    # Some responses are not strict JSON depending on BGG behavior.
}

[pscustomobject]@{
    StatusCode = $response.StatusCode
    GameId = $GameId
    PlayDate = $PlayDate
    Quantity = $Quantity
    PlayId = if ($null -ne $parsed -and $parsed.PSObject.Properties['playid']) { $parsed.playid } else { $null }
    NumPlays = if ($null -ne $parsed -and $parsed.PSObject.Properties['numplays']) { $parsed.numplays } else { $null }
    Raw = if ($null -ne $parsed) { $parsed } else { $response.Content }
}
