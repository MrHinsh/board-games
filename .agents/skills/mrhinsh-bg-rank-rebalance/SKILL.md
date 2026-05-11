# mrhinsh-bg-rank-rebalance

Purpose:
- Convert tier membership and rank-in-tier into final decimal BGG ratings.
- Update canonical data and generate pending rating updates queue.

Inputs:
- data/working/ranking/tier-membership.json
- optional data/working/ranking/external-ordering.json

Outputs:
- data/working/ranking/rank-order.json
- data/publish/queue/pending-rating-updates.json
- updated data/working/canonical/games.json

Examples:
```powershell
./.agents/skills/mrhinsh-bg-rank-rebalance/scripts/run.ps1
./.agents/skills/mrhinsh-bg-rank-rebalance/scripts/run.ps1 -ImportPath .\data\working\ranking\external-ordering.json
```
