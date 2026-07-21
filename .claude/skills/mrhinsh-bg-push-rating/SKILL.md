---
name: mrhinsh-bg-push-rating
description: Set the personal rating for one game directly on BoardGameGeek. Direct authenticated write — confirm game and rating with the user before running. For bulk queue sync use mrhinsh-bg-push instead.
---

Confirm game and rating with the user, then:

```powershell
./.agents/skills/mrhinsh-bg-push-rating/scripts/run.ps1 -Username 'MrHinsh' -GameId <id> -Rating <1-10>
```

Full doc: `.agents/skills/mrhinsh-bg-push-rating/SKILL.md`.
