# mrhinsh-bg-push-rating

Purpose:
- Push personal ratings to BoardGameGeek web endpoints.
- Focused skill for setting personal ratings only.

Inputs:
- BGG username and password (via `PSCredential`).
- Game id and rating value.

Outputs:
- JSON-like PowerShell object summarizing rating before/requested/after values.

Preconditions:
- Valid BGG credentials.
- Internet access to boardgamegeek.com.
- Game is present in your BGG collection.

Postconditions:
- A personal rating update is submitted to BGG.

Idempotency:
- Idempotent for the same target value.

Failure Modes:
- Login failure, HTTP non-200 response, or game missing from collection.

Examples:
```powershell
$cred = Get-Credential -UserName "YOUR_BGG_USERNAME" -Message "Enter BGG credentials"
./.agents/skills/mrhinsh-bg-push-rating/scripts/Set-BggPersonalRating.ps1 -Credential $cred -GameId 167355 -Rating 8.999
```
