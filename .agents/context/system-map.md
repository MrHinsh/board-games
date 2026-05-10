# System Map

## Repository Layers
- Skill layer: `.agents/skills/` contains script wrappers and task entrypoints.
- Data layer: `data/` stores raw snapshots, canonical working data, reports, and publish artifacts.
- Tooling layer: `tools/bgg-mcp/` hosts MCP server implementation.

## Core Flow
1. Fetch:
- Uses MCP tools to collect played collection and details.
- Produces timestamped raw snapshot under `data/raw/bgg/collection/`.

2. Reconcile:
- Merges snapshot into canonical working dataset.
- Preserves manual rating edits where applicable.

3. Rank:
- Produces stackranked outputs and unrated intake artifacts.

4. Report/Publish:
- Generates top lists and upload sheets.
- Optional push scripts can write ratings/plays back to BGG.

## Auth Separation
- MCP read operations: no cookie passed via query by repo policy.
- Direct BGG write scripts: use cookie from `.local/secrets/bgg-session.json`.

## Important Paths
- Login helper: `Login-Bgg.ps1`
- Cookie cache: `.local/secrets/bgg-session.json`
- Canonical games: `data/working/canonical/games.json`
- Ranked output: `data/reports/ranking/stackranked.json`
