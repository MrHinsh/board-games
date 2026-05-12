# Data Contracts

This file defines stable contracts for core working files. Agents should treat these as the source of truth for shape and field meaning.

## Canonical Games Contract

Path:

- `data/working/canonical/games.json`

Type:

- JSON array of game objects

Required fields per object:

- `group_key`: string
- `bgg_id`: integer
- `name`: string
- `year_published`: integer
- `rating`: number
- `num_plays`: integer

Optional metadata fields:

- `players`: string or null
- `complexity`: number or null
- `bgg_rating`: number or null
- `num_ratings`: integer or null
- `collection`: boolean or null
- `previously_owned`: boolean or null
- `want_to_play`: boolean or null
- `want_to_buy`: boolean or null
- `collection_to_exit`: boolean or null
- `collection_status`: string in `{Owned,NotOwned,OwnedToExit}` or empty when unknown
- `categories`: string array
- `mechanics`: string array

Rules:

- `bgg_id` is the identity key.
- `rating` uses personal scale where 0 means unrated.
- `num_plays` must be non-negative.
- `collection_to_exit` is sourced from BGG `fortrade` status.
- Collection status fields remain blank until a successful authenticated fetch/reconcile backfill populates them.
- `categories` and `mechanics` default to empty arrays.

## Equivalent Games Contract

Path:

- `data/working/canonical/equivalent-games.json`

Type:

- JSON array of equivalence-group objects

Required fields per object:

- `primary_bgg_id`: integer
- `linked_bgg_ids`: integer array

Optional fields:

- `notes`: string

Rules:

- `primary_bgg_id` is the single ranking/export identity for the group.
- `linked_bgg_ids` are additional BGG ids that should mirror the primary game's rating updates.
- Tier mapping collapses each equivalence group to one ranking row using `primary_bgg_id`.
- Rank rebalance expands queued/persisted rating changes back to every id in the equivalence group.

## Unrated Intake Contract

Path:

- `data/working/unrated/intake.json`
- `data/working/unrated/intake-ranked.json`

Type:

- JSON array of intake objects

Required fields:

- `group_key`: string
- `bgg_id`: integer
- `name`: string
- `current_rating`: number
- `num_plays`: integer

Optional fields:

- `players`: string or null
- `complexity`: number or null
- `bgg_rating`: number or null
- `categories`: string array
- `mechanics`: string array

Rules:

- `current_rating` is 0 when awaiting operator input.
- `intake-ranked.json` must be sorted by `num_plays` descending, then `name` ascending.

## Stackrank Output Contract

Path:

- `data/reports/ranking/stackranked.json`

Type:

- JSON array of ranked objects

Required fields:

- `group_key`: string
- `stack_rank`: integer, 1-based in each source bucket
- `group_count`: integer
- `source_rating_bucket`: integer
- `target_rating_band`: string
- `bgg_id`: integer
- `name`: string
- `current_rating`: number
- `proposed_rating`: number
- `num_plays`: integer

Optional fields:

- `players`: string or null
- `complexity`: number or null
- `bgg_rating`: number or null
- `categories`: string array
- `mechanics`: string array

Rules:

- `proposed_rating` is analytical ordering output.
- `current_rating` remains the operator source of truth until tier rebalance updates canonical.

## Tier Membership Contract

Path:

- `data/working/ranking/tier-membership.json`

Type:

- JSON array of tier membership objects

Required fields:

- `tier`: string in `{S,A,B,C,D,F,U,X}`
- `tier_sort`: integer
- `source_bucket`: integer
- `bgg_id`: integer
- `name`: string
- `current_rating`: number
- `num_plays`: integer
- `group_key`: string

Optional fields:

- `rank_in_tier`: integer or null
- `proposed_rating`: number or null
- `collection`: boolean or null
- `previously_owned`: boolean or null
- `want_to_play`: boolean or null
- `want_to_buy`: boolean or null
- `collection_to_exit`: boolean or null
- `collection_status`: string in `{Owned,NotOwned,OwnedToExit}` or empty when unknown
- `players`: string or null
- `complexity`: number or null
- `bgg_rating`: number or null
- `num_ratings`: integer or null
- `categories`: string array
- `mechanics`: string array
- `bgg_game_url`: string
- `linked_bgg_ids`: integer array

