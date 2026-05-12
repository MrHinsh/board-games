<#
.SYNOPSIS
    Authenticates with BoardGameGeek and sets BGG_COOKIE for the current session.

.DESCRIPTION
    POSTs credentials to BGG's JSON login API, extracts the authenticated session cookies,
    and sets the BGG_COOKIE environment variable so other skills can use it without further
    prompts.

    The cookie is written to .local/secrets/bgg-session.json (gitignored) for
    persistence across terminal sessions. Subsequent runs will reuse the cached
    session if it is still valid.

.PARAMETER Username
    BGG username. Defaults to the BGG_USERNAME environment variable.

.PARAMETER Password
    BGG password as a SecureString. If omitted you will be prompted interactively.

.PARAMETER Force
    Re-authenticate even if a cached session exists.

.PARAMETER Cookie
    Existing BGG cookie header value to use directly. Useful when automated login
    is blocked by Cloudflare and you copy cookies from a browser session.

.PARAMETER PersistScope
    Scope for persistent environment variables. Defaults to User.
    Use Machine for system-wide variables (requires elevated PowerShell).

.EXAMPLE
    .\Login-Bgg.ps1
    # Prompts for password, sets $env:BGG_COOKIE

.EXAMPLE
    .\Login-Bgg.ps1 -Username MrHinsh -Force
    # Forces fresh login even if a cached session exists
#>
[CmdletBinding()]
param(
    [string]$Username = $env:BGG_USERNAME,
    [SecureString]$Password,
    [switch]$Force,
    [string]$Cookie,
    [ValidateSet('User', 'Machine')]
    [string]$PersistScope = 'User'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SessionDir  = Join-Path $PSScriptRoot '.local\secrets'
$SessionFile = Join-Path $SessionDir 'bgg-session.json'
$LoginApiUri = 'https://boardgamegeek.com/login/api/v1'

#region --- helpers ---

function Get-MaskedCookie([string]$Cookie) {
    if ($Cookie.Length -le 8) { return '***' }
    $Cookie.Substring(0, 4) + ('*' * ($Cookie.Length - 8)) + $Cookie.Substring($Cookie.Length - 4)
}

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

function Convert-CookieHeaderToMap {
    param([string]$CookieHeader)

    $map = [ordered]@{}
    if ([string]::IsNullOrWhiteSpace($CookieHeader)) {
        return $map
    }

    foreach ($segment in ($CookieHeader -split ';')) {
        $trimmed = $segment.Trim()
        if (-not $trimmed) {
            continue
        }

        $parts = $trimmed -split '=', 2
        if ($parts.Count -eq 2 -and $parts[0]) {
            $map[$parts[0].Trim()] = $parts[1].Trim()
        }
    }

    return $map
}

function Convert-SetCookieHeadersToMap {
    param([string[]]$SetCookieHeaders)

    $map = [ordered]@{}
    foreach ($header in @($SetCookieHeaders)) {
        if ([string]::IsNullOrWhiteSpace($header)) {
            continue
        }

        $match = [regex]::Match($header, '^([^=;\s]+)=([^;]*)')
        if ($match.Success) {
            $map[$match.Groups[1].Value] = $match.Groups[2].Value
        }
    }

    return $map
}

function Add-CookiesFromWebSession {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [object]$CookieMap
    )

    if ($null -eq $WebSession -or $null -eq $WebSession.Cookies) {
        return
    }

    foreach ($uri in @('https://boardgamegeek.com/', 'https://www.boardgamegeek.com/')) {
        foreach ($cookie in $WebSession.Cookies.GetCookies($uri)) {
            if ($cookie.Name -and $cookie.Value) {
                $CookieMap[$cookie.Name] = $cookie.Value
            }
        }
    }
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
        $cookieMap = Convert-ToCookieMap -InputObject $SessionRecord.cookies
        $cookieHeader = Build-BggCookieHeader -CookieMap $cookieMap
        if ($cookieHeader) {
            return $cookieHeader
        }
    }

    if ($SessionRecord.PSObject.Properties.Name -contains 'cookie' -and $SessionRecord.cookie) {
        return ([string]$SessionRecord.cookie).Trim()
    }

    return $null
}

