# mrhinsh-bg-tier-map

Purpose:
- Build first-class tier membership from canonical game ratings.
- Export a tier-engine-friendly file for external tier tools.

Inputs:
- data/working/canonical/games.json
- optional existing data/working/ranking/tier-membership.json

Outputs:
- data/working/ranking/tier-membership.json
- data/working/ranking/tiers.json
- data/publish/tiers/tier-engine-export.json
- data/publish/tiers/tier-engine-export.csv

Example:
```powershell
./.agents/skills/mrhinsh-bg-tier-map/scripts/run.ps1
```
