# Workflows

Workflow implementations are descriptively named PowerShell files directly in
this directory. They coordinate system operations; business rules stay with
the owning system. Tests live in `tests/workflows/`.

| Script | Purpose |
| --- | --- |
| `Rebuild-BoardGames.ps1` | Rebuild local artifacts across systems without pulling or pushing BGG |
| `Refresh-BoardGames.ps1` | Pull BGG data, then run Rebuild |
| `Update-BggData.ps1` | Legacy played-game export/report workflow retained for the existing Update-BggData entrypoint |

The system implementations have not yet been converted into PowerShell modules;
these workflows currently invoke system-owned scripts. Module conversion is
separate work.

## Rebuild

Cross-system composition of local ranking/intake, tier mapping, external ordering,
tier moves and decimal rebalance. Each calculation stays in its owning system.

Run from the repository root: `./workflows/Rebuild-BoardGames.ps1`.

Rebuild does not pull or push BGG. It preserves the existing rank/report before
tier/rebalance sequence; those earlier reports describe pre-rebalance state.
It writes generated PubMeeple text to `data/publish/pubmeeple/in/` and still
reads operator PubMeeple results from `data/raw/pubmeeple/out/`.

The existing queue/local-rating coupling remains a known limitation: repeated
rebalance can replace an outstanding queue based on local differences. Fixing
that state contract is separate from this structural migration.

Prediction and discovery require their own inputs and run separately. For a
network refresh followed by this workflow, use `./workflows/Refresh-BoardGames.ps1 -Username MrHinsh`.

## Refresh

Convenience workflow: BGG Integration Pull, followed by cross-system Rebuild.

Run from the repository root:
`./workflows/Refresh-BoardGames.ps1 -Username MrHinsh -ApiKey $env:BGG_API_KEY`.

Requires the BGG MCP server for Pull. Stops at the first failure. It does not
publish ratings to BGG. Returns separate Pull and Rebuild results.
