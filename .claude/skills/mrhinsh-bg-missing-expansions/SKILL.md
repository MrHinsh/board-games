---
name: mrhinsh-bg-missing-expansions
description: For each owned base game, list expansions on BGG that are not owned. Read-only against BGG; writes a local report and caches per-game XML details.
---

```powershell
./.agents/skills/mrhinsh-bg-missing-expansions/scripts/run.ps1 `
    -Username 'MrHinsh' -ApiKey $env:BGG_API_KEY
```

Report is written to `data/reports/expansions/` (JSON, CSV, and summary.md).
Summarize the top games by missing-expansion count for the user instead of
pasting the file. Fan expansions are excluded by default — pass
`-IncludeFanExpansions` to include them.

Full doc: `.agents/skills/mrhinsh-bg-missing-expansions/SKILL.md`.
