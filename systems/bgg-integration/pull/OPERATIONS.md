# mrhinsh-bg-pull

BGG Integration Pull: fetch an immutable BGG snapshot, then reconcile local data.

```powershell
./.agents/skills/mrhinsh-bg-pull/scripts/run.ps1 -Username MrHinsh -ApiKey $env:BGG_API_KEY
```

Optional parameters: Endpoint, ApiKey, Cookie, IncludeExpansions. Requires the
local MCP server; see `.agents/context/ops-runbook.md`.

Implementation: `systems/bgg-integration/pull/run.ps1`.
Outputs: snapshot path and reconciliation result. Pull no longer runs ranking,
tier rebalance or upload preparation. This is the agreed Pull/Rebuild split.

For the previous end-to-end refresh, run
`./workflows/Refresh-BoardGames.ps1 -Username MrHinsh -ApiKey $env:BGG_API_KEY`.
For local rebuild only, run `./workflows/Rebuild-BoardGames.ps1`.
Publishing remains separately invoked through BGG Integration.
