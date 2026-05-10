# mrhinsh-bg-reconcile

Purpose:
- Read a normalized snapshot produced by mrhinsh-bg-fetch.
- Merge it into `data/working/canonical/games.json` using the following sequential steps:
  1. **Load**: read the snapshot and the existing canonical file (empty list if not present).
  2. **Existing games** — for each game already in canonical (matched by `bgg_id`):
     - Update **all** of the following metadata fields from the snapshot: `num_plays`,
       `bgg_rating`, `num_ratings`, `complexity`, `players`, `categories`, `mechanics`,
       `year_published`, `name`. Every field in this list is safe to overwrite.
     - **Protected field**: `rating` (the locally-set user rating). Never clear it, lower it,
       or derive it from any snapshot value. `bgg_rating` is a separate field and is safe
       to update; only `rating` is protected.
     - `num_plays` may only be raised, never lowered (BGG can lag behind local records).
  3. **New games** — for each game in the snapshot not found in canonical:
     - Add it to canonical with `rating = 0`.
     - Append it to `data/working/unrated/intake.json`.
  4. **Write canonical**: persist the updated list sorted by `group_key` then `name`.
  5. **Write intake**: persist the updated intake sorted by `num_plays` desc then `name`.
  6. **Write report**: write a reconciliation report to `data/reports/quality/reconcile-report.json`.

Inputs:
- `$SnapshotPath` — path to the JSON snapshot produced by mrhinsh-bg-fetch (mandatory)
- `data/working/canonical/games.json` — existing canonical record (may not exist on first run)
- `data/working/unrated/intake.json` — existing intake list (may not exist on first run)

Outputs:
- `data/working/canonical/games.json` — updated (metadata only; ratings/tiers/ranks preserved)
- `data/working/unrated/intake.json` — new games appended
- `data/reports/quality/reconcile-report.json` — diff summary with added/updated/unchanged counts

Preconditions:
- Snapshot file exists at `$SnapshotPath` (run mrhinsh-bg-fetch first).

Postconditions:
- Canonical contains all games from the snapshot.
- No locally-set rating has been lowered or cleared.
- New games appear in intake with `current_rating = 0`.
- Reconcile report reflects the current run.

Idempotency:
- Safe to re-run with the same snapshot. Merge is additive; nothing is deleted from canonical.

Failure Modes:
- Missing snapshot: throws before modifying any file.
- Malformed snapshot: throws before modifying any file.

Example:
```powershell
$snapshot = & ./.agents/skills/mrhinsh-bg-fetch/scripts/run.ps1 -Username "MrHinsh"
& ./.agents/skills/mrhinsh-bg-reconcile/scripts/run.ps1 -SnapshotPath $snapshot
```
