# mrhinsh-bg-tier-move

Purpose:
- Apply tier moves imported from external tier tools or direct operator commands.

Inputs:
- data/working/ranking/tier-membership.json
- optional data/publish/queue/pending-tier-moves.json
- optional import CSV/JSON with bgg_id, tier, source_bucket

Outputs:
- updated data/working/ranking/tier-membership.json
- cleared queue file after processing when queue mode is used

Examples:
```powershell
./.agents/skills/mrhinsh-bg-tier-move/scripts/run.ps1
./.agents/skills/mrhinsh-bg-tier-move/scripts/run.ps1 -GameId 12345 -Tier A
```
