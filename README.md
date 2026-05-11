# Board Games Operator Runbook

This repository is operated through skills in `.agents/skills` and data files in `data`.

Primary operator goals:

- Refresh canonical game data from BGG
- Rank and review unrated games
- Apply ratings back into canonical data
- Build a tiered final ranking
- Generate reports and optional publish payloads

## Repo Layout

- `.agents/skills`: skill entrypoints and scripts
- `.agents/guardrails`: hard policy rules for agents
- `.agents/context`: operator and system context
- `data/raw`: immutable BGG snapshots
- `data/working`: canonical and intermediate working files
- `data/reports`: generated reports
- `data/publish`: upload sheets and publish artifacts
- `.local/secrets`: local auth cache, gitignored

## Authentication Model

Password automation to BGG may be blocked by Cloudflare. Use `Login-Bgg.ps1` to maintain local cookie cache.

- Cache file: `.local/secrets/bgg-session.json`
- Persisted env vars: `BGG_COOKIE`, `BGG_USERNAME`

Run:

```powershell
./Login-Bgg.ps1
```

If login is blocked, import browser cookie:

```powershell
$cookie = Read-Host "Paste full Cookie header"
./Login-Bgg.ps1 -Username MrHinsh -Cookie $cookie -PersistScope User -Force
```

## Refresh Workflow

Use the refresh skill as orchestration.

In agent chat, invoke:

- `/mrhinsh-bg-refresh`

Skill doc:

- `.agents/skills/mrhinsh-bg-refresh/SKILL.md`

It runs two implemented skills in order:

1. Fetch snapshot.

```powershell
$snapshot = ./.agents/skills/mrhinsh-bg-fetch/scripts/run.ps1 `
  -Username "MrHinsh" `
  -Endpoint "http://localhost:8080/mcp" `
  -ApiKey $env:BGG_API_KEY
