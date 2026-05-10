# mrhinsh-bg-fetch

Purpose:
- Call the BGG MCP server to retrieve the user's played collection.
- Enrich each entry with game details (complexity, players, categories, mechanics) in batches of 20.
- Deduplicate by bgg_id, keeping the entry with the highest play count.
- Map raw BGG field names to the canonical schema.
- Write an immutable timestamped JSON snapshot to `data/raw/bgg/collection/<timestamp>.json`.
- Emit the snapshot path to stdout for downstream skills (e.g. mrhinsh-bg-reconcile).

Inputs:
- BGG MCP server at `$Endpoint` (default `http://localhost:8080/mcp`)
- Environment / params: `$Username`, `$ApiKey`, `$Cookie`

Outputs:
- `data/raw/bgg/collection/<timestamp>.json` — immutable snapshot in canonical schema:
  `bgg_id`, `name`, `year_published`, `rating`, `num_plays`, `players`, `complexity`,
  `bgg_rating`, `num_ratings`, `categories`, `mechanics`
- Stdout: absolute path to the written snapshot file

Preconditions:
- BGG MCP server is running and reachable at `$Endpoint`.

Postconditions:
- A new timestamped snapshot exists. No existing files are modified.

Idempotency:
- Safe to re-run. Each call writes a new timestamped snapshot; nothing is overwritten.

Failure Modes:
- MCP unreachable: throws before writing any file.
- No games returned: throws with a descriptive message.
- Partial detail failure: games without details are saved with null metadata fields.

Example:
```powershell
$snapshot = & ./.agents/skills/mrhinsh-bg-fetch/scripts/run.ps1 -Username "MrHinsh"
Write-Host "Snapshot saved to: $snapshot"
```
