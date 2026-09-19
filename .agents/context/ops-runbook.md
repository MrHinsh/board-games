# Ops Runbook

## Preflight Checks
1. For reads: `BGG_API_KEY` is set (Machine or Process scope). No cookie needed.
2. For writes only: cookie cache at `.local/secrets/bgg-session.json` is still valid
   (see Refresh Auth Cache — it expires and `Login-Bgg.ps1` silently falls through when it has).
3. Canonical file exists at `data/working/canonical/games.json`.
4. MCP server is running at `http://localhost:8080/mcp` before any pull (see Start The MCP Server).
5. After editing any PowerShell script, run `./scripts/Test-Repo.ps1`.

## Auth Paths

Two independent credentials. They are not interchangeable.

| Credential | Covers | Obtain | Status |
| --- | --- | --- | --- |
| `BGG_API_KEY` | All reads (MCP server, `bgg-details`, `bgg-collection`, ...) | <https://boardgamegeek.com/applications> | Preferred. Does not expire on a fixed clock. |
| Session cookie | Writes only (rating/play push) | Browser cookie import | Expires; re-import by hand. |
| Password login | — | `Login-Bgg.ps1 -Force` | **Broken.** Cloudflare 403. |

The BGG XML API (`boardgamegeek.com/xmlapi2/...`) returns **HTTP 401 unauthenticated**. Reads must
go through the MCP server (which applies `BGG_API_KEY`), not via direct `Invoke-WebRequest`.

## Start The MCP Server

Docker is **not** used on this machine. `Start-BggMcpServer.ps1` is Docker-only and will fail with
`failed to connect to the docker API at npipe:...`. Use the native binary instead:

`./tools/bgg-mcp/bgg-mcp.exe -mode http -port 8080`

It inherits `BGG_API_KEY` and `BGG_USERNAME` from the environment, so the key never has to be
passed on the command line or in a header. Stop it with
`Get-Process bgg-mcp | Stop-Process -Force`.

Ad-hoc read example (JSON-RPC; `initialize` first, then `tools/call`):
use `.agents/skills/mrhinsh-bg-shared/scripts/Invoke-BggMcp.ps1` -> `Invoke-BggMcpTool`
rather than hand-rolling the handshake. Useful tools: `bgg-details` (accepts `ids`, max 20),
`bgg-search`, `bgg-collection`, `bgg-recommender`.

## Refresh Auth Cache

Only needed for the write side.

1. `./Login-Bgg.ps1` reuses the cached session if it still validates against
   `www.boardgamegeek.com/api/preferences`. If it does not, it falls through to a password
   prompt — which then fails (see below).
2. Password login (`-Force`) is blocked by Cloudflare (HTTP 403). Do not rely on it.
3. Import a browser cookie instead:
   - Log in to boardgamegeek.com in a browser.
   - DevTools -> Network -> any `boardgamegeek.com` request -> copy the full `Cookie` request header.
   - `./Login-Bgg.ps1 -Username 'MrHinsh' -Cookie '<full cookie header>'`
4. `Login-Bgg.ps1` persists `BGG_COOKIE` at **User** scope. A shell started before that write will
   not see it — start a new shell, or read the cookie from the session file.

## Verify Auth Variables
- User scope cookie:
  ` [System.Environment]::GetEnvironmentVariable('BGG_COOKIE','User') `
- User scope username:
  ` [System.Environment]::GetEnvironmentVariable('BGG_USERNAME','User') `

## Main Commands
- Pull and rebuild through the Refresh workflow:
  `./workflows/Refresh-BoardGames.ps1 -Username 'mrhinsh' -Endpoint 'http://localhost:8080/mcp' -ApiKey $env:BGG_API_KEY`
- Push pending ratings to BGG:
  `./.agents/skills/mrhinsh-bg-push/scripts/run.ps1 -Username 'mrhinsh'`

## Fetch + Reconcile (under pull)
Pull now wraps fetch and reconcile only. Refresh composes Pull and the separate local Rebuild workflow.

Equivalent lower-level example:
`$snapshot = ./.agents/skills/mrhinsh-bg-pull-fetch/scripts/run.ps1 -Username 'mrhinsh' -Endpoint 'http://localhost:8080/mcp' -ApiKey $env:BGG_API_KEY`
`./.agents/skills/mrhinsh-bg-pull-reconcile/scripts/run.ps1 -SnapshotPath $snapshot`

