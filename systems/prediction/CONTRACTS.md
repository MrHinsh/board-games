# Prediction System contracts

Resolved and scored nominations, designer cache and model results. These are advisory outputs; the model remains provisional. See the nomination documentation for the current CSV fields and rank-stability outputs.

## Conference previews

`conference-previews/Import-ConferencePreview.ps1` normalizes a BGG GeekPreview
into a working JSON document with preview metadata and a `candidates` array.
Candidates retain the base BGG id, edition id, expansion flag, designers,
mechanisms, categories, player and time ranges, preview popularity and booth
location. Duplicate editions of the same base BGG game collapse to one row.

`conference-previews/Score-ConferencePreview.ps1` writes an advisory CSV and an
optional Markdown report. It screens ownership against canonical plus the
reimplementation links returned for both canonical and candidate games and the
explicit equivalent-edition graph. Expansions and already-covered games
remain in the CSV with explicit statuses but are excluded from the main ranking.
The overall score uses the existing prediction as 50%, then shrunk descriptive
affinities for designer (20%), mechanism (12.5%), type (12.5%) and theme (5%).
Missing explanatory affinities use the operator's mean as a neutral value so
the weights remain fixed. A missing existing-model prediction makes the row
unrankable, though it stays in the all-games CSV as `Watch for reviews`.
Mechanism, type and theme scores explain similarity; they are not independently
validated predictors. A low-confidence game cannot enter `Must investigate`,
and an insufficient-data game is capped at `Watch for reviews`. Ranked games
form connected tie groups: a new group begins only across an adjacent score gap
larger than the model CV RMSE. The report does not present smaller differences
as precise unique ranks.

Every CSV row also carries `why_you_may_like_it`, separate designer, mechanism,
theme and type evidence, and `cautions`. Evidence names the matching historical
feature, rated-game sample size, average personal rating and, for designers,
recorded plays. The Markdown report renders the same evidence as readable
profiles for its leading candidates. Explanations must state missing evidence
and confidence limits rather than inventing a preference signal. Only evidence
above the operator's shrunk mean appears under why the game may fit; evidence at
or below that mean for designer, mechanism or theme appears under cautions. Type evidence is a
complexity-weighted comparison and names its rated-game sample; it must not claim
duration similarity until historical duration data is available.
Type evidence at or below the mean belongs in cautions under the same rule.

The existing persisted shapes remain defined in the
[data contracts](../../.agents/context/contracts.md). This migration does not
split or rewrite stored data. Ownership above records the intended responsibility;
the system map explicitly lists implementation differences.
