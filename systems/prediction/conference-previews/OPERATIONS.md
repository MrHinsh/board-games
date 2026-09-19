# Conference preview ranking

Imports a BoardGameGeek GeekPreview and ranks its base games with the same taste
model, designer cache, canonical ownership rules and edition equivalence used by
the rest of the prediction system.

Run from the repository root with the local BGG MCP service available:

```powershell
./systems/prediction/conference-previews/run.ps1 -PreviewId 93
```

Preview 93 is SPIEL Essen 2026 and is the default. The run writes:

- a rebuildable normalized candidate and BGG-details cache under
  `data/working/conferences/`;
- the complete ordered CSV under `data/reports/conferences/`;
- a Markdown report containing the first 30 new base-game candidates.

Use `-RefreshDetails` when cached BGG ratings, complexity or relationships need
refreshing. The preview list itself is fetched on every run because publishers
continue changing it before the event.

The importer calls BGG's public GeekPreview JSON endpoints with a bounded page
throttle and retries transient non-JSON responses. BGG currently emits
`"dynamicinfo":}` for empty dynamic information; only that exact malformed token
is repaired. Any other malformed response fails the run.

Expansions and candidates already covered by an owned, played, reimplemented or
explicitly equivalent edition remain in the CSV with their exclusion reason.
They do not enter the main rank. Low-confidence candidates cannot receive `Must
investigate`; candidates without usable model inputs or with fewer than ten BGG
ratings are capped at `Watch for reviews`. Candidates without a compact-model
prediction stay unranked, and ranked candidates within the model CV RMSE share a
connected tie-group number. A new group starts only when adjacent sorted scores
differ by more than CV RMSE. Canonical records that are neither owned nor played
remain eligible candidates unless an owned or played equivalent covers them.
