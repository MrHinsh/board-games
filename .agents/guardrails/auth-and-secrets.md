# Auth And Secrets Guardrails

## Auth Model
- BGG scripted username/password login may be blocked by Cloudflare challenges.
- Primary auth path is imported session cookie captured from browser.
- Cookie is cached at `.local/secrets/bgg-session.json`.

## Allowed Secret Locations
- `.local/` only (ignored by git).
- Process/User/Machine environment variables when needed by runtime.

## Prohibited Secret Locations
- Any tracked file under repo root except `.gitignore` rules.
- Commit messages, issue text, PR descriptions, or generated reports.

## Environment Variable Policy
- `BGG_COOKIE` may be set at User or Machine scope.
- `BGG_USERNAME` may be set alongside cookie for convenience.
- If Machine scope write fails due to privileges, fall back to User scope and log a warning.

## Redaction Policy
- Do not echo full cookie values.
- Display only masked prefixes/suffixes when confirming configuration.

## Operational Guidance
- Run `./Login-Bgg.ps1` to refresh cache and env vars.
- If password login returns HTTP 403, use browser cookie import mode.
- Restart long-lived processes after env var changes if they read env at startup.
