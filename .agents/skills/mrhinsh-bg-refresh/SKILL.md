# mrhinsh-bg-refresh

Purpose:
- Pull a fresh collection snapshot from BGG.
- Merge it into the canonical working data without overwriting any locally-set ratings, tiers or ranks.
- Route genuinely new games (not in canonical) into the unrated intake.
- Update safe metadata fields (num_plays, bgg_rating, complexity, players, categories, mechanics) on existing games.
- Produce a reconciliation report showing what changed.

Inputs:
- BGG API / MCP endpoint (live fetch)
- `data/working/canonical/games.json`   — master record of all played games
- `data/working/unrated/intake.json`    — games awaiting a local rating
- `data/raw/bgg/collection/<timestamp>.json` — written by this skill as the raw snapshot

Outputs:
- `data/raw/bgg/collection/<timestamp>.json`  — immutable raw snapshot
- `data/working/canonical/games.json`          — updated (metadata only, ratings preserved)
- `data/working/unrated/intake.json`           — new games appended
- `data/reports/quality/reconcile-report.json` — diff summary

Preconditions:
- MCP server running at $Endpoint
- `data/working/canonical/games.json` exists (run mrhinsh-bg-fetch first)

Postconditions:
- Canonical contains all games from the fresh pull
- No locally-set rating is lowered or cleared
- New games with no local rating appear in intake with current_rating = 0
- Reconcile report contains added/updated/unchanged counts

Idempotency:
- Safe to re-run. Each run writes a new timestamped raw snapshot.
- Merge is additive; nothing is deleted from canonical.

Failure Modes:
- MCP unreachable: script exits before writing any output files
- Malformed response: raw snapshot saved, merge skipped with error message

Example:
```powershell
./.agents/skills/mrhinsh-bg-refresh/scripts/Invoke-BggRefresh.ps1 -Username "MrHinsh"
```
