# mrhinsh-bg-pull

Read-side orchestration: pull from BGG, reconcile into canonical data, rebuild all local
ranking, report, and publish artifacts. The entire sequence is implemented in `scripts/run.ps1`
— run it; do not step through the sub-skills manually unless recovering from a failure.

## Run

```powershell
./.agents/skills/mrhinsh-bg-pull/scripts/run.ps1 `
    -Username 'MrHinsh' `
    -Endpoint 'http://localhost:8080/mcp' `
    -ApiKey $env:BGG_API_KEY
```

Optional: `-Cookie` (auth override), `-IncludeExpansions`.

## Preconditions

- MCP server running at `$Endpoint`
  (`./.agents/skills/mrhinsh-bg-pull-fetch/scripts/Start-BggMcpServer.ps1`).

## Outputs

- Raw immutable snapshot: `data/raw/bgg/collection/<timestamp>.json`
- Canonical data: `data/working/canonical/games.json`, `data/working/unrated/intake.json`
- Reports: `data/reports/quality/`, `data/reports/ranking/`, `data/reports/top/`
- Publish artifacts: `data/publish/sheets/`, `data/publish/ranking/`, `data/publish/tiers/`
- Pending rating queue: `data/publish/queue/pending-rating-updates.json`

## Idempotency

Safe to re-run. Each run writes a new immutable snapshot and rebuilds derived artifacts.

## Failure recovery

`run.ps1` executes these sub-skills in order and stops at the first failure, leaving earlier
outputs in place. To resume, run the failed step's `run.ps1` (each has its own `SKILL.md`),
then continue down the list:

1. `mrhinsh-bg-pull-fetch` (emits snapshot path; pass it to reconcile via `-SnapshotPath`)
2. `mrhinsh-bg-pull-reconcile`
3. `mrhinsh-bg-pull-rank-set`
4. `mrhinsh-bg-pull-publish-queue`
5. `mrhinsh-bg-pull-report`
6. `mrhinsh-bg-pull-tier-map`
7. `mrhinsh-bg-pull-normalize`
8. `mrhinsh-bg-pull-tier-move`
9. `mrhinsh-bg-pull-rank-rebalance` (`-ImportPath .\data\working\ranking\external-ordering.json`)
