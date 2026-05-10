<#
.SYNOPSIS
    Authenticates with BoardGameGeek and sets BGG_COOKIE for the current session.

.DESCRIPTION
    POSTs credentials to BGG's login API (same endpoint used by the Android app),
    extracts the bggpassword session cookie from the response, and sets the BGG_COOKIE
    environment variable so other skills can use it without further prompts.

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
$LoginPageUri = 'https://boardgamegeek.com/login'
$LoginPostUri = 'https://boardgamegeek.com/login'

#region --- helpers ---

function Get-MaskedCookie([string]$Cookie) {
    if ($Cookie.Length -le 8) { return '***' }
    $Cookie.Substring(0, 4) + ('*' * ($Cookie.Length - 8)) + $Cookie.Substring($Cookie.Length - 4)
}

function Test-CachedSession([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    try {
        $cached = Get-Content $Path -Raw | ConvertFrom-Json
        if (-not $cached.cookie) { return $false }

        # Quick validation — hit a lightweight authenticated endpoint
        $headers = @{ Cookie = $cached.cookie }
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
    try {
        Set-BggEnvironmentVariables -CookieValue $cached.cookie -UsernameValue $cached.username -Scope $PersistScope
    } catch {
        if ($PersistScope -eq 'Machine') {
            Write-Warning 'Unable to set Machine-scope environment variables (run elevated). Falling back to User scope.'
            Set-BggEnvironmentVariables -CookieValue $cached.cookie -UsernameValue $cached.username -Scope 'User'
        } else {
            throw
        }
    }
    Write-Host "BGG: using cached session ($(Get-MaskedCookie $cached.cookie))" -ForegroundColor Green
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

    @{
        username = $Username
        cookie   = $cookieString
        savedAt  = (Get-Date -Format 'o')
    } | ConvertTo-Json | Set-Content $SessionFile -Encoding UTF8

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

# Some BGG login flows use anti-forgery tokens. Fetch login page first and include token if present.
$csrfToken = $null
try {
    $loginPage = Invoke-WebRequest -Uri $LoginPageUri `
        -Method Get `
        -UseBasicParsing `
        -WebSession $loginWebSession `
        -TimeoutSec 30

    if ($loginPage -and $loginPage.Content) {
        $tokenMatch = [regex]::Match($loginPage.Content, 'name="csrf_token"\s+value="([^"]+)"')
        if ($tokenMatch.Success) {
            $csrfToken = $tokenMatch.Groups[1].Value
        }
    }
} catch {
    # Continue anyway; many deployments do not require explicit token in posted form.
}

$formBody = @{
    username = $Username
    password = $PlainPassword
}

if ($csrfToken) {
    $formBody['csrf_token'] = $csrfToken
}

try {
    # Use Invoke-WebRequest so we can inspect session cookies.
    $response = Invoke-WebRequest -Uri $LoginPostUri `
        -Method Post `
        -Body $formBody `
        -ContentType 'application/x-www-form-urlencoded' `
        -UseBasicParsing `
        -WebSession $loginWebSession `
        -MaximumRedirection 5 `
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

if ($response.StatusCode -notin 200, 204, 302) {
    Write-Error "BGG login returned HTTP $($response.StatusCode). Check credentials."
    exit 1
}

#endregion

#region --- extract cookie ---

# Build cookie string from session cookie container after login + redirects.
$cookiePairs = @()
foreach ($cookie in $loginWebSession.Cookies.GetCookies('https://boardgamegeek.com/')) {
    if ($cookie.Name -and $cookie.Value) {
        $cookiePairs += ("{0}={1}" -f $cookie.Name, $cookie.Value)
    }
}

if (-not $cookiePairs -or $cookiePairs.Count -eq 0) {
    Write-Error "BGG login succeeded but no cookies were captured. BGG may have changed its auth flow."
    exit 1
}

# Build a Cookie header string from all pairs (bggpassword + any companion cookies)
$cookieString = ($cookiePairs -join '; ')

if ($cookieString -notmatch 'bggpassword') {
    Write-Warning "bggpassword not found in Set-Cookie. Cookie string: $cookieString"
    Write-Warning "BGG may have changed its auth mechanism."
}

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
@{
    username   = $Username
    cookie     = $cookieString
    savedAt    = (Get-Date -Format 'o')
} | ConvertTo-Json | Set-Content $SessionFile -Encoding UTF8

Write-Host "BGG: authenticated as '$Username'" -ForegroundColor Green
Write-Host "Cookie: $(Get-MaskedCookie $cookieString)" -ForegroundColor DarkGray
Write-Host "BGG_COOKIE is set for this session and persisted at $PersistScope scope. Cached to .local/secrets/bgg-session.json." -ForegroundColor Cyan

#endregion
