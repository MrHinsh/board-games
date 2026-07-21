---
name: mrhinsh-bg-push-play
description: Log a single board game play to BoardGameGeek (game id, date, quantity, length). Direct authenticated write to BGG — confirm details with the user before running.
---

Confirm game, date, and details with the user, then:

```powershell
./.agents/skills/mrhinsh-bg-push-play/scripts/run.ps1 -GameId <id> -PlayDate 'YYYY-MM-DD' -Quantity 1 -LengthMinutes <min>
```

Full doc: `.agents/skills/mrhinsh-bg-push-play/SKILL.md`.
