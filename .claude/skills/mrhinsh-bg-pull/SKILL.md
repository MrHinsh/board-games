---
name: mrhinsh-bg-pull
description: Pull BGG collection data and reconcile into the canonical dataset. Rebuild is a separate cross-system workflow. Requires the local bgg-mcp server running. Use for "refresh my board game data" or as the read-side step before rating/tier work.
---

Run the orchestrator and report its summary object. Do not step through sub-skills manually
unless a step fails.

```powershell
./.agents/skills/mrhinsh-bg-pull/scripts/run.ps1 -Username 'MrHinsh' -ApiKey $env:BGG_API_KEY
```

If the MCP server is not running, start it first:
`./.agents/skills/mrhinsh-bg-pull-fetch/scripts/Start-BggMcpServer.ps1`

For a complete refresh, use `./workflows/Refresh-BoardGames.ps1 -Username MrHinsh`. For local rebuilding use `./workflows/Rebuild-BoardGames.ps1`. Pull stops on a fetch or reconcile failure.
Never read `data/**` JSON/CSV wholesale into context — query with scripts or filters.
