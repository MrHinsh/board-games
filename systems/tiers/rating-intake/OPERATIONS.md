# mrhinsh-bg-import-ratings

Import operator-assigned integer ratings (1-10) back into the canonical dataset. This is the
"apply" half of the rating intake loop (see `.agents/context/ops-runbook.md`).

## Run

Preferred CSV workflow — after editing `new_rating` in the upload sheet:

```powershell
./.agents/skills/mrhinsh-bg-import-ratings/scripts/run.ps1
# equivalent to: scripts/Import-BggRatingSheet.ps1
```

Alternative — if `data/working/unrated/intake-ranked.json` was edited directly:

```powershell
./.agents/skills/mrhinsh-bg-import-ratings/scripts/Import-BggRatingsFromUnrated.ps1
```

## Inputs

- `data/publish/sheets/bgg-rating-upload-sheet.csv` (`-SheetPath`) — `new_rating` column, integers 1-10
- `data/working/unrated/intake-ranked.json` (`-UnratedPath`)
- `data/working/canonical/games.json` (`-PlayedPath`)

## Outputs

- Updated `data/working/canonical/games.json` (ratings applied)
- Updated `data/working/unrated/intake-ranked.json`

## Postconditions

Re-run rank-set and publish-queue afterwards so derived artifacts reflect the new ratings
(or run the local cross-system workflow `./workflows/Rebuild-BoardGames.ps1`).

## Idempotency

Safe to re-run; importing the same sheet twice applies the same ratings again.

## Failure Modes

- Missing sheet file: run `New-BggRatingUploadSheet.ps1` first.
- Rows with empty/non-integer `new_rating` are skipped, not errors.
