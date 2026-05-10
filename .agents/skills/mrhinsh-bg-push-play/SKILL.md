# mrhinsh-bg-push-play

Purpose:
- Push play entries to BoardGameGeek web endpoints.
- Focused skill for posting plays only.

Inputs:
- BGG username and password (via `PSCredential`).
- Game id and play-specific fields.

Outputs:
- JSON-like PowerShell object summarizing the posted play result.

Preconditions:
- Valid BGG credentials.
- Internet access to boardgamegeek.com.

Postconditions:
- A play update is submitted to BGG.

Idempotency:
- Not idempotent; repeated calls can create multiple plays.

Failure Modes:
- Login failure or HTTP non-200 response.

Examples:
```powershell
$cred = Get-Credential -UserName "YOUR_BGG_USERNAME" -Message "Enter BGG credentials"
./.agents/skills/mrhinsh-bg-push-play/scripts/Push-BggPlay.ps1 -Credential $cred -GameId 167355 -PlayDate 2026-05-10 -Quantity 1
```
