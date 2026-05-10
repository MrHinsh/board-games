# mrhinsh-bg-refresh

This is an **orchestration workflow**. It has no scripts of its own. Invoke the sub-skills
below in sequence and pass outputs between them.

---

## Workflow: Refresh canonical game data from BGG

### Step 1 — Fetch
Invoke **mrhinsh-bg-fetch**.

Read `.agents/skills/mrhinsh-bg-fetch/SKILL.md` and run its script:

```powershell
$snapshot = & ./.agents/skills/mrhinsh-bg-fetch/scripts/run.ps1 `
    -Username $Username `
    -Endpoint $Endpoint `
    -ApiKey $ApiKey `
    -Cookie $Cookie
```

The script emits the path to the saved snapshot file. Capture it in `$snapshot`.

### Step 2 — Reconcile
Invoke **mrhinsh-bg-reconcile**.

Read `.agents/skills/mrhinsh-bg-reconcile/SKILL.md` and run its script, passing the snapshot
path from Step 1:

```powershell
& ./.agents/skills/mrhinsh-bg-reconcile/scripts/run.ps1 `
    -SnapshotPath $snapshot
```

---

## Inputs
- BGG MCP server running at `$Endpoint` (default `http://localhost:8080/mcp`)
- `$Username` — BGG username (mandatory)
- `$ApiKey`, `$Cookie` — optional BGG auth tokens from environment variables

## Outputs
- `data/raw/bgg/collection/<timestamp>.json` — immutable raw snapshot (written by fetch)
- `data/working/canonical/games.json` — updated metadata, ratings preserved (written by reconcile)
- `data/working/unrated/intake.json` — new games appended (written by reconcile)
- `data/reports/quality/reconcile-report.json` — diff summary (written by reconcile)

## Preconditions
- MCP server is running (start it if needed before invoking mrhinsh-bg-fetch)

## Idempotency
- Safe to re-run. Each run writes a new timestamped snapshot; canonical merge is additive.

## Failure Modes
- MCP unreachable: fetch throws before writing any file; reconcile is not invoked.
- Empty collection returned: fetch throws; reconcile is not invoked.
- Missing snapshot path: reconcile throws before modifying canonical.
