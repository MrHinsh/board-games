# Agent Operating Guide

Personal BoardGameGeek (BGG) collection pipeline: pull plays and collection data via a
local MCP server, rate and tier-rank games, push ratings back to BGG. Deterministic
PowerShell scripts do the work — agents orchestrate and apply judgment only where a doc
says so. Do not re-derive logic the scripts already implement.

## Hard rules (always apply)

- Never commit secrets, cookies, or tokens. Local secret material lives only in `.local/` (gitignored).
- Never overwrite files under `data/raw/` — snapshots are immutable.
- Keep the data-flow order: fetch -> reconcile -> rank/report -> tier/rebalance -> publish/push.
- Never read `data/**/*.json` or CSV files wholesale into context (`games.json` alone is ~420 KB).
  Query with a script, `jq`-style filter, or targeted grep instead.
- Preserve script entrypoints and parameter names unless explicitly asked to break them.

## Commands

- Pull (BGG fetch and reconcile):
  `./.agents/skills/mrhinsh-bg-pull/scripts/run.ps1 -Username 'MrHinsh'`
- Rebuild local artifacts: `./workflows/Rebuild-BoardGames.ps1`
- Refresh (Pull then Rebuild): `./workflows/Refresh-BoardGames.ps1 -Username 'MrHinsh'`
- Push (write side, sync pending rating queue to BGG):
  `./.agents/skills/mrhinsh-bg-push/scripts/run.ps1 -Username 'MrHinsh'`
- Smoke check (script parse + data contract validation):
  `./scripts/Test-Repo.ps1`
- Status briefing (compact JSON, no large-file reads needed):
  `./scripts/Get-BgStatus.ps1`

## Read only what the task needs

| Task | Read first |
| --- | --- |
| Operating the pipeline, auth problems | `.agents/context/ops-runbook.md` |
| Editing data schemas or file shapes | `.agents/context/contracts.md` |
| Rating, tier, or rank conversion logic | `.agents/context/rating-system.md` and `.agents/context/tier-ranking-formula.md` |
| Predicting a rating for a game not yet owned (purchases, nominations) | `.agents/context/purchase-prediction.md` |
| Touching auth or secrets code | `.agents/guardrails/auth-and-secrets.md` |
| Any other policy question | `.agents/guardrails/global-rules.md` |
| Architecture orientation | `.agents/context/system-map.md` |

System implementations and operating docs live in `systems/`. Skill instructions and compatibility entrypoints remain in `.agents/skills/`. The agreed boundaries are in `.agents/context/system-map.md`.

## Definition of done

- `./scripts/Test-Repo.ps1` passes.
- If code behavior changed, the matching context doc above was updated in the same change set.
