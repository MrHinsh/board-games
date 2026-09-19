# Purchase Prediction

Estimates what personal rating a game would earn **before it is owned or played**.
Used to rank purchase candidates and weekly club nominations. Advisory only — it
never writes to the canonical dataset, the tier engine, or the publish queue.

Distinct from `rating-system.md`, which converts an **already assigned** tier and
rank-in-tier into a BGG decimal. This document predicts the rating itself.

Implementation: `.agents/skills/mrhinsh-bg-shared/scripts/BggTasteModel.ps1`.
Validation harness: `.agents/skills/mrhinsh-bg-nominations/scripts/Measure-TasteModel.ps1`.

The designer index includes every played game, even when it has no personal
rating, plus the rated games eligible to train the taste model. New played games
are fetched into the cache on the next nomination scoring run. BGG entries with
no designer credit remain present with an empty designer list; no designer is
inferred from a similarly named game.

## Rule Zero

**Screen ownership against `data/working/canonical/games.json`, never against
`tier-engine-export.csv`.** The export holds only *rated* rows (397 of 550). A
game that is owned but unrated, or already on the want-to-buy list, is absent
from the export and will be misclassified as a fresh candidate. Match on
`bgg_id` and read `collection_status`, `rating`, `num_plays`, `want_to_buy`.

## The model

Ridge regression on three features, plus a shrunk designer term:

```
pred = ridge(complexity, bgg_rating, scifi) + designer_adjustment

designer_adjustment(d) = (n_d / (n_d + K)) * mean_residual(d)      K = 3
```

- `scifi` is 1 when BGG categories include Science Fiction or Space Exploration.
- Features are standardised; the intercept is unpenalised.
- Lambda is chosen by 5-fold cross-validation from a sweep; the harness warns if
  the chosen value sits at the edge of the sweep rather than at an interior
  minimum.
- Where the operator has already rated a game, **the actual rating is used and
  no prediction happens at all**.

Shrinking the designer term by sample size is what makes it safe. An unshrunk
mean with a hard `n >= 3` cut-off produced a visible artefact: Marco Polo II
inherited Daniele Tascini's full +1.76 because his co-designer fell one game
below the threshold and was silently dropped, floating the game to second place
overall.

## Measured accuracy

5-fold cross-validated RMSE, n = 397. Lower is better. Every figure is
out-of-sample; in-sample R² is deliberately not reported because it flatters.

| Model | CV RMSE |
| --- | --- |
| predict the mean | 1.599 |
| BGG rating rescaled | 1.412 |
| mechanics + categories (78 features), no designer | 1.364 |
| compact (3 features), no designer | 1.345 |
| mechanics + categories + designer | 1.328 |
| **compact + designer — shipped** | **1.303** |

The shipped model beats the BGG-rating baseline by **7.7%**. That is a real but
modest margin: differences under about 1.3 rating points are noise and must be
reported as such.

## The mechanics experiment failed

A per-mechanic, per-category model was built and rejected on evidence. With 50
mechanics and 26 categories present in at least 15 rated games — 78 features
against 397 rows, ridge-regularised — it scored **worse** than three features:
1.364 against 1.345 without the designer term, 1.328 against 1.303 with it.

So the collection does not currently contain enough signal to learn per-mechanic
taste. Almost everything predictable about a rating is captured by complexity,
BGG consensus, a sci-fi flag, and who designed it.

The `full` feature set is retained behind `-FeatureSet full` so the comparison
can be re-run cheaply as the collection grows. `Measure-TasteModel.ps1` prints
both and warns if `full` overtakes `compact`.

## Known limitations

- **BGG consensus is still the largest single term.** This predicts "what BGG
  thinks, adjusted for weight, sci-fi and designer" more than it models taste
  from first principles. Ark Nova — BGG 8.54, rated 3.999 — remains a case the
  model cannot see coming.
- **Range restriction.** Every training row is a game already chosen for
  purchase, so the model never observes what was rejected before buying.
- **The "spectacle" effect is unmodelled.** The largest negative residuals are
  dry, gimmick-free euros by unrelated designers: Ark Nova, Newton, Concordia.
  Apply it as a manual downward flag and say so explicitly.
- **New releases carry unsettled BGG averages.** Under roughly 1000 ratings, the
  average usually drifts down. Weight accordingly.
- **Never validated against outcomes.** Accuracy is measured against existing
  ratings, not against whether its recommendations proved enjoyable. Until club
  picks are tracked and rated, that remains unknown.

## Procedure

1. Screen ownership against canonical (Rule Zero).
2. Start the MCP server — `ops-runbook.md`, Start The MCP Server.
3. Fetch candidate details with `bgg-details` (`ids` array, max 20 per call).
4. Fit with `New-BggTasteModel`; predict with `Get-BggTastePrediction`.
5. Report the CV RMSE alongside the ranking, and flag anything inside it as a
   tie rather than an ordering.

## Snapshot

Validated 2026-09-09 against a 397-row training set. Re-run
`Measure-TasteModel.ps1` after any material change to the collection.
