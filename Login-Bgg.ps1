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

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot 'systems/bgg-integration/auth/Login-Bgg.ps1') @PSBoundParameters