function Save-BggSession {
    param(
        [string]$Path,
        [string]$Username,
        [object]$CookieMap,
        [string]$Source
    )

    $resolvedCookieMap = Convert-ToCookieMap -InputObject $CookieMap
    $cookieHeader = Build-BggCookieHeader -CookieMap $resolvedCookieMap

    [pscustomobject]@{
        username = $Username
        cookie = $cookieHeader
        cookies = [pscustomobject]$resolvedCookieMap
        source = $Source
        savedAt = (Get-Date -Format 'o')
    } | ConvertTo-Json -Depth 5 | Set-Content $Path -Encoding UTF8
}

function Test-CachedSession([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    try {
        $cached = Get-Content $Path -Raw | ConvertFrom-Json
        $cookieHeader = Get-SessionCookieHeader -SessionRecord $cached
        if (-not $cookieHeader) { return $false }

        # Quick validation — hit a lightweight authenticated endpoint
        $headers = @{ Cookie = $cookieHeader }
        $r = Invoke-WebRequest -Uri 'https://www.boardgamegeek.com/api/preferences' `
                               -Headers $headers -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
        return ($r -and $r.StatusCode -eq 200)
    } catch {
        return $false
    }
}

function Set-BggEnvironmentVariables(
    [string]$CookieValue,
    [string]$UsernameValue,
    [string]$Scope
) {
    $env:BGG_COOKIE = $CookieValue
    if ($UsernameValue) {
        $env:BGG_USERNAME = $UsernameValue
    }

    [System.Environment]::SetEnvironmentVariable('BGG_COOKIE', $CookieValue, $Scope)
    if ($UsernameValue) {
        [System.Environment]::SetEnvironmentVariable('BGG_USERNAME', $UsernameValue, $Scope)
    }
}

#endregion

#region --- use cached session ---

if (-not $Force -and (Test-CachedSession $SessionFile)) {
    $cached = Get-Content $SessionFile -Raw | ConvertFrom-Json
    $cachedCookie = Get-SessionCookieHeader -SessionRecord $cached
    try {
        Set-BggEnvironmentVariables -CookieValue $cachedCookie -UsernameValue $cached.username -Scope $PersistScope
    } catch {
        if ($PersistScope -eq 'Machine') {
            Write-Warning 'Unable to set Machine-scope environment variables (run elevated). Falling back to User scope.'
            Set-BggEnvironmentVariables -CookieValue $cachedCookie -UsernameValue $cached.username -Scope 'User'
        } else {
            throw
        }
    }
    Write-Host "BGG: using cached session ($(Get-MaskedCookie $cachedCookie))" -ForegroundColor Green
    Write-Host "BGG_COOKIE is set for this session and persisted at $PersistScope scope." -ForegroundColor Cyan
    return
}

#endregion

if (-not (Test-Path $SessionDir)) {
    New-Item -ItemType Directory -Path $SessionDir -Force | Out-Null
}

#region --- get credentials ---

if (-not $Username) {
    $Username = Read-Host 'BGG username'
}

if ($Cookie) {
    $cookieString = $Cookie.Trim()
    $cookieMap = Convert-CookieHeaderToMap -CookieHeader $cookieString
    try {
        Set-BggEnvironmentVariables -CookieValue $cookieString -UsernameValue $Username -Scope $PersistScope
    } catch {
        if ($PersistScope -eq 'Machine') {
            Write-Warning 'Unable to set Machine-scope environment variables (run elevated). Falling back to User scope.'
            Set-BggEnvironmentVariables -CookieValue $cookieString -UsernameValue $Username -Scope 'User'
        } else {
            throw
        }
    }

    if (-not (Test-Path $SessionDir)) {
        New-Item -ItemType Directory -Path $SessionDir -Force | Out-Null
    }

    Save-BggSession -Path $SessionFile -Username $Username -CookieMap $cookieMap -Source 'import'

    Write-Host "BGG: imported cookie and persisted env vars at $PersistScope scope." -ForegroundColor Green
    Write-Host "Cookie: $(Get-MaskedCookie $cookieString)" -ForegroundColor DarkGray
    return
}

if (-not $Password) {
    $Password = Read-Host 'BGG password' -AsSecureString
}

$PlainPassword = [System.Net.NetworkCredential]::new('', $Password).Password

#endregion

#region --- authenticate ---

Write-Host "Authenticating as '$Username'..." -ForegroundColor Cyan

$loginWebSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$loginHeaders = @{
    Accept = 'application/json'
    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0'
}

$formBody = @{
    credentials = @{
        username = $Username
        password = $PlainPassword
    }
} | ConvertTo-Json -Depth 3 -Compress

try {
    $response = Invoke-WebRequest -Uri $LoginApiUri `
        -Method Post `
        -Body $formBody `
        -ContentType 'application/json' `
        -Headers $loginHeaders `
        -UseBasicParsing `
        -WebSession $loginWebSession `
        -TimeoutSec 30
} catch {
    $statusCode = $_.Exception.Response?.StatusCode.value__ ?? 'unknown'
    if ($statusCode -eq 403) {
        Write-Error "BGG login blocked by Cloudflare (HTTP 403). Log in via browser and rerun with -Cookie '<full cookie header>' or use a BGG API key."
    } else {
        Write-Error "BGG login failed (HTTP $statusCode): $($_.Exception.Message)"
    }
    exit 1
} finally {
    # Zero out plain-text password from memory
    $PlainPassword = $null
}

if ($response.StatusCode -notin 200, 204) {
    Write-Error "BGG login returned HTTP $($response.StatusCode). Check credentials."
    exit 1
}

#endregion

#region --- extract cookie ---

$cookieMap = Convert-SetCookieHeadersToMap -SetCookieHeaders @($response.Headers['Set-Cookie'])
Add-CookiesFromWebSession -WebSession $loginWebSession -CookieMap $cookieMap

if ($cookieMap.Count -eq 0) {
    Write-Error "BGG login succeeded but no cookies were captured. BGG may have changed its auth flow."
    exit 1
}

$missingRequiredCookies = @('SessionID', 'bggusername', 'bggpassword' | Where-Object { -not $cookieMap.Contains($_) })
if ($missingRequiredCookies.Count -gt 0) {
    Write-Error "BGG login did not return the expected session cookies: $($missingRequiredCookies -join ', ')."
    exit 1
}

$cookieString = Build-BggCookieHeader -CookieMap $cookieMap

# JSON login currently returns the same three cookies used by BGG write endpoints.

#endregion

#region --- persist and export ---

try {
    Set-BggEnvironmentVariables -CookieValue $cookieString -UsernameValue $Username -Scope $PersistScope
} catch {
    if ($PersistScope -eq 'Machine') {
        Write-Warning 'Unable to set Machine-scope environment variables (run elevated). Falling back to User scope.'
        Set-BggEnvironmentVariables -CookieValue $cookieString -UsernameValue $Username -Scope 'User'
    } else {
        throw
    }
}

# Save to .local/secrets/bgg-session.json (gitignored)
Save-BggSession -Path $SessionFile -Username $Username -CookieMap $cookieMap -Source 'login-api'

Write-Host "BGG: authenticated as '$Username'" -ForegroundColor Green
Write-Host "Cookie: $(Get-MaskedCookie $cookieString)" -ForegroundColor DarkGray
Write-Host "BGG_COOKIE is set for this session and persisted at $PersistScope scope. Cached to .local/secrets/bgg-session.json." -ForegroundColor Cyan

#endregion
