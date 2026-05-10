# Data Contracts

This file defines stable contracts for core working files. Agents should treat these as the source of truth for shape and field meaning.

## Canonical Games Contract

Path:
- data/working/canonical/games.json

Type:
- JSON array of game objects

Required fields per object:
- group_key: string
- bgg_id: integer
- name: string
- year_published: integer
- rating: number
- num_plays: integer

Optional metadata fields:
- players: string or null
- complexity: number or null
- bgg_rating: number or null
- num_ratings: integer or null
- categories: string array
- mechanics: string array

Rules:
- bgg_id is the identity key.
- rating uses personal scale where 0 means unrated.
- num_plays must be non-negative.
- categories and mechanics default to empty arrays.

## Unrated Intake Contract

Path:
- data/working/unrated/intake.json
- data/working/unrated/intake-ranked.json

Type:
- JSON array of intake objects

Required fields:
- group_key: string
- bgg_id: integer
- name: string
- current_rating: number
- num_plays: integer

Optional fields:
- players: string or null
- complexity: number or null
- bgg_rating: number or null
- categories: string array
- mechanics: string array

Rules:
- current_rating is 0 when awaiting operator input.
- intake-ranked.json must be sorted by num_plays descending, then name ascending.

## Stackrank Output Contract

Path:
- data/reports/ranking/stackranked.json

Type:
- JSON array of ranked objects

Required fields:
- group_key: string
- stack_rank: integer (1-based in each source bucket)
- group_count: integer
- source_rating_bucket: integer
- target_rating_band: string
- bgg_id: integer
- name: string
- current_rating: number
- proposed_rating: number
- num_plays: integer

Optional fields:
- players: string or null
- complexity: number or null
- bgg_rating: number or null
- categories: string array
- mechanics: string array

Rules:
- proposed_rating is analytical ordering output.
- current_rating remains operator source of truth.

## Reconcile Report Contract

Path:
- data/reports/quality/reconcile-report.json

Required fields:
- run_at: ISO-8601 timestamp
- raw_snapshot: string path
- total_from_snapshot: integer
- total_in_canonical: integer
- added: integer
- updated: integer
- unchanged: integer
- new_games: array
- updated_games: array

Rules:
- added + updated + unchanged should equal total_from_snapshot after dedupe assumptions.

## CSV Rating Sheet Contract

Path:
- data/publish/sheets/bgg-rating-upload-sheet.csv

Required columns:
- bgg_id
- name
- num_plays
- current_rating
- new_rating
- bgg_game_url

Rules:
- new_rating accepts integer values 1..10.
- blank new_rating means no change.
