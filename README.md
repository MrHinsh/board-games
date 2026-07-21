# Board Games — BGG Collection Pipeline

Personal pipeline for managing the [BoardGameGeek](https://boardgamegeek.com) collection of
`MrHinsh`: pull plays and collection data into a local canonical dataset, rate and tier-rank
games, and push the resulting ratings back to BGG.

Everything deterministic is a PowerShell script under `.agents/skills/`. The repo is designed
to be operated by AI agents (start at [AGENTS.md](AGENTS.md)) or by hand using the commands
below. Full operational detail lives in
[.agents/context/ops-runbook.md](.agents/context/ops-runbook.md).

## One-time setup

1. **Build the MCP server** (Go required; source is vendored, see
   [tools/bgg-mcp/VENDORED.md](tools/bgg-mcp/VENDORED.md)):

   ```powershell
   cd tools/bgg-mcp
   go build -o bgg-mcp.exe .
   ```

2. **Enable the pre-commit smoke check** (once per clone):

   ```powershell
   git config core.hooksPath .githooks
   ```

3. **Authenticate to BGG** (cookie cache in gitignored `.local/`):

   ```powershell
   ./Login-Bgg.ps1
   ```

   If Cloudflare blocks scripted login (HTTP 403), import a browser cookie:

   ```powershell
   $cookie = Read-Host "Paste full Cookie header"
   ./Login-Bgg.ps1 -Username MrHinsh -Cookie $cookie -PersistScope User -Force
   ```

## Everyday use

Two commands are the operator surface:

```powershell
# Pull: fetch from BGG, reconcile into canonical data, rebuild rankings/reports/publish artifacts
./.agents/skills/mrhinsh-bg-pull/scripts/run.ps1 -Username 'MrHinsh' -ApiKey $env:BGG_API_KEY

# Push: sync the pending rating queue to BGG (dry-run first with -WhatIf)
./.agents/skills/mrhinsh-bg-push/scripts/run.ps1 -Username 'MrHinsh' -WhatIf
./.agents/skills/mrhinsh-bg-push/scripts/run.ps1 -Username 'MrHinsh'
```

The pull command requires the MCP server running at `http://localhost:8080/mcp`.

Between pull and push sit the human loops — rating new games via the CSV sheet, and
tier/rank adjustments. Step-by-step sequences for both are in the
[ops runbook](.agents/context/ops-runbook.md).

## Where things live

| Path | Contents |
| --- | --- |
| `.agents/skills/` | Skill scripts and per-skill docs (`SKILL.md`) |
| `.agents/context/` | Runbook, data contracts, rating/tier specs, system map |
| `.agents/guardrails/` | Non-negotiable agent policy |
| `.claude/skills/` | Claude Code slash-command entrypoints (thin shims) |
| `data/raw/` | Immutable BGG snapshots |
| `data/working/` | Canonical dataset and intermediates (`canonical/games.json` is the heart) |
| `data/reports/` | Generated ranking/top/quality reports |
| `data/publish/` | Upload sheets, tier exports, pending-update queues |
| `tools/bgg-mcp/` | Vendored BGG MCP server (Go) |
| `.local/` | Secrets and cookie cache — gitignored, never commit |

## Verify and inspect

```powershell
./scripts/Test-Repo.ps1      # parse all scripts + validate canonical data contract (also runs pre-commit)
./scripts/Get-BgStatus.ps1   # compact pipeline status: counts, queue, anomalies, freshness
```

Safety nets: every script that mutates canonical data first snapshots it to
`data/state/checkpoints/` (local, last 20 kept) via `scripts/Checkpoint-Canonical.ps1`, and
the push sync refuses out-of-range ratings, X/U-tier entries, and rating jumps larger than
2 points unless re-run with `-AllowLargeDelta`.
