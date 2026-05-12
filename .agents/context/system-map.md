# System Map

## Repository Layers

- Skill layer: `.agents/skills/` contains script wrappers and task entrypoints.
- Data layer: `data/` stores raw snapshots, canonical working data, reports, and publish artifacts.
- Tooling layer: `tools/bgg-mcp/` hosts MCP server implementation.

## Primary Operator Surface

- `mrhinsh-bg-pull` is the main read-side orchestration entrypoint.
- `mrhinsh-bg-push` is the main write-side orchestration entrypoint.
- Existing lower-level skills remain available behind those surfaces.

## Core Flow

1. Fetch.

- Uses MCP tools to collect played collection and details.
- Produces timestamped raw snapshot under `data/raw/bgg/collection/`.

1. Reconcile.

- Merges snapshot into canonical working dataset.
- Preserves manual rating edits where applicable.

1. Rank.

- Produces stackranked outputs and unrated intake artifacts.

1. Report and publish prep.

- Generates top lists and upload sheets.
- Optional push scripts can write ratings and plays back to BGG.

1. Tier workflow.

- Maps canonical ratings into tier membership and tier exports.
- Normalizes external tier and ranking engine imports.
- Rebalances rank-in-tier into final decimal BGG ratings.
- Queues final rating updates for optional bulk sync to BGG.

## Auth Separation

- MCP read operations: no cookie passed via query by repo policy.
- Direct BGG write scripts: use cookie from `.local/secrets/bgg-session.json`.

## Important Paths

- Login helper: `Login-Bgg.ps1`
- Cookie cache: `.local/secrets/bgg-session.json`
- Canonical games: `data/working/canonical/games.json`
- Ranked output: `data/reports/ranking/stackranked.json`
- Tier membership: `data/working/ranking/tier-membership.json`
- Tier summaries: `data/working/ranking/tiers.json`
- Rank order: `data/working/ranking/rank-order.json`
- Pending rating queue: `data/publish/queue/pending-rating-updates.json`
