---
name: mrhinsh-bg-push
description: Push pending personal rating updates from the local publish queue to BoardGameGeek. Write-side of the pipeline; needs a valid BGG cookie cache. Always offer a -WhatIf dry-run first.
---

Dry-run first and show the user what would be pushed, then run live only after they confirm:

```powershell
./.agents/skills/mrhinsh-bg-push/scripts/run.ps1 -Username 'MrHinsh' -WhatIf
./.agents/skills/mrhinsh-bg-push/scripts/run.ps1 -Username 'MrHinsh'
```

Optional: `-QueuePath` (default `data/publish/queue/pending-rating-updates.json`), `-Limit N`
for partial syncs.

Auth failures: refresh the cookie cache per `.agents/context/ops-runbook.md`.
Full doc: `.agents/skills/mrhinsh-bg-push/SKILL.md`.
