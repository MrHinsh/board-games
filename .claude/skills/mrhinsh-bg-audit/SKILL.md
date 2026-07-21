---
name: mrhinsh-bg-audit
description: Audit the live BGG owned collection for duplicate rows sharing a bgg_id and flag diverged ratings between copies. Read-only against BGG; writes a local quality report.
---

```powershell
./.agents/skills/mrhinsh-bg-audit/scripts/run.ps1 -Username 'MrHinsh'
```

Report is written to `data/reports/quality/duplicate-collection-report.json` — summarize the
duplicate groups for the user instead of pasting the file.
Full doc: `.agents/skills/mrhinsh-bg-audit/SKILL.md`.