```

1. Reconcile into canonical.

```powershell
./.agents/skills/mrhinsh-bg-reconcile/scripts/run.ps1 -SnapshotPath $snapshot
```

Outputs after refresh:

- `data/raw/bgg/collection/[timestamp].json`
- `data/working/canonical/games.json`
- `data/working/unrated/intake.json`
- `data/reports/quality/reconcile-report.json`

## What To Do After Refresh

After refresh, run ranking and rating intake flow.

### Step 1: Build stack rank and unrated intake

```powershell
./.agents/skills/mrhinsh-bg-rank-set/scripts/Export-BggStackRank.ps1
```

Key outputs:

- `data/reports/ranking/stackranked.json`
- `data/reports/ranking/stackranked.csv`
- `data/working/unrated/intake.json`
- `data/working/unrated/intake-ranked.json`

### Step 2: Create rating sheet for human review

```powershell
./.agents/skills/mrhinsh-bg-publish-queue/scripts/New-BggRatingUploadSheet.ps1
```

Output:

- `data/publish/sheets/bgg-rating-upload-sheet.csv`

Fill column `new_rating` with integer values 1-10.

### Step 3: Import edited ratings

Option A, recommended CSV workflow:

```powershell
./.agents/skills/mrhinsh-bg-import-ratings/scripts/Import-BggRatingSheet.ps1
```

Option B, if you edited `intake-ranked.json` directly:

```powershell
./.agents/skills/mrhinsh-bg-import-ratings/scripts/Import-BggRatingsFromUnrated.ps1
```

This updates:

- `data/working/canonical/games.json`
- `data/working/unrated/intake-ranked.json`

### Step 4: Rebuild rank outputs and reports

Re-run stackrank:

```powershell
./.agents/skills/mrhinsh-bg-rank-set/scripts/Export-BggStackRank.ps1
```

Generate top report:

```powershell
./.agents/skills/mrhinsh-bg-report/scripts/Export-BggTop10.ps1 -Username "MrHinsh" -Top 10 -ApiKey $env:BGG_API_KEY
```

## Tier Workflow

This is the higher-order workflow that turns integer ratings into a tiered final ordering and prepares BGG sync.

### Step 1: Build tier membership from canonical ratings

```powershell
./.agents/skills/mrhinsh-bg-tier-map/scripts/run.ps1
```

Outputs:

- `data/working/ranking/tier-membership.json`
- `data/working/ranking/tiers.json`
- `data/publish/tiers/tier-engine-export.csv`

### Step 2: Export for external tier and ranking tools

```powershell
./.agents/skills/mrhinsh-bg-normalize/scripts/run.ps1
```

Outputs:

- `data/publish/tiers/tier-engine-export.csv`
- `data/publish/ranking/tier-*-ranking.csv`

Optional imports consumed by normalize:

- `data/publish/tiers/tier-engine-import.csv`
- `data/publish/ranking/import/*.csv`

Normalize writes:

- `data/publish/queue/pending-tier-moves.json`
- `data/working/ranking/external-ordering.json`

### Step 3: Apply tier moves from external tool or manual queue

```powershell
./.agents/skills/mrhinsh-bg-tier-move/scripts/run.ps1
```

Or move one game directly:

```powershell
./.agents/skills/mrhinsh-bg-tier-move/scripts/run.ps1 -GameId 12345 -Tier A
```

### Step 4: Rebalance rank-in-tier into final decimal ratings

```powershell
./.agents/skills/mrhinsh-bg-rank-rebalance/scripts/run.ps1
```

If you imported within-tier order from external ranking files:

```powershell
./.agents/skills/mrhinsh-bg-rank-rebalance/scripts/run.ps1 -ImportPath .\data\working\ranking\external-ordering.json
```

Outputs:

- `data/working/ranking/rank-order.json`
- `data/publish/queue/pending-rating-updates.json`
- updated `data/working/canonical/games.json`

### Step 5: Dry-run BGG sync

```powershell
./.agents/skills/mrhinsh-bg-push-rating/scripts/Sync-BggRatingQueue.ps1 -WhatIf
```

### Step 6: Live BGG sync

```powershell
./.agents/skills/mrhinsh-bg-push-rating/scripts/Sync-BggRatingQueue.ps1
```

## Rating System

### Tier mapping used in discussion

Rating intent: 10 highest preference, 6 acceptable, 1-5 low preference, 0 unrated.

- S tier: 10
- A tier: 9
- B tier: 8
- C tier: 7
- D tier: 6
- F tier: 1-5
- U tier: 0
- X tier: exit collection marker, excluded from rebalance

### Stack rank behavior

Within each integer rating bucket, the rank tool proposes decimal ordering in a lower band:

- 10 bucket maps to 9.000-9.999
- 9 bucket maps to 8.000-8.999
- lower buckets continue by the documented formula

This is used for ordering analysis and for final tier rebalance output.

## Optional: Push Writes To BGG

These scripts perform direct web writes and use cookie from `.local` cache.

Set a personal rating for one game:

```powershell
./.agents/skills/mrhinsh-bg-push-rating/scripts/run.ps1 -Username "MrHinsh" -GameId 12345 -Rating 8
```

Post a play:

```powershell
./.agents/skills/mrhinsh-bg-push-play/scripts/run.ps1 -GameId 12345 -PlayDate "2026-05-10" -Quantity 1 -LengthMinutes 90
```

## Current Skill Status Notes

Implemented and usable now:

- `mrhinsh-bg-refresh` (orchestration via SKILL.md)
- `mrhinsh-bg-fetch`
- `mrhinsh-bg-reconcile`
- `mrhinsh-bg-rank-set`
- `mrhinsh-bg-tier-map`
- `mrhinsh-bg-tier-move`
- `mrhinsh-bg-rank-rebalance`
- `mrhinsh-bg-normalize`
- `mrhinsh-bg-publish-queue`
- `mrhinsh-bg-import-ratings`
- `mrhinsh-bg-report`
- `mrhinsh-bg-push-rating`
- `mrhinsh-bg-push-play`

## Operator Quick Commands

End-to-end refresh and reconcile:

```powershell
$snapshot = ./.agents/skills/mrhinsh-bg-fetch/scripts/run.ps1 -Username "MrHinsh" -Endpoint "http://localhost:8080/mcp" -ApiKey $env:BGG_API_KEY
./.agents/skills/mrhinsh-bg-reconcile/scripts/run.ps1 -SnapshotPath $snapshot
```

Then run rating loop:

```powershell
./.agents/skills/mrhinsh-bg-rank-set/scripts/Export-BggStackRank.ps1
./.agents/skills/mrhinsh-bg-publish-queue/scripts/New-BggRatingUploadSheet.ps1
# edit data/publish/sheets/bgg-rating-upload-sheet.csv
./.agents/skills/mrhinsh-bg-import-ratings/scripts/Import-BggRatingSheet.ps1
./.agents/skills/mrhinsh-bg-rank-set/scripts/Export-BggStackRank.ps1
./.agents/skills/mrhinsh-bg-report/scripts/Export-BggTop10.ps1 -Username "MrHinsh" -ApiKey $env:BGG_API_KEY
```

Then run tier loop:

```powershell
./.agents/skills/mrhinsh-bg-tier-map/scripts/run.ps1
./.agents/skills/mrhinsh-bg-normalize/scripts/run.ps1
# optionally edit data/publish/tiers/tier-engine-import.csv or data/publish/ranking/import/*.csv
./.agents/skills/mrhinsh-bg-tier-move/scripts/run.ps1
./.agents/skills/mrhinsh-bg-rank-rebalance/scripts/run.ps1 -ImportPath .\data\working\ranking\external-ordering.json
./.agents/skills/mrhinsh-bg-push-rating/scripts/Sync-BggRatingQueue.ps1 -WhatIf
```
