# mrhinsh-bg-audit

Purpose:
- Audit the live BGG owned collection for duplicate collection rows that share the same `bgg_id`.
- Flag where multiple owned copies have diverged personal ratings.

Inputs:
- `Username` optional BGG username.
- `Cookie` optional BGG cookie override.
- `SessionFile` defaults to `.local/secrets/bgg-session.json`.
- `ReportPath` defaults to `data/reports/quality/duplicate-collection-report.json`.

Outputs:
- `data/reports/quality/duplicate-collection-report.json` containing duplicate owned-copy groups and whether their ratings match.

Preconditions:
- Valid BGG session cookie available via `.local/secrets/bgg-session.json`, `-Cookie`, or `BGG_COOKIE`.
- BGG username available via `-Username`, session file, or `BGG_USERNAME`.

Postconditions:
- A fresh duplicate collection report is written.

Idempotency:
- Safe to re-run. The report file is overwritten with current live results.

Failure Modes:
- Missing cookie or username resolution.
- BGG returns a non-200 response for the collection query.

Example:
```powershell
./.agents/skills/mrhinsh-bg-audit/scripts/run.ps1 -Username 'MrHinsh'
```
