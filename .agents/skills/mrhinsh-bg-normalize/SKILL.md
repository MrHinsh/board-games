# mrhinsh-bg-normalize

Purpose:
- Export tier/ranking files for external tools.
- Normalize external imports into internal queue/order files.

Inputs:
- data/working/ranking/tier-membership.json
- optional data/publish/tiers/tier-engine-import.csv
- optional data/publish/ranking/import/*.csv or *.json

Outputs:
- data/publish/tiers/tier-engine-export.csv
- data/publish/ranking/tier-*-ranking.csv
- data/publish/queue/pending-tier-moves.json
- data/working/ranking/external-ordering.json

Example:
```powershell
./.agents/skills/mrhinsh-bg-normalize/scripts/run.ps1
```