Rules:

- Tier `U` indicates unrated entries.
- Tier `X` indicates exit candidates and is excluded from ranked scoring.
- `source_bucket` is explicit for F tier and preserved even when tier is F.
- `rank_in_tier` is 1-based within each `(tier, source_bucket)` group.
- When `bgg_id` appears in `equivalent-games.json`, tier membership uses the configured `primary_bgg_id` and may include `linked_bgg_ids` for mirrored updates.

## Tier Summary Contract

Path:

- `data/working/ranking/tiers.json`

Type:

- JSON array of tier summary objects

Required fields:

- `tier`: string
- `tier_sort`: integer
- `count`: integer
- `source_buckets`: array

Rules:

- `source_buckets` contains objects with `bucket` and `count`.

## Tier Rank Order Contract

Path:

- `data/working/ranking/rank-order.json`

Type:

- JSON array of final tier-ordered ranking rows

Required fields:

- `tier`: string
- `source_bucket`: integer
- `rank_in_tier`: integer
- `tier_count`: integer
- `bgg_id`: integer
- `name`: string
- `current_rating`: number
- `proposed_rating`: number
- `num_plays`: integer
- `delta`: number

Rules:

- Contains only ranked entries, non-`U` and non-`X` tiers.
- `proposed_rating` is the final decimal score used for canonical update and publish queue.
- When equivalent games are configured, `bgg_id` is the ranking/export primary id for that equivalence group.

## Reconcile Report Contract

Path:

- `data/reports/quality/reconcile-report.json`

Required fields:

- `run_at`: ISO-8601 timestamp
- `raw_snapshot`: string path
- `total_from_snapshot`: integer
- `total_in_canonical`: integer
- `added`: integer
- `updated`: integer
- `unchanged`: integer
- `new_games`: array
- `updated_games`: array

Rules:

- `added + updated + unchanged` should equal `total_from_snapshot` after dedupe assumptions.

## CSV Rating Sheet Contract

Path:

- `data/publish/sheets/bgg-rating-upload-sheet.csv`

Required columns:

- `bgg_id`
- `name`
- `num_plays`
- `current_rating`
- `new_rating`
- `bgg_game_url`

Rules:

- `new_rating` accepts integer values 1..10.
- Blank `new_rating` means no change.

## Pending Tier Moves Contract

Path:

- `data/publish/queue/pending-tier-moves.json`

Type:

- JSON array

Required fields per move:

- `bgg_id`: integer
- `tier`: string

Optional fields:

- `source_bucket`: integer
- `notes`: string

## Pending Rating Updates Contract

Path:

- `data/publish/queue/pending-rating-updates.json`

Type:

- JSON array

Required fields:

- `bgg_id`: integer
- `name`: string
- `tier`: string
- `source_bucket`: integer
- `rank_in_tier`: integer
- `current_rating`: number
- `target_rating`: number
- `delta`: number
- `status`: string

Rules:

- Queue is generated by rank rebalance.
- Bulk BGG sync consumes this queue and removes successful entries.
- Equivalent game groups may produce multiple queued rows with the same `target_rating` so all linked BGG ids stay in sync.

## External Ordering Contract

Path:

- `data/working/ranking/external-ordering.json`

Type:

- JSON array

Required fields:

- `tier`: string
- `source_bucket`: integer
- `bgg_id`: integer
- `rank_in_tier`: integer
- `import_file`: string

Rules:

- Produced by normalize skill from external ranking engine files.
- Consumed by rank rebalance using `-ImportPath`.
- PubMeeple title-only files in `data/raw/pubmeeple/out/tier-*-ranking.csv` are normalized into this contract by matching `item` to tier ranking `name`.

## PubMeeple Round-Trip Contract

Paths:

- `data/raw/pubmeeple/in/tier-*-ranking.txt`
- `data/raw/pubmeeple/out/tier-*-ranking.csv`

Rules:

- normalize exports ranked tier names as newline-delimited text for PubMeeple input.
- PubMeeple output CSVs must contain `rank` and `item` columns.
- `item` values are matched case-insensitively after whitespace normalization against publish ranking `name`.
- matched PubMeeple order reorders the corresponding publish ranking CSV and contributes `bgg_id`-based rows to `external-ordering.json`.