## Rank + Report
- Rank set:
  `./.agents/skills/mrhinsh-bg-pull-rank-set/scripts/run.ps1`
- Top report:
  `./.agents/skills/mrhinsh-bg-pull-report/scripts/run.ps1`

## Rating Intake Loop (human-in-the-loop)

Run after a pull when unrated games need scoring:

1. Rebuild stack rank and unrated intake:
  `./.agents/skills/mrhinsh-bg-pull-rank-set/scripts/Export-BggStackRank.ps1`
2. Rebuild the rating sheet:
  `./.agents/skills/mrhinsh-bg-pull-publish-queue/scripts/New-BggRatingUploadSheet.ps1`
3. Edit `data/publish/sheets/bgg-rating-upload-sheet.csv`:
  fill `new_rating` with integers 1-10; use `notes` for local review notes
  (`bgg_comment` is the fetched BGG comment when present).
4. Import the edited sheet:
  `./.agents/skills/mrhinsh-bg-import-ratings/scripts/Import-BggRatingSheet.ps1`
  (or `Import-BggRatingsFromUnrated.ps1` if you edited `intake-ranked.json` directly).
5. Rebuild outputs: re-run steps 1-2, then the top report:
  `./.agents/skills/mrhinsh-bg-pull-report/scripts/run.ps1 -Username 'mrhinsh'`

## Tier Workflow
1. Build tier membership from canonical ratings:
  `./.agents/skills/mrhinsh-bg-pull-tier-map/scripts/run.ps1`
2. Export files for external tier/ranking tools and normalize any imports:
  `./.agents/skills/mrhinsh-bg-pull-normalize/scripts/run.ps1`
3. Apply imported/manual tier moves:
  `./.agents/skills/mrhinsh-bg-pull-tier-move/scripts/run.ps1`
4. Rebalance rank-in-tier into decimal ratings and publish queue:
  `./.agents/skills/mrhinsh-bg-pull-rank-rebalance/scripts/run.ps1`
5. Dry-run BGG sync:
  `./.agents/skills/mrhinsh-bg-push-rating/scripts/Sync-BggRatingQueue.ps1 -WhatIf`
6. Live BGG sync:
  `./.agents/skills/mrhinsh-bg-push-rating/scripts/Sync-BggRatingQueue.ps1`

These lower-level steps remain available, but the preferred operator surface is now
`mrhinsh-bg-pull` and `mrhinsh-bg-push`.

## Recovering Canonical Data
Every mutating script (reconcile, imports, rebalance) writes a checkpoint of
`games.json`, `equivalent-games.json`, and `intake-ranked.json` to
`data/state/checkpoints/<timestamp>-<reason>/` first (last 20 kept, gitignored). Retention handles a fresh directory with a single checkpoint under strict PowerShell mode.
To recover from a bad mutation, copy the files back from the newest good checkpoint,
or use `git restore` if the last good state was committed.

## Common Failures
- HTTP 403 during password login:
  Cloudflare challenge. Password login is permanently broken — use browser cookie import.
- HTTP 401 from `boardgamegeek.com/xmlapi2/...`:
  Direct XML API calls are unauthenticated. Go through the MCP server, which applies `BGG_API_KEY`.
- `Login-Bgg.ps1` prompts for a password in a non-interactive shell:
  The cached cookie has expired and it fell through to the interactive path. Re-import a browser
  cookie; the fall-through is not an error message, so check the cookie age first.
- `failed to connect to the docker API at npipe:...`:
  `Start-BggMcpServer.ps1` is Docker-only. Run `./tools/bgg-mcp/bgg-mcp.exe -mode http -port 8080`.
- Empty/unauthorized collection results:
  Validate MCP auth configuration and username.
- Environment variable updated but process still fails:
  Restart the long-lived process. `Login-Bgg.ps1` writes `BGG_COOKIE` at User scope, which existing
  shells do not inherit.

## System boundaries

Pull: `./systems/bgg-integration/pull/run.ps1 -Username MrHinsh`.
Local rebuild: `./workflows/Rebuild-BoardGames.ps1`.
See `system-map.md` for current boundaries and remaining state-ownership work.
