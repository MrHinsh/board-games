# mrhinsh-bg-pull

This is an orchestration workflow. It has no scripts of its own beyond the wrapper entrypoint.
Invoke the existing implemented skills below in sequence and pass outputs between them.

---

## Workflow: Pull from BGG and rebuild local publish artifacts

### Step 1 - Fetch
Run the existing fetch entrypoint and capture the emitted snapshot path.

```powershell
$snapshot = & ./.agents/skills/mrhinsh-bg-fetch/scripts/run.ps1 `
    -Username $Username `
    -Endpoint $Endpoint `
    -ApiKey $ApiKey `
    -Cookie $Cookie `
    -IncludeExpansions:$IncludeExpansions
```

### Step 2 - Reconcile
Merge the fetched snapshot into canonical working data.

```powershell
& ./.agents/skills/mrhinsh-bg-reconcile/scripts/run.ps1 `
    -SnapshotPath $snapshot
```

### Step 3 - Rank and rating intake artifacts
Refresh ranking outputs and rebuild the operator upload sheet.

```powershell
& ./.agents/skills/mrhinsh-bg-rank-set/scripts/run.ps1
& ./.agents/skills/mrhinsh-bg-publish-queue/scripts/run.ps1
```

### Step 4 - Reports
Refresh top reports from the reconciled dataset.

```powershell
& ./.agents/skills/mrhinsh-bg-report/scripts/run.ps1 `
    -Username $Username `
    -Endpoint $Endpoint `
    -ApiKey $ApiKey `
    -Cookie $Cookie `
    -IncludeExpansions:$IncludeExpansions
```

### Step 5 - Tier and publish outputs
Rebuild tier membership, normalize external ordering, apply any queued tier moves, and recalculate
final decimal BGG ratings.

```powershell
& ./.agents/skills/mrhinsh-bg-tier-map/scripts/run.ps1
& ./.agents/skills/mrhinsh-bg-normalize/scripts/run.ps1
& ./.agents/skills/mrhinsh-bg-tier-move/scripts/run.ps1
& ./.agents/skills/mrhinsh-bg-rank-rebalance/scripts/run.ps1 `
    -ImportPath .\data\working\ranking\external-ordering.json
```

---

## Inputs
- `$Username` - BGG username (mandatory)
- `$Endpoint` - BGG MCP endpoint (default `http://localhost:8080/mcp`)
- `$ApiKey`, `$Cookie` - optional auth material for MCP reads
- `$IncludeExpansions` - include expansions in BGG reads and reports when set

## Outputs
- Raw BGG snapshot under `data/raw/bgg/collection/`
- Reconciled canonical data under `data/working/canonical/`
- Ranking reports under `data/reports/ranking/` and `data/reports/top/`
- Publish artifacts under `data/publish/`
- Pending BGG rating queue at `data/publish/queue/pending-rating-updates.json`

## Preconditions
- MCP server is running before fetch starts
- Existing canonical and publish directories are present

## Idempotency
- Safe to re-run. Each run writes a new immutable raw snapshot and rebuilds derived local artifacts.

## Failure Modes
- Fetch failure stops the workflow before reconcile
- Reconcile failure stops downstream rank/report/tier steps
- Any downstream script failure leaves previously generated artifacts in place from the last successful run