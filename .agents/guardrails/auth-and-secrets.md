# Auth And Secrets Guardrails

## Auth Model
- Two independent credentials, not interchangeable:
  - `BGG_API_KEY` covers **all reads** via the MCP server. Preferred path.
  - Session cookie covers **writes only** (rating/play push).
- BGG scripted username/password login is blocked by Cloudflare (HTTP 403). Do not rely on it.
- The write-side auth path is an imported session cookie captured from a browser.
- Cookie is cached at `.local/secrets/bgg-session.json` and expires. `Login-Bgg.ps1` silently falls
  through to an interactive password prompt when it has — check `savedAt` before assuming it is live.
- Direct calls to `boardgamegeek.com/xmlapi2/...` return HTTP 401. Route reads through the MCP server.

## Allowed Secret Locations
- `.local/` only (ignored by git).
- Process/User/Machine environment variables when needed by runtime.

## Prohibited Secret Locations
- Any tracked file under repo root except `.gitignore` rules.
- Commit messages, issue text, PR descriptions, or generated reports.

## Environment Variable Policy
- `BGG_API_KEY` may be set at User or Machine scope. Prefer passing it to child processes by
  environment inheritance rather than on a command line or in a request header.
- `BGG_COOKIE` may be set at User or Machine scope.
- `BGG_USERNAME` may be set alongside cookie for convenience.
- If Machine scope write fails due to privileges, fall back to User scope and log a warning.
- User-scope writes are not visible to already-running shells. Start a new shell after a change.

## Redaction Policy
- Do not echo full cookie values.
- Display only masked prefixes/suffixes when confirming configuration.

## Operational Guidance
- Run `./Login-Bgg.ps1` to refresh cache and env vars.
- If password login returns HTTP 403, use browser cookie import mode.
- Restart long-lived processes after env var changes if they read env at startup.
