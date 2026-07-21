---
name: mrhinsh-bg-import-ratings
description: Import operator-assigned ratings (1-10) from the edited CSV upload sheet back into the canonical dataset. Run after the user has filled new_rating in data/publish/sheets/bgg-rating-upload-sheet.csv.
---

```powershell
./.agents/skills/mrhinsh-bg-import-ratings/scripts/run.ps1
```

Afterwards rebuild derived artifacts (rank-set + publish-queue, or full `/mrhinsh-bg-pull`).
Full doc and the JSON-edit alternative: `.agents/skills/mrhinsh-bg-import-ratings/SKILL.md`.
