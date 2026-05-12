# Ops Runbook

## Refresh Auth Cache
1. Run `./Login-Bgg.ps1`.
2. If blocked by Cloudflare 403, import browser cookie using `-Cookie`.

## Verify Auth Variables
- User scope cookie:
  ` [System.Environment]::GetEnvironmentVariable('BGG_COOKIE','User') `
- User scope username:
  ` [System.Environment]::GetEnvironmentVariable('BGG_USERNAME','User') `

## Main Commands
- Pull local state and rebuild artifacts:
  `./.agents/skills/mrhinsh-bg-pull/scripts/run.ps1 -Username 'mrhinsh' -Endpoint 'http://localhost:8080/mcp' -ApiKey $env:BGG_API_KEY`
- Push pending ratings to BGG:
  `./.agents/skills/mrhinsh-bg-push/scripts/run.ps1 -Username 'mrhinsh'`

## Fetch + Reconcile (under pull)
The pull command wraps the existing fetch and reconcile pattern before continuing into rank,
report, and publish rebuild steps.

Equivalent lower-level example:
`$snapshot = ./.agents/skills/mrhinsh-bg-fetch/scripts/run.ps1 -Username 'mrhinsh' -Endpoint 'http://localhost:8080/mcp' -ApiKey $env:BGG_API_KEY`
`./.agents/skills/mrhinsh-bg-reconcile/scripts/run.ps1 -SnapshotPath $snapshot`

## Rank + Report
- Rank set:
  `./.agents/skills/mrhinsh-bg-rank-set/scripts/run.ps1`
- Top report:
  `./.agents/skills/mrhinsh-bg-report/scripts/run.ps1`

## Tier Workflow
1. Build tier membership from canonical ratings:
  `./.agents/skills/mrhinsh-bg-tier-map/scripts/run.ps1`
2. Export files for external tier/ranking tools and normalize any imports:
  `./.agents/skills/mrhinsh-bg-normalize/scripts/run.ps1`
3. Apply imported/manual tier moves:
  `./.agents/skills/mrhinsh-bg-tier-move/scripts/run.ps1`
4. Rebalance rank-in-tier into decimal ratings and publish queue:
  `./.agents/skills/mrhinsh-bg-rank-rebalance/scripts/run.ps1`
5. Dry-run BGG sync:
  `./.agents/skills/mrhinsh-bg-push-rating/scripts/Sync-BggRatingQueue.ps1 -WhatIf`
6. Live BGG sync:
  `./.agents/skills/mrhinsh-bg-push-rating/scripts/Sync-BggRatingQueue.ps1`

These lower-level steps remain available, but the preferred operator surface is now
`mrhinsh-bg-pull` and `mrhinsh-bg-push`.

## Common Failures
- HTTP 403 during password login:
  Cloudflare challenge. Use browser cookie import.
- Empty/unauthorized collection results:
  Validate MCP auth configuration and username.
- Environment variable updated but process still fails:
  Restart the long-lived process.
