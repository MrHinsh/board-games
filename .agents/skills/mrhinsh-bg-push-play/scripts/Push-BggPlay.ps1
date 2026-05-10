[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [pscredential]$Credential,

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

    [string]$Endpoint = 'https://boardgamegeek.com'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$username = $Credential.UserName
$passwordText = $Credential.GetNetworkCredential().Password

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$headers = @{ 'content-type' = 'application/json' }

$loginPayload = @{
    credentials = @{
        username = $username
        password = $passwordText
    }
}

$null = Invoke-WebRequest `
    -Uri "$Endpoint/login/api/v1" `
    -Method Post `
    -WebSession $session `
    -Headers $headers `
    -Body ($loginPayload | ConvertTo-Json -Depth 5 -Compress)

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
    -WebSession $session `
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
